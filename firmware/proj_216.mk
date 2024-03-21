# GUI mode:
# - create original Vivado project
# - DO NOT run implementation
syn-zcu216:
	vivado -source proj_216.tcl
.PHONY: syn-zcu216

# Batch mode:
# - create original Vivado project
# - run implementation
syn-zcu216-batch-orig:
ifeq ($(GUI),1)
	vivado -mode gui -source proj_216_batch_orig.tcl
else
	vivado -mode batch -source proj_216_batch_orig.tcl
endif
.PHONY: syn-zcu216-batch-orig

# Batch mode:
# - create Vivado project
# - ILAs
# - run implementation
syn-zcu216-batch-ila:
ifeq ($(GUI),1)
	vivado -mode gui -source proj_216_batch_ila.tcl
else
	vivado -mode batch -source proj_216_batch_ila.tcl
endif
.PHONY: syn-zcu216-batch-ila

# Batch mode:
# - create Vivado project
# - add NN
# - use BRAMs + AXI-lite for NN
# - ILAs
# - run implementation
syn-zcu216-batch-nn:
ifeq ($(GUI),1)
	vivado -mode gui -source proj_216_batch_nn.tcl
else
	vivado -mode batch -source proj_216_batch_nn.tcl
endif
.PHONY: syn-zcu216-batch-nn

# Open GUI of the latest Vivado project
gui-zcu216-orig:
	vivado top_216_orig/top_216.xpr
.PHONY: gui-zcu216-orig

gui-zcu216-ila:
	vivado top_216_ila/top_216.xpr
.PHONY: gui-zcu216-ila

gui-zcu216-nn:
	vivado top_216_nn/top_216.xpr
.PHONY: gui-zcu216-nn

# Package BIT, HWH, and LTX files
package-zcu216-ila:
	@./package.sh \
		top_216 \
		d_1 \
		top_216_ila \
		qick_216_ila
.PHONY: package-zcu216-ila

package-zcu216-nn:
	@./package.sh \
		top_216 \
		d_1 \
		top_216_nn \
		qick_216_nn
.PHONY: package-zcu216-nn

# Copy package remotely
copy-zcu216:
	@./copy.sh \
		xilinx@rfsoc216-ml01.dhcp.fnal.gov:~/jupyter_notebooks/qick_dev/qick_ml/216/ml-dev \
		qick_216 \
		quantum2023.
.PHONY: copy-zcu216

ultraclean-zcu216-orig:
	@rm -rf top_216_orig
.PHONY: ultraclean-zcu216-orig

ultraclean-zcu216-ila:
	@rm -rf top_216_ila
.PHONY: ultraclean-zcu216-ila

ultraclean-zcu216-nn:
	@rm -rf top_216_nn
.PHONY: ultraclean-zcu216-nn
