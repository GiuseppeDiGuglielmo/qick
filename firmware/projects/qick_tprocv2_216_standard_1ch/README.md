# tProc v2 ZCU216, single channel

A ZCU216 design running **tProc v2**, derived from `../qick_tprocv2_216_standard` and
reduced to one channel so that implementation is fast and the design has room for ML blocks.

Build it with **Vivado 2023.1** — the version is fixed by the block design file name,
`bd_2023-1.tcl`. See [`../../tools/README.md`](../../tools/README.md) for the build flow.

## What differs from `qick_tprocv2_216_standard`

* **One channel instead of many.** 18 generators become a single `axis_signal_gen_v6`,
  12 readouts become a single `axis_dyn_readout_v1`, and 10 `axis_avg_buffer` instances
  become one. `axis_pfb_readout_v4`, `axis_sg_int4_v2` and `axis_sg_mixmux8_v1` are gone.
* **Hierarchies.** The flat block design is reorganized into `clk_rst_wrapper`,
  `signal_gen_wrapper` and `readout_wrapper`.
* **No `clk104_gpio`.** The CLK104 SPI mux GPIO was removed, so `PMOD1_0_LS` and the two
  `CLK104_CLK_SPI_MUX_SEL_LS` pins are commented out in `ios.xdc`.
* **Debug is part of the block design.** `debug_bridge_0` plus `system_ila_1/2/3` probe the
  `qick_processor_0` core, port, time and fifo debug buses. Every build therefore emits an
  LTX file alongside the bitstream.

## Build variants

The project scripts are layered. Each one sources the one below it and then edits the
in-memory block design, so `bd_2023-1.tcl` stays exactly as delivered:

```
proj_ila.tcl        ILA=1          adds the readout ILA
  └─ proj_dac.tcl   DAC=228|230    picks the generator's DAC
       └─ proj.tcl                 the design as delivered
```

Every combination builds into its own project directory, so all of them can exist side by
side:

| | DAC | ILA | project | `out/` name |
| --- | --- | --- | --- | --- |
| `make bitstream` | 228 | no | `top_dac228/` | `qick_216_tprocv2_dac228.*` |
| `make bitstream ILA=1` | 228 | yes | `top_dac228_ila/` | `qick_216_tprocv2_dac228_ila.*` |
| `make bitstream DAC=230` | 230 | no | `top_dac230/` | `qick_216_tprocv2_dac230.*` |
| `make bitstream DAC=230 ILA=1` | 230 | yes | `top_dac230_ila/` | `qick_216_tprocv2_dac230_ila.*` |

(run from `../../tools`). `system_ila_1/2/3` on the tProc debug buses are in every variant.

### Generator DAC: `proj_dac.tcl`

The delivered design drives its generator out of DAC tile 0 blk 0 (`0_228` on JHC1, QICK
box DAC port 0). The tProc v1 designs used DAC tile 2 blk 0 (`0_230` on JHC3, QICK box DAC
port 8), so a bench wired for them sees only noise on the readout with this design.
`DAC=230` moves the generator there instead of moving the cable:

* DAC tile 2 (slices 20-23) is put in the same full-rate direct mode as tile 0: no
  interpolation, 16-bit data, coarse mixer bypassed. `axis_signal_gen_v6` then runs at
  6881.28 Msps on the 430.08 MHz `clk_dac2`, as in the tProc v1 designs.
* `signal_gen_wrapper/m_axis` moves from the RF data converter's `s00_axis` to `s20_axis`.
* The generator side of `signal_gen_wrapper` moves from `clk_dac0`/`rst_dac0` to
  `clk_dac2`/`rst_dac2`. Its CDC input from the tProc was already on `clk_dac2`.

DAC tile 0 stays enabled and idle, so `timing.xdc` needs no change. After loading the
bitstream, `print(soc)` shows `DAC tile 2, blk 0 is 0_230 on JHC3, or QICK box DAC port 8`
with fs=6881.280 Msps and fabric=430.080 MHz. The envelope memory then holds 9.5 us instead
of 6.8 us. `DAC=228` is the default and leaves the block design as delivered; it only names the
build `_dac228`, so that every bitstream of this design says which DAC it drives.

### Readout ILA: `proj_ila.tcl`

`proj_ila.tcl` adds

* an AXI-Stream monitor, in "Data and Trigger" mode, on
  `readout_wrapper/axis_dyn_readout_v1_0_m1_axis` — the readout output feeding the averager
  buffer — clocked by `usp_rf_data_converter_0/clk_adc2`;
* a native probe on `qick_processor_0_trig_10_o`, the readout trigger on tProc port 10.

Vivado taps the stream through a new `Monitor`-mode port on `readout_wrapper`, so nothing in
the data path is altered. The block design already contains ILAs, so the script identifies
the one the debug automation adds rather than assuming a name, and fails loudly if the nets
it expects are not there.

These are the tProc v2 equivalents of what `ml-integration-tproc-v1-2026` probed
(`axis_readout_v2_0_m1_axis` and `vect2bits_16_0_dout8`).

`timing.xdc` is unchanged from `qick_tprocv2_216_standard`. `proj.tcl` differs only by the
optional `_xil_proj_name_suffix_`, which the layers above set to pick the project
directory; left unset, as when `proj.tcl` is run on its own, it builds the same `top/`
project as the original.

### Debug access

`debug_bridge_0` is configured with `C_DEBUG_MODE 2`, so the ILAs are reached over the AXI
debug bridge from the PS rather than over JTAG:

```sh
cd ../../tools && make hw-server        # or hw-server-tcl for no GUI
```

## Reference configuration

`README.txt` in this directory is the `print(soccfg)` dump of the bitstream this design was
validated with (QICK 0.2.371, built 2025-11-07). After loading a freshly built bitstream,
`print(soc)` should match it: one `axis_signal_gen_v6` generator on DAC tile 0 blk 0, one
`axis_dyn_readout_v1` readout on ADC tile 2 blk 0 triggered by tport 10, eight PMOD0 pins,
tProc v2 rev 28 at 200 MHz, plus the DDR4 and MR buffers. A `DAC=230` build differs only in
the generator: DAC tile 2 blk 0 (`0_230`) at fs=6881.280 Msps, fabric=430.080 MHz.

The dump was taken with QICK 0.2.371, so the version line and incidental wording will differ
from what a newer qick package prints. The channel counts, the IP names, the tProc revision
and the trigger and tile assignments are what must match.

## Software

The ML notebook and helper library from the tProc v1 branch
(`ml-integration-tproc-v1-2026`) are **not** on this branch: they are built on
`AveragerProgram`, which is tProc v1 only, and will not run against this firmware. Porting
them to the v2 API is follow-up work; `docs/source/tutorials/00_Getting_Started.ipynb` is
the v2 send/receive-pulse reference.
