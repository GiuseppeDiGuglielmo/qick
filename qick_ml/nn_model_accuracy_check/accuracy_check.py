#!/usr/bin/env python3
"""
Accuracy of the bit-exact C model of the NN() core on the 20240528 test set.

The NN IP on the board computes the same logits as this C model (checked
bit-exact against ILA captures), so this is the accuracy of the deployed IP
on inputs like the training data. Scored as in the training notebook
(workflow_800x4x1_ternary.ipynb): samples 100-499 (columns 200:1000, I/Q
interleaved), class 1 when the logit >= 0, fidelity = 2 * accuracy - 1.

Runs on the host, not the board. Build the library and run with "make run";
see the Makefile for the paths.
"""
import argparse
import ctypes
import hashlib
import json
import os
import sys
import time

import numpy as np

# Checksums asserted by the training notebook
MD5_X = 'b7d85f42522a0a57e877422bc5947cde'
MD5_Y = '8c9cce1821372380371ade5f0ccfd4a2'
COLS = slice(200, 1000)  # samples 100-499, I/Q interleaved


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('--lib', default=os.path.join(here, 'libnn_eval.so'))
    parser.add_argument('--hls-prj', required=True, help='HLS project dir (tb_data/, notes.json)')
    parser.add_argument('--data', required=True, help='Dir with X_test_000_770.npy and y_test_000_770.npy')
    parser.add_argument('--limit', type=int, help='Score only the first N shots')
    parser.add_argument('--out', default=here, help='Dir for result.json and logits.npy')
    args = parser.parse_args()

    X = np.load(os.path.join(args.data, 'X_test_000_770.npy'))
    y = np.load(os.path.join(args.data, 'y_test_000_770.npy'))
    md5_ok = hashlib.md5(X).hexdigest() == MD5_X and hashlib.md5(y).hexdigest() == MD5_Y
    print('Test set: X {}, y {}, md5 {}'.format(X.shape, y.shape, 'OK' if md5_ok else 'MISMATCH'))

    # The core takes ap_fixed<14,14> inputs: the data must be 14-bit integers
    X = X[:, COLS]
    if np.any(X != np.round(X)) or X.min() < -8192 or X.max() > 8191:
        sys.exit('Inputs are not 14-bit integers')
    Xi = np.ascontiguousarray(X.astype(np.int32))
    del X

    lib = ctypes.CDLL(os.path.abspath(args.lib))
    lib.nn_eval.restype = ctypes.c_double
    lib.nn_eval.argtypes = [ctypes.POINTER(ctypes.c_int)]

    def logit(row):
        return lib.nn_eval(row.ctypes.data_as(ctypes.POINTER(ctypes.c_int)))

    # The HLS testbench holds the csim logits of the first and last 10 test shots
    tb = np.loadtxt(os.path.join(args.hls_prj, 'tb_data', 'tb_output_predictions.dat'))
    rows = list(range(10)) + list(range(len(Xi) - 10, len(Xi)))
    tb_equal = int(sum(logit(Xi[i]) == t for i, t in zip(rows, tb)))
    print('HLS testbench: {}/20 logits equal'.format(tb_equal))

    n = len(Xi) if args.limit is None else args.limit
    t0 = time.time()
    logits = np.array([logit(Xi[i]) for i in range(n)])
    pred = (logits >= 0).astype(int)
    y = y[:n]
    acc = float((pred == y).mean())
    res = {'n': n,
           'accuracy': acc,
           'fidelity': 2 * acc - 1,
           'accuracy_ground': float((pred[y == 0] == 0).mean()) if (y == 0).any() else None,
           'accuracy_excited': float((pred[y == 1] == 1).mean()) if (y == 1).any() else None,
           'md5_ok': md5_ok,
           'tb_equal': tb_equal,
           'training_notes': json.load(open(os.path.join(args.hls_prj, 'notes.json'))),
           'lib': os.path.abspath(args.lib),
           'hls_prj': args.hls_prj,
           'data': args.data,
           'seconds': round(time.time() - t0, 1)}
    print('Shots {}: accuracy {:.5f}, fidelity {:.5f} (HLS notes.json: {:.5f} / {:.5f})'.format(
        n, acc, 2 * acc - 1, res['training_notes']['HLS Acc'], res['training_notes']['HLS Fidelity']))
    print('Per class: ground {}, excited {}'.format(res['accuracy_ground'], res['accuracy_excited']))

    np.save(os.path.join(args.out, 'logits.npy'), logits)
    with open(os.path.join(args.out, 'result.json'), 'w') as f:
        json.dump(res, f, indent=1)
    print('Results:', os.path.join(args.out, 'result.json'))


if __name__ == '__main__':
    main()
