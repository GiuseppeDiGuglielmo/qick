#!/usr/bin/env python3
"""
Board side of the NN ILA capture: load qick_216_nn_ila.bit once, then fire
one shot each time the host creates <dir>/go_<i>, and log the NN count after
it. <dir>/ready means the bitstream is loaded; <dir>/done_<i> means shot i
was fired. Needs root and the pynq login environment.
"""
import argparse
import json
import os
import time

from nn_phase_check import (CONFIG, WINDOW_SIZE, WINDOW_OFFSET, SCALING_FACTOR, REPO_QICK_ML,
                            pulse_iq, QickSoc, qick_ml_lib, LoopbackProgram, to_float,
                            reset_classifier, configure_classifier,
                            get_classifier_prediction_count, get_classifier_prediction)

BITFILE = os.path.join(REPO_QICK_ML, '216', 'ml-integration-2024', 'qick_216_nn_ila.bit')


def touch(path):
    open(path, 'w').close()
    os.chmod(path, 0o666)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--shots', type=int, default=20)
    ap.add_argument('--dir', default='/tmp/nn_ila_bug3')
    ap.add_argument('--timeout', type=float, default=300.0)
    ap.add_argument('--window-offset', type=int, default=WINDOW_OFFSET)
    args = ap.parse_args()

    soc = QickSoc(bitfile=BITFILE)
    qick_ml_lib.set_soccfg(soc)
    reset_classifier(deep_reset=True, index_lo=0, index_hi=args.shots - 1)
    configure_classifier(WINDOW_SIZE, args.window_offset, SCALING_FACTOR)
    touch(os.path.join(args.dir, 'ready'))
    print('READY ' + BITFILE + ' window_offset {}'.format(args.window_offset), flush=True)

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
        count = get_classifier_prediction_count()
        row = dict(pulse_iq(iq), shot=i, count=count, registered=count == prev + 1, logit=None,
                   i=[float(v) for v in iq[0]], q=[float(v) for v in iq[1]],
                   time=time.time())
        if row['registered']:
            row['logit'] = to_float(get_classifier_prediction(prev)[0])
        prev = count
        rows.append(row)
        print('SHOT {:2d} count {:2d} registered {} phase {:6.1f}'.format(
            i, count, row['registered'], row['phase_deg']), flush=True)
        touch(os.path.join(args.dir, 'done_{}'.format(i)))

    out = os.path.join(args.dir, 'shots.json')
    with open(out, 'w') as f:
        json.dump(rows, f, indent=1)
    os.chmod(out, 0o666)
    print('DONE ' + out, flush=True)


if __name__ == '__main__':
    main()
