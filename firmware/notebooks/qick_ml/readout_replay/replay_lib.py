"""
Support library for the readout replay (tProc v2, REPLAY=1 builds).

The replay builds (firmware/projects/qick_tprocv2_216_standard_1ch/
proj_replay.tcl) put axis_readout_replay between the readout's decimated
output and the broadcaster that feeds the averager, the DDR buffer and the NN.
In replay mode it streams stored I/Q words from a BRAM after each readout
trigger, so the NN (and the averager) see recorded traces exactly as stored:
no DAC/ADC loopback, no scale, phase or timing to calibrate beyond one start
delay, and hundreds of shots per BRAM load.

Contents:
  - ReplayBuffer: the BRAM and the player's control registers (AXI GPIOs)
  - pack: N x L x 2 [I, Q] samples to BRAM words
  - TriggerProgram: a tProc v2 program that only triggers the readout
  - align: the start delay that puts BRAM word j on trace sample first + j
  - run_shots: replay dataset shots in batches and read one NN logit each

It reuses ../qick_ml_lib.py (classifier helpers) and
../readout_mock/readout_mock_lib.py (dataset loading and scoring, memory
report).
"""

import os
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
QICK_ML_DIR = os.path.abspath(os.path.join(HERE, '..'))
for d in (QICK_ML_DIR, os.path.join(QICK_ML_DIR, 'readout_mock')):
    if d not in sys.path:
        sys.path.insert(0, d)

from pynq import MMIO  # noqa: E402
from qick.asm_v2 import AveragerProgramV2  # noqa: E402
from qick_ml_lib import (reset_classifier, configure_classifier,  # noqa: E402
                         get_classifier_prediction_count, get_classifier_predictions,
                         to_float)

F_RO = 307.2          # MHz, decimated readout rate
WINDOW_START = 100    # first trace sample the NN sees (WINDOW_OFFSET 95)
WINDOW_SIZE = 400

# AXI GPIO registers (one 32-bit word per channel)
GPIO_DATA, GPIO2_DATA = 0x0, 0x8


def _find_ip(soc, name):
    """
    The ip_dict or mem_dict entry whose name ends with name (the blocks sit in
    readout_wrapper; PYNQ lists AXI BRAM controllers in mem_dict).
    """
    d = dict(soc.mem_dict)
    d.update(soc.ip_dict)
    hits = [k for k in d if k == name or k.endswith('/' + name)]
    if len(hits) != 1:
        raise RuntimeError('expected one IP named {} in this bitstream, found {}: '
                           'is it a REPLAY=1 build?'.format(name, hits))
    return d[hits[0]]


def pack(iq):
    """
    N x L x 2 (or L x 2) integer [I, Q] samples to 32-bit BRAM words, as the
    readout sends them: Q in bits 31:16, I in 15:0 (16-bit two's complement).
    """
    iq = np.asarray(iq).astype(np.int64)
    w = ((iq[..., 1] & 0xffff) << 16) | (iq[..., 0] & 0xffff)
    return w.astype(np.uint32).reshape(-1)


class ReplayBuffer:
    """
    The replay BRAM (replay_bram_ctrl_0) and the player's controls:
    replay_ctrl_0 ch1 = {index_reset, mode}, ch2 = {n_shots, shot_len};
    replay_ctrl_1 ch1 = start_delay, ch2 = status {busy, shot_index}.
    Set the controls while no shot plays.
    """
    def __init__(self, soc):
        b = _find_ip(soc, 'replay_bram_ctrl_0')
        c0 = _find_ip(soc, 'replay_ctrl_0')
        c1 = _find_ip(soc, 'replay_ctrl_1')
        self.bram = MMIO(b['phys_addr'], b['addr_range'])
        self.ctrl0 = MMIO(c0['phys_addr'], c0['addr_range'])
        self.ctrl1 = MMIO(c1['phys_addr'], c1['addr_range'])
        self.capacity = b['addr_range'] // 4      # words
        self.bram_addr = b['phys_addr']
        self._mode = 0

    def __repr__(self):
        return 'ReplayBuffer: {} words at 0x{:x}, mode {}, shot {} {}'.format(
            self.capacity, self.bram_addr, 'replay' if self._mode else 'live',
            self.shot_index, '(busy)' if self.busy else '')

    def load(self, words):
        """Write BRAM words from address 0."""
        words = np.asarray(words, dtype=np.uint32)
        if len(words) > self.capacity:
            raise ValueError('{} words do not fit the {}-word replay BRAM'.format(len(words), self.capacity))
        self.bram.array[:len(words)] = words

    def read(self, n, start=0):
        return np.array(self.bram.array[start:start + n], dtype=np.uint32)

    def configure(self, shot_len, n_shots, start_delay):
        if not (0 < shot_len < 65536 and 0 < n_shots < 65536 and 0 <= start_delay < 65536):
            raise ValueError('shot_len, n_shots and start_delay are 16-bit (shot_len, n_shots > 0)')
        if shot_len * n_shots > self.capacity:
            raise ValueError('{} shots of {} words do not fit {} words'.format(n_shots, shot_len, self.capacity))
        self.ctrl0.write(GPIO2_DATA, (n_shots << 16) | shot_len)
        self.ctrl1.write(GPIO_DATA, start_delay)

    def set_mode(self, replay):
        """True: replay the BRAM after each trigger; False: pass the live readout through."""
        self._mode = 1 if replay else 0
        self.ctrl0.write(GPIO_DATA, self._mode)

    def reset_index(self):
        """Back to shot 0 (index_reset held for a moment)."""
        self.ctrl0.write(GPIO_DATA, self._mode | 2)
        time.sleep(1e-3)
        self.ctrl0.write(GPIO_DATA, self._mode)

    @property
    def status(self):
        return self.ctrl1.read(GPIO2_DATA)

    @property
    def shot_index(self):
        return self.status & 0xffff

    @property
    def busy(self):
        return bool(self.status >> 31)


class TriggerProgram(AveragerProgramV2):
    """
    Trigger readout cfg['ro_ch'] (and the NN and the replay player, which share
    its trigger) once per repetition, without playing any pulse.
    cfg keys: ro_ch, ro_len (us).
    """
    def _initialize(self, cfg):
        self.declare_readout(ch=cfg['ro_ch'], length=cfg['ro_len'])

    def _body(self, cfg):
        self.trigger(ros=[cfg['ro_ch']], pins=[0], t=0)


def capture(soc, ro_ch=0, ro_len=2.5):
    """One readout trace (N x 2 int array), exactly as the averager received it."""
    prog = TriggerProgram(soc, reps=1, final_delay=1.0, cfg={'ro_ch': ro_ch, 'ro_len': ro_len})
    iq = prog.acquire_decimated(soc, rounds=1, progress=False, remove_offset=False)[0]
    return np.round(np.asarray(iq)).astype(np.int64)


def _ramp_start(tr, ramp):
    """The trace sample where the whole ramp sits, bit for bit and zeros around it, or None."""
    nz = np.flatnonzero(tr.any(axis=1))
    if len(nz) != len(ramp):
        return None
    p = int(nz[0])
    return p if np.array_equal(tr[p:p + len(ramp)], ramp) else None


def align(rb, soc, first=WINDOW_START, length=WINDOW_SIZE, ro_ch=0, n_capture=9, debug=True):
    """
    Find the start delay that puts BRAM word j on trace sample first + j.

    Replays a ramp (I = j + 1, Q = -(j + 1)) with start_delay 0 n_capture
    times, takes the trace sample p0 where it most often lands (the averager
    synchronizes the tProc trigger separately from the player, so some
    captures land one sample later or earlier; the NN and the player share one
    synchronized trigger and do not move relative to each other), sets
    start_delay = first - p0, and checks the ramp bit for bit on every capture.

    Returns:
        int: the start delay.
    """
    j = np.arange(length) + 1
    ramp = np.stack([j, -j], axis=1)
    rb.set_mode(True)
    rb.load(pack(ramp))
    ro_len = (first + length + 50) / F_RO

    def starts(delay):
        rb.configure(length, 1, delay)
        out = []
        for _ in range(n_capture):
            rb.reset_index()
            p = _ramp_start(capture(soc, ro_ch, ro_len=ro_len), ramp)
            if p is None:
                raise RuntimeError('the replayed ramp does not match the trace sample for sample: '
                                   'is the build a REPLAY=1 one?')
            out.append(p - delay)
        return out

    s0 = starts(0)
    p0 = max(set(s0), key=s0.count)
    delay = first - p0
    if delay < 0:
        raise RuntimeError('word 0 lands at trace sample {}, after the target {}'.format(p0, first))
    s1 = starts(delay)
    if max(abs(p - p0) for p in s0 + s1) > 1:
        raise RuntimeError('the ramp landed on trace samples {} (start_delay 0) and {} (start_delay {}): '
                           'more than one sample apart'.format(sorted(set(s0)), sorted(set(p + delay for p in s1)), delay))
    if debug:
        hits = sum(p == p0 for p in s0 + s1)
        print('INFO: ramp exact in all {} captures; word 0 on trace sample {} + start_delay in {} of them '
              '(the others one sample off, averager trigger sync); start_delay {} puts it on sample {}'.format(
                  len(s0 + s1), p0, hits, delay, first))
    return delay


def run_shots(rb, soc, windows, start_delay, window_offset=95, batch=None, ro_ch=0,
              trigger_period=5.0, progress=True):
    """
    Replay NN windows (N x 400 x 2 [I, Q], trace samples 100-499 of each shot)
    in batches that fill the BRAM, and read one NN logit per shot.

    Per batch: load the shots, reset the NN and the shot index, fire one
    readout trigger per shot (TriggerProgram, trigger_period us apart), then
    read the batch's logits.

    Returns:
        dict: logits (N), count (predictions registered), seconds.
    """
    windows = np.asarray(windows)
    n, length = windows.shape[0], windows.shape[1]
    batch = batch or min(n, rb.capacity // length)
    logits = np.zeros(n)
    count = 0
    t0 = time.time()
    rb.set_mode(True)
    for k0 in range(0, n, batch):
        w = windows[k0:k0 + batch]
        rb.load(pack(w))
        rb.configure(length, len(w), start_delay)
        rb.reset_index()
        reset_classifier()
        configure_classifier(WINDOW_SIZE, window_offset, 1)
        prog = TriggerProgram(soc, reps=len(w), final_delay=trigger_period, cfg={'ro_ch': ro_ch, 'ro_len': 0.1})
        prog.acquire(soc, rounds=1, progress=False)
        c = get_classifier_prediction_count()
        if c != len(w):
            raise RuntimeError('batch at shot {}: the NN registered {} of {} shots'.format(k0, c, len(w)))
        count += c
        logits[k0:k0 + len(w)] = [to_float(x) for x, _ in get_classifier_predictions(0, len(w) - 1)]
        if progress:
            print('  shots {:6d}-{:6d}: {} logits, {:.1f} s'.format(k0, k0 + len(w) - 1, c, time.time() - t0), flush=True)
    return {'logits': logits, 'count': count, 'seconds': time.time() - t0}
