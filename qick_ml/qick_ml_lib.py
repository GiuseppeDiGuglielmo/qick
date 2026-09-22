"""
Support library for the send-receive-pulse ZCU216/QICK experiment.

Provides the QICK program that fires a single readout pulse and captures the
loopback ADC trace (LoopbackProgram), a couple of numeric formatting helpers
for dumping I/Q samples as hex (float_to_hex32, int_to_twos_complement_hex32),
and a set of MMIO-based helpers for driving the FPGA-resident NN classifier
that scores each pulse (reset_classifier, configure_classifier,
get_classifier_prediction_count, get_classifier_prediction,
get_classifier_predictions, print_classifier_buffer).

The classifier helpers talk to the classifier IP over its AXI-Lite config
registers and to its prediction output over a separate memory-mapped port, both
reached through the `soccfg` QickSoc/QickConfig handle. Call set_soccfg() once
with that handle before using any classifier helper.
"""

from ctypes import *
import struct

from pynq import MMIO
from qick import AveragerProgram

# QickSoc/QickConfig handle the classifier helpers read/write through.
soccfg = None


def set_soccfg(sc):
    """
    Register the QickSoc/QickConfig instance the classifier helpers should use.

    Args:
        sc: The QickSoc/QickConfig instance (the notebook's `soccfg`).
    """
    global soccfg
    soccfg = sc


class LoopbackProgram(AveragerProgram):
    """
    QICK program that fires one readout pulse on a generator channel and
    captures the decimated I/Q trace on the paired ADC channel, for a simple
    DAC-to-ADC loopback measurement.
    """
    def initialize(self):
        cfg=self.cfg
        res_ch = cfg["res_ch"]

        # set the nyquist zone
        self.declare_gen(ch=cfg["res_ch"], nqz=1)

        # configure the readout lengths and downconversion frequencies (ensuring it is an available DAC frequency)
        for ch in cfg["ro_chs"]:
            self.declare_readout(ch=ch, length=self.cfg["readout_length"],
                                 freq=self.cfg["pulse_freq"], gen_ch=cfg["res_ch"])

        # convert frequency to DAC frequency (ensuring it is an available ADC frequency)
        freq = self.freq2reg(cfg["pulse_freq"],gen_ch=res_ch, ro_ch=cfg["ro_chs"][0])
        phase = self.deg2reg(cfg["res_phase"], gen_ch=res_ch)
        gain = cfg["pulse_gain"]
        self.default_pulse_registers(ch=res_ch, freq=freq, phase=phase, gain=gain)

        style=self.cfg["pulse_style"]

        if style in ["flat_top","arb"]:
            sigma = cfg["sigma"]
            self.add_gauss(ch=res_ch, name="measure", sigma=sigma, length=sigma*5)

        if style == "const":
            self.set_pulse_registers(ch=res_ch, style=style, length=cfg["length"])
        elif style == "flat_top":
            # The first half of the waveform ramps up the pulse, the second half ramps down the pulse
            self.set_pulse_registers(ch=res_ch, style=style, waveform="measure", length=cfg["length"])
        elif style == "arb":
            self.set_pulse_registers(ch=res_ch, style=style, waveform="measure")

        self.synci(200)  # give processor some time to configure pulses

    def body(self):
        # fire the pulse
        # trigger all declared ADCs
        # pulse PMOD0_0 for a scope trigger
        # pause the tProc until readout is done
        # increment the time counter to give some time before the next measurement
        # (the syncdelay also lets the tProc get back ahead of the clock)
        self.measure(pulse_ch=self.cfg["res_ch"],
                     adcs=self.ro_chs,
                     pins=[0],
                     adc_trig_offset=self.cfg["adc_trig_offset"],
                     wait=True,
                     syncdelay=self.us2cycles(self.cfg["relax_delay"]))

        # equivalent to the following:
        # self.trigger(adcs=self.ro_chs,
        #              pins=[0],
        #              adc_trig_offset=self.cfg["adc_trig_offset"])
        # self.pulse(ch=self.cfg["res_ch"])
        # self.wait_all()
        # self.sync_all(self.us2cycles(self.cfg["relax_delay"]))


def float_to_hex32(f):
    """Pack a Python float into its IEEE-754 32b representation, as an 8-digit hex string."""
    return format(struct.unpack('!I', struct.pack('!f', f))[0], '08x')


def int_to_twos_complement_hex32(n):
    """Encode a signed int as its 32b two's-complement value, as an 8-digit hex string."""
    # If the number is negative, get its two's complement
    if n < 0:
        n = (1 << 32) + n  # "Wrap around" to get 32-bit two's complement
    return format(n, '08x')


# --- Classifier helpers -----------------------------------------------------
# Drive the NN classifier IP that scores each readout pulse: its config
# registers (window size/offset, scaling factor, reset) sit behind
# soccfg.NN_0.mmio, and its prediction (logit) output is read back through
# soccfg.axi_blk_bram_ctrl_0. Two other addressing schemes for the same IP
# (a DDR output buffer, and separate s_axi_config/s_axi_out ports) are given
# further below, commented out, matching different NN IP/bitstream builds.

def to_float(w):
    """
    Convert a 32b memory word to a floating-point number using ctypes.

    Args:
        w (int): The 32b word to convert.

    Returns:
        float: The converted floating-point number.
    """
    cp = pointer(c_int(w))
    fp = cast(cp, POINTER(c_float))
    return fp.contents.value


def reset_classifier(deep_reset=False, index_lo=0, index_hi=0):
    """
    Reset the classifier. Optionally perform a deep reset.

    Args:
        deep_reset (bool): If True, perform a deep reset by setting specific memory locations to zero. Default is False.
        index_lo (int): The lower index for the deep reset range. Default is 0.
        index_hi (int): The upper index for the deep reset range. Default is 0.
    """
    RESET_HI = 255
    RESET_LO = 0
    # Access the MMIO interface of the classifier
    mmio_nn = MMIO(soccfg.NN_0.mmio.base_addr, soccfg.NN_0.mmio.length)
    # This sends a "reset pulse" to the classifier
    mmio_nn.write(soccfg.NN_0.register_map.out_reset.address, RESET_HI)
    mmio_nn.write(soccfg.NN_0.register_map.out_reset.address, RESET_LO)
    if deep_reset:
        # Perform a deep reset by setting specific memory locations to zero
        # Warning: This may run for a long time; use only for debugging
        print('WARNING: Deep reset may run for some time... use only for debugging')
        entry_count = ((index_hi - index_lo) + 1) * 2
        for i in range(index_lo * 2, index_lo * 2 + entry_count):
            soccfg.axi_blk_bram_ctrl_0.mmio.array[i] = 0


def configure_classifier(window_size, window_offset, scaling_factor, debug=False):
    """
    Configure the classifier with the specified parameters.

    Args:
        window_size (int): The size of the window for classification.
        window_offset (int): The offset of the window for classification.
        scaling_factor (int): The scaling factor for classification.
        debug (bool): If True, print debug information. Default is False.
    """
    if debug:
        # Print debug information about the classifier configuration
        print('INFO: classifier MMIO')
        print('INFO:   - base address:   @{:08x}'.format(soccfg.NN_0.mmio.base_addr))
        print('INFO:   - window_size:    @{:04x} = {}'.format(soccfg.NN_0.register_map.window_size.address, window_size))
        print('INFO:   - window_offset:  @{:04x} = {}'.format(soccfg.NN_0.register_map.window_offset.address, window_offset))
        print('INFO:   - scaling_factor: @{:04x} = {}'.format(soccfg.NN_0.register_map.scaling_factor.address, scaling_factor))
    # Access the MMIO interface of the classifier and configure it
    mmio_nn = MMIO(soccfg.NN_0.mmio.base_addr, soccfg.NN_0.mmio.length)
    mmio_nn.write(soccfg.NN_0.register_map.window_size.address, window_size)
    mmio_nn.write(soccfg.NN_0.register_map.window_offset.address, window_offset)
    mmio_nn.write(soccfg.NN_0.register_map.scaling_factor.address, scaling_factor)


def get_classifier_prediction_count():
    """
    Get how many predictions (pulses) have run through the classifier. This is 0 at the very beginning or if you reset the classifier.

    Returns:
        int: The number of predictions made by the classifier.
    """
    # Access the MMIO interface of the classifier
    mmio_nn = MMIO(soccfg.NN_0.mmio.base_addr, soccfg.NN_0.mmio.length)
    # Read and return the prediction count
    prediction_count = mmio_nn.read(soccfg.NN_0.register_map.out_offset.address)
    return prediction_count


def get_classifier_prediction(index=0):
    """
    Get the classifier prediction for a specific index of the buffer.

    Args:
        index (int): The index of the prediction to retrieve. Default is 0.

    Returns:
        tuple: A tuple containing the ground state logit and the excited state logit.
    """
    WORD_SIZE_BYTE = 4
    WORD_COUNT_PER_PREDICTION = 2
    # Access the MMIO interface of the BRAM
    mmio_bram = MMIO(soccfg.axi_blk_bram_ctrl_0.base_address, soccfg.axi_blk_bram_ctrl_0.size)
    # Read the logits for the ground state and excited state
    ground_state_logit = mmio_bram.read(index * WORD_COUNT_PER_PREDICTION * WORD_SIZE_BYTE + 0)
    excited_state_logit = mmio_bram.read(index * WORD_COUNT_PER_PREDICTION * WORD_SIZE_BYTE + WORD_SIZE_BYTE)
    return ground_state_logit, excited_state_logit


def get_classifier_predictions(index_lo=0, index_hi=0):
    """
    Get a range of classifier predictions from the buffer.

    Args:
        index_lo (int): The lower index of the range of predictions to retrieve. Default is 0.
        index_hi (int): The upper index of the range of predictions to retrieve. Default is 0.

    Returns:
        list: A list of tuples, each containing the ground state logit and the excited state logit.
    """
    WORD_SIZE_BYTE = 4
    WORD_COUNT_PER_PREDICTION = 2
    # Access the MMIO interface of the BRAM
    mmio_bram = MMIO(soccfg.axi_blk_bram_ctrl_0.base_address, soccfg.axi_blk_bram_ctrl_0.size)
    # TODO: You can read the whole memory area rather than one element at a time and append
    predictions = []
    for index in range(index_lo, index_hi + 1):
        ground_state_logit = mmio_bram.read(index * WORD_COUNT_PER_PREDICTION * WORD_SIZE_BYTE + 0)
        excited_state_logit = mmio_bram.read(index * WORD_COUNT_PER_PREDICTION * WORD_SIZE_BYTE + WORD_SIZE_BYTE)
        predictions.append([ground_state_logit, excited_state_logit])
    return predictions


def print_classifier_buffer(index_lo, index_hi):
    """
    Print the classifier buffer for a range of indices.

    Args:
        index_lo (int): The lower index of the range to print.
        index_hi (int): The upper index of the range to print.
    """
    # Get the prediction count and buffer size
    prediction_count = get_classifier_prediction_count()
    buffer_size = len(soccfg.axi_blk_bram_ctrl_0.mmio.array)
    print('INFO: buffer index : {:6}'.format(prediction_count))
    print('INFO: buffer size  : {:6} ({:6}KB)'.format(buffer_size, (buffer_size*4)/1024))
    print('INFO:')
    for i in range(index_lo, index_hi + 1):
        # Get the logits for each prediction and print them
        ground_state_logit, excited_state_logit = get_classifier_prediction(i)
        print('INFO: g [{:5d}] {:08x} ({}) {}'.format(i, ground_state_logit, to_float(ground_state_logit), '<<<' if prediction_count == i else ''))
        print('INFO: e [{:5d}] {:08x} ({}) {}'.format(i, excited_state_logit, to_float(excited_state_logit), '<<<' if prediction_count == i else ''))


# --- Alternate classifier addressing schemes (inactive) --------------------
#
# Variant 1: config registers behind soccfg.NN_0.s_axi_config, and predictions
# read from a DDR output buffer allocated with pynq.allocate() and passed in
# as 'buffer' (matches a bitstream build where the NN IP streams predictions
# to DDR instead of exposing them over a memory-mapped port). Defines the
# same function names as the active implementation above, so only one
# variant's functions should be defined at a time.
#
# def to_float(w):
#     """
#     Convert a 32b memory word to a floating-point number using ctypes.
#
#     Args:
#         w (int): The 32b word to convert.
#
#     Returns:
#         float: The converted floating-point number.
#     """
#     cp = pointer(c_int(w))
#     fp = cast(cp, POINTER(c_float))
#     return fp.contents.value
#
# def to_uint(w):
#     """
#     Convert a 32b memory word to a floating-point number using ctypes.
#
#     Args:
#         w (int): The 32b word to convert.
#
#     Returns:
#         float: The converted floating-point number.
#     """
#     fp = pointer(c_float(w))
#     cp = cast(fp, POINTER(c_int))
#     return cp.contents.value
#
# def reset_classifier(buffer, deep_reset=False, index_lo=0, index_hi=0, debug=False):
#     """
#     Reset the classifier. Optionally perform a deep reset.
#
#     Args:
#         deep_reset (bool): If True, perform a deep reset by setting specific memory locations to zero. Default is False.
#         index_lo (int): The lower index for the deep reset range. Default is 0.
#         index_hi (int): The upper index for the deep reset range. Default is 0.
#     """
#
#     nn_config = soccfg.NN_0.s_axi_config
#
#     if debug:
#         # Print debug information about the classifier configuration
#         print('INFO: classifier config MMIO')
#         print('INFO:   - base address:   @{:08x}'.format(nn_config.mmio.base_addr))
#         print('INFO:   - out_reset:      @{:04x}'.format(nn_config.register_map.out_reset.address))
#         print('INFO: classifier buffer')
#         print('INFO:   - base address:   @{:08x}'.format(buffer.physical_address))
#     RESET_HI = 255
#     RESET_LO = 0
#
#     # Access the MMIO interface of the classifier
#     mmio_nn_config = MMIO(nn_config.mmio.base_addr, nn_config.mmio.length)
#     # This sends a "reset pulse" to the classifier
#     mmio_nn_config.write(nn_config.register_map.out_reset.address, RESET_HI)
#     mmio_nn_config.write(nn_config.register_map.out_reset.address, RESET_LO)
#     if deep_reset:
#         # Perform a deep reset by setting specific memory locations to zero
#         # Warning: This may run for a long time; use only for debugging
#         print('WARNING: Deep reset may run for some time... use only for debugging')
#         entry_count = ((index_hi - index_lo) + 1) * 2
#         for i in range(entry_count):
#             buffer[i] = 0
#
# def configure_classifier(window_size, window_offset, scaling_factor, debug=False):
#     """
#     Configure the classifier with the specified parameters.
#
#     Args:
#         window_size (int): The size of the window for classification.
#         window_offset (int): The offset of the window for classification.
#         scaling_factor (int): The scaling factor for classification.
#         debug (bool): If True, print debug information. Default is False.
#     """
#
#     nn_config = soccfg.NN_0.s_axi_config
#
#     if debug:
#         # Print debug information about the classifier configuration
#         print('INFO: classifier config MMIO')
#         print('INFO:   - base address:   @{:08x}'.format(nn_config.mmio.base_addr))
#         print('INFO:   - window_size:    @{:04x} = {}'.format(nn_config.register_map.window_size.address, window_size))
#         print('INFO:   - window_offset:  @{:04x} = {}'.format(nn_config.register_map.window_offset.address, window_offset))
#         print('INFO:   - scaling_factor: @{:04x} = {}'.format(nn_config.register_map.scaling_factor.address, scaling_factor))
#
#     # Access the MMIO interface of the classifier and configure it
#     mmio_nn_config = MMIO(nn_config.mmio.base_addr, nn_config.mmio.length)
#     mmio_nn_config.write(nn_config.register_map.window_size.address, window_size)
#     mmio_nn_config.write(nn_config.register_map.window_offset.address, window_offset)
#     mmio_nn_config.write(nn_config.register_map.scaling_factor.address, scaling_factor)
#
# def get_classifier_prediction_count():
#     """
#     Get how many predictions (pulses) have run through the classifier. This is 0 at the very beginning or if you reset the classifier.
#
#     Returns:
#         int: The number of predictions made by the classifier.
#     """
#
#     nn_config = soccfg.NN_0.s_axi_config
#
#     # Access the MMIO interface of the classifier
#     mmio_nn_config = MMIO(nn_config.mmio.base_addr, nn_config.mmio.length)
#     # Read and return the prediction count
#     prediction_count = mmio_nn_config.read(nn_config.register_map.out_offset.address)
#     return prediction_count
#
# def get_classifier_prediction(buffer, index=0):
#     """
#     Get the classifier prediction for a specific index of the buffer.
#
#     Args:
#         index (int): The index of the prediction to retrieve. Default is 0.
#
#     Returns:
#         tuple: A tuple containing the ground state logit and the excited state logit.
#     """
#     WORD_COUNT_PER_PREDICTION = 2
#
#     # Read the logits for the ground state and excited state
#     ground_state_logit = buffer[index * WORD_COUNT_PER_PREDICTION + 0]
#     excited_state_logit = buffer[index * WORD_COUNT_PER_PREDICTION + 1]
#     return ground_state_logit, excited_state_logit
#
# def get_classifier_predictions(buffer, index_lo=0, index_hi=0):
#     """
#     Get a range of classifier predictions from the buffer.
#
#     Args:
#         index_lo (int): The lower index of the range of predictions to retrieve. Default is 0.
#         index_hi (int): The upper index of the range of predictions to retrieve. Default is 0.
#
#     Returns:
#         list: A list of tuples, each containing the ground state logit and the excited state logit.
#     """
#     WORD_SIZE_BYTE = 4
#     WORD_COUNT_PER_PREDICTION = 2
#
#     nn_out = soccfg.NN_0.s_axi_out
#
#     # TODO: You can read the whole memory area rather than one element at a time and append
#     predictions = []
#     for index in range(index_lo, index_hi + 1):
#         ground_state_logit = buffer[index * WORD_COUNT_PER_PREDICTION * WORD_SIZE_BYTE + 0]
#         excited_state_logit = buffer[index * WORD_COUNT_PER_PREDICTION * WORD_SIZE_BYTE + WORD_SIZE_BYTE]
#         predictions.append([ground_state_logit, excited_state_logit])
#     return predictions
#
# def print_classifier_buffer(buffer, index_lo, index_hi):
#     """
#     Print the classifier buffer for a range of indices.
#
#     Args:
#         index_lo (int): The lower index of the range to print.
#         index_hi (int): The upper index of the range to print.
#     """
#
#     # Get the prediction count and buffer size
#     prediction_count = get_classifier_prediction_count()
#     buffer_size = buffer.size
#     print('INFO: buffer base address: @{:08x}'.format(buffer.physical_address))
#     print('INFO: buffer index :        {:6}'.format(prediction_count))
#     print('INFO: buffer size  :        {:6}B ({:6}KB)'.format(buffer_size, int((buffer_size)/1024)))
#     print('INFO:')
#     for i in range(index_lo, index_hi + 1):
#         # Get the logits for each prediction and print them
#         ground_state_logit, excited_state_logit = get_classifier_prediction(buffer, i)
#         print('INFO: g [{:5d}] {:08x} ({}) {}'.format(i, to_uint(ground_state_logit), ground_state_logit, '<<<' if prediction_count == i else ''))
#         print('INFO: e [{:5d}] {:08x} ({}) {}'.format(i, to_uint(excited_state_logit), excited_state_logit, '<<<' if prediction_count == i else ''))
#
# Variant 2: config registers behind soccfg.NN_0.s_axi_config as above, but
# predictions are read back through a separate soccfg.NN_0.s_axi_out
# memory-mapped port instead of a DDR buffer. Same restriction: only one
# variant's functions should be defined at a time.
#
# def to_float(w):
#     """
#     Convert a 32b memory word to a floating-point number using ctypes.
#
#     Args:
#         w (int): The 32b word to convert.
#
#     Returns:
#         float: The converted floating-point number.
#     """
#     cp = pointer(c_int(w))
#     fp = cast(cp, POINTER(c_float))
#     return fp.contents.value
#
# def reset_classifier(deep_reset=False, index_lo=0, index_hi=0, debug=False):
#     """
#     Reset the classifier. Optionally perform a deep reset.
#
#     Args:
#         deep_reset (bool): If True, perform a deep reset by setting specific memory locations to zero. Default is False.
#         index_lo (int): The lower index for the deep reset range. Default is 0.
#         index_hi (int): The upper index for the deep reset range. Default is 0.
#     """
#
#     nn_config = soccfg.NN_0.s_axi_config
#     nn_out = soccfg.NN_0.s_axi_out
#
#     if debug:
#         # Print debug information about the classifier configuration
#         print('INFO: classifier config MMIO')
#         print('INFO:   - base address:   @{:08x}'.format(nn_config.mmio.base_addr))
#         print('INFO:   - out_reset:      @{:04x}'.format(nn_config.register_map.out_reset.address))
#         print('INFO: classifier out MMIO')
#         print('INFO:   - base address:   @{:08x}'.format(nn_out.mmio.base_addr))
#     RESET_HI = 255
#     RESET_LO = 0
#
#     # Access the MMIO interface of the classifier
#     mmio_nn_config = MMIO(nn_config.mmio.base_addr, nn_config.mmio.length)
#     # This sends a "reset pulse" to the classifier
#     mmio_nn_config.write(nn_config.register_map.out_reset.address, RESET_HI)
#     mmio_nn_config.write(nn_config.register_map.out_reset.address, RESET_LO)
#     if deep_reset:
#         # Perform a deep reset by setting specific memory locations to zero
#         # Warning: This may run for a long time; use only for debugging
#         print('WARNING: Deep reset may run for some time... use only for debugging')
#         entry_count = ((index_hi - index_lo) + 1) * 2
#         for i in range(entry_count):
#             nn_out.mmio.array[i] = 0
#
# def configure_classifier(window_size, window_offset, scaling_factor, debug=False):
#     """
#     Configure the classifier with the specified parameters.
#
#     Args:
#         window_size (int): The size of the window for classification.
#         window_offset (int): The offset of the window for classification.
#         scaling_factor (int): The scaling factor for classification.
#         debug (bool): If True, print debug information. Default is False.
#     """
#
#     nn_config = soccfg.NN_0.s_axi_config
#
#     if debug:
#         # Print debug information about the classifier configuration
#         print('INFO: classifier config MMIO')
#         print('INFO:   - base address:   @{:08x}'.format(nn_config.mmio.base_addr))
#         print('INFO:   - window_size:    @{:04x} = {}'.format(nn_config.register_map.window_size.address, window_size))
#         print('INFO:   - window_offset:  @{:04x} = {}'.format(nn_config.register_map.window_offset.address, window_offset))
#         print('INFO:   - scaling_factor: @{:04x} = {}'.format(nn_config.register_map.scaling_factor.address, scaling_factor))
#
#     # Access the MMIO interface of the classifier and configure it
#     mmio_nn_config = MMIO(nn_config.mmio.base_addr, nn_config.mmio.length)
#     mmio_nn_config.write(nn_config.register_map.window_size.address, window_size)
#     mmio_nn_config.write(nn_config.register_map.window_offset.address, window_offset)
#     mmio_nn_config.write(nn_config.register_map.scaling_factor.address, scaling_factor)
#
# def get_classifier_prediction_count():
#     """
#     Get how many predictions (pulses) have run through the classifier. This is 0 at the very beginning or if you reset the classifier.
#
#     Returns:
#         int: The number of predictions made by the classifier.
#     """
#
#     nn_config = soccfg.NN_0.s_axi_config
#
#     # Access the MMIO interface of the classifier
#     mmio_nn_config = MMIO(nn_config.mmio.base_addr, nn_config.mmio.length)
#     # Read and return the prediction count
#     prediction_count = mmio_nn_config.read(nn_config.register_map.out_offset.address)
#     return prediction_count
#
# def get_classifier_prediction(index=0):
#     """
#     Get the classifier prediction for a specific index of the buffer.
#
#     Args:
#         index (int): The index of the prediction to retrieve. Default is 0.
#
#     Returns:
#         tuple: A tuple containing the ground state logit and the excited state logit.
#     """
#     WORD_SIZE_BYTE = 4
#     WORD_COUNT_PER_PREDICTION = 2
#
#     nn_out = soccfg.NN_0.s_axi_out
#
#     # Access the MMIO interface of the BRAM
#     mmio_nn_out = MMIO(nn_out.mmio.base_addr, nn_out.mmio.length)
#     # Read the logits for the ground state and excited state
#     ground_state_logit = mmio_nn_out.read(index * WORD_COUNT_PER_PREDICTION * WORD_SIZE_BYTE + 0)
#     excited_state_logit = mmio_nn_out.read(index * WORD_COUNT_PER_PREDICTION * WORD_SIZE_BYTE + WORD_SIZE_BYTE)
#     return ground_state_logit, excited_state_logit
#
# def get_classifier_predictions(index_lo=0, index_hi=0):
#     """
#     Get a range of classifier predictions from the buffer.
#
#     Args:
#         index_lo (int): The lower index of the range of predictions to retrieve. Default is 0.
#         index_hi (int): The upper index of the range of predictions to retrieve. Default is 0.
#
#     Returns:
#         list: A list of tuples, each containing the ground state logit and the excited state logit.
#     """
#     WORD_SIZE_BYTE = 4
#     WORD_COUNT_PER_PREDICTION = 2
#
#     nn_out = soccfg.NN_0.s_axi_out
#
#     # Access the MMIO interface of the BRAM
#     mmio_nn_out = MMIO(nn_out.base_address, nn_out.mmio.length)
#     # TODO: You can read the whole memory area rather than one element at a time and append
#     predictions = []
#     for index in range(index_lo, index_hi + 1):
#         ground_state_logit = mmio_nn_out.read(index * WORD_COUNT_PER_PREDICTION * WORD_SIZE_BYTE + 0)
#         excited_state_logit = mmio_nn_out.read(index * WORD_COUNT_PER_PREDICTION * WORD_SIZE_BYTE + WORD_SIZE_BYTE)
#         predictions.append([ground_state_logit, excited_state_logit])
#     return predictions
#
# def print_classifier_buffer(index_lo, index_hi):
#     """
#     Print the classifier buffer for a range of indices.
#
#     Args:
#         index_lo (int): The lower index of the range to print.
#         index_hi (int): The upper index of the range to print.
#     """
#
#     nn_out = soccfg.NN_0.s_axi_out
#
#     # Get the prediction count and buffer size
#     prediction_count = get_classifier_prediction_count()
#     buffer_size = nn_out.mmio.length
#     print('INFO: buffer base address: @{:08x}'.format(nn_out.mmio.base_addr))
#     print('INFO: buffer index :        {:6}'.format(prediction_count))
#     print('INFO: buffer size  :        {:6}B ({:6}KB)'.format(buffer_size, int((buffer_size)/1024)))
#     print('INFO:')
#     for i in range(index_lo, index_hi + 1):
#         # Get the logits for each prediction and print them
#         ground_state_logit, excited_state_logit = get_classifier_prediction(i)
#         print('INFO: g [{:5d}] {:08x} ({}) {}'.format(i, ground_state_logit, to_float(ground_state_logit), '<<<' if prediction_count == i else ''))
#         print('INFO: e [{:5d}] {:08x} ({}) {}'.format(i, excited_state_logit, to_float(excited_state_logit), '<<<' if prediction_count == i else ''))
