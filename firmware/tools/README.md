# Firmware build flow

A Makefile flow for the designs in [`../projects`](../projects). There is no build
automation upstream; this directory is this fork's addition, kept out of `firmware/` proper
so that directory keeps its shape and a project directory keeps to `proj.tcl`, the block
design, the constraints and `out/`.

Every target works on one design, selected with `DESIGN=<directory name>`:

```sh
source envsetup.sh                                  # Vivado + XILINXD_LICENSE_FILE
make project                                        # create the project, no build
make bitstream                                      # build through write_bitstream
make bitstream ILA=1                                # ... with the readout ILAs
make copy                                           # send out/ to the board
make bitstream DESIGN=qick_tprocv2_216_standard     # a different design
```

`make help` lists every target and variable.

| variable | default | meaning |
| --- | --- | --- |
| `DESIGN` | `qick_tprocv2_216_standard_1ch` | design directory under `../projects` |
| `GUI` | `0` | `GUI=1` runs `bitstream` in the GUI instead of batch |
| `JOBS` | `20` | parallel synthesis jobs |
| `ILA` | `0` | `ILA=1` builds the design's `proj_ila.tcl` variant into `top_ila/` |
| `REMOTE` | a board path derived from the branch name | scp destination for `copy` |
| `HW_SERVER` | `localhost:3121` | hw_server that `hw-server` connects to |

## Notes

**`JOBS` is worth setting.** Each job is a full Vivado process of roughly 2.5 GB, so the
default of 20 needs around 50 GB of RAM. On a smaller machine `make bitstream JOBS=8` fits
in about 20 GB; going over pushes the machine into swap and makes the build slower, not
faster.

**Vivado runs in the design directory.** `proj.tcl` uses paths relative to its own
directory (`../../ip` for the IP repository, `./top` for the project), so the targets change
into `../projects/$(DESIGN)` first. That is also why `make project` needs no wrapper script,
and why the design can equally be built by hand the plain upstream way:

```sh
cd ../projects/<design> && vivado -source proj.tcl
```

**Build results are symlinks.** A design's `out/` holds links into `top/` (and `top_ila/`),
following the convention of the upstream projects, so there is no packaging step. They dangle
until the design is built; `make copy` warns about the ones that are not built yet and sends
the rest, so a board can hold both variants under their distinct names.

**`ILA=1` is per design.** It selects `proj_ila.tcl` next to the design's `proj.tcl`, which
is where design-specific probe definitions belong; a design without one is rejected before
Vivado starts.

**Generated files are ignored.** `top*/` is covered by `firmware/.gitignore`, and logs,
journals and reports by the repository `.gitignore`. `make clean` sweeps the leftovers,
`make distclean` also removes the generated project directories.
