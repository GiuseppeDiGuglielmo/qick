#!/usr/bin/env python3
"""
Check whether the NN classifier registers one prediction per pulse.

On the tProc v1 branches send_receive_pulse.ipynb once fired 10 pulses but the
NN count register read 3 (fixed by the NN trigger synchronizer and the NN IP
count fixes). This script repeats that flow with an NN build and prints the
count after every shot, to tell apart:

  - lock-up: the count climbs, then stops for good (even after out_reset)
  - misses:  the count skips shots at random but keeps climbing
  - rewind:  the count goes backwards (a negative step)

Phase A uses the notebook's program unchanged (trigger width 10 tProc timing
cycles, the tProc v2 default). Phase B reloads the bitstream and widens the
readout/NN trigger to --wide-width tProc timing cycles, to check whether the
trigger width matters: the NN samples its trigger only once every 5 clocks
while idle.

Ported from the tProc v1 branch (ml-integration-tproc-v1-2026) to the tProc v2
program (SinglePulseProgram in qick_ml_lib.py) and this branch's bitstream
names (qick_216_tprocv2_dac<DAC>_<build>.bit).

Each phase reloads the bitstream, so the NN starts from reset. This also
reprograms the FPGA under any open notebook kernel: re-run the notebook from
the bitstream cell afterwards.

Needs root, because QickSoc(bitfile=...) needs it. Run from the repo root as:

    sudo -E /usr/local/share/pynq-venv/bin/python3 firmware/notebooks/qick_ml/nn_count_check.py [--build nn_ila]

or, from a notebook cell (the kernel already runs as root):

    !/usr/local/share/pynq-venv/bin/python3 nn_count_check.py --build nn

Over ssh, run it in a login shell (bash -lc '...') so that BOARD is set.
"""
import argparse
import json
import os
import subprocess
import sys
import time

QICK_ML_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, QICK_ML_DIR)
# Use this repo's own qick_lib (it matches this branch's firmware) instead of
# whatever qick package is installed system-wide, as the notebook does
sys.path.insert(0, os.path.abspath(os.path.join(QICK_ML_DIR, '..', '..', '..', 'qick_lib')))

from qick import QickSoc  # noqa: E402  (path set up above)
import qick_ml_lib  # noqa: E402
from qick_ml_lib import (SinglePulseProgram, to_float, reset_classifier,  # noqa: E402
                         configure_classifier, get_classifier_prediction_count,
                         get_classifier_predictions)

DEFAULT_BUILD = 'nn'
DEFAULT_DAC = 230

# Same as the notebook's "Loopback pulse configuration" cell
CONFIG = {'gen_ch': 0, 'ro_ch': 0, 'freq': 250.0, 'pulse_len': 400 / 307.2,
          'phase': 0, 'gain': 3000 / 32766, 'trig_time': 0.12, 'ro_len': 2.5}
FINAL_DELAY = 1.0

# Same as the notebook's classifier setup cell
WINDOW_SIZE = 400
WINDOW_OFFSET = 95
SCALING_FACTOR = 1


class WideTriggerProgram(SinglePulseProgram):
    """SinglePulseProgram with a configurable readout/NN trigger width (us)."""
    def _body(self, cfg):
        self.pulse(ch=cfg['gen_ch'], name="my_pulse", t=0)
        self.trigger(ros=[cfg['ro_ch']], pins=[0], t=cfg['trig_time'], width=cfg['trig_width'])


def load_soc(bitfile):
    soc = QickSoc(bitfile=bitfile)
    if not (hasattr(soc, 'NN_0') and hasattr(soc, 'axi_blk_bram_ctrl_0')):
        raise RuntimeError('No NN in ' + bitfile)
    qick_ml_lib.set_soccfg(soc)
    reset_classifier(deep_reset=True, index_lo=0, index_hi=63)
    configure_classifier(WINDOW_SIZE, WINDOW_OFFSET, SCALING_FACTOR)
    return soc


def fire(soc, prog_cls, cfg, shots, label):
    """Fire `shots` pulses one program at a time, logging the NN count after each."""
    counts = []
    for i in range(shots):
        prog = prog_cls(soc, reps=1, final_delay=FINAL_DELAY, cfg=cfg)
        prog.acquire_decimated(soc, rounds=1, progress=False)
        time.sleep(0.001)  # NN latency is ~10 us; make sure it's done
        counts.append(get_classifier_prediction_count())
        print('  {} shot {:3d}: NN count = {}'.format(label, i, counts[-1]), flush=True)
    return counts


def summarize(counts, start):
    """Classify a count sequence that should go start+1, start+2, ..."""
    registered = counts[-1] - start
    steps = [b - a for a, b in zip([start] + counts[:-1], counts)]
    last_step = max((i for i, s in enumerate(steps) if s > 0), default=-1)
    stalled_after = None
    if registered < len(counts) and last_step < len(counts) - 1:
        stalled_after = last_step + 1  # shots registered before the count froze
    return {'shots': len(counts), 'registered': registered, 'steps': steps,
            'frozen_after_shot': stalled_after}


def run_phase(bitfile, prog_cls, cfg, shots, extra_shots, label, width_cycles):
    print('\n== Phase {}: {} shots, trigger width {} tProc timing cycles'.format(
        label, shots, width_cycles), flush=True)
    soc = load_soc(bitfile)
    if 'trig_width' in cfg:
        # The width is given in tProc timing cycles; the program takes microseconds
        cfg = dict(cfg, trig_width=soc.cycles2us(width_cycles))
    counts = fire(soc, prog_cls, cfg, shots, label)
    n = counts[-1]
    logits = [to_float(w) for w, _ in get_classifier_predictions(0, max(n, 1) - 1)] if n else []
    main = summarize(counts, 0)
    print('  -> registered {}/{}'.format(main['registered'], shots), flush=True)

    # Lock-up check: does the NN still count after out_reset?
    print('  out_reset, then {} more shots'.format(extra_shots), flush=True)
    reset_classifier()
    after = fire(soc, prog_cls, cfg, extra_shots, label + '+')
    post = summarize(after, 0)
    print('  -> registered {}/{} after out_reset'.format(post['registered'], extra_shots), flush=True)
    return {'trig_width': width_cycles, 'counts': counts, 'summary': main,
            'logits': logits, 'after_reset_counts': after, 'after_reset_summary': post}


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('--build', default=DEFAULT_BUILD, choices=['nn', 'nn_ila'])
    parser.add_argument('--dac', type=int, default=DEFAULT_DAC, choices=[228, 230],
                        help='Generator DAC of the build (default {})'.format(DEFAULT_DAC))
    parser.add_argument('--shots', type=int, default=30)
    parser.add_argument('--extra-shots', type=int, default=5)
    parser.add_argument('--wide-width', type=int, default=100,
                        help='Phase B trigger width in tProc timing cycles (default 100, ~233 ns)')
    parser.add_argument('--out', help='Results JSON (default: nn_count_check_<build>.json next to this script)')
    args = parser.parse_args()
    if args.out is None:
        args.out = os.path.join(QICK_ML_DIR, 'nn_count_check_{}.json'.format(args.build))

    branch = subprocess.getoutput('git -C {} rev-parse --abbrev-ref HEAD'.format(QICK_ML_DIR)).replace('/', '-')
    rev = subprocess.getoutput('git -C {} rev-parse --short HEAD'.format(QICK_ML_DIR))
    bitfile = os.path.join(QICK_ML_DIR, '216', branch,
                           'qick_216_tprocv2_dac{}_{}.bit'.format(args.dac, args.build))
    print('Bitstream: {} (git {})'.format(bitfile, rev), flush=True)

    results = {'build': args.build, 'dac': args.dac, 'bitfile': bitfile, 'git_rev': rev,
               'config': CONFIG, 'final_delay': FINAL_DELAY,
               'window': [WINDOW_SIZE, WINDOW_OFFSET, SCALING_FACTOR]}
    results['A'] = run_phase(bitfile, SinglePulseProgram, CONFIG, args.shots, args.extra_shots, 'A', 10)
    results['B'] = run_phase(bitfile, WideTriggerProgram, dict(CONFIG, trig_width=None),
                             args.shots, args.extra_shots, 'B', args.wide_width)

    with open(args.out, 'w') as f:
        json.dump(results, f, indent=1)
    os.chmod(args.out, 0o666)  # written as root; let the xilinx user read/replace it
    print('\nA: {}/{} registered, B (width {}): {}/{} registered'.format(
        results['A']['summary']['registered'], args.shots, args.wide_width,
        results['B']['summary']['registered'], args.shots))
    print('Results: ' + args.out)


if __name__ == '__main__':
    main()
