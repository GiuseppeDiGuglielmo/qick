#!/usr/bin/env python3
"""
Board side of the ILA capture: load qick_216_<build>.bit once, then fire one
loopback shot each time the host creates <dir>/go_<i>, and log the NN count
after it (NN builds only). <dir>/ready means the bitstream is loaded;
<dir>/done_<i> means shot i was fired.

Run it from the board's checkout of this repo: the bitstream is taken from
qick_ml/216/<branch>/, the qick driver from this repo's qick_lib, and the pulse
and window settings from qick_ml/nn_count_check.py. Needs root and the pynq
login environment.
"""
import argparse
import json
import os
import subprocess
import sys
import time

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
QICK_ML_DIR = os.path.join(REPO, 'qick_ml')
sys.path.insert(0, QICK_ML_DIR)
# Use this repo's own qick_lib (it matches this branch's firmware) instead of
# whatever qick package is installed system-wide
sys.path.insert(0, os.path.join(REPO, 'qick_lib'))

import numpy as np  # noqa: E402
import qick  # noqa: E402
from qick import QickSoc  # noqa: E402
import qick_ml_lib  # noqa: E402
from qick_ml_lib import (LoopbackProgram, to_float, reset_classifier,  # noqa: E402
                         configure_classifier, get_classifier_prediction_count,
                         get_classifier_prediction)
from nn_count_check import CONFIG, WINDOW_SIZE, WINDOW_OFFSET, SCALING_FACTOR  # noqa: E402


def touch(path):
    open(path, 'w').close()
    os.chmod(path, 0o666)


def pulse_iq(iq):
    """Phase, amplitude and plateau of the loopback pulse in a decimated trace.

    The plateau is the set of samples with |I + jQ| above half of the peak (as
    in qick_ml_lib.measure_phase), amp the mean |I + jQ| over it, phase_deg the
    angle of (mean I + j mean Q) over it, and plateau [first, last] sample.
    """
    i, q = np.asarray(iq[0], float), np.asarray(iq[1], float)
    mag = np.hypot(i, q)
    idx = np.nonzero(mag > mag.max() / 2)[0]
    return dict(phase_deg=float(np.degrees(np.arctan2(q[idx].mean(), i[idx].mean()))),
                amp=float(mag[idx].mean()), plateau=[int(idx[0]), int(idx[-1])])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--build', default='nn_ila', choices=['nn_ila', 'orig_ila', 'nn_replay_ila'])
    ap.add_argument('--shots', type=int, default=20)
    ap.add_argument('--dir', default='/tmp/ila_capture')
    ap.add_argument('--timeout', type=float, default=300.0)
    ap.add_argument('--window-offset', type=int, default=WINDOW_OFFSET)
    args = ap.parse_args()

    branch = subprocess.getoutput('git -C {} rev-parse --abbrev-ref HEAD'.format(REPO)).replace('/', '-')
    bitfile = os.path.join(QICK_ML_DIR, '216', branch, 'qick_216_{}.bit'.format(args.build))
    soc = QickSoc(bitfile=bitfile)
    has_nn = hasattr(soc, 'NN_0')
    if has_nn:
        qick_ml_lib.set_soccfg(soc)
        reset_classifier(deep_reset=True, index_lo=0, index_hi=args.shots - 1)
        configure_classifier(WINDOW_SIZE, args.window_offset, SCALING_FACTOR)
    touch(os.path.join(args.dir, 'ready'))
    print('READY {} (NN: {}, qick from {}) window_offset {}'.format(
        bitfile, has_nn, os.path.dirname(qick.__file__), args.window_offset), flush=True)

    rows, prev = [], 0
    for i in range(args.shots):
        go = os.path.join(args.dir, 'go_{}'.format(i))
        t0 = time.time()
        while not os.path.exists(go):
            if time.time() - t0 > args.timeout:
                print('TIMEOUT waiting for ' + go, flush=True)
                return
            time.sleep(0.05)
        iq = LoopbackProgram(soc, CONFIG).acquire_decimated(soc, progress=False)[0]
        time.sleep(0.001)
        row = dict(pulse_iq(iq), shot=i, logit=None,
                   i=[float(v) for v in iq[0]], q=[float(v) for v in iq[1]],
                   time=time.time())
        if has_nn:
            count = get_classifier_prediction_count()
            row.update(count=count, registered=count == prev + 1)
            if row['registered']:
                row['logit'] = to_float(get_classifier_prediction(prev)[0])
            prev = count
        rows.append(row)
        print('SHOT {:2d} phase {:6.1f} logit {}'.format(i, row['phase_deg'], row['logit']), flush=True)
        touch(os.path.join(args.dir, 'done_{}'.format(i)))

    out = os.path.join(args.dir, 'shots.json')
    with open(out, 'w') as f:
        json.dump(rows, f, indent=1)
    os.chmod(out, 0o666)
    print('DONE ' + out, flush=True)


if __name__ == '__main__':
    main()
