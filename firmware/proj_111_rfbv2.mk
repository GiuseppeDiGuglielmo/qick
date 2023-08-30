# Open GUI, create Vivado project, but DOES NOT run implementation
syn-zcu111-rfbv2:
	vivado -source proj_111_rfbv2.tcl
.PHONY: syn-zcu111-rfbv2

# Batch mode: create Vivado project and run implementation
syn-zcu111-rfbv2-batch:
	vivado -mode batch -source proj_111_rfbv2_batch.tcl
.PHONY: syn-zcu111-rfbv2-batch

## Batch model, create Vivado project, enable ILA, run implementation, copy package remotely
#syn-zcu111-rfbv2-batch-ila:
#	vivado -mode batch -source proj_111_rfbv2_batch_ila.tcl
#.PHONY: syn-zcu111-rfbv2-batch-ila

# Batch mode: create Vivado project, use BRAMs + AXI-lite, and run implementation
syn-zcu111-rfbv2-batch-bram:
	vivado -mode batch -source proj_111_rfbv2_batch_bram.tcl
.PHONY: syn-zcu216-batch-bram

# Open GUI of the latest Vivado project
gui-zcu111-rfbv2:
	vivado top_111_rfbv2/top_111_rfbv2.xpr
.PHONY: gui-zcu111-rfbv2

# Package BIT, HWH, and LTX files
package-zcu111-rfbv2:
	@./package.sh \
		top_111_rfbv2 \
		d_1 \
		top_111_rfbv2 \
		qick_111_rfbv2
.PHONY: package-zcu111-rfbv2

# Copy package remotely
copy-zcu111-rfbv2: package-zcu111-rfbv2
	@./copy.sh \
		xilinx@192.168.1.59:~/jupyter_notebooks/qick_fermilab/qick/qick_ml \
		qick_111_rfbv2
.PHONY: package-zcu111-rfbv2

ultraclean-zcu111-rfbv2:
	@rm -rf top_111_rfbv2
.PHONY: ultraclean-zcu111-rfbv2
