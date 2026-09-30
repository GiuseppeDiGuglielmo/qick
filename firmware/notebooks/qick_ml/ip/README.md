# NN classifier IPs

Vivado IP-catalog zips of the hls4ml readout classifier (`xilinx.com:hls:NN_axi:1.0`),
added to the ZCU216 tProc v2 block design by the NN build layer
(`firmware/projects/qick_tprocv2_216_standard_1ch/proj_nn.tcl`, built with
`make bitstream NN=1` in `firmware/tools`). Each zip has a `.log` next to it
with the HLS and post-synthesis resource estimates.

The zips are build products of the HLS projects in
[ml-quantum-readout](https://github.com/GiuseppeDiGuglielmo/ml-quantum-readout),
which does not track them, so they are kept here. Next to each IP there is also
a zip of the HLS project it was built from, used by the NN accuracy check
in `firmware/notebooks/qick_ml/nn_model_accuracy_check/`.

## Provenance

### 20240528/xilinx_com_hls_NN_axi_1_0_nonregistered_l2_w400_ternary_h4_s100.zip

| | |
|---|---|
| md5 | `b6b173a94ec75848b567d9d6d15d2298` |
| Source repo | `git@github.com:GiuseppeDiGuglielmo/ml-quantum-readout.git`, branch `nn-axi-input-gain` (from `dev`) |
| Source commit | `74402e3` (2026-09-30), "Use scaling_factor as NN input gain" (on `f2361c7`) |
| HLS project | `hls_models/vivado_hls/two_layers_w400_ternary_h4_s100_20240528_hls4ml_prj/` |
| Model | dense 800 → 4 → 1 (400 I/Q samples in, one logit out), ternary weights, window starting at sample 100, trained on the 2024-05-28 dataset |
| Tool | Vivado HLS 2020.1.1 |
| Patched | no (no Floating-Point sub-cores; zip is the unmodified HLS export) |
| Part / clock | `xczu49dr-ffvf1760-2-e`, 3.0 ns target (1.813 ns after synthesis) |
| Resources (post-synthesis) | 29387 LUT (6.9%), 26457 FF (3.1%), 0 BRAM, 0 DSP (`8e7e8128`: 29361 LUT, 26447 FF) |
| History | `f893fb1` (2024-10-30, md5 `f5986643...`): original IP. `ca2d146` (qick `4eafcd5f`): trigger read every cycle (`volatile`), one input sample per cycle, output index fix. `f2361c7` (qick `44dc7dc5`, md5 `8e7e8128...`): exact window start. `nn-axi-input-gain` (md5 `b6b173a9...`): `scaling_factor` is an input gain. |

Interface:

- `in_V_V`: 32-bit AXI-Stream input (packed I/Q) from the readout
- `trigger`: starts a classification window
- `out_r`: BRAM port that writes predictions to an external BRAM
- `s_axi_config`: AXI-Lite registers
  - `window_size` 0x10
  - `window_offset` 0x18 (in samples: the window starts 5 + `window_offset`
    samples after the trigger; 95 puts it at trace sample 100)
  - `scaling_factor` 0x20 (input gain, since md5 `b6b173a9...`: every I
    and Q sample is shifted left by log2 of the gain before it enters the
    window; the gain is a power of two, 1, 2, 4 or 8, from bits 3:0: other
    values round down, 9-15 give 8, and 0, the value after reset, gives 1.
    The NN keeps the low 14 bits of the product, as it always kept bits
    13:0 of each sample, so a product that does not fit wraps around. It is
    re-read while the IP waits for a trigger, so a new value applies to the
    next window. With gain 1 the IP is bit-exact with `8e7e8128...`, and the
    timing from the trigger to the window and to the BRAM write is the same)
  - `out_reset` 0x28
  - `out_offset` 0x30 (read-only prediction count)

### 20240528/two_layers_w400_ternary_h4_s100_20240528_hls4ml_prj.zip

The HLS project the IP above was built from.

| | |
|---|---|
| md5 | `7e38e6df6b63bc849fe397d3a9934864` |
| Source commit | `f2361c7`, same as the IP |
| Contents | the project's tracked files at that commit, plus two sets that ml-quantum-readout gitignores: `tb_data/*` (csim inputs and outputs of 20 test shots) and `firmware/weights/*.txt` (the weights `NN()` loads in C simulation; same values as the `weights/*.h` arrays used for synthesis) |

Made with (`<prj>` = `two_layers_w400_ternary_h4_s100_20240528_hls4ml_prj`,
in a checkout of ml-quantum-readout at `f2361c7`):

    git archive --format=zip --prefix=<prj>/ f2361c7:hls_models/vivado_hls/<prj> -o <prj>.zip
    cd hls_models/vivado_hls && zip -X <abs path>/<prj>.zip <prj>/tb_data/* <prj>/firmware/weights/*.txt

(`tb_data/` comes from the training notebook and C simulation, the `.txt`
weights from hls4ml when it writes the project; neither is in git.)

## Rebuilding an IP

In the HLS project directory of ml-quantum-readout (needs Vivado HLS 2020.1):

    make hls

This runs `vivado_hls -f build_prj.tcl` and writes the IP to
`NN_prj/solution1/impl/ip/xilinx_com_hls_NN_axi_1_0.zip` and the resource
summary to `xilinx_com_hls_NN_axi_1_0.log`.

If the exported IP contains Floating-Point v7.1 sub-cores
(`*_ap_fpext_*_no_dsp_32.vhd`, pulled in by models that convert from float),
also run:

    make patch

This runs `patch.sh`, which bumps those sub-cores from revision `v7_1_10` to
`v7_1_11` inside the zip so that Vivado 2022.1 accepts them without an IP
upgrade (this branch builds with Vivado 2023.1; check whether it still needs
the patch). Skip it for fixed-point-only models, which have no sub-cores to
patch (some HLS projects, like the one above, don't ship a `patch.sh`). Record
in the provenance entry whether the zip was patched.

The log comes from `profile.sh` on the HLS and export reports (the HLS
Makefile runs it); regenerate it after every rebuild. Copy the zip and the log
here as `<dataset date>/xilinx_com_hls_NN_axi_1_0_<variant>.{zip,log}`, then add
or update the provenance entry above. Also refresh the HLS project zip (see
above) so the C-model check matches the new IP.
