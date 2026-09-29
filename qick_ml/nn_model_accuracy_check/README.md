# NN model accuracy check

Two checks of the NN classifier on the 20240528 test set, both on the host:

1. **C model** (`make run`): scores the bit-exact C model of the NN core
   (`NN()` from the HLS project) on the whole test set, the same way the
   training notebook (`workflow_800x4x1_ternary.ipynb`) scored the HLS model:
   samples 100-499 (I/Q interleaved), class 1 when the logit >= 0,
   fidelity = 2 * accuracy - 1.
2. **RTL** (`make rtl`): simulates the RTL of the NN IP (`NN_axi`, the Verilog
   in the IP zip) with Icarus Verilog on a sample of the shots and compares
   every logit with the C model's, exactly.

The C model is the HLS core itself, and the RTL is what the board runs (the
board IP also matched the C model bit for bit on ILA captures of NN_0's input
and output). Together they give the accuracy of the deployed IP on inputs like
the training data. They do not check that the board's readout delivers inputs
on the same scale as the dataset.

Runs on the host, not the board. The HLS project (sources, weights, testbench
outputs, `notes.json`) comes from its zip next to the IP,
`qick_ml/ip/20240528/two_layers_w400_ternary_h4_s100_20240528_hls4ml_prj.zip`,
and the RTL from the IP zip
`qick_ml/ip/20240528/xilinx_com_hls_NN_axi_1_0_nonregistered_l2_w400_ternary_h4_s100.zip`
(see `qick_ml/ip/README.md`). The only outside input is the dataset on the NAS;
the RTL check also needs `iverilog`.

## Usage

    make          # unzip the HLS project into build/, build libnn_eval.so
    make run      # C model on the full test set, write result.json and logits.npy
    make rtl      # RTL vs the C model on a sample, write rtl_result.json
    make clean    # remove build/, the library and the results
    make help     # list the targets and variables

The paths are Makefile variables (`PRJ_ZIP`, `IP_ZIP`, `DATA`, `PYTHON`), e.g.
`make run DATA=/path/to/20240528/000_770`. The zips are unzipped again, and the
library rebuilt, when they change.

`make run` checks the test set's md5 against the training notebook's, and the
first and last 10 logits against the HLS csim outputs in `tb_data/`.

`make rtl` needs `logits.npy` (it runs `make run` if it is missing). It
simulates the first 20 shots (the HLS testbench shots), `SHOTS` random shots
balanced over the classes (default 1000), the `WRONG` shots the C model
misclassifies (100) and the `NEAR` shots closest to the decision threshold
(100), split over `JOBS` parallel simulations (20). `make rtl ALL=1` simulates
every test shot. With 20 or more simulations in parallel a shot costs about
one core-second, so the default 1,213 shots take about a minute and all
100,000 about 87 minutes on 22 cores (measured). It exits with an error if any
logit differs, the latency changes, or the testbench reports a problem.

`tb_nn_axi.v` configures the IP over AXI-Lite (window_size 400, window_offset
0, scaling_factor 1), pulses the trigger, streams the shot's 400 packed I/Q
samples (Q in bits 29:16, I in 13:0) and prints the BRAM write, a float32 word
holding the integer logit. The sample source advances only on a
TVALID & TREADY handshake, so this checks trigger, load, compute and output;
it does not model the timing against the free-running ADC stream or a nonzero
window_offset (the board ILA measurements cover those).

## Sources

- HLS project (`NN.cpp`, headers, weights, `tb_data/`, `notes.json`): the zip
  in `qick_ml/ip/20240528/`, made from
  `hls_models/vivado_hls/two_layers_w400_ternary_h4_s100_20240528_hls4ml_prj/`
  of [ml-quantum-readout](https://github.com/GiuseppeDiGuglielmo/ml-quantum-readout)
  (`git@github.com:GiuseppeDiGuglielmo/ml-quantum-readout.git`), branch `dev`,
  commit `f2361c7`. `tb_data/` and `firmware/weights/*.txt` are gitignored
  there; the recipe is in `qick_ml/ip/README.md`.
- RTL: `hdl/verilog/` of the NN IP zip, the export of the same HLS project.
- `nn_eval.cpp`: written for this repo. It calls `NN()` from the HLS project
  and returns the logit, so the C model is exactly the HLS core.
- `accuracy_check.py`: written for this repo. The scoring (samples 100-499,
  class 1 when the logit >= 0, fidelity = 2 * accuracy - 1) and the test set
  md5 checksums come from `notebooks/workflow_800x4x1_ternary.ipynb` in
  ml-quantum-readout.
- `tb_nn_axi.v`, `rtl_check.py`: written for this repo, from the `NN_axi`
  interface (`NN_axi.cpp` in the HLS project, `NN_axi.v` in the IP).
- Dataset: `X_test_000_770.npy` and `y_test_000_770.npy` of the QICK ZCU216
  20240528 data, on the NAS at
  `/nas/work/research/quantum/readout/data/qick_data/20240528/000_770/`
  (not in git; described in `data/README.md` of ml-quantum-readout).

## Result (2026-09-29)

HLS project zip md5 `7e38e6df...` (ml-quantum-readout `f2361c7`, branch
`dev`), the source of the IP in `qick_ml/ip/20240528/` (md5 `8e7e8128...`).

C model:

| | accuracy | fidelity |
|---|---|---|
| C model, 100,000 test shots | 96.014% | 92.028% |
| HLS model (`notes.json`) | 96.014% | 92.028% |
| Keras model (`notes.json`) | 96.004% | 92.008% |

Per class: ground 97.49%, excited 94.54%. HLS testbench 20/20 equal.

RTL (`make rtl`, defaults): 1,213 shots (591 ground, 622 excited, including
the misclassified and threshold-nearest ones), all 1,213 logits exactly equal
to the C model's, 429 cycles from trigger to BRAM write on every shot, 62 s on
20 cores. A corrupted C-model logit (one count off) is caught.

RTL on all 100,000 test shots (`make rtl ALL=1 JOBS=22`, 5,207 s): every one of
the 100,000 logits (50,000 ground, 50,000 excited) is exactly equal to the C
model's, 429 cycles from trigger to BRAM write on every shot, so the RTL
scores the same 96.014% accuracy / 92.028% fidelity. This covers the RTL of the
IP zip (`hdl/verilog/`) as a whole, not only the NN() core, over the entire
test set; it does not cover the free-running ADC stream timing or a nonzero
window_offset (see above).
