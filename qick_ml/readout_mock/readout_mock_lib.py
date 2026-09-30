"""
Support library for the readout mock (tProc v1): replay recorded qubit readout
traces through the DAC-to-ADC loopback so that the on-board NN classifier
scores them.

Ported from the tProc v2 readout mock (ml-integration-tproc-v2-2026,
firmware/notebooks/qick_ml/readout_mock/): everything but the replay program
(ArbPulseProgram, acquire_trace) is the same. The pulse edge finder and the
phase calibration with a program class (pulse_edges, measure_phase,
calibrate_phase) are here because this branch's qick_ml_lib has older ones.

The traces are the 20240528 QICK ZCU216 dataset the NN IP
(l2_w400_ternary_h4_s100) was trained on: decimated readout traces (307.2 MHz,
770 samples, I/Q interleaved, 14-bit integers). The NN sees trace samples
100-499. Each trace is resampled to the DAC rate (6881.28 Msps) and played as
an arbitrary envelope on the generator (ArbPulseProgram, tProc v1
AveragerProgram), so that it reaches
the readout, and the NN, as it was recorded: same phase, same sample
positions, and the same scale, or 1/g of it with the NN's input gain set to g
(its scaling_factor register, 1, 2, 4 or 8, see ../ip/README.md): the
loopback cannot reach the dataset's amplitude with an arbitrary envelope, so
the replay runs at 1/g and the NN multiplies it back.

The older tProc v1 notebooks in qick_dev/qick_ml/readout_mock/
(readout_mock_malab*.ipynb) replayed ZCU111 traces to an earlier two-logit NN.

Contents:
  - load_dataset, select_shots: the traces (the 20 HLS testbench shots in the
    IP project zip, or the full test set copied from the NAS)
  - ArbPulseProgram, trace_to_envelope, rect_envelope: the replay
  - measure_full_scale, nn_gain_for, align_timing, check_iq_orientation,
    replay_error, refine_calibration: the calibrations
  - run_shots, score: the NN run
  - memory_report: the board's free memory

It reuses qick_ml_lib (one directory up) for the classifier helpers.
"""

import hashlib
import io
import os
import sys
import time
import zipfile

import numpy as np

QICK_ML_DIR = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
if QICK_ML_DIR not in sys.path:
    sys.path.insert(0, QICK_ML_DIR)

from qick import AveragerProgram  # noqa: E402
from qick_ml_lib import (_wrap_deg, to_float,  # noqa: E402
                         get_classifier_prediction,
                         get_classifier_prediction_count)

F_RO = 307.2        # MHz, decimated readout rate (the dataset's sample rate)
WINDOW_START = 100  # first trace sample the NN sees
WINDOW_SIZE = 400   # samples the NN sees
# Where the rising edge (half maximum) of a replayed rectangle that starts
# with the window's first sample must land for a 1:1 replay: dataset sample k
# is DAC sample k * 22.4 of the envelope (trace_to_envelope), and the
# rectangle steps up there, so the edge lands on sample 100 (to 1/44.8 sample)
EDGE_TARGET = float(WINDOW_START)

# The HLS project the NN IP was built from; its tb_data/ holds 20 test shots
HLS_PRJ = 'two_layers_w400_ternary_h4_s100_20240528_hls4ml_prj'
HLS_PRJ_ZIP = os.path.join(QICK_ML_DIR, 'ip', '20240528', HLS_PRJ + '.zip')

# The full test set, on the NAS at
# /nas/work/research/quantum/readout/data/qick_data/20240528/000_770/,
# and the checksums the training notebook (workflow_800x4x1_ternary.ipynb in
# ml-quantum-readout) asserts for it
X_TEST = 'X_test_000_770.npy'
Y_TEST = 'y_test_000_770.npy'
MD5_X = 'b7d85f42522a0a57e877422bc5947cde'
MD5_Y = '8c9cce1821372380371ade5f0ccfd4a2'

# Offline accuracy of the deployed IP on the full test set: the bit-exact C
# model (../nn_model_accuracy_check/)
C_MODEL_ACCURACY = 0.96014
C_MODEL_FIDELITY = 0.92028


# --- Memory -------------------------------------------------------------------

def memory_report(label='', warn_mb=500):
    """
    Print the board's available memory, the swap in use and this process's
    resident memory (from /proc), and warn when the available memory falls
    below warn_mb. The ZCU216 has 3.9 GB of RAM and 1 GB of swap on the SD
    card; when both fill up it stops responding (it needed a power cycle on
    2026-09-30), so keep an eye on it and close the kernels you do not need.

    Returns:
        dict: available_mb, swap_used_mb, process_mb.
    """
    info = {}
    with open('/proc/meminfo') as f:
        for line in f:
            k, v = line.split(':', 1)
            info[k] = int(v.split()[0]) // 1024      # kB -> MB
    rss = 0
    with open('/proc/self/status') as f:
        for line in f:
            if line.startswith('VmRSS:'):
                rss = int(line.split()[1]) // 1024
    out = {'available_mb': info.get('MemAvailable', 0),
           'swap_used_mb': info.get('SwapTotal', 0) - info.get('SwapFree', 0),
           'process_mb': rss}
    print('Memory{}: {} MB available of {} MB, swap used {} of {} MB, this kernel {} MB'.format(
        ' ({})'.format(label) if label else '', out['available_mb'], info.get('MemTotal', 0),
        out['swap_used_mb'], info.get('SwapTotal', 0), out['process_mb']))
    if out['available_mb'] < warn_mb:
        print('WARNING: less than {} MB available: close other notebooks/kernels before going on'.format(warn_mb))
    return out


# --- Dataset ------------------------------------------------------------------

class Dataset:
    """
    Readout traces to replay.

    Attributes:
        traces: N x L x 2 int array of [I, Q] rows; trace sample `first + k`
            is row k.
        first: The trace sample of row 0 (0 for full traces, 100 for window
            only).
        y: The labels (0 = ground, 1 = excited), or None.
        ref_logits: The expected NN logits (HLS C simulation), or None.
        name: A short description.
    """
    def __init__(self, traces, first, y, ref_logits, name):
        self.traces = traces
        self.first = first
        self.y = y
        self.ref_logits = ref_logits
        self.name = name

    def __len__(self):
        return len(self.traces)

    def window(self, i):
        """The NN window (samples 100-499) of shot i, a 400 x 2 array."""
        k = WINDOW_START - self.first
        return np.asarray(self.traces[i][k:k + WINDOW_SIZE])


def _to_iq(X):
    """N x 2L interleaved I/Q columns to N x L x 2."""
    return X.reshape(X.shape[0], -1, 2)


def load_dataset(data_dir=None, x_name=X_TEST, y_name=Y_TEST, check_md5=False):
    """
    Load the traces to replay.

    With data_dir None, loads the 20 test shots of the HLS testbench from the
    NN's HLS project zip (ip/20240528/): window only (samples 100-499), no
    labels, but with the exact logits of the C simulation, which the board
    logits can be compared with. These are the first and the last 10 shots of
    the test set.

    With data_dir set, loads x_name and y_name from it (memory-mapped). The
    X array is either the full traces (N x 1540, samples 0-769, as on the NAS)
    or the window only (N x 800, samples 100-499).

    Args:
        data_dir (str): The dataset directory, or None for the testbench shots.
        x_name, y_name (str): The file names in data_dir.
        check_md5 (bool): Check the full test set's checksums (reads the whole
            file).

    Returns:
        Dataset
    """
    if data_dir is None:
        with zipfile.ZipFile(HLS_PRJ_ZIP) as z:
            def read(name):
                return z.read('{}/tb_data/{}'.format(HLS_PRJ, name)).decode()
            X = np.loadtxt(io.StringIO(read('tb_input_features.dat')))
            ref = np.loadtxt(io.StringIO(read('tb_output_predictions.dat')))
        return Dataset(_to_iq(X.astype(np.int32)), WINDOW_START, None, ref,
                       'HLS testbench, 20 shots')

    X = np.load(os.path.join(data_dir, x_name), mmap_mode='r')
    y = np.load(os.path.join(data_dir, y_name), mmap_mode='r')
    if check_md5:
        ok = hashlib.md5(np.ascontiguousarray(X)).hexdigest() == MD5_X and \
            hashlib.md5(np.ascontiguousarray(y)).hexdigest() == MD5_Y
        print('INFO: test set md5 {}'.format('OK' if ok else 'MISMATCH'))
    if X.shape[1] == 2 * 770:
        first = 0
    elif X.shape[1] == 2 * WINDOW_SIZE:
        first = WINDOW_START
    else:
        raise ValueError('Expected 1540 (samples 0-769) or 800 (samples 100-499) '
                         'columns, got {}'.format(X.shape[1]))
    return Dataset(_to_iq(X), first, np.asarray(y).astype(int).ravel(), None,
                   '{}, {} shots'.format(os.path.join(data_dir, x_name), len(X)))


def select_shots(dataset, n=None, seed=0):
    """
    Pick the shots to replay.

    Args:
        dataset (Dataset): The traces.
        n (int): The number of shots, half of each class when the labels are
            known; None for all of them.
        seed (int): The random seed.

    Returns:
        numpy.ndarray: The shot indices, sorted.
    """
    if n is None or n >= len(dataset):
        return np.arange(len(dataset))
    rng = np.random.RandomState(seed)
    if dataset.y is None:
        return np.sort(rng.choice(len(dataset), n, replace=False))
    idx = [rng.choice(np.flatnonzero(dataset.y == c), n // 2 + (n % 2) * c, replace=False)
           for c in (0, 1)]
    return np.sort(np.concatenate(idx))


# --- Replay -------------------------------------------------------------------

class ArbPulseProgram(AveragerProgram):
    """
    Play one arbitrary-envelope pulse on a generator and capture the decimated
    I/Q trace on a readout: qick_ml_lib.LoopbackProgram with the constant
    pulse replaced by the envelope in cfg, and the tProc v2 mock's
    configuration keys.

    cfg keys: gen_ch, ro_ch, freq (MHz), phase (deg), env (M x 2 array of
    [I, Q] DAC units, M a multiple of the generator's samples per clock),
    trig_time (us, readout trigger after the pulse start; applied as
    adc_trig_offset in tProc cycles), ro_len (us). acquire_trace adds the
    AveragerProgram keys (reps, soft_avgs).
    """
    def initialize(self):
        cfg = self.cfg
        ch, ro = cfg['gen_ch'], cfg['ro_ch']
        self.declare_gen(ch=ch, nqz=1)
        self.declare_readout(ch=ro, length=int(round(cfg['ro_len'] * F_RO)), freq=cfg['freq'], gen_ch=ch)

        env = np.asarray(cfg['env'])
        self.add_pulse(ch=ch, name='replay', idata=env[:, 0], qdata=env[:, 1])
        self.set_pulse_registers(ch=ch, style='arb', waveform='replay',
                                 freq=self.freq2reg(cfg['freq'], gen_ch=ch, ro_ch=ro),
                                 phase=self.deg2reg(cfg['phase'], gen_ch=ch),
                                 gain=int(self.soccfg['gens'][ch]['maxv']))  # the envelope sets the amplitude
        self.synci(200)  # give the processor some time to configure the pulse

    def body(self):
        f_time = self.soccfg['tprocs'][0]['f_time']
        self.measure(pulse_ch=self.cfg['gen_ch'], adcs=[self.cfg['ro_ch']], pins=[0],
                     adc_trig_offset=int(round(self.cfg['trig_time'] * f_time)),
                     wait=True, syncdelay=self.us2cycles(self.cfg.get('relax_delay', 1.0)))


def acquire_trace(soc, cfg, final_delay=1.0):
    """Run one ArbPulseProgram shot and return its trace, an N x 2 float array."""
    prog = ArbPulseProgram(soc, dict(cfg, reps=1, soft_avgs=1, relax_delay=final_delay))
    iq = prog.acquire_decimated(soc, progress=False)[0]   # 2 x N ([I, Q])
    return np.asarray(iq, float).T


def gen_params(soccfg, gen_ch):
    """The generator's DAC rate (Msps), samples per fabric clock and envelope full scale."""
    g = soccfg['gens'][gen_ch]
    return g['f_fabric'] * g['samps_per_clk'], g['samps_per_clk'], g['maxv'] * g['maxv_scale']


def _pad_to(n, m):
    return -n % m


def rect_envelope(soccfg, gen_ch, amp, n_samples=WINDOW_SIZE, margin=0, lead=0, angle_deg=0.0):
    """
    A rectangular envelope n_samples readout samples long, after margin
    readout samples of zeros and lead extra DAC samples of zeros, at amp DAC
    units and angle_deg in the I/Q plane. The timing, amplitude and phase
    calibrations use it in place of a trace.
    """
    f_dac, spc, _ = gen_params(soccfg, gen_ch)
    ratio = f_dac / F_RO
    n0 = lead + int(round(margin * ratio))
    n1 = int(round(n_samples * ratio))
    n = n0 + n1 + int(round(margin * ratio))
    n += _pad_to(n, spc)
    env = np.zeros((n, 2))
    z = amp * np.exp(1j * np.radians(angle_deg))
    env[n0:n0 + n1, 0] = z.real
    env[n0:n0 + n1, 1] = z.imag
    return np.round(env).astype(np.int16)


def _resample(seg, n):
    """
    Band-limited resampling of a complex sequence to n samples (zero padding
    of its spectrum): output sample j is the band-limited interpolant of seg
    at seg sample j * len(seg) / n.
    """
    m = len(seg)
    S = np.fft.fft(seg)
    h = (m + 1) // 2
    P = np.zeros(n, complex)
    P[:h] = S[:h]
    P[n - (m - h):] = S[h:]
    if m % 2 == 0:
        # Split the Nyquist bin between the positive and negative frequencies
        P[m // 2] = P[n - m // 2] = S[m // 2] / 2
    return np.fft.ifft(P) * (n / m)


def trace_to_envelope(dataset, i, cal, soccfg, gen_ch, margin=20):
    """
    Turn shot i into a generator envelope.

    Takes the NN window (samples 100-499) and margin samples on each side:
    the dataset's own samples when it has them, else the window mirrored at
    its edges. Tapers the margins to zero (half cosine), so the envelope has
    no step, and resamples it from the readout rate to the DAC rate. The
    resampling is band-limited (the traces have noise up to ~140 MHz, near
    the readout's 153.6 MHz Nyquist frequency, which linear interpolation
    would attenuate). Then it applies the calibration and prepends
    cal['lead'] zero DAC samples (fine timing).

    Args:
        dataset (Dataset): The traces.
        i (int): The shot index.
        cal (dict): scale (DAC units per ADC unit), conj (negate Q), lead
            (zero DAC samples before the trace), trim (optional complex
            factor applied to the trace first, from refine_calibration),
            nn_gain (optional, the NN's input gain g: the trace is replayed
            at 1/g of its recorded scale).
        soccfg: The QickConfig.
        gen_ch (int): The generator channel.
        margin (int): The readout samples replayed on each side of the
            window; 400 + 2 * margin must be a multiple of 5, so that the
            trace resamples to a whole number of DAC samples (x22.4).

    Returns:
        tuple: The envelope (M x 2 int16) and the number of DAC samples whose
            magnitude was clipped to full scale.
    """
    f_dac, spc, maxv = gen_params(soccfg, gen_ch)
    k0 = WINDOW_START - margin - dataset.first
    k1 = WINDOW_START + WINDOW_SIZE + margin - dataset.first
    tr = np.asarray(dataset.traces[i])
    if k0 >= 0 and k1 <= len(tr):
        seg = tr[k0:k1].astype(float)
    else:
        w = dataset.window(i).astype(float)
        seg = np.pad(w, ((margin, margin), (0, 0)), mode='reflect')
    z = seg[:, 0] + 1j * seg[:, 1]
    if margin > 0:
        taper = 0.5 - 0.5 * np.cos(np.pi * (np.arange(margin) + 0.5) / margin)
        z[:margin] *= taper
        z[-margin:] *= taper[::-1]

    n = len(z) * f_dac / F_RO
    if abs(n - round(n)) > 1e-6:
        raise ValueError('{} readout samples do not resample to a whole number of '
                         'DAC samples; change the margin'.format(len(z)))
    z = _resample(z, int(round(n))) * cal.get('trim', 1)
    if cal.get('conj'):
        z = z.conj()
    z = z * cal['scale'] / cal.get('nn_gain', 1)

    lead = int(cal.get('lead', 0))
    env = np.zeros((lead + len(z) + _pad_to(lead + len(z), spc), 2))
    env[lead:lead + len(z), 0] = z.real
    env[lead:lead + len(z), 1] = z.imag

    # The generator output reaches |I + jQ|: limit the magnitude
    mag = np.hypot(env[:, 0], env[:, 1])
    over = mag > maxv
    env[over] *= (maxv / mag[over])[:, None]
    env = np.clip(np.round(env), -maxv, maxv).astype(np.int16)
    return env, int(np.count_nonzero(over))


# --- Calibrations -------------------------------------------------------------

def pulse_edges(iq):
    """
    Find the rising and falling edges of the loopback pulse in a trace.

    The edges are the half-maximum crossings of the magnitude, linearly
    interpolated between samples.

    Args:
        iq: One readout trace, an Nx2 array of [I, Q] rows.

    Returns:
        tuple: The rising and falling edges, in (fractional) decimated samples.
    """
    iq = np.asarray(iq, float)
    mag = np.hypot(iq[:, 0], iq[:, 1])
    half = 0.5 * mag.max()
    on = np.flatnonzero(mag > half)
    r, f = on[0], on[-1]
    rise = r - 1 + (half - mag[r - 1]) / (mag[r] - mag[r - 1]) if r > 0 else 0.0
    fall = f + (mag[f] - half) / (mag[f] - mag[f + 1]) if f + 1 < len(mag) else float(f)
    return rise, fall


def measure_phase(soc, config, n=2, prog_cls=None):
    """
    Measure the phase of the loopback pulse at the ADC.

    Fires n pulses with prog_cls. For each, I and Q are averaged over the pulse
    plateau (the samples above half the peak magnitude) of the readout trace.

    Args:
        soc: The QickSoc instance.
        config (dict): The program configuration, including phase.
        n (int): The number of pulses to average over.
        prog_cls: Ignored (the tProc v2 mock passes its program class); the
            pulse is played with ArbPulseProgram (acquire_trace).

    Returns:
        float: The circular mean phase in degrees, in [-180, 180).
    """
    z = 0
    for _ in range(n):
        iq = acquire_trace(soc, config)
        i, q = iq[:, 0], iq[:, 1]
        on = np.hypot(i, q) > 0.5 * np.hypot(i, q).max()
        z += np.exp(1j * np.arctan2(q[on].mean(), i[on].mean()))
    return _wrap_deg(np.angle(z, deg=True))


def calibrate_phase(soc, config, target_deg=60.0, n=2, tol_deg=10.0, tol_fine_deg=0.1,
                    max_passes=5, debug=True, prog_cls=None):
    """
    Find the generator phase (the pulse's phase) that brings the loopback
    pulse to the ADC at target_deg.

    Measures the phase with phase = 0 and with phase = 90 deg: the phase at
    the ADC moves by about +90 or -90 deg, which gives the direction in which
    the pulse phase turns it. Then sets the pulse phase to the difference from
    the target and corrects the remaining error again, up to max_passes times,
    until it is below tol_fine_deg: the logit changes by several percent per
    degree. Call it after each bitstream load and before resetting the
    classifier: the calibration pulses also trigger the NN.

    Args:
        soc: The QickSoc instance.
        config (dict): The program configuration; not modified.
        target_deg (float): The phase the pulse should have at the ADC.
        n (int): The number of pulses per phase measurement.
        tol_deg (float): The largest accepted error; a larger one raises.
        tol_fine_deg (float): The error the refinement aims for; a larger one
            (up to tol_deg) only prints a warning.
        max_passes (int): The largest number of refinement passes.
        debug (bool): Print the measured and corrected phases.
        prog_cls: Ignored (see measure_phase).

    Returns:
        float: The phase value, in degrees, to put in config['phase'].

    Raises:
        RuntimeError: If the 90 deg probe does not move the phase by about
            +-90 deg, or the phase is still more than tol_deg off the target.
    """
    def measure(phase):
        return measure_phase(soc, dict(config, phase=phase), n, prog_cls)

    raw = measure(0.0)
    step = _wrap_deg(measure(90.0) - raw)
    if abs(abs(step) - 90.0) > tol_deg:
        raise RuntimeError('phase calibration failed: phase 90 deg moved the phase by {:.1f} deg'.format(step))
    sign = 1 if step > 0 else -1
    phase = _wrap_deg(sign * (target_deg - raw))
    got = measure(phase)
    passes = 0
    while passes < max_passes and abs(_wrap_deg(target_deg - got)) >= tol_fine_deg:
        phase = _wrap_deg(phase + sign * _wrap_deg(target_deg - got))
        got = measure(phase)
        passes += 1
    err = abs(_wrap_deg(got - target_deg))
    if debug:
        print('INFO: phase calibration: raw {:.1f} deg, phase {:.2f} deg -> {:.2f} deg '
              '(target {:.1f}, sign {:+d}, {} passes)'.format(raw, phase, got, target_deg, sign, passes))
    if err > tol_deg:
        raise RuntimeError('phase calibration failed: {:.1f} deg, target {:.1f} deg'.format(got, target_deg))
    if err >= tol_fine_deg:
        print('WARNING: phase calibration is {:.2f} deg off the target (aim {:.2f} deg)'.format(err, tol_fine_deg))
    return phase



def _plateau_mean(iq):
    """Mean I + jQ over the samples above half the peak magnitude."""
    z = iq[:, 0] + 1j * iq[:, 1]
    on = np.abs(z) > 0.5 * np.abs(z).max()
    return z[on].mean()


def measure_full_scale(soc, cfg, fractions=(0.05, 0.1, 0.2, 0.3), debug=True):
    """
    Measure the loopback gain: the readout magnitude a full-scale envelope
    would give.

    Replays rectangular envelopes at the given fractions of full scale and
    fits the plateau magnitude against the envelope amplitude (a line through
    the origin). Stays at small amplitudes so as not to saturate anything.

    Args:
        soc: The QickSoc.
        cfg (dict): The program configuration (gen_ch, ro_ch, freq, phase,
            trig_time, ro_len); env is replaced.
        fractions: The envelope amplitudes, as fractions of full scale.

    Returns:
        tuple: The readout magnitude at full scale (ADC units), and the
            fit residual (relative RMS), which shows whether the gain is
            linear.
    """
    _, _, maxv = gen_params(soc, cfg['gen_ch'])
    a = np.array(fractions) * maxv
    m = []
    for amp in a:
        env = rect_envelope(soc, cfg['gen_ch'], amp)
        m.append(abs(_plateau_mean(acquire_trace(soc, dict(cfg, env=env)))))
    m = np.array(m)
    k = (a @ m) / (a @ a)
    resid = np.sqrt(np.mean((m - k * a) ** 2)) / m.mean()
    if debug:
        for amp, mm in zip(a, m):
            print('INFO:   envelope {:6.0f} DAC units -> |IQ| {:7.1f}'.format(amp, mm))
        print('INFO: full scale ({:.0f} DAC units) -> |IQ| {:.0f} ADC units '
              '(linear fit, residual {:.2%})'.format(maxv, k * maxv, resid))
    return k * maxv, resid


def nn_gain_for(peak, full_scale, gains=(1, 2, 4, 8)):
    """
    The smallest NN input gain g (a scaling_factor value) for which a replay
    at 1/g of the dataset's scale fits the loopback: peak / g <= full_scale.

    Args:
        peak (float): The dataset's peak |IQ| (ADC units).
        full_scale (float): The readout magnitude of a full-scale envelope
            (measure_full_scale).

    Returns:
        int: The gain, or None if even the largest one is not enough.
    """
    for g in gains:
        if peak / g <= full_scale:
            return g
    return None


def check_iq_orientation(soc, cfg, amp, debug=True):
    """
    Check whether the loopback keeps or mirrors the I/Q plane.

    With the phase calibrated so that an I-only envelope arrives at 0 deg,
    replays a Q-only envelope: it arrives at +90 deg when the loopback keeps
    the orientation and at -90 deg when it mirrors it (then the envelope's Q
    must be negated).

    Returns:
        bool: True when Q has to be negated.

    Raises:
        RuntimeError: If the two measurements are not about 90 deg apart.
    """
    a_i = np.angle(_plateau_mean(acquire_trace(
        soc, dict(cfg, env=rect_envelope(soc, cfg['gen_ch'], amp, angle_deg=0)))), deg=True)
    a_q = np.angle(_plateau_mean(acquire_trace(
        soc, dict(cfg, env=rect_envelope(soc, cfg['gen_ch'], amp, angle_deg=90)))), deg=True)
    d = _wrap_deg(a_q - a_i)
    if debug:
        print('INFO: I-only envelope at {:.1f} deg, Q-only at {:.1f} deg (difference {:+.1f} deg)'.format(
            a_i, a_q, d))
    if abs(abs(d) - 90) > 10:
        raise RuntimeError('I/Q orientation check failed: difference {:.1f} deg'.format(d))
    return d < 0


def align_timing(soc, cfg, amp, margin=20, debug=True):
    """
    Place the replay so that each dataset sample lands on the trace sample of
    the same index (the window's first sample on trace sample 100).

    Replays a rectangular envelope with the same layout as a trace envelope
    (margin readout samples of zeros, the 400-sample window, margin samples
    of zeros) and finds its rising edge, whose target is 100 (see
    EDGE_TARGET). Moves the readout trigger in whole tProc timing cycles
    (0.714 readout samples each; a later trigger moves the pulse earlier in
    the trace) so that the pulse lands early, then delays it by leading zero
    DAC samples (1/22.4 readout sample each).

    Args:
        soc: The QickSoc.
        cfg (dict): The program configuration; trig_time is the start value.
        amp (float): The envelope amplitude (DAC units).
        margin (int): As in trace_to_envelope.

    Returns:
        tuple: trig_time (us), lead (DAC samples), and the rising edge
            measured with both applied (target EDGE_TARGET).
    """
    f_dac, _, _ = gen_params(soc, cfg['gen_ch'])
    f_time = soc['tprocs'][0]['f_time']
    cyc = F_RO / f_time         # readout samples per tProc timing cycle

    def edge(trig_time, lead):
        env = rect_envelope(soc, cfg['gen_ch'], amp, margin=margin, lead=lead)
        return pulse_edges(acquire_trace(soc, dict(cfg, env=env, trig_time=trig_time)))[0]

    r0 = edge(cfg['trig_time'], 0)
    err = r0 - EDGE_TARGET      # > 0: the pulse lands late
    n = int(np.ceil(err / cyc))
    trig_time = (round(cfg['trig_time'] * f_time) + n) / f_time
    if trig_time < 0:
        raise RuntimeError('The replay lands {:.1f} samples early even with the trigger at the '
                           'pulse start: the loopback latency is shorter than expected'.format(-err))
    r1 = edge(trig_time, 0)
    # The lead can only delay the pulse, so it has to land early here. The
    # step above assumes exactly cyc samples per tick, and the edge can come
    # out a fraction of a sample late: move the trigger one more tick then
    for _ in range(3):
        if r1 <= EDGE_TARGET:
            break
        trig_time += 1 / f_time
        r1 = edge(trig_time, 0)
    lead = max(0, int(round((EDGE_TARGET - r1) * f_dac / F_RO)))
    r2 = edge(trig_time, lead)
    if debug:
        print('INFO: rising edge {:.2f} (trig_time {:.4f} us) -> {:.2f} (trig_time {:.4f} us) '
              '-> {:.2f} (+{} lead DAC samples), target {}'.format(
                  r0, cfg['trig_time'], r1, trig_time, r2, lead, EDGE_TARGET))
    return trig_time, lead, r2


def replay_error(data, captured, max_lag=2.0):
    """
    Compare a captured NN window with the dataset window it replays.

    Fits captured = g * data (complex least squares), which the calibrations
    should bring to g = 1 (gain 1, angle 0), and finds the sub-sample lag
    that best aligns the two (the timing calibration should bring it to 0).

    Args:
        data, captured: 400 x 2 arrays of [I, Q] rows.
        max_lag (float): The largest lag searched, in samples.

    Returns:
        dict: gain (|g|), angle_deg, lag (samples; > 0 when the capture is
            late), rms (of captured - data, ADC units), rms_rel (relative to
            the data's RMS), corr_i, corr_q (correlation per component).
    """
    d = np.asarray(data, float)
    c = np.asarray(captured, float)
    zd = d[:, 0] + 1j * d[:, 1]
    zc = c[:, 0] + 1j * c[:, 1]
    g = np.vdot(zd, zc) / np.vdot(zd, zd)

    # Sub-sample lag: shift the data by linear interpolation, keep the best fit
    k = np.arange(len(zd))
    inner = slice(int(np.ceil(max_lag)), len(zd) - int(np.ceil(max_lag)))

    def misfit(lag):
        s = np.interp(k - lag, k, zd.real) + 1j * np.interp(k - lag, k, zd.imag)
        gs = np.vdot(s[inner], zc[inner]) / np.vdot(s[inner], s[inner])
        return np.sum(np.abs(zc[inner] - gs * s[inner]) ** 2)

    step = 0.05
    lags = np.arange(-max_lag, max_lag + 1e-9, step)
    m = np.array([misfit(x) for x in lags])
    j = int(np.argmin(m))
    lag = float(lags[j])
    if 0 < j < len(m) - 1:
        # Parabola through the minimum and its neighbours
        den = m[j - 1] - 2 * m[j] + m[j + 1]
        if den > 0:
            lag += step * 0.5 * (m[j - 1] - m[j + 1]) / den

    e = c - d
    return {'gain': float(abs(g)), 'angle_deg': float(np.angle(g, deg=True)), 'lag': lag,
            'rms': float(np.sqrt(np.mean(np.sum(e ** 2, axis=1)))),
            'rms_rel': float(np.sqrt(np.sum(e ** 2) / np.sum(d ** 2))),
            'corr_i': float(np.corrcoef(d[:, 0], c[:, 0])[0, 1]),
            'corr_q': float(np.corrcoef(d[:, 1], c[:, 1])[0, 1])}


def refine_calibration(soc, dataset, idx, cal, cfg, margin=20, trim_magnitude=False, debug=True):
    """
    Correct the calibration with replays of real traces.

    The amplitude and phase calibrations use a rectangle, which only has
    content at the carrier; the traces are broadband, and the loopback's
    response is not flat over +-150 MHz. Replays the shots idx, fits
    captured = g * data on each (replay_error, with data at 1/cal['nn_gain']
    of the recorded scale), and folds the mean g into cal['trim'] and the
    mean lag into cal['lead'].

    By default only the angle of g goes into the trim, not its magnitude.
    The fit weighs the whole band, and the DAC and ADC filters attenuate the
    traces' high-frequency noise, so |g| comes out below 1 even when the
    signal the NN responds to (mostly low frequency) has the right scale,
    which the rectangle calibration sets at the carrier: folding |g| in made
    the board logits ~15% too large on the testbench shots (2026-09-30).
    trim_magnitude=True folds it in too.

    Returns:
        tuple: The refined calibration (a new dict) and the replay_error of
            each shot before the correction.
    """
    f_dac, _, _ = gen_params(soc, cfg['gen_ch'])
    errs = []
    for i in idx:
        env, _ = trace_to_envelope(dataset, i, cal, soc, cfg['gen_ch'], margin)
        iq = acquire_trace(soc, dict(cfg, env=env))
        errs.append(replay_error(dataset.window(i) / cal.get('nn_gain', 1),
                                 iq[WINDOW_START:WINDOW_START + WINDOW_SIZE]))
    g = np.mean([e['gain'] * np.exp(1j * np.radians(e['angle_deg'])) for e in errs])
    lag = np.mean([e['lag'] for e in errs])
    new = dict(cal, trim=cal.get('trim', 1) / (g if trim_magnitude else g / abs(g)))
    lead = int(round(cal.get('lead', 0) - lag * f_dac / F_RO))
    if lead < 0:
        print('WARNING: the replay is {:.2f} samples late; it needs a later trigger '
              '(rerun align_timing), lead left at 0'.format(lag))
        lead = 0
    new['lead'] = lead
    if debug:
        print('INFO: replay of {} shots: gain {:.3f}, angle {:+.2f} deg, lag {:+.2f} samples, '
              'rms {:.1%} of the signal'.format(len(errs), abs(g), np.angle(g, deg=True), lag,
                                                np.mean([e['rms_rel'] for e in errs])))
        print('INFO: trim {:.3f} at {:+.2f} deg, lead {} -> {} DAC samples'.format(
            abs(new['trim']), np.angle(new['trim'], deg=True), cal.get('lead', 0), lead))
    return new, errs


# --- NN run -------------------------------------------------------------------

def run_shots(soc, dataset, idx, cal, cfg, margin=20, keep_traces=True, progress=True):
    """
    Replay the shots idx and read the NN logit of each.

    Reset the classifier before: the logit of the k-th shot is read from
    buffer slot (count before + k).

    Args:
        soc: The QickSoc.
        dataset (Dataset): The traces.
        idx: The shot indices.
        cal (dict): The calibration (see trace_to_envelope).
        cfg (dict): The program configuration; env is replaced.
        margin (int): As in trace_to_envelope.
        keep_traces (bool): Return the captured NN windows too.
        progress (bool): Print one character per shot, '.' when the prediction
            matches the label (or the reference logit's sign), '*' when not,
            'o' when there is nothing to compare with.

    Returns:
        dict: idx, logits, count (the NN's prediction count at the end),
            clipped (clipped envelope samples per shot), seconds, and
            windows (N x 400 x 2 captured samples 100-499) if keep_traces.
    """
    idx = np.asarray(idx)
    logits = np.zeros(len(idx))
    clipped = np.zeros(len(idx), int)
    windows = np.zeros((len(idx), WINDOW_SIZE, 2)) if keep_traces else None
    start = get_classifier_prediction_count()
    t0 = time.time()
    for k, i in enumerate(idx):
        env, clipped[k] = trace_to_envelope(dataset, i, cal, soc, cfg['gen_ch'], margin)
        iq = acquire_trace(soc, dict(cfg, env=env))
        if keep_traces:
            windows[k] = iq[WINDOW_START:WINDOW_START + WINDOW_SIZE]
        logits[k] = to_float(get_classifier_prediction(start + k)[0])
        if progress:
            if dataset.y is not None:
                c = '.' if (logits[k] >= 0) == bool(dataset.y[i]) else '*'
            elif dataset.ref_logits is not None:
                c = '.' if (logits[k] >= 0) == (dataset.ref_logits[i] >= 0) else '*'
            else:
                c = 'o'
            if k % 50 == 0:
                print('{:6d} '.format(k), end='')
            print(c, end='\n' if k % 50 == 49 or k == len(idx) - 1 else '')
    res = {'idx': idx, 'logits': logits, 'clipped': clipped,
           'count': get_classifier_prediction_count() - start,
           'seconds': time.time() - t0}
    if keep_traces:
        res['windows'] = windows
    return res


def score(dataset, res):
    """
    Score the NN run: accuracy, fidelity (2 * accuracy - 1) and per class
    accuracy against the labels, and agreement with the reference logits.
    Class 1 (excited) when the logit >= 0, as in the training notebook.

    Returns:
        dict: The figures that apply to the dataset.
    """
    pred = (res['logits'] >= 0).astype(int)
    out = {'n': len(pred)}
    if dataset.y is not None:
        y = dataset.y[res['idx']]
        acc = float((pred == y).mean())
        out.update(accuracy=acc, fidelity=2 * acc - 1,
                   accuracy_ground=float((pred[y == 0] == 0).mean()) if (y == 0).any() else None,
                   accuracy_excited=float((pred[y == 1] == 1).mean()) if (y == 1).any() else None)
    if dataset.ref_logits is not None:
        ref = dataset.ref_logits[res['idx']]
        out.update(sign_agreement=float((pred == (ref >= 0)).mean()),
                   logit_corr=float(np.corrcoef(ref, res['logits'])[0, 1]) if len(ref) > 1 else None)
    return out
