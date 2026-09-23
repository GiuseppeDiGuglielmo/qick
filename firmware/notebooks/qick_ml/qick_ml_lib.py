"""
Support library for the send-receive-pulse ZCU216/QICK experiment (tProc v2).

Provides the QICK program that fires a single readout pulse and captures the
loopback ADC trace (LoopbackProgram, built on tProc v2's AveragerProgramV2), a
couple of numeric formatting helpers for dumping I/Q samples as hex
(float_to_hex32, int_to_twos_complement_hex32), and a set of MMIO-based
helpers for driving the FPGA-resident NN classifier that scores each pulse
(reset_classifier, configure_classifier, get_classifier_prediction_count,
get_classifier_prediction, get_classifier_predictions, print_classifier_buffer).

The classifier helpers are unchanged from the tProc v1 branch: they talk to
the classifier IP over MMIO, independent of which tProc version generated the
pulse, and are kept disabled (HAS_NN=0 in the notebook) until an NN IP is
built into a tProc v2 bitstream.

Call set_soccfg() once with the QickSoc/QickConfig handle before using any
classifier helper.
"""

from ctypes import *
import struct

from pynq import MMIO
from qick.asm_v2 import AveragerProgramV2

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


class LoopbackProgram(AveragerProgramV2):
    """
    tProc v2 QICK program that fires one readout pulse on a generator channel
    and captures the decimated I/Q trace on the paired ADC channel(s), for a
    simple DAC-to-ADC loopback measurement.

    Unlike the tProc v1 version of this program, pulse/readout timing is
    specified in microseconds and frequency in MHz (cfg["length"], cfg["sigma"],
    cfg["readout_length"], cfg["trig_time"]), and gain is a float in [-1, 1]
    rather than a raw DAC code.
    """
    def _initialize(self, cfg):
        res_ch = cfg["res_ch"]

        # set the nyquist zone
        self.declare_gen(ch=res_ch, nqz=1)

        # configure the readout length and downconversion frequency for every
        # declared ADC channel
        for ch in cfg["ro_chs"]:
            self.declare_readout(ch=ch, length=cfg["readout_length"])
            self.add_readoutconfig(ch=ch, name=f"ro{ch}", freq=cfg["pulse_freq"], gen_ch=res_ch)
            self.send_readoutconfig(ch=ch, name=f"ro{ch}", t=0)

        style = cfg["pulse_style"]

        if style in ["flat_top", "arb"]:
            sigma = cfg["sigma"]
            self.add_gauss(ch=res_ch, name="measure_env", sigma=sigma, length=sigma * 5, even_length=True)

        if style == "const":
            self.add_pulse(ch=res_ch, name="measure", style=style,
                            freq=cfg["pulse_freq"], length=cfg["length"],
                            phase=cfg["res_phase"], gain=cfg["pulse_gain"])
        elif style == "flat_top":
            # The first half of the envelope ramps up the pulse, the second half ramps down the pulse
            self.add_pulse(ch=res_ch, name="measure", style=style, envelope="measure_env",
                            freq=cfg["pulse_freq"], length=cfg["length"],
                            phase=cfg["res_phase"], gain=cfg["pulse_gain"])
        elif style == "arb":
            self.add_pulse(ch=res_ch, name="measure", style=style, envelope="measure_env",
                            freq=cfg["pulse_freq"],
                            phase=cfg["res_phase"], gain=cfg["pulse_gain"])

    def _body(self, cfg):
        # fire the pulse at t=0
        # trigger all declared ADCs at cfg["trig_time"]
        # pulse PMOD0_0 for a scope trigger
        # the reps/final_delay loop (set on the program, not here) gives the
        # tProc time to get back ahead of the clock before the next shot
        self.pulse(ch=cfg["res_ch"], name="measure", t=0)
        self.trigger(ros=cfg["ro_chs"], pins=[0], t=cfg["trig_time"])


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
# soccfg.axi_blk_bram_ctrl_0. Ported unchanged from the tProc v1 branch: this
# is pure MMIO/register access and does not depend on which tProc version
# generated the pulse. Disabled (HAS_NN=0) until an NN IP is built into a
# tProc v2 bitstream.

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
    print('INFO: buffer size  : {:6} ({:6}KB)'.format(buffer_size, (buffer_size * 4) / 1024))
    print('INFO:')
    for i in range(index_lo, index_hi + 1):
        # Get the logits for each prediction and print them
        ground_state_logit, excited_state_logit = get_classifier_prediction(i)
        print('INFO: g [{:5d}] {:08x} ({}) {}'.format(i, ground_state_logit, to_float(ground_state_logit), '<<<' if prediction_count == i else ''))
        print('INFO: e [{:5d}] {:08x} ({}) {}'.format(i, excited_state_logit, to_float(excited_state_logit), '<<<' if prediction_count == i else ''))
