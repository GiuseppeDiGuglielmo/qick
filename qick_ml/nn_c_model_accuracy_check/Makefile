# Accuracy of the bit-exact C model of the NN() core on the 20240528 test set.
# Runs on the host (needs the dataset on the NAS), not on the board.
#
#   make         unzip the HLS project into build/ and build libnn_eval.so
#   make run     run the check, write result.json and logits.npy
#   make clean   remove build/, the library and the results
#
# Override the paths on the command line, e.g. make run DATA=/path/to/000_770

PRJ := two_layers_w400_ternary_h4_s100_20240528_hls4ml_prj
PRJ_ZIP ?= ../ip/20240528/$(PRJ).zip
DATA ?= /nas/work/research/quantum/readout/data/qick_data/20240528/000_770
PYTHON ?= python3

BUILD := build
HLS_PRJ := $(BUILD)/$(PRJ)
FW := $(HLS_PRJ)/firmware
STAMP := $(HLS_PRJ)/.unzipped
LIB := libnn_eval.so

all: $(LIB)

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

run: $(LIB)
	$(PYTHON) accuracy_check.py --lib ./$(LIB) --hls-prj $(HLS_PRJ) --data $(DATA)

clean:
	rm -rf $(BUILD) $(LIB) result.json logits.npy

.PHONY: all run clean
