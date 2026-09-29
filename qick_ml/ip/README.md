# NN classifier IPs

Vivado IP-catalog zips of the hls4ml readout classifier (`xilinx.com:hls:NN_axi:1.0`),
added to the ZCU216 block design by the firmware build. Each zip has a `.log`
next to it with the HLS and post-synthesis resource estimates.

The zips are build products of the HLS projects in
[ml-quantum-readout](https://github.com/GiuseppeDiGuglielmo/ml-quantum-readout),
which does not track them, so they are kept here. Next to each IP there is also
a zip of the HLS project it was built from, used by the C-model accuracy check
in `qick_ml/nn_c_model_accuracy_check/`.

## Provenance

### 20240528/xilinx_com_hls_NN_axi_1_0_nonregistered_l2_w400_ternary_h4_s100.zip

| | |
|---|---|
| md5 | `8e7e8128f5134f96b2b5a9b530be4fe8` |
| Source repo | `git@github.com:GiuseppeDiGuglielmo/ml-quantum-readout.git`, branch `dev` |
| Source commit | `f2361c7` (2026-09-28), "Fix NN_axi window start" |
| HLS project | `hls_models/vivado_hls/two_layers_w400_ternary_h4_s100_20240528_hls4ml_prj/` |
| Model | dense 800 → 4 → 1 (400 I/Q samples in, one logit out), ternary weights, window starting at sample 100, trained on the 2024-05-28 dataset |
| Tool | Vivado HLS 2020.1.1 |
| Patched | no (no Floating-Point sub-cores; zip is the unmodified HLS export) |
| Part / clock | `xczu49dr-ffvf1760-2-e`, 3.0 ns target (1.813 ns after synthesis) |
| Resources (post-synthesis) | 29361 LUT (6.9%), 26447 FF (3.1%), 0 BRAM, 0 DSP |
| History | `f893fb1` (2024-10-30, md5 `f5986643...`): original IP. `ca2d146` (qick `4eafcd5f`): trigger read every cycle (`volatile`), one input sample per cycle, output index fix. `f2361c7` (qick `44dc7dc5`): exact window start. |

Interface:

- `in_V_V`: 32-bit AXI-Stream input (packed I/Q) from the readout
- `trigger`: starts a classification window
- `out_r`: BRAM port that writes predictions to an external BRAM
- `s_axi_config`: AXI-Lite registers
  - `window_size` 0x10
  - `window_offset` 0x18 (in samples: the window starts 5 + `window_offset`
    samples after the trigger; 95 puts it at trace sample 100)
  - `scaling_factor` 0x20
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
upgrade. Skip it for fixed-point-only models, which have no sub-cores to patch
(some HLS projects, like the one above, don't ship a `patch.sh`). Record in the
provenance entry whether the zip was patched.

The log comes from `profile.sh` on the HLS and export reports (the HLS
Makefile runs it); regenerate it after every rebuild. Copy the zip and the log
here as `<dataset date>/xilinx_com_hls_NN_axi_1_0_<variant>.{zip,log}`, then add
or update the provenance entry above. Also refresh the HLS project zip (see
above) so the C-model check matches the new IP.
