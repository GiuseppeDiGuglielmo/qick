# Open GUI, create Vivado project, but DOES NOT run implementation
syn-zcu216:
	vivado -source proj_216.tcl
.PHONY: syn-zcu216

# Batch mode: create Vivado, QICK, project and run implementation
syn-zcu216-batch-orig:
	vivado -mode batch -source proj_216_batch_orig.tcl
.PHONY: syn-zcu216-batch-orig

# Batch mode: create Vivado, QICK, ILAs, project and run implementation
syn-zcu216-batch-ila:
	vivado -mode batch -source proj_216_batch_ila.tcl
.PHONY: syn-zcu216-batch-ila

# Batch mode: create Vivado project, QICK+NN, use BRAMs + AXI-lite for NN, ILAs, and run implementation
syn-zcu216-batch-nn:
	vivado -mode batch -source proj_216_batch_nn.tcl
.PHONY: syn-zcu216-batch-nn

# Open GUI of the latest Vivado project
gui-zcu216:
	vivado top_216/top_216.xpr
.PHONY: gui-zcu216

# Package BIT, HWH, and LTX files
package-zcu216:
	@./package.sh \
		top_216 \
		d_1 \
		top_216 \
		qick_216
.PHONY: package-zcu216

# Copy package remotely
copy-zcu216: package-zcu216
	@./copy.sh \
		xilinx@rfsoc216-ml01.dhcp.fnal.gov:~/jupyter_notebooks/qick/qick_ml \
		qick_216 \
		quantum2023.
.PHONY: package-zcu216

ultraclean-zcu216:
	@rm -rf top_216
.PHONY: ultraclean-zcu216