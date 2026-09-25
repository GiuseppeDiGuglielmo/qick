# NN classifier IPs

Vivado IP-catalog zips of the hls4ml readout classifier (`xilinx.com:hls:NN_axi:1.0`),
added to the ZCU216 block design by the firmware build. Each zip has a `.log`
next to it with the HLS and post-synthesis resource estimates.

The zips are build products of the HLS projects in
[ml-quantum-readout](https://github.com/GiuseppeDiGuglielmo/ml-quantum-readout),
which does not track them, so they are kept here.

## Provenance

### 20240528/xilinx_com_hls_NN_axi_1_0_nonregistered_l2_w400_ternary_h4_s100.zip

| | |
|---|---|
| md5 | `f59866434d570a96438ed136b754d052` |
| Source repo | `git@github.com:GiuseppeDiGuglielmo/ml-quantum-readout.git`, branch `dev` |
| Source commit | `f893fb1` (2024-10-30) |
| HLS project | `hls_models/vivado_hls/two_layers_w400_ternary_h4_s100_20240528_hls4ml_prj/` |
| Model | dense 800 → 4 → 1 (400 I/Q samples in, one logit out), ternary weights, window starting at sample 100, trained on the 2024-05-28 dataset |
| Tool | Vivado HLS 2020.1.1 |
| Patched | no (no Floating-Point sub-cores; zip is the unmodified HLS export) |
| Part / clock | `xczu49dr-ffvf1760-2-e`, 3.0 ns target (1.72 ns estimated after synthesis) |
| Resources (post-synthesis) | 68635 LUT (16.1%), 37151 FF (4.4%), 0 BRAM, 0 DSP |

Interface:

- `in_V_V`: 32-bit AXI-Stream input (packed I/Q) from the readout
- `trigger`: starts a classification window
- `out_r`: BRAM port that writes predictions to an external BRAM
- `s_axi_config`: AXI-Lite registers
  - `window_size` 0x10
  - `window_offset` 0x18
  - `scaling_factor` 0x20
  - `out_reset` 0x28
  - `out_offset` 0x30 (read-only prediction count)

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

Copy the zip and the log here as
`<dataset date>/xilinx_com_hls_NN_axi_1_0_<variant>.{zip,log}`, then add a
provenance entry above.
