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
  ila_capture.tcl  host side (Vivado batch), arms the ILA on a trigger probe:
                   probe1_1 by default (nn_ila: the trigger NN_0 sees),
                   probe0_1 for orig_ila (the tProc trigger)
  ila_shots_wo.py  board side, loads qick_216_<build>.bit (--build nn_ila or
                   orig_ila), fires the shots and saves the decimated I/Q trace
                   of each shot in shots.json, with a --window-offset option.
                   Runs from the board's checkout of this repo: bitstream from
                   qick_ml/216/<branch>/, driver from this repo's qick_lib,
                   pulse and window settings from qick_ml/nn_count_check.py

Run everything below from this directory (firmware/ila_tools).

C model for analyze.py (bit-exact; the C wrapper nn_eval.cpp is in
qick_ml/nn_model_accuracy_check):

  make -C ../../qick_ml/nn_model_accuracy_check libnn_eval.so
  cp ../../qick_ml/nn_model_accuracy_check/libnn_eval.so .

Analyze a capture of the nn_ila build (a directory made by the capture step
below):

  python3 analyze.py cap_woN

analyze.py needs the NN probes, so it does not apply to orig_ila captures.

Capture. The host reaches the board's Vivado hw_server through an ssh tunnel
(localhost:3120 -> <hw_server host>:3121). The bitstream must be in the
board's checkout (make -C .. copy-zcu216) and the checkout on the same
commit as the host's. <B> is the board's checkout of this repo, e.g.
/home/xilinx/jupyter_notebooks/qick-ml-integration-tproc-v1-2026.

  board: mkdir -m 777 /tmp/ila_capture/woN, then, as root in a login shell
    (bash -lc, for BOARD):
    /usr/local/share/pynq-venv/bin/python3 <B>/firmware/ila_tools/ila_shots_wo.py \
      --build nn_ila --shots 10 --dir /tmp/ila_capture/woN --window-offset N
  host (after source ../envsetup.sh):
    vivado -mode batch -nojournal -nolog -source ila_capture.tcl -tclargs \
      localhost:3120 ../package/qick_216_nn_ila/qick_216_nn_ila.ltx cap_woN 10 \
      /tmp/ila_capture/woN
  then scp the board's shots.json into cap_woN/.

For orig_ila, pass --build orig_ila on the board, and on the host its .ltx
(../package/qick_216_orig_ila/qick_216_orig_ila.ltx) and probe0_1 as the
sixth argument of ila_capture.tcl.

The first captures (2026-09-28, branch ml-integration-2024) ran an earlier
version of ila_shots_wo.py that imported its settings and helpers from a
board-only module, ~/nn_phase_check/nn_phase_check.py, since deleted; the
script is now self-contained.
