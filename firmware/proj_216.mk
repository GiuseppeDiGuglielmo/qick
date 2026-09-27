# Per-build Vivado log, journal and scratch dir, so builds don't overwrite each
# other's vivado.log/vivado.jou/.Xil: $(call vivado_out,<build>)
vivado_out = -log vivado_$(1).log -journal vivado_$(1).jou -tempDir .Xil_$(1)

# Create original Vivado project from proj_216.tcl (no implementation run)
syn-zcu216:
	vivado $(call vivado_out,216) -source proj_216.tcl
.PHONY: syn-zcu216

# Create original Vivado project and run implementation (batch/GUI mode)
syn-zcu216-orig: check_license
ifeq ($(GUI),1)
	vivado -mode gui $(call vivado_out,orig) -source proj_216_orig.tcl
else
	bash -c 'TIMEFORMAT="Elapsed time: %0lR"; time vivado -mode batch $(call vivado_out,orig) -source proj_216_orig.tcl'
endif
.PHONY: syn-zcu216-orig

# Batch/GUI mode: create Vivado project with ILAs and run implementation
syn-zcu216-orig-ila: check_license
ifeq ($(GUI),1)
	vivado -mode gui $(call vivado_out,orig_ila) -source proj_216_orig_ila.tcl
else
	bash -c 'TIMEFORMAT="Elapsed time: %0lR"; time vivado -mode batch $(call vivado_out,orig_ila) -source proj_216_orig_ila.tcl'
endif
.PHONY: syn-zcu216-orig-ila

# Batch/GUI mode: create Vivado project with the NN IP (BRAM + AXI-Lite) and run implementation
syn-zcu216-nn: check_license
ifeq ($(GUI),1)
	vivado -mode gui $(call vivado_out,nn) -source proj_216_nn.tcl
else
	bash -c 'TIMEFORMAT="Elapsed time: %0lR"; time vivado -mode batch $(call vivado_out,nn) -source proj_216_nn.tcl'
endif
.PHONY: syn-zcu216-nn

# Batch/GUI mode: create Vivado project with the NN IP and ILAs and run implementation
syn-zcu216-nn-ila: check_license
ifeq ($(GUI),1)
	vivado -mode gui $(call vivado_out,nn_ila) -source proj_216_nn_ila.tcl
else
	bash -c 'TIMEFORMAT="Elapsed time: %0lR"; time vivado -mode batch $(call vivado_out,nn_ila) -source proj_216_nn_ila.tcl'
endif
.PHONY: syn-zcu216-nn-ila

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

# Open GUI of the top_216_nn Vivado project created by syn-zcu216-nn
gui-zcu216-nn:
	vivado top_216_nn/top_216.xpr
.PHONY: gui-zcu216-nn

# Open GUI of the top_216_nn_ila Vivado project created by syn-zcu216-nn-ila
gui-zcu216-nn-ila:
	vivado top_216_nn_ila/top_216.xpr
.PHONY: gui-zcu216-nn-ila

# Package BIT, HWH, and LTX files of top_216_orig into package/qick_216_orig/ (recreated on every run)
package-zcu216-orig:
	@./package.sh \
		top_216 \
		d_1 \
		top_216_orig \
		qick_216_orig
.PHONY: package-zcu216-orig

# Package BIT, HWH, and LTX files of top_216_orig_ila into package/qick_216_orig_ila/ (recreated on every run)
package-zcu216-orig-ila:
	@./package.sh \
		top_216 \
		d_1 \
		top_216_orig_ila \
		qick_216_orig_ila
.PHONY: package-zcu216-orig-ila

# Package BIT, HWH, and LTX files of top_216_nn into package/qick_216_nn/ (recreated on every run)
package-zcu216-nn:
	@./package.sh \
		top_216 \
		d_1 \
		top_216_nn \
		qick_216_nn
.PHONY: package-zcu216-nn

# Package BIT, HWH, and LTX files of top_216_nn_ila into package/qick_216_nn_ila/ (recreated on every run)
package-zcu216-nn-ila:
	@./package.sh \
		top_216 \
		d_1 \
		top_216_nn_ila \
		qick_216_nn_ila
.PHONY: package-zcu216-nn-ila

# Git branch this checkout is on, with / replaced by - (used in REMOTE)
BRANCH ?= $(shell git rev-parse --abbrev-ref HEAD | tr / -)

# scp destination of copy-zcu216 (override with REMOTE=user@host:path)
REMOTE ?= xilinx@rfsoc216-ml01.dhcp.fnal.gov:~/jupyter_notebooks/qick-$(BRANCH)/qick_ml/216/$(BRANCH)

# Packaged builds copied by copy-zcu216: all of them (empty), or a list of
# orig, orig_ila, nn, nn_ila (e.g. make copy-zcu216 BUILD=nn or BUILD="nn nn_ila")
BUILD ?=

# Copy the packaged builds in package/ (created by package-zcu216-*) to REMOTE
# Authenticates with an SSH key/agent, or export SSHPASS to use a password instead
copy-zcu216:
	@./copy.sh "$(REMOTE)" $(addprefix qick_216_,$(BUILD))
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

# Remove top_216_nn project directory created by syn-zcu216-nn
distclean-zcu216-nn:
	@rm -rf top_216_nn
.PHONY: distclean-zcu216-nn

# Remove top_216_nn_ila project directory created by syn-zcu216-nn-ila
distclean-zcu216-nn-ila:
	@rm -rf top_216_nn_ila
.PHONY: distclean-zcu216-nn-ila
