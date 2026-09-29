# NN C-model accuracy check

Scores the bit-exact C model of the NN classifier core (`NN()` from the HLS
project) on the full 20240528 test set, the same way the training notebook
(`workflow_800x4x1_ternary.ipynb`) scored the HLS model: samples 100-499
(I/Q interleaved), class 1 when the logit >= 0, fidelity = 2 * accuracy - 1.

The NN IP on the board computes the same logits as this C model (checked
bit-exact against ILA captures of NN_0's input and output), so this is the
accuracy of the deployed IP on inputs like the training data. It does not check
that the board's readout delivers inputs on the same scale as the dataset.

Runs on the host, not the board. The HLS project (sources, weights, testbench
outputs, `notes.json`) comes from its zip next to the IP,
`qick_ml/ip/20240528/two_layers_w400_ternary_h4_s100_20240528_hls4ml_prj.zip`
(see `qick_ml/ip/README.md`); the only outside input is the dataset on the NAS.

## Usage

    make          # unzip the HLS project into build/, build libnn_eval.so
    make run      # score the test set, write result.json and logits.npy
    make clean    # remove build/, the library and the results

The paths are Makefile variables (`PRJ_ZIP`, `DATA`, `PYTHON`), e.g.
`make run DATA=/path/to/20240528/000_770`. The project is unzipped again, and
the library rebuilt, when the zip changes.

The script checks the test set's md5 against the training notebook's, and the
first and last 10 logits against the HLS csim outputs in `tb_data/`.

## Sources

- HLS project (`NN.cpp`, headers, weights, `tb_data/`, `notes.json`): the zip
  in `qick_ml/ip/20240528/`, made from
  `hls_models/vivado_hls/two_layers_w400_ternary_h4_s100_20240528_hls4ml_prj/`
  of [ml-quantum-readout](https://github.com/GiuseppeDiGuglielmo/ml-quantum-readout)
  (`git@github.com:GiuseppeDiGuglielmo/ml-quantum-readout.git`), branch `dev`,
  commit `f2361c7`. `tb_data/` and `firmware/weights/*.txt` are gitignored
  there; the recipe is in `qick_ml/ip/README.md`.
- `nn_eval.cpp`: written for this repo. It calls `NN()` from the HLS project
  and returns the logit, so the C model is exactly the HLS core.
- `accuracy_check.py`: written for this repo. The scoring (samples 100-499,
  class 1 when the logit >= 0, fidelity = 2 * accuracy - 1) and the test set
  md5 checksums come from `notebooks/workflow_800x4x1_ternary.ipynb` in
  ml-quantum-readout.
- Dataset: `X_test_000_770.npy` and `y_test_000_770.npy` of the QICK ZCU216
  20240528 data, on the NAS at
  `/nas/work/research/quantum/readout/data/qick_data/20240528/000_770/`
  (not in git; described in `data/README.md` of ml-quantum-readout).

## Result (2026-09-29)

HLS project zip md5 `7e38e6df...` (ml-quantum-readout `f2361c7`, branch
`dev`), the source of the IP in `qick_ml/ip/20240528/` (md5 `8e7e8128...`).

| | accuracy | fidelity |
|---|---|---|
| C model, 100,000 test shots | 96.014% | 92.028% |
| HLS model (`notes.json`) | 96.014% | 92.028% |
| Keras model (`notes.json`) | 96.004% | 92.008% |

Per class: ground 97.49%, excited 94.54%. HLS testbench 20/20 equal.
