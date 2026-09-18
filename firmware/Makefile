help:
	@echo "syn-zcu216       create top_216 project (GUI, no build)"
	@echo "syn-zcu216-orig  build top_216_orig (GUI=1 for gui mode)"
	@echo "gui-zcu216       open top_216 project"
	@echo "gui-zcu216-orig  open top_216_orig project"
	@echo "hw-server        open Hardware Manager and connect to hw_server (GUI)"
	@echo "hw-server-tcl    same, in the Vivado Tcl shell (no GUI)"
	@echo "clean            remove Vivado logs/journals/reports and .Xil scratch"
	@echo "distclean        clean + remove all top_216* project dirs and packages"
.PHONY: help

GUI ?= 0

-include proj_216.mk

# Disabled: ip_local/ does not exist in this repo yet
#check_ip:
#	@ls ip_local
#.PHONY: check_ip

# hw_server to connect to (host:port); Vivado starts a local one if none is running
HW_SERVER ?= localhost:3121

# Open the Hardware Manager and connect to hw_server (GUI)
hw-server:
	vivado -source open_hw.tcl -tclargs $(HW_SERVER)
.PHONY: hw-server

# Same as hw-server, in the Vivado Tcl shell (no GUI)
hw-server-tcl:
	vivado -mode tcl -source open_hw.tcl -tclargs $(HW_SERVER)
.PHONY: hw-server-tcl

# Fail if XILINXD_LICENSE_FILE is not set (needed by targets that run synthesis)
check_license:
	@test -n "$$XILINXD_LICENSE_FILE" || { echo "ERROR: XILINXD_LICENSE_FILE is not set, run: source envsetup.sh" >&2; exit 1; }
.PHONY: check_license

# Generated Vivado project directories: top_216 plus any top_216_<suffix>
# (orig, and ila/nn once enabled). Globbed so distclean needs no per-project
# target and works even if proj_216.mk is missing.
PROJ_DIRS = $(wildcard top_216 top_216_*)

# Vivado litter left in this directory: logs, journals, reports, pid files
# (*.log covers hs_err_pid*.log and *.backup.log; *.str covers vivado_pid*.str)
clean:
	@rm -rf *.log *.jou *.rpt *.str .Xil
.PHONY: clean

distclean: clean
	@rm -rf $(PROJ_DIRS) package package.tar.gz package.zip
.PHONY: distclean
