VIVADO_SETTINGS="/tools/Xilinx/Vivado/2022.1/settings64.sh"

if [ ! -f "$VIVADO_SETTINGS" ]; then
	echo "ERROR: Vivado settings script not found at $VIVADO_SETTINGS" >&2
	return 1 2>/dev/null || exit 1
fi

source "$VIVADO_SETTINGS"

export XILINXD_LICENSE_FILE=2100@xilinx-lic.fnal.gov
