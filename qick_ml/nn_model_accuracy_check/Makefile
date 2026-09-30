# Accuracy of the NN classifier on the 20240528 test set, in two steps:
#   - the bit-exact C model of the NN() core scores the whole test set;
#   - the RTL of the NN IP (Icarus Verilog) is compared with it on a sample.
# Runs on the host (needs the dataset on the NAS and iverilog), not on the board.
#
#   make         unzip the HLS project into build/ and build libnn_eval.so
#   make run     C model on the full test set, write result.json and logits.npy
#   make rtl     RTL simulation of a sample of shots, compared with logits.npy
#                (SHOTS, WRONG, NEAR, JOBS; ALL=1 simulates every shot;
#                GAIN=k tests the IP's input gain, NODIVIDE=1 its wrap-around)
#   make clean   remove build/, the library and the results
#
# Override the paths on the command line, e.g. make run DATA=/path/to/000_770

PRJ := two_layers_w400_ternary_h4_s100_20240528_hls4ml_prj
PRJ_ZIP ?= ../ip/20240528/$(PRJ).zip
IP_ZIP ?= ../ip/20240528/xilinx_com_hls_NN_axi_1_0_nonregistered_l2_w400_ternary_h4_s100.zip
DATA ?= /nas/work/research/quantum/readout/data/qick_data/20240528/000_770
PYTHON ?= python3

# RTL check: random shots (half per class), misclassified shots, shots nearest
# the threshold, parallel simulations
SHOTS ?= 1000
WRONG ?= 100
NEAR ?= 100
JOBS ?= 20
# RTL check: scaling_factor (input gain) written to the IP; the shots are
# streamed at 1/GAIN unless NODIVIDE=1
GAIN ?= 1

BUILD := build
HLS_PRJ := $(BUILD)/$(PRJ)
FW := $(HLS_PRJ)/firmware
STAMP := $(HLS_PRJ)/.unzipped
IP_DIR := $(BUILD)/ip
IP_STAMP := $(IP_DIR)/.unzipped
LIB := libnn_eval.so

.DEFAULT_GOAL := all

# Targets are documented with a trailing "## text"
help:  ## Show this help
	@echo "NN accuracy check (C model and RTL) on the 20240528 test set"
	@echo
	@echo "Targets:"
	@awk 'BEGIN {FS = ":.*## "} /^[a-z]+:.*## / {printf "  make %-6s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo
	@echo "Variables (override with make <target> VAR=value):"
	@echo "  PRJ_ZIP  HLS project zip     [$(PRJ_ZIP)]"
	@echo "  IP_ZIP   NN IP zip (RTL)     [$(IP_ZIP)]"
	@echo "  DATA     test set directory  [$(DATA)]"
	@echo "  PYTHON   interpreter         [$(PYTHON)]"
	@echo "  SHOTS    rtl: random shots, half per class [$(SHOTS)]"
	@echo "  WRONG    rtl: misclassified shots          [$(WRONG)]"
	@echo "  NEAR     rtl: shots nearest the threshold  [$(NEAR)]"
	@echo "  JOBS     rtl: parallel simulations         [$(JOBS)]"
	@echo "  ALL=1    rtl: simulate every test shot (about 85 min on 20 cores)"
	@echo "  GAIN     rtl: IP input gain (scaling_factor)  [$(GAIN)]"
	@echo "  NODIVIDE=1 rtl: stream shots unscaled (wrap-around test)"

all: $(LIB)  ## Unzip the HLS project into build/ and build libnn_eval.so

# Unzip again whenever the zip changes
$(STAMP): $(PRJ_ZIP)
	rm -rf $(HLS_PRJ)
	mkdir -p $(BUILD)
	unzip -q $(PRJ_ZIP) -d $(BUILD)
	touch $@

# NN() reads its weights from WEIGHTS_DIR/*.txt at run time
$(LIB): nn_eval.cpp $(STAMP)
	g++ -O2 -fPIC -std=c++11 -shared -I$(FW)/ap_types -I$(FW) \
	    -DWEIGHTS_DIR='"$(abspath $(FW)/weights)"' $(FW)/NN.cpp nn_eval.cpp -o $@

run: $(LIB)  ## C model on the full test set: result.json, logits.npy
	$(PYTHON) accuracy_check.py --lib ./$(LIB) --hls-prj $(HLS_PRJ) --data $(DATA)

# The IP's Verilog, unzipped again whenever the IP zip changes
$(IP_STAMP): $(IP_ZIP)
	rm -rf $(IP_DIR)
	mkdir -p $(IP_DIR)
	unzip -q $(IP_ZIP) 'hdl/verilog/*' -d $(IP_DIR)
	touch $@

logits.npy: $(LIB)
	$(MAKE) run

rtl: $(IP_STAMP) logits.npy tb_nn_axi.v $(LIB)  ## RTL simulation vs the C model on a sample: rtl_result.json
	$(PYTHON) rtl_check.py --ip-rtl $(IP_DIR)/hdl/verilog --data $(DATA) \
	    --random $(SHOTS) --wrong $(WRONG) --near $(NEAR) --jobs $(JOBS) $(if $(ALL),--all) \
	    --gain $(GAIN) $(if $(NODIVIDE),--no-divide) --lib ./$(LIB)

clean:  ## Remove build/, the library and the results
	rm -rf $(BUILD) $(LIB) result.json logits.npy rtl_result.json

.PHONY: all run rtl clean help
