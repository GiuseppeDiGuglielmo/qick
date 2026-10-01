# Build flow for the QICK designs in ../projects.
#
# Every target works on one design, selected with DESIGN=<directory name>.
# Run "make help" for the list of targets and variables.

# Design directory under ../projects, and the base name of its out/ links
DESIGN ?= qick_tprocv2_216_standard_1ch

TOOLS      := $(CURDIR)
DESIGN_DIR := $(CURDIR)/../projects/$(DESIGN)

# Open Vivado in GUI mode for targets that would otherwise run in batch
GUI ?= 0

# Parallel synthesis jobs. Each is a full Vivado process of roughly 2.5 GB,
# so lower this on a machine that cannot hold 20 of them.
JOBS ?= 20

# The project scripts are layered, each sourcing the one below it:
#   proj_ila.tcl (ILA=1) -> proj_replay.tcl (REPLAY=1) -> proj_nn.tcl (NN=1)
#   -> proj_dac.tcl (DAC=228|230) -> proj.tcl
# A design with proj_dac.tcl builds into top_dac228*/ or top_dac230*/, and
# DAC=230 moves its generator to DAC 0_230;
# NN=1 adds the NN classifier on readout 0 and appends _nn to the project directory;
# REPLAY=1 adds the readout replay buffer (stored I/Q in place of the readout
# output, for the averager and the NN) and appends _replay;
# ILA=1 adds ILAs on the readout path (on the NN with NN=1) and appends _ila
DAC ?= 228
NN  ?= 0
REPLAY ?= 0
ILA ?= 0
ifeq ($(filter $(DAC),228 230),)
$(error DAC must be 228 or 230, got: $(DAC))
endif
ifeq ($(filter $(NN),0 1),)
$(error NN must be 0 or 1, got: $(NN))
endif
ifeq ($(filter $(REPLAY),0 1),)
$(error REPLAY must be 0 or 1, got: $(REPLAY))
endif
# Start from the topmost layer needed. A design without proj_dac.tcl builds
# from proj.tcl into top/ when DAC=228; DAC=230 requires proj_dac.tcl, and
# NN=1 requires proj_nn.tcl, and REPLAY=1 proj_replay.tcl.
HAS_DAC_LAYER := $(if $(wildcard $(DESIGN_DIR)/proj_dac.tcl),1)
ifeq ($(ILA),1)
PROJ_TCL    := proj_ila.tcl
else ifeq ($(REPLAY),1)
PROJ_TCL    := proj_replay.tcl
else ifeq ($(NN),1)
PROJ_TCL    := proj_nn.tcl
else ifneq ($(HAS_DAC_LAYER)$(filter 230,$(DAC)),)
PROJ_TCL    := proj_dac.tcl
else
PROJ_TCL    := proj.tcl
endif
PROJ_SUFFIX := $(if $(HAS_DAC_LAYER),_dac$(DAC))$(if $(filter 1,$(NN)),_nn)$(if $(filter 1,$(REPLAY)),_replay)$(if $(filter 1,$(ILA)),_ila)

# hw_server to connect to (host:port); Vivado starts a local one if none is running
HW_SERVER ?= localhost:3121

# Git branch this checkout is on, with / replaced by - (used in REMOTE)
BRANCH ?= $(shell git rev-parse --abbrev-ref HEAD | tr / -)

# scp destination of the copy target (override with REMOTE=user@host:path).
# Matches where ../notebooks/qick_ml/send_receive_pulse.ipynb looks for
# bitstreams (216/$BRANCH, relative to the notebook), assuming the board
# checkout mirrors this repo's layout under ~/jupyter_notebooks/qick-$(BRANCH).
REMOTE ?= xilinx@rfsoc216-ml01.dhcp.fnal.gov:~/jupyter_notebooks/qick-$(BRANCH)/firmware/notebooks/qick_ml/216/$(BRANCH)

help:
	@echo "Targets:"
	@echo "  designs       list the designs usable as DESIGN="
	@echo "  project       create the Vivado project (GUI, no build)"
	@echo "  bitstream     build through write_bitstream and report utilization"
	@echo "  gui           open the project created by a previous target"
	@echo "  copy          copy the design's out/ files to the board"
	@echo "  hw-server     open Hardware Manager and connect to hw_server (GUI)"
	@echo "  hw-server-tcl same, in the Vivado Tcl shell (no GUI)"
	@echo "  clean         remove Vivado logs, journals, reports and .Xil scratch"
	@echo "  distclean     clean + remove the generated project directories"
	@echo "  clean-bitstreams"
	@echo "                remove the bitstreams deployed by copy (on the board)"
	@echo ""
	@echo "Variables:"
	@echo "  DESIGN=<dir>      design under ../projects (default: $(DESIGN))"
	@echo "  GUI=1             run bitstream in GUI mode instead of batch"
	@echo "  JOBS=<n>          parallel synthesis jobs (default: $(JOBS))"
	@echo "  DAC=228|230       generator DAC: 0_228 as delivered (default), or 0_230"
	@echo "                    as in the tProc v1 designs, built into top_dac<DAC>*/"
	@echo "  NN=1              add the NN classifier on readout 0, built into top*_nn*/"
	@echo "  REPLAY=1          add the readout replay buffer, built into top*_replay*/"
	@echo "  ILA=1             add the readout ILAs (on the NN with NN=1), built into top*_ila/"
	@echo "  REMOTE=<target>   scp destination for copy"
	@echo "  DRYRUN=1          copy: print what would be copied without copying"
	@echo "  HW_SERVER=<url>   hw_server to connect to (default: $(HW_SERVER))"
	@echo ""
	@echo "Run 'source envsetup.sh' first to select Vivado and the license server."
.PHONY: help

# List the designs under ../projects that can be built (those with a proj.tcl).
# * marks the default; DAC, NN, REPLAY and ILA show which options the design supports.
designs:
	@printf "  %-40s %-4s %-4s %-6s %s\n" "DESIGN" "DAC" "NN" "REPLAY" "ILA"
	@for dir in $(CURDIR)/../projects/*/; do \
		test -f "$$dir/proj.tcl" || continue; \
		name=$$(basename "$$dir"); \
		mark=" "; test "$$name" = "$(DESIGN)" && mark="*"; \
		dac=-; test -f "$$dir/proj_dac.tcl" && dac=yes; \
		nn=-; test -f "$$dir/proj_nn.tcl" && nn=yes; \
		rp=-; test -f "$$dir/proj_replay.tcl" && rp=yes; \
		ila=-; test -f "$$dir/proj_ila.tcl" && ila=yes; \
		printf "%s %-40s %-4s %-4s %-6s %s\n" "$$mark" "$$name" "$$dac" "$$nn" "$$rp" "$$ila"; \
	done
.PHONY: designs

# Fail early if the design does not exist, so targets do not fail inside Vivado
check_design:
	@test -f "$(DESIGN_DIR)/$(PROJ_TCL)" || { echo "ERROR: design '$(DESIGN)' has no $(PROJ_TCL)" >&2; exit 1; }
	@test "$(NN)" != 1 || test -f "$(DESIGN_DIR)/proj_nn.tcl" || { echo "ERROR: design '$(DESIGN)' has no proj_nn.tcl" >&2; exit 1; }
	@test "$(REPLAY)" != 1 || test -f "$(DESIGN_DIR)/proj_replay.tcl" || { echo "ERROR: design '$(DESIGN)' has no proj_replay.tcl" >&2; exit 1; }
.PHONY: check_design

# Fail if XILINXD_LICENSE_FILE is not set (needed by targets that run synthesis)
check_license:
	@test -n "$$XILINXD_LICENSE_FILE" || { echo "ERROR: XILINXD_LICENSE_FILE is not set, run: source envsetup.sh" >&2; exit 1; }
.PHONY: check_license

# Create the Vivado project without building it. proj.tcl is run from the design
# directory, which is what its relative paths assume, so it needs no wrapper.
project: check_design
	cd $(DESIGN_DIR) && NN=$(NN) REPLAY=$(REPLAY) DAC=$(DAC) vivado -source $(PROJ_TCL)
.PHONY: project

# Create the project and run implementation through bitstream generation
bitstream: check_design check_license
ifeq ($(GUI),1)
	cd $(DESIGN_DIR) && JOBS=$(JOBS) ILA=$(ILA) NN=$(NN) REPLAY=$(REPLAY) DAC=$(DAC) vivado -mode gui -source $(TOOLS)/bitstream.tcl
else
	cd $(DESIGN_DIR) && JOBS=$(JOBS) ILA=$(ILA) NN=$(NN) REPLAY=$(REPLAY) DAC=$(DAC) bash -c 'TIMEFORMAT="Elapsed time: %0lR"; time vivado -mode batch -source $(TOOLS)/bitstream.tcl'
endif
.PHONY: bitstream

# Open the GUI of an already created project
gui: check_design
	vivado $(DESIGN_DIR)/top$(PROJ_SUFFIX)/top.xpr
.PHONY: gui

# Copy the design's out/ files to REMOTE
# Authenticates with an SSH key/agent, or export SSHPASS to use a password instead
# DRYRUN=1 prints what would be copied without copying anything
copy: check_design
	@DRYRUN=$(DRYRUN) $(TOOLS)/copy.sh "$(REMOTE)" "$(DESIGN_DIR)/out"
.PHONY: copy

# Open the Hardware Manager and connect to hw_server (GUI)
hw-server:
	vivado -source $(TOOLS)/open_hw.tcl -tclargs $(HW_SERVER)
.PHONY: hw-server

# Same as hw-server, in the Vivado Tcl shell (no GUI)
hw-server-tcl:
	vivado -mode tcl -source $(TOOLS)/open_hw.tcl -tclargs $(HW_SERVER)
.PHONY: hw-server-tcl

# Vivado litter: logs, journals, reports, pid files (*.log covers hs_err_pid*.log
# and *.backup.log; *.str covers vivado_pid*.str). Vivado writes these into the
# directory it was started from, which is the design directory for the targets
# above and here for anything run by hand.
clean:
	@rm -rf *.log *.jou *.rpt *.str .Xil
	@rm -rf ../projects/*/*.log ../projects/*/*.jou ../projects/*/*.rpt ../projects/*/*.str ../projects/*/.Xil
.PHONY: clean

# Generated Vivado project directories, under any design
distclean: clean
	@rm -rf $(wildcard ../projects/*/top ../projects/*/top_*)
.PHONY: distclean

# Bitstreams deployed by copy, when this checkout is the board's. Kept out of
# distclean, which only removes build outputs, so cleaning a build on the board
# does not remove the bitstreams its notebooks load.
clean-bitstreams:
	@rm -rf ../notebooks/qick_ml/216
.PHONY: clean-bitstreams
