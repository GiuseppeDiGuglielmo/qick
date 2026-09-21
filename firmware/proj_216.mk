# Create original Vivado project from proj_216.tcl (no implementation run)
syn-zcu216:
	vivado -source proj_216.tcl
.PHONY: syn-zcu216

# Create original Vivado project and run implementation (batch/GUI mode)
syn-zcu216-orig: check_license
ifeq ($(GUI),1)
	vivado -mode gui -source proj_216_orig.tcl
else
	bash -c 'TIMEFORMAT="Elapsed time: %0lR"; time vivado -mode batch -source proj_216_orig.tcl'
endif
.PHONY: syn-zcu216-orig

# Batch/GUI mode: create Vivado project with ILAs and run implementation
syn-zcu216-orig-ila: check_license
ifeq ($(GUI),1)
	vivado -mode gui -source proj_216_orig_ila.tcl
else
	bash -c 'TIMEFORMAT="Elapsed time: %0lR"; time vivado -mode batch -source proj_216_orig_ila.tcl'
endif
.PHONY: syn-zcu216-orig-ila

# Disabled: proj_216_nn.tcl does not exist in this repo yet
## Batch/GUI mode: create Vivado project with NN (BRAMs + AXI-lite), ILAs, and run implementation
#syn-zcu216-nn: check_license
#	@rm -rf ip_local/*
#ifeq ($(GUI),1)
#	vivado -mode gui -source proj_216_nn.tcl
#else
#	bash -c 'TIMEFORMAT="Elapsed time: %0lR"; time vivado -mode batch -source proj_216_nn.tcl'
#endif
#.PHONY: syn-zcu216-nn

# Open GUI of the top_216 Vivado project created by syn-zcu216
gui-zcu216:
	vivado top_216/top_216.xpr
.PHONY: gui-zcu216

# Open GUI of the top_216_orig Vivado project created by syn-zcu216-orig
gui-zcu216-orig:
	vivado top_216_orig/top_216.xpr
.PHONY: gui-zcu216-orig

# Open GUI of the top_216_orig_ila Vivado project created by syn-zcu216-orig-ila
gui-zcu216-orig-ila:
	vivado top_216_orig_ila/top_216.xpr
.PHONY: gui-zcu216-orig-ila

# Disabled: top_216_nn/ is only created by syn-zcu216-nn, which is disabled above
## Open GUI of the latest Vivado project
#gui-zcu216-nn:
#	vivado top_216_nn/top_216.xpr
#.PHONY: gui-zcu216-nn

# Package BIT, HWH, and LTX files of top_216_orig into package/ (recreated on every run)
package-zcu216-orig:
	@./package.sh \
		top_216 \
		d_1 \
		top_216_orig \
		qick_216_orig
.PHONY: package-zcu216-orig

# Package BIT, HWH, and LTX files of top_216_orig_ila into package/ (recreated on every run)
package-zcu216-orig-ila:
	@./package.sh \
		top_216 \
		d_1 \
		top_216_orig_ila \
		qick_216_orig_ila
.PHONY: package-zcu216-orig-ila

# Disabled: top_216_nn/ is only created by syn-zcu216-nn, which is disabled above
## Package BIT, HWH, and LTX files
#package-zcu216-nn:
#	@./package.sh \
#		top_216 \
#		d_1 \
#		top_216_nn \
#		qick_216_nn
#.PHONY: package-zcu216-nn

# Git branch this checkout is on, with / replaced by - (used in REMOTE)
BRANCH ?= $(shell git rev-parse --abbrev-ref HEAD | tr / -)

# scp destination of copy-zcu216 (override with REMOTE=user@host:path)
REMOTE ?= xilinx@rfsoc216-ml01.dhcp.fnal.gov:~/jupyter_notebooks/qick-$(BRANCH)/qick_ml/216

# Copy the files in package/ (created by package-zcu216-*) to REMOTE
# Authenticates with an SSH key/agent, or export SSHPASS to use a password instead
copy-zcu216:
	@./copy.sh "$(REMOTE)"
.PHONY: copy-zcu216

# Remove top_216 project directory created by syn-zcu216
distclean-zcu216:
	@rm -rf top_216
.PHONY: distclean-zcu216

# Remove top_216_orig project directory created by syn-zcu216-orig
distclean-zcu216-orig:
	@rm -rf top_216_orig
.PHONY: distclean-zcu216-orig

# Remove top_216_orig_ila project directory created by syn-zcu216-orig-ila
distclean-zcu216-orig-ila:
	@rm -rf top_216_orig_ila
.PHONY: distclean-zcu216-orig-ila

# Disabled: top_216_nn/ is only created by syn-zcu216-nn, which is disabled above
## Remove top_216_nn project directory
#distclean-zcu216-nn:
#	@rm -rf top_216_nn
#.PHONY: distclean-zcu216-nn
