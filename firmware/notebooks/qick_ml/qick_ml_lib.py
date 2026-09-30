"""
Support library for the send-receive-pulse ZCU216/QICK experiment (tProc v2).

Provides the QICK program that plays a single constant pulse and captures the
loopback ADC trace (SinglePulseProgram, from
docs/source/tutorials/01_Basic_Sequencing.ipynb), a couple of numeric
formatting helpers for dumping I/Q samples as hex (float_to_hex32,
int_to_twos_complement_hex32), a pulse edge finder for setting the loopback
timing (pulse_edges), a loopback phase calibration (measure_phase,
calibrate_phase), and a set of MMIO-based helpers for driving the
FPGA-resident NN classifier that scores each pulse (reset_classifier,
configure_classifier, get_classifier_prediction_count,
get_classifier_prediction, get_classifier_predictions,
print_classifier_buffer).

The classifier and phase calibration helpers are ported from the tProc v1
branch (ml-integration-tproc-v1-2026). The classifier helpers talk to the
classifier IP over MMIO, independent of which tProc version generated the
pulse; the phase calibration is rewritten for the tProc v2 program.

Call set_soccfg() once with the QickSoc/QickConfig handle before using any
classifier helper.
"""

from ctypes import *
import struct

import numpy as np
from pynq import MMIO
from qick.asm_v2 import AveragerProgramV2

# QickSoc/QickConfig handle the classifier helpers read/write through.
soccfg = None


def set_soccfg(sc):
    """
    Register the QickSoc/QickConfig instance the classifier helpers should use.

    Args:
        sc: The QickSoc/QickConfig instance (the notebook's `soccfg`).
    """
    global soccfg
    soccfg = sc


# Single constant pulse and readout, as in "A Simple Single-Pulse Program" of
# docs/source/tutorials/01_Basic_Sequencing.ipynb
class SinglePulseProgram(AveragerProgramV2):
    """
    Play one constant pulse on a generator and capture the decimated I/Q trace
    on a readout, for a DAC-to-ADC loopback measurement.

    cfg keys: gen_ch, ro_ch, freq (MHz), pulse_len (us), phase (deg), gain
    (-1 to 1), trig_time (us, readout trigger after the pulse start), ro_len
    (us).
    """
    def _initialize(self, cfg):
        # Declare the generator and readout channels
        self.declare_gen(ch=cfg['gen_ch'], nqz=1)  # nqz=1 means no frequency folding
        self.declare_readout(ch=cfg['ro_ch'], length=cfg['ro_len'])

        # Define a constant pulse (no envelope shaping)
        self.add_pulse(
            ch=cfg['gen_ch'],
            name="my_pulse",
            style="const",           # Constant amplitude
            freq=cfg['freq'],        # Frequency in MHz
            length=cfg['pulse_len'], # Duration in microseconds
            phase=cfg['phase'],      # Phase in degrees
            gain=cfg['gain']         # Amplitude (0 to 1)
        )

        # Configure the readout
        self.add_readoutconfig(
            ch=cfg['ro_ch'],
            name="my_ro",
            freq=cfg['freq'],
            gen_ch=cfg['gen_ch']
        )
        self.send_readoutconfig(ch=cfg['ro_ch'], name="my_ro", t=0)

    def _body(self, cfg):
        # Play the pulse at time t=0
        self.pulse(ch=cfg['gen_ch'], name="my_pulse", t=0)
        # Trigger the readout
        self.trigger(ros=[cfg['ro_ch']], pins=[0], t=cfg['trig_time'])


def float_to_hex32(f):
    """Pack a Python float into its IEEE-754 32b representation, as an 8-digit hex string."""
    return format(struct.unpack('!I', struct.pack('!f', f))[0], '08x')


def int_to_twos_complement_hex32(n):
    """Encode a signed int as its 32b two's-complement value, as an 8-digit hex string."""
    # If the number is negative, get its two's complement
    if n < 0:
        n = (1 << 32) + n  # "Wrap around" to get 32-bit two's complement
    return format(n, '08x')


# --- Pulse timing -----------------------------------------------------------
# The NN window covers trace samples 100-499 (WINDOW_OFFSET 95 in the
# notebook), and the NN was trained on pulses that fill it. The loopback pulse
# must land on those samples; its position depends on the DAC-to-ADC latency
# of the design, so it is measured on the board and trig_time corrected.

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


# --- Phase calibration ------------------------------------------------------
# The DAC-to-ADC loopback phase changes on every bitstream load, and the NN
# logit follows it (its sign flips at ~180 deg). Rotating the generator phase
# (the pulse's phase) so the pulse always reaches the ADC at the same phase
# makes the logits repeatable across loads. This is a single-frequency version
# of the QICK phase calibration in qick_demos/01_Phase_coherent_readout.ipynb,
# ported from the tProc v1 branch.

def _wrap_deg(deg):
    """Wrap an angle in degrees to [-180, 180)."""
    return (deg + 180.0) % 360.0 - 180.0


def measure_phase(soc, config, n=2, prog_cls=SinglePulseProgram):
    """
    Measure the phase of the loopback pulse at the ADC.

    Fires n pulses with prog_cls. For each, I and Q are averaged over the pulse
    plateau (the samples above half the peak magnitude) of the readout trace.

    Args:
        soc: The QickSoc instance.
        config (dict): The program configuration, including phase.
        n (int): The number of pulses to average over.
        prog_cls: The program class; it must take config as cfg, play one
            pulse and read one trace (see SinglePulseProgram).

    Returns:
        float: The circular mean phase in degrees, in [-180, 180).
    """
    z = 0
    for _ in range(n):
        prog = prog_cls(soc, reps=1, final_delay=0.5, cfg=config)
        iq = prog.acquire_decimated(soc, rounds=1, progress=False)[0]
        i, q = np.asarray(iq[:, 0], float), np.asarray(iq[:, 1], float)
        on = np.hypot(i, q) > 0.5 * np.hypot(i, q).max()
        z += np.exp(1j * np.arctan2(q[on].mean(), i[on].mean()))
    return _wrap_deg(np.angle(z, deg=True))


def calibrate_phase(soc, config, target_deg=60.0, n=2, tol_deg=10.0, tol_fine_deg=0.1,
                    max_passes=5, debug=True, prog_cls=SinglePulseProgram):
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
        prog_cls: The program class (see measure_phase).

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


# --- Classifier helpers -----------------------------------------------------
# Drive the NN classifier IP that scores each readout pulse: its config
# registers (window size/offset, scaling factor, reset) sit behind
# soccfg.NN_0.mmio, and its prediction (logit) output is read back through
# soccfg.axi_blk_bram_ctrl_0 (see the design's proj_nn.tcl). Ported from the
# tProc v1 branch: this is pure MMIO/register access and does not depend on
# which tProc version generated the pulse.

def to_float(w):
    """
    Convert a 32b memory word to a floating-point number using ctypes.

    Args:
        w (int): The 32b word to convert.

    Returns:
        float: The converted floating-point number.
    """
    cp = pointer(c_int(w))
    fp = cast(cp, POINTER(c_float))
    return fp.contents.value


def reset_classifier(deep_reset=False, index_lo=0, index_hi=0):
    """
    Reset the classifier. Optionally perform a deep reset.

    Args:
        deep_reset (bool): If True, perform a deep reset by setting specific memory locations to zero. Default is False.
        index_lo (int): The lower index for the deep reset range. Default is 0.
        index_hi (int): The upper index for the deep reset range. Default is 0.
    """
    RESET_HI = 255
    RESET_LO = 0
    # Access the MMIO interface of the classifier
    mmio_nn = MMIO(soccfg.NN_0.mmio.base_addr, soccfg.NN_0.mmio.length)
    # This sends a "reset pulse" to the classifier
    mmio_nn.write(soccfg.NN_0.register_map.out_reset.address, RESET_HI)
    mmio_nn.write(soccfg.NN_0.register_map.out_reset.address, RESET_LO)
    if deep_reset:
        # Perform a deep reset by setting specific memory locations to zero
        # Warning: This may run for a long time; use only for debugging
        print('WARNING: Deep reset may run for some time... use only for debugging')
        entry_count = ((index_hi - index_lo) + 1) * 2
        for i in range(index_lo * 2, index_lo * 2 + entry_count):
            soccfg.axi_blk_bram_ctrl_0.mmio.array[i] = 0


def configure_classifier(window_size, window_offset, scaling_factor, debug=False):
    """
    Configure the classifier with the specified parameters.

    Args:
        window_size (int): The size of the window for classification.
        window_offset (int): The offset of the window for classification.
        scaling_factor (int): The scaling factor for classification.
        debug (bool): If True, print debug information. Default is False.
    """
    if debug:
        # Print debug information about the classifier configuration
        print('INFO: classifier MMIO')
        print('INFO:   - base address:   @{:08x}'.format(soccfg.NN_0.mmio.base_addr))
        print('INFO:   - window_size:    @{:04x} = {}'.format(soccfg.NN_0.register_map.window_size.address, window_size))
        print('INFO:   - window_offset:  @{:04x} = {}'.format(soccfg.NN_0.register_map.window_offset.address, window_offset))
        print('INFO:   - scaling_factor: @{:04x} = {}'.format(soccfg.NN_0.register_map.scaling_factor.address, scaling_factor))
    # Access the MMIO interface of the classifier and configure it
    mmio_nn = MMIO(soccfg.NN_0.mmio.base_addr, soccfg.NN_0.mmio.length)
    mmio_nn.write(soccfg.NN_0.register_map.window_size.address, window_size)
    mmio_nn.write(soccfg.NN_0.register_map.window_offset.address, window_offset)
    mmio_nn.write(soccfg.NN_0.register_map.scaling_factor.address, scaling_factor)


def get_classifier_prediction_count():
    """
    Get how many predictions (pulses) have run through the classifier. This is 0 at the very beginning or if you reset the classifier.

    Returns:
        int: The number of predictions made by the classifier.
    """
    # Access the MMIO interface of the classifier
    mmio_nn = MMIO(soccfg.NN_0.mmio.base_addr, soccfg.NN_0.mmio.length)
    # Read and return the prediction count
    prediction_count = mmio_nn.read(soccfg.NN_0.register_map.out_offset.address)
    return prediction_count


def get_classifier_prediction(index=0):
    """
    Get the classifier prediction for a specific index of the buffer.

    Args:
        index (int): The index of the prediction to retrieve. Default is 0.

    Each prediction takes a 2-word slot. The current NN IP has a single output:
    the logit is in the first word and the second word is never written (0).

    Returns:
        tuple: The logit word and the unused word, both as raw 32b words.
    """
    WORD_SIZE_BYTE = 4
    WORD_COUNT_PER_PREDICTION = 2
    # Access the MMIO interface of the BRAM
    mmio_bram = MMIO(soccfg.axi_blk_bram_ctrl_0.base_address, soccfg.axi_blk_bram_ctrl_0.size)
    # Read the logit word and the unused word of the slot
    logit_word = mmio_bram.read(index * WORD_COUNT_PER_PREDICTION * WORD_SIZE_BYTE + 0)
    unused_word = mmio_bram.read(index * WORD_COUNT_PER_PREDICTION * WORD_SIZE_BYTE + WORD_SIZE_BYTE)
    return logit_word, unused_word


def get_classifier_predictions(index_lo=0, index_hi=0):
    """
    Get a range of classifier predictions from the buffer.

    Args:
        index_lo (int): The lower index of the range of predictions to retrieve. Default is 0.
        index_hi (int): The upper index of the range of predictions to retrieve. Default is 0.

    Returns:
        list: A list of [logit word, unused word] pairs (see get_classifier_prediction).
    """
    WORD_SIZE_BYTE = 4
    WORD_COUNT_PER_PREDICTION = 2
    # Access the MMIO interface of the BRAM
    mmio_bram = MMIO(soccfg.axi_blk_bram_ctrl_0.base_address, soccfg.axi_blk_bram_ctrl_0.size)
    # TODO: You can read the whole memory area rather than one element at a time and append
    predictions = []
    for index in range(index_lo, index_hi + 1):
        logit_word = mmio_bram.read(index * WORD_COUNT_PER_PREDICTION * WORD_SIZE_BYTE + 0)
        unused_word = mmio_bram.read(index * WORD_COUNT_PER_PREDICTION * WORD_SIZE_BYTE + WORD_SIZE_BYTE)
        predictions.append([logit_word, unused_word])
    return predictions


def print_classifier_buffer(index_lo, index_hi):
    """
    Print the classifier buffer for a range of indices.

    Args:
        index_lo (int): The lower index of the range to print.
        index_hi (int): The upper index of the range to print.
    """
    # Get the prediction count and buffer size
    prediction_count = get_classifier_prediction_count()
    buffer_size = len(soccfg.axi_blk_bram_ctrl_0.mmio.array)
    print('INFO: buffer index : {:6}'.format(prediction_count))
    print('INFO: buffer size  : {:6} ({:6}KB)'.format(buffer_size, (buffer_size * 4) / 1024))
    print('INFO:')
    print('INFO: <<< marks the next slot to be written; logit >= 0 means excited')
    print('INFO:')
    for i in range(index_lo, index_hi + 1):
        # Only the logit word is written by the NN IP; the second word of the slot stays 0
        logit_word, unused_word = get_classifier_prediction(i)
        state = 'excited' if to_float(logit_word) >= 0 else 'ground'
        if i >= prediction_count:
            state = '(empty)'
        print('INFO: [{:5d}] logit {:08x} ({}) {:8} (unused {:08x}) {}'.format(
            i, logit_word, to_float(logit_word), state, unused_word,
            '<<<' if prediction_count == i else ''))
