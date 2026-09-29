#!/usr/bin/env python3
"""
Compare the RTL of the NN IP with the C model on shots of the 20240528 test set.

Simulates NN_axi (the Verilog in the IP zip) with Icarus Verilog, several
shards in parallel, and compares each simulated logit with the C model's
logit for the same shot (logits.npy, written by accuracy_check.py). The RTL
writes the logit as a float32 word; the values are integers, so the
comparison is exact.

Shots simulated: the first 20 (the HLS testbench shots), --random N shots
balanced over the two classes, the --wrong K shots the C model misclassifies,
and the --near K shots whose logit is closest to the decision threshold, or
all of them with --all.

Run from this directory with "make rtl"; see the Makefile for the paths.
"""
import argparse
import hashlib
import json
import os
import struct
import subprocess
import sys
import time

import numpy as np

COLS = slice(200, 1000)  # samples 100-499, I/Q interleaved
SAMPLES = 400
LATENCY = 429  # cycles from the trigger to the BRAM write, seen on 20/20 shots


def select(y, logits, args):
    rng = np.random.default_rng(args.seed)
    n = len(y)
    if args.all:
        return np.arange(n)
    picked = set(range(20))
    per = args.random // 2
    for c in (0, 1):
        picked.update(rng.choice(np.flatnonzero(y == c), size=per, replace=False).tolist())
    wrong = np.flatnonzero((logits >= 0).astype(int) != y)
    picked.update(rng.choice(wrong, size=min(args.wrong, len(wrong)), replace=False).tolist())
    picked.update(np.argsort(np.abs(logits))[:args.near].tolist())
    return np.array(sorted(picked))


def pack(rows):
    """Packed 32-bit stream words (Q in [29:16], I in [13:0]) as hex lines."""
    i = rows[:, 0::2].astype(np.int64) & 0x3fff
    q = rows[:, 1::2].astype(np.int64) & 0x3fff
    return '\n'.join('{:08x}'.format(w) for w in ((q << 16) | i).ravel()) + '\n'


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('--ip-rtl', required=True, help='Dir with the IP Verilog (hdl/verilog)')
    p.add_argument('--data', required=True, help='Dir with X_test_000_770.npy and y_test_000_770.npy')
    p.add_argument('--logits', default=os.path.join(here, 'logits.npy'), help='C-model logits (accuracy_check.py)')
    p.add_argument('--work', default=os.path.join(here, 'build', 'rtl'), help='Dir for the simulations')
    p.add_argument('--out', default=os.path.join(here, 'rtl_result.json'))
    p.add_argument('--random', type=int, default=1000, help='Random shots, half per class')
    p.add_argument('--wrong', type=int, default=100, help='Misclassified shots')
    p.add_argument('--near', type=int, default=100, help='Shots nearest the threshold')
    p.add_argument('--all', action='store_true', help='Simulate every test shot')
    p.add_argument('--jobs', type=int, default=20, help='Parallel simulations')
    p.add_argument('--seed', type=int, default=1)
    args = p.parse_args()

    X = np.load(os.path.join(args.data, 'X_test_000_770.npy'), mmap_mode='r')
    y = np.load(os.path.join(args.data, 'y_test_000_770.npy'))
    logits = np.load(args.logits)
    if len(logits) != len(y):
        sys.exit('logits.npy has {} shots, the test set {}: run "make run"'.format(len(logits), len(y)))
    idx = select(y, logits, args)
    print('Simulating {} shots on {} jobs'.format(len(idx), args.jobs), flush=True)

    os.makedirs(args.work, exist_ok=True)
    shards = [s for s in np.array_split(idx, min(args.jobs, len(idx))) if len(s)]
    maxshots = max(len(s) for s in shards)
    args.work = os.path.abspath(args.work)
    sim = os.path.join(args.work, 'sim')
    srcs = [os.path.join(args.ip_rtl, f) for f in sorted(os.listdir(args.ip_rtl)) if f.endswith('.v')]
    tb = os.path.join(here, 'tb_nn_axi.v')
    subprocess.check_call(['iverilog', '-g2012', '-P', 'tb_nn_axi.MAXSHOTS={}'.format(maxshots),
                           '-o', sim, tb] + srcs)

    t0 = time.time()
    procs = []
    for n, s in enumerate(shards):
        rows = np.asarray(X[s][:, COLS])
        if np.any(rows != np.round(rows)) or rows.min() < -8192 or rows.max() > 8191:
            sys.exit('Inputs are not 14-bit integers')
        hexf = os.path.join(args.work, 'shard{}.hex'.format(n))
        with open(hexf, 'w') as f:
            f.write(pack(rows))
            f.write('00000000\n' * ((maxshots - len(s)) * SAMPLES))  # pad to the size of the memory
        out = open(os.path.join(args.work, 'shard{}.out'.format(n)), 'w')
        procs.append((subprocess.Popen(['vvp', '-n', sim, '+hex=' + os.path.basename(hexf),
                                        '+nshots={}'.format(len(s))], stdout=out, stderr=subprocess.STDOUT,
                                       cwd=args.work), out))
    for pr, out in procs:
        pr.wait()
        out.close()

    got = np.full(len(idx), np.nan)
    latency, counts, bad = [], [], []
    pos = 0
    for n, s in enumerate(shards):
        text = open(os.path.join(args.work, 'shard{}.out'.format(n))).read().splitlines()
        errors = [l for l in text if 'ERROR' in l or 'TIMEOUT' in l or 'WARNING' in l]
        if errors:
            sys.exit('shard {}: {} (see {}/shard{}.out)'.format(n, errors[0], args.work, n))
        w = [l for l in text if l.startswith('W ')]
        lat = [int(l.split('latency_cycles=')[1].split()[0]) for l in text if l.startswith('S ')]
        cnt = [int(l.split('= ')[1]) for l in text if l.startswith('count register')]
        if len(w) != len(s) or len(lat) != len(s) or cnt != [len(s)]:
            sys.exit('shard {}: {} writes, {} shots done, count {} for {} shots (see {}/shard{}.out)'.format(
                n, len(w), len(lat), cnt, len(s), args.work, n))
        for k, line in enumerate(w):
            data = line.split('data=')[1]
            if 'x' in data or 'z' in data:
                sys.exit('shard {}: unknown logit bits {} (see {}/shard{}.out)'.format(n, data, args.work, n))
            word = int(data, 16)
            got[pos + k] = struct.unpack('!f', struct.pack('!I', word))[0]
        latency += lat
        counts += cnt
        pos += len(s)

    ref = logits[idx]
    equal = got == ref
    for i in np.flatnonzero(~equal):
        bad.append({'shot': int(idx[i]), 'rtl': float(got[i]), 'c_model': float(ref[i]), 'label': int(y[idx[i]])})
    cls_rtl = (got >= 0).astype(int)
    res = {'shots': int(len(idx)), 'equal_to_c_model': int(equal.sum()), 'mismatches': bad[:50],
           'rtl_accuracy': float((cls_rtl == y[idx]).mean()),
           'c_model_accuracy': float(((ref >= 0).astype(int) == y[idx]).mean()),
           'classes': {'ground': int((y[idx] == 0).sum()), 'excited': int((y[idx] == 1).sum())},
           'latency_cycles': sorted(set(latency)), 'expected_latency': LATENCY,
           'jobs': len(shards), 'seconds': round(time.time() - t0, 1),
           'ip_rtl_md5': hashlib.md5(b''.join(open(s, 'rb').read() for s in srcs)).hexdigest(),
           'seed': args.seed}
    print('RTL == C model on {}/{} shots (ground {}, excited {}); latency cycles {}; {} s'.format(
        res['equal_to_c_model'], res['shots'], res['classes']['ground'], res['classes']['excited'],
        res['latency_cycles'], res['seconds']))
    print('Accuracy on these shots: RTL {:.5f}, C model {:.5f}'.format(res['rtl_accuracy'], res['c_model_accuracy']))
    json.dump(res, open(args.out, 'w'), indent=1)
    print('Results:', args.out)
    if bad:
        print('MISMATCHES:', bad[:5])
        sys.exit(1)


if __name__ == '__main__':
    main()
