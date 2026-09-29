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

## Result (2026-09-29)

HLS project zip md5 `7e38e6df...` (ml-quantum-readout `f2361c7`, branch
`dev`), the source of the IP in `qick_ml/ip/20240528/` (md5 `8e7e8128...`).

| | accuracy | fidelity |
|---|---|---|
| C model, 100,000 test shots | 96.014% | 92.028% |
| HLS model (`notes.json`) | 96.014% | 92.028% |
| Keras model (`notes.json`) | 96.004% | 92.008% |

Per class: ground 97.49%, excited 94.54%. HLS testbench 20/20 equal.
