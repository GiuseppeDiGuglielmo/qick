# Readout replay (tProc v1)

Feeds recorded readout traces to the NN classifier on the board without the
DAC-to-ADC loopback. The `nn_replay` builds (`firmware/replay_216.tcl`,
sourced by `firmware/proj_216_nn_replay*.tcl` after `nn_216.tcl`) insert a
replay player between readout 0's decimated output and the broadcaster that
feeds the NN and the average and decimated buffers:

    axis_readout_v2_0/m1_axis -> axis_readout_replay_0 -> axis_broadcaster_0
                                      ^ BRAM (replay_bram_ctrl_0, PS)
                                      ^ controls (replay_ctrl_0/1, AXI GPIO)

In live mode the player passes the readout through (registered: one cycle
later than in the builds without it). In replay mode it streams stored I/Q
words after each readout trigger (tProc output 0 pin 8, the trigger of the
average buffer and the NN), so the NN sees the shots exactly as stored. The
player takes the trigger copy that `nn_trigger_sync_0` already
resynchronized for the NN: on the tProc v2 branch, a synchronizer of its own
caught the asynchronous trigger edge one cycle apart from the NN's on ~14% of
the shots, shifting those windows by one sample. No loopback scale, phase or
timing to calibrate beyond one start delay, and a BRAM load holds 163 shots of
400 samples.

Ported from `ml-integration-tproc-v2-2026`
(`firmware/notebooks/qick_ml/readout_replay/`): the same player, library and
notebook, with a tProc v1 trigger program. The player has no `tready`, so the
broadcaster has none either: `replay_216.tcl` removes `always_ready0`, which
`nn_216.tcl` uses to tie the broadcaster's `tready` high.

QICK has no such feature (`axis_kidsim_v3` simulates resonators in the
DAC-ADC path; the upstream `qick_emu` branch is a software emulator). The only
QICK change needed is in `qick_lib/qick/ip.py`: `trace_back` (the readout
behind each averager) and `trace_forward` (the averager and buffers behind
each readout) have to pass through `axis_readout_replay`; this branch's
`qick_lib` does.

## Files

- `readout_replay.ipynb`: alignment, the 20 HLS testbench shots (logits must
  equal the C simulation), test-set shots (1000 by default) and their score.
- `replay_lib.py`: `ReplayBuffer` (BRAM and controls), `pack`,
  `TriggerProgram` (readout trigger only, a tProc v1 `AveragerProgram`),
  `capture`, `align`, `run_shots`. Reuses `../qick_ml_lib.py` and
  `../readout_mock/readout_mock_lib.py` (dataset loading, scoring, memory
  report).
- `results/`: one `.npz` per run (gitignored).
- Hardware: `firmware/hdl/axis_readout_replay.v` and its testbench
  `tb_axis_readout_replay.v`.

## Register map

| block | channel | bits | meaning |
|---|---|---|---|
| `replay_ctrl_0` (0xA002_0000) | 1 (0x0) | 0 | mode: 0 live, 1 replay |
| | | 1 | index_reset: shot index held at 0 while 1 |
| | 2 (0x8) | 15:0 | shot_len, words per shot |
| | | 31:16 | n_shots, shots loaded (the index wraps) |
| `replay_ctrl_1` (0xA003_0000) | 1 (0x0) | 15:0 | start_delay, readout cycles from the trigger to word 0 |
| | 2 (0x8, read) | 15:0 / 31 | shot_index / busy |
| `replay_bram_ctrl_0` (0xA040_0000, 256 KB) | | | 64K words, Q in 31:16, I in 15:0 |

Set the controls while no shot plays (they cross from the PS clock into the
readout clock through 2-flop synchronizers). Each trigger in replay mode plays
words `shot_index * shot_len` to `+ shot_len - 1`, then the index advances.

## Alignment

`rp.align` replays a ramp with `start_delay` 0, finds the trace sample p0
where word 0 lands, and sets `start_delay = 100 - p0`, so BRAM word j is trace
sample 100 + j: with `WINDOW_OFFSET = 95` the NN window is then exactly the
400 stored words. It checks the whole ramp sample for sample on 18 captures.
The average buffer synchronizes the trigger on its own, so some captures land
one sample off; `align` takes the most frequent landing sample. The NN and the
player share one synchronized trigger and stay locked; the testbench shots
check that. Only the NN window (trace samples 100-499) of each shot needs
storing.

## Running

In Jupyter on the board, open `readout_replay.ipynb` and run all cells (no
cable needed for the replay itself). It loads
`../216/<branch>/qick_216_nn_replay.bit` and the test set from
`/home/xilinx/data/20240528/000_770/` (see
`../readout_mock/README.md` for the int16 copy). The last cell switches back
to live mode, for the other notebooks.

## Checking the player in simulation

    cd firmware/hdl
    iverilog -g2012 -P tb_axis_readout_replay.RDLAT=1 -o tb tb_axis_readout_replay.v axis_readout_replay.v && vvp -n tb

prints `PASS`: live passthrough one cycle late, each replayed shot word for
word at a fixed latency (6 cycles from the trigger rise at start_delay 0, plus
start_delay), zeros between shots, index advance, wrap and reset.

## Expected results

Board logits equal to the C model's on every replayed shot (the replay is bit
exact), so the accuracy equals the C model's on the same shots: 96.20% on the
default 1000 (seed 0), 96.014% on all 100,000.
