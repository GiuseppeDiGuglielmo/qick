#!/usr/bin/env python3
"""
Check whether the NN classifier registers one prediction per pulse.

send_receive_pulse.ipynb fired 10 pulses but the NN count register read 3.
This script repeats that flow with the NN build and prints the count after
every shot, to tell apart:

  - lock-up: the count climbs, then stops for good (even after out_reset)
  - misses:  the count skips shots at random but keeps climbing
  - rewind:  the count goes backwards (a negative step)

Phase A uses the notebook's program unchanged (trigger width 10 tProc cycles).
Phase B reloads the bitstream and widens the readout/NN trigger to
--wide-width tProc cycles, to check whether the trigger width matters: the NN
samples its trigger only once every 5 clocks while idle.

Each phase reloads the bitstream, so the NN starts from reset. This also
reprograms the FPGA under any open notebook kernel: re-run the notebook from
the bitstream cell afterwards.

Needs root, because QickSoc(bitfile=...) needs it. Run from the repo root as:

    sudo -E /usr/local/share/pynq-venv/bin/python3 qick_ml/nn_count_check.py [--build nn_ila]

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
sys.path.insert(0, os.path.join(os.path.dirname(QICK_ML_DIR), 'qick_lib'))

from qick import QickSoc  # noqa: E402  (path set up above)
import qick_ml_lib  # noqa: E402
from qick_ml_lib import (LoopbackProgram, to_float, reset_classifier,  # noqa: E402
                         configure_classifier, get_classifier_prediction_count,
                         get_classifier_predictions)

DEFAULT_BUILD = 'nn'

# Same as the notebook's "Loopback pulse configuration" cell
CONFIG = {"res_ch": 0, "ro_chs": [0], "reps": 1, "relax_delay": 1.0,
          "res_phase": 0, "pulse_style": "const", "length": 560,
          "readout_length": 770, "pulse_gain": 3000, "pulse_freq": 250,
          "adc_trig_offset": 45, "soft_avgs": 1}

# Same as the notebook's classifier setup cell
WINDOW_SIZE = 400
WINDOW_OFFSET = 95
SCALING_FACTOR = 1


class WideTriggerProgram(LoopbackProgram):
    """LoopbackProgram with a configurable readout/NN trigger width."""
    def body(self):
        # Same as measure(..., wait=True, syncdelay=...), with the trigger width exposed
        self.trigger(adcs=self.ro_chs, pins=[0],
                     adc_trig_offset=self.cfg["adc_trig_offset"],
                     width=self.cfg["trig_width"])
        self.pulse(ch=self.cfg["res_ch"], t='auto')
        self.wait_all()
        self.sync_all(self.us2cycles(self.cfg["relax_delay"]))


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
        prog_cls(soc, cfg).acquire_decimated(soc, progress=False)
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


def run_phase(bitfile, prog_cls, cfg, shots, extra_shots, label):
    print('\n== Phase {}: {} shots, trigger width {} tProc cycles'.format(
        label, shots, cfg.get('trig_width', 10)), flush=True)
    soc = load_soc(bitfile)
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
    return {'trig_width': cfg.get('trig_width', 10), 'counts': counts, 'summary': main,
            'logits': logits, 'after_reset_counts': after, 'after_reset_summary': post}


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('--build', default=DEFAULT_BUILD, choices=['nn', 'nn_ila'])
    parser.add_argument('--shots', type=int, default=30)
    parser.add_argument('--extra-shots', type=int, default=5)
    parser.add_argument('--wide-width', type=int, default=100,
                        help='Phase B trigger width in tProc cycles (default 100, ~233 ns)')
    parser.add_argument('--out', help='Results JSON (default: nn_count_check_<build>.json next to this script)')
    args = parser.parse_args()
    if args.out is None:
        args.out = os.path.join(QICK_ML_DIR, 'nn_count_check_{}.json'.format(args.build))

    branch = subprocess.getoutput('git -C {} rev-parse --abbrev-ref HEAD'.format(QICK_ML_DIR)).replace('/', '-')
    rev = subprocess.getoutput('git -C {} rev-parse --short HEAD'.format(QICK_ML_DIR))
    bitfile = os.path.join(QICK_ML_DIR, '216', branch, 'qick_216_{}.bit'.format(args.build))
    print('Bitstream: {} (git {})'.format(bitfile, rev), flush=True)

    results = {'build': args.build, 'bitfile': bitfile, 'git_rev': rev, 'config': CONFIG,
               'window': [WINDOW_SIZE, WINDOW_OFFSET, SCALING_FACTOR]}
    results['A'] = run_phase(bitfile, LoopbackProgram, CONFIG, args.shots, args.extra_shots, 'A')
    results['B'] = run_phase(bitfile, WideTriggerProgram, dict(CONFIG, trig_width=args.wide_width),
                             args.shots, args.extra_shots, 'B')

    with open(args.out, 'w') as f:
        json.dump(results, f, indent=1)
    os.chmod(args.out, 0o666)  # written as root; let the xilinx user read/replace it
    print('\nA: {}/{} registered, B (width {}): {}/{} registered'.format(
        results['A']['summary']['registered'], args.shots, args.wide_width,
        results['B']['summary']['registered'], args.shots))
    print('Results: ' + args.out)


if __name__ == '__main__':
    main()
