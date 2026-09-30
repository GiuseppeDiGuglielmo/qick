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

By default (`DATA_DIR = None`) the notebook replays the 20 test shots of the
NN's HLS testbench, from `tb_data/` in
`../ip/20240528/two_layers_w400_ternary_h4_s100_20240528_hls4ml_prj.zip`. They
are the first and the last 10 shots of the test set. They carry no labels and
only samples 100-499, but they come with the exact logits of the C
simulation. A faithful replay reproduces those logits, so they check the replay
shot by shot without anything else to copy.

The accuracy needs the test set: `X_test_000_770.npy` (100,000 x 1540,
samples 0-769 with I/Q interleaved) and `y_test_000_770.npy` (0 = ground,
1 = excited). They are on the NAS at
`/nas/work/research/quantum/readout/data/qick_data/20240528/000_770/`, which
the board does not mount. Copy them from a host that has the NAS:

    scp /nas/work/research/quantum/readout/data/qick_data/20240528/000_770/{X,y}_test_000_770.npy \
        xilinx@<board>:/home/xilinx/data/20240528/000_770/

and set `DATA_DIR = '/home/xilinx/data/20240528/000_770'`. The notebook
memory-maps the files, and `N_SHOTS` picks a balanced random subset. To copy
less, keep only the NN window (samples 100-499) as int16, on the host:

    python3 -c "import numpy as np; X = np.load('X_test_000_770.npy', mmap_mode='r'); \
        np.save('X_test_w100_500.npy', np.asarray(X[:, 200:1000]).astype(np.int16))"

and in the notebook call `rm.load_dataset(DATA_DIR, x_name='X_test_w100_500.npy')`.
`load_dataset` accepts this 800-column form. The replay then pads the
20-sample margins on each side by mirroring the window instead of using the
recorded samples. Keep the full file if you can; the checksums
(`check_md5=True`) only match the original.

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

The NN run replays one program per shot. Its speed shows in the run cell;
measure it on the 20 testbench shots before choosing `N_SHOTS` for the test
set.

## Expected results

With the testbench shots, the board logits should follow the C-simulation
logits (the notebook prints both, and their correlation). Shot 4 (+11k) sits
close to the threshold. With the test set, the offline reference is the C
model on all 100,000 shots: 96.014% accuracy, 92.028% fidelity
(`qick_ml/nn_model_accuracy_check/` on the `ml-integration-tproc-v1-2026`
branch). The replay is not perfect, so expect the board to score somewhat
lower.
