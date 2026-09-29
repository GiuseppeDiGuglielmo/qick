import os, sys; CAP = sys.argv[1]
import csv, json, struct, ctypes, numpy as np
lib = ctypes.CDLL(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'libnn_eval.so')); lib.nn_eval.restype = ctypes.c_double
P = 'd_1_i/system_ila_0/inst/'
def s14(v): v &= 0x3fff; return v - 0x4000 if v & 0x2000 else v
shots = json.load(open(CAP + '/shots.json'))
for k in range(len(shots)):
    r = list(csv.reader(open(CAP + '/shot_%d.csv' % k))); h = r[0]; d = r[2:]
    col = lambda n: [x[h.index(P + n)] for x in d]
    trg = [int(v, 16) for v in col('probe1_1')]
    raw = [int(v, 16) for v in col('probe0_1')]
    td = [int(v, 16) for v in col('net_slot_0_axis_tdata[31:0]')]
    we = [int(v, 16) for v in col('SLOT_1_BRAM_we_1[3:0]')]
    din = [int(v, 16) for v in col('SLOT_1_BRAM_din_1[31:0]')]
    addr = [int(v, 16) for v in col('SLOT_1_BRAM_addr_1[31:0]')]
    t0 = next(i for i in range(1, len(trg)) if trg[i] and not trg[i-1])
    r0 = next(i for i in range(1, len(raw)) if raw[i] and not raw[i-1])
    w = [i for i in range(len(we)) if we[i]]
    hw = struct.unpack('>f', struct.pack('>I', din[w[0]]))[0]
    I = np.array([s14(v) for v in td]); Q = np.array([s14(v >> 16) for v in td])
    x = np.empty(2 * len(td), int); x[0::2] = I; x[1::2] = Q
    m = []
    for s in range(t0 - 400, len(td) - 400):
        if s < 0: continue
        a = (ctypes.c_int * 800)(*x[2*s:2*s+800])
        if lib.nn_eval(a) == hw: m.append(s - t0)
    # software trace alignment: first I sample of the decimated trace in tdata
    ti = np.array(shots[k]['i']); tq = np.array(shots[k]['q'])
    best = None
    for s in range(0, len(td) - len(ti)):
        c = np.abs(I[s:s+len(ti)] - ti).sum() + np.abs(Q[s:s+len(tq)] - tq).sum()
        if best is None or c < best[0]: best = (c, s)
    print('shot %d: raw trig %d, NN trig %d (+%d), write at +%d addr %d, hw logit %.0f, board logit %.0f' % (
        k, r0, t0, t0 - r0, w[0] - t0, addr[w[0]], hw, shots[k]['logit']))
    print('   exact matches (window start, cycles after NN trig):', m[:10], '...' if len(m) > 10 else '')
    print('   decimated trace sample 0 at tdata +%d cycles after NN trig (L1 err %.1f)' % (best[1] - t0, best[0]))
