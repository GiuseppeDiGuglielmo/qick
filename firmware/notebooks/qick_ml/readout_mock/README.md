# Readout mock (tProc v2)

Replays recorded qubit readout traces through a DAC-to-ADC loopback, so the NN
classifier on the board (`l2_w400_ternary_h4_s100`, in `../ip/20240528/`)
scores real readout signals, and compares its on-board accuracy with the
offline one.

The traces are the QICK ZCU216 20240528 dataset the NN was trained on. Each
trace is resampled to the DAC rate and played as an arbitrary envelope, then
captured by readout 0, which feeds the NN. The notebook calibrates the replay
to match the recording (phase, I/Q orientation, sample timing and scale)
before the run. The loopback reaches only about a third of the dataset's
amplitude with an arbitrary envelope, so the replay runs at 1/g of the
recorded scale and the NN's input gain (its `scaling_factor` register, see
`../ip/README.md`) multiplies it back by g; the notebook picks the smallest g
of 1, 2, 4 and 8 that fits, 4 on the ZCU216 loopback.

This is the tProc v2 counterpart of the tProc v1 notebooks in
`qick_dev/qick_ml/readout_mock/` (`readout_mock_malab*.ipynb`). Those replayed
older ZCU111 traces (`readout_data.npy`) to an earlier NN with two logits, and
matched the scale with `ADC_fake_gain` and the NN's scaling factor, which the
current IP no longer has.

## Files

- `readout_mock.ipynb`: the experiment (bitstream, dataset, calibrations, NN
  run, results).
- `readout_mock_lib.py`: dataset loading, the replay program
  (`ArbPulseProgram`), trace-to-envelope resampling, the calibrations and the
  NN run. It reuses `../qick_ml_lib.py` (phase calibration, pulse edges,
  classifier helpers).
- `results/`: one `.npz` per run (gitignored).

## Dataset

By default the notebook replays 1000 shots of the test set (`N_SHOTS = 1000`,
500 per class, random with `SEED = 0`): `X_test_000_770.npy` (100,000 x
1540, samples 0-769 with I/Q interleaved) and `y_test_000_770.npy` (0 =
ground, 1 = excited). They are on the NAS at
`/nas/work/research/quantum/readout/data/qick_data/20240528/000_770/`, which
the board does not mount. The X file is float64 (1.2 GB); the notebook reads
an exact int16 copy of it (308 MB; the values are 14-bit integers). Make it on
a host that has the NAS and copy both files to the board:

    python3 -c "import numpy as np; \
        X = np.load('/nas/work/research/quantum/readout/data/qick_data/20240528/000_770/X_test_000_770.npy', mmap_mode='r'); \
        np.save('X_test_000_770_int16.npy', np.asarray(X).astype(np.int16))"
    ssh xilinx@<board> mkdir -p /home/xilinx/data/20240528/000_770
    scp X_test_000_770_int16.npy \
        /nas/work/research/quantum/readout/data/qick_data/20240528/000_770/y_test_000_770.npy \
        xilinx@<board>:/home/xilinx/data/20240528/000_770/

(On rfsoc216-ml01 they are there since 2026-09-30.) The notebook reads them
from `DATA_DIR` (`X_NAME` is the int16 file) and memory-maps them;
`N_SHOTS = None` replays all 100,000 (about 5.5 hours at 0.2 s per shot). The
checksums (`check_md5=True`) only match the original float64 file.

With `DATA_DIR = None` the notebook replays instead the 20 test shots of the
NN's HLS testbench, from `tb_data/` in
`../ip/20240528/two_layers_w400_ternary_h4_s100_20240528_hls4ml_prj.zip`, with
nothing to copy. They are the first and the last 10 shots of the test set.
They carry no labels and only samples 100-499, but they come with the exact
logits of the C simulation. A faithful replay reproduces those logits, so they
check the replay shot by shot.

`load_dataset` also accepts a window-only file (800 columns, samples 100-499),
e.g. `np.asarray(X[:, 200:1000]).astype(np.int16)`, set with `X_NAME`; the
replay then pads the 20-sample margins by mirroring the window instead of
using the recorded samples.

## Running

In Jupyter on the board, open `readout_mock.ipynb` and run all cells. It
loads `../216/<branch>/qick_216_tprocv2_dac<DAC>_nn.bit`, so the cabling is
the same as for `../send_receive_pulse.ipynb`. The calibration cells print
what they measure:

1. Amplitude: the readout magnitude a full-scale envelope reaches, and the
   NN input gain g that fits: the replay at 1/g must stay at or below it
   (the dataset's peak |IQ| is ~3500 ADC units; the loopback reaches ~1130,
   so g = 4). The notebook stops if even g = 8 falls short. Lowering the ADC
   attenuation or changing the carrier frequency can help.
2. Timing: the window's first sample on trace sample 100, to a fraction of a
   sample.
3. Phase and I/Q orientation.
4. Replay check: fit residuals on real traces. Gain and angle are folded back
   as a trim; the remaining RMS difference is what the DAC and ADC filters
   change.

The NN run replays one program per shot, 0.1-0.2 s each (0.2 s on tProc v2,
0.08-0.15 s on tProc v1), so the default 1000 shots take a few minutes.

## Expected results

With the test set, the offline reference is the C model: 96.014% accuracy,
92.028% fidelity on all 100,000 shots (`../nn_model_accuracy_check/`), and
96.20% on the default 1000 shots (seed 0). Measured on the ZCU216 on
2026-09-30 (nn builds, NN input gain 4), board against the C model on the
same shots:

| branch                         | shots | board          | C model |
|--------------------------------|-------|----------------|---------|
| `ml-integration-tproc-v2-2026` | 2000  | 96.15%, 96.30% | 96.15%  |
| `ml-integration-tproc-v1-2026` | 1000  | 96.40%         | 96.20%  |
| `ml-integration-2024`          | 1000  | 96.20%         | 96.20%  |

The board logits are 1.000-1.001 x the C model's (correlation 0.9995); the
few shots where the two disagree sit at the threshold (|logit| below ~12k,
against a typical ~370k), so they go either way from run to run. With the
testbench shots, the board logits should follow the C-simulation logits (the
notebook prints both, and their correlation); shot 4 (+11k) sits close to the
threshold.
