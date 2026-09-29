NN ILA capture and analysis tools

Tools used to measure when the NN classifier's window starts (the Bug 3
window-start measurement, 2026-09-28), on the nn_ila build
(firmware/package/qick_216_nn_ila). They log the ILA around each shot, then
find, for every shot, the window start for which the C model reproduces the
logit the hardware wrote.

Results: with the volatile-trigger IP (md5 4e2958b7...) the window started
~= 11 + 3 * window_offset trace samples after NN_0's trigger, with 0-5 cycles
jitter. With the fixed IP (md5 8e7e8128..., ml-quantum-readout f2361c7) it
starts exactly 5 + window_offset samples after the trigger, no jitter:
window_offset 95 puts it at trace sample 100. The raw captures are not kept in
git.

Files
  analyze.py       per shot: NN trigger, logit write, the window start whose
                   C-model logit equals the hardware logit, trace alignment.
                   Reads <capture dir>/shot_<i>.csv and shots.json, and loads
                   libnn_eval.so from its own directory
  ila_capture.tcl  host side (Vivado batch), arms the ILA on probe1. Probe
                   names are those of the nn_ila build (qick_216_nn_ila.ltx)
  ila_shots_wo.py  board side, saves the decimated I/Q trace of each shot in
                   shots.json, with a --window-offset option

Run everything below from this directory (firmware/ila_tools).

C model for analyze.py (bit-exact; the C wrapper nn_eval.cpp is in
qick_ml/nn_model_accuracy_check):

  make -C ../../qick_ml/nn_model_accuracy_check libnn_eval.so
  cp ../../qick_ml/nn_model_accuracy_check/libnn_eval.so .

Analyze a capture (a directory made by the capture step below):

  python3 analyze.py cap_woN

Capture. The host reaches the board's Vivado hw_server through an ssh tunnel
(localhost:3120 -> <hw_server host>:3121):

  board: first provide ~/nn_phase_check/nn_phase_check.py (see below), then
    mkdir -m 777 /tmp/nn_ila_bug3/woN, copy ila_shots_wo.py there, then, as root,
    cd ~/nn_phase_check && env PYTHONPATH=/home/xilinx/nn_phase_check \
      /usr/local/share/pynq-venv/bin/python3 /tmp/nn_ila_bug3/ila_shots_wo.py \
      --shots 10 --dir /tmp/nn_ila_bug3/woN --window-offset N
  host (after source ../envsetup.sh):
    vivado -mode batch -nojournal -nolog -source ila_capture.tcl -tclargs \
      localhost:3120 ../package/qick_216_nn_ila/qick_216_nn_ila.ltx cap_woN 10 \
      /tmp/nn_ila_bug3/woN
  then scp the board's shots.json into cap_woN/.

nn_phase_check.py is not in the repo. ila_shots_wo.py does

  from nn_phase_check import (CONFIG, WINDOW_SIZE, WINDOW_OFFSET,
      SCALING_FACTOR, REPO_QICK_ML, pulse_iq, QickSoc, qick_ml_lib,
      LoopbackProgram, to_float, reset_classifier, configure_classifier,
      get_classifier_prediction_count, get_classifier_prediction)

so the module must provide:
  - CONFIG, WINDOW_SIZE, WINDOW_OFFSET, SCALING_FACTOR: the values at the top
    of qick_ml/nn_count_check.py (pulse length 560, adc_trig_offset 45, window
    400, offset 95, scaling 1);
  - REPO_QICK_ML: the qick_ml directory of the board's repo, e.g.
    ~/jupyter_notebooks/qick-ml-integration-2024/qick_ml (used to find
    216/ml-integration-2024/qick_216_nn_ila.bit), and that directory on
    sys.path so that qick_ml_lib imports;
  - QickSoc (from qick), qick_ml_lib (the module) and LoopbackProgram,
    to_float, reset_classifier, configure_classifier,
    get_classifier_prediction_count, get_classifier_prediction (from
    qick_ml_lib);
  - pulse_iq(iq) -> dict(phase_deg, amp, plateau), for iq = the decimated
    trace [I, Q] returned by acquire_decimated: the plateau is the set of
    samples with |I + jQ| above half of the peak (as in
    qick_ml_lib.measure_phase), amp is the mean |I + jQ| over it, phase_deg
    the angle of (mean I + j mean Q) over it in degrees, and plateau is
    [first sample, last sample] of that set ([101, 500] for a loopback pulse
    filling the window). Only phase_deg is printed; the other two are saved.
