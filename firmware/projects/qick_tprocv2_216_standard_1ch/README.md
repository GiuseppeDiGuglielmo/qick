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

`proj.tcl` and `timing.xdc` are unchanged from `qick_tprocv2_216_standard`.

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
tProc v2 rev 28 at 200 MHz, plus the DDR4 and MR buffers.

The dump was taken with QICK 0.2.371, so the version line and incidental wording will differ
from what a newer qick package prints. The channel counts, the IP names, the tProc revision
and the trigger and tile assignments are what must match.

## Software

The ML notebook and helper library from the tProc v1 branch
(`ml-integration-tproc-v1-2026`) are **not** on this branch: they are built on
`AveragerProgram`, which is tProc v1 only, and will not run against this firmware. Porting
them to the v2 API is follow-up work; `docs/source/tutorials/00_Getting_Started.ipynb` is
the v2 send/receive-pulse reference.
