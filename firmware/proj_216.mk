# Open GUI, create Vivado project, but DOES NOT run implementation
syn-zcu216:
	vivado -source proj_216.tcl
.PHONY: syn-zcu216

# Batch mode: create Vivado project and run implementation
syn-zcu216-batch:
	vivado -mode batch -source proj_216_batch.tcl
.PHONY: syn-zcu216-batch

# Batch mode: create Vivado project, enable ILA, and run implementation
syn-zcu216-batch-ila:
	vivado -mode batch -source proj_216_batch_ila.tcl
.PHONY: syn-zcu216-batch-ila

# Batch mode: create Vivado project, use BRAMs + AXI-lite, and run implementation
syn-zcu216-batch-bram:
	vivado -mode batch -source proj_216_batch_bram.tcl
.PHONY: syn-zcu216-batch-bram

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
