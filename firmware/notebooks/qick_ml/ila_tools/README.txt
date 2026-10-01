NN ILA capture and analysis tools

Tools to measure when the NN classifier's window starts, on the nn_ila build
(make bitstream DAC=230 NN=1 ILA=1 in firmware/tools). They log the ILA around
each shot, then find, for every shot, the window start for which the C model
reproduces the logit the hardware wrote. Ported from the tProc v1 branch
(ml-integration-tproc-v1-2026, firmware/ila_tools/): the nn_ila ILA of this
design has the same probes (d_1_i/system_ila_0: probe0_1 the tProc trigger,
probe1_1 the trigger NN_0 sees, slot 0 the NN input stream, slot 1 the NN
prediction writes), so analyze.py and ila_capture.tcl are unchanged; the
board side runs the tProc v2 program.

On the tProc v1 branches, with the fixed IP (md5 8e7e8128..., ml-quantum-readout
f2361c7), the window started exactly 5 + window_offset samples after NN_0's
trigger, no jitter: window_offset 95 puts it at trace sample 100. The raw
captures are not kept in git.

Files
  analyze.py       per shot: NN trigger, logit write, the window start whose
                   C-model logit equals the hardware logit, trace alignment.
                   Reads <capture dir>/shot_<i>.csv and shots.json, and loads
                   libnn_eval.so from its own directory
  ila_capture.tcl  host side (Vivado batch), arms the ILA on a trigger probe:
                   probe1_1 by default (nn_ila: the trigger NN_0 sees),
                   probe0_1 for the ila build (the tProc trigger)
  ila_shots_wo.py  board side, loads qick_216_tprocv2_dac<DAC>_<build>.bit
                   (--build nn_ila, nn_replay_ila or ila, --dac 230 by
                   default), fires the shots and saves the decimated I/Q
                   trace of each shot in shots.json, with a --window-offset
                   option. Runs from the
                   board's checkout of this repo: bitstream from
                   firmware/notebooks/qick_ml/216/<branch>/, driver from this
                   repo's qick_lib, program from qick_ml_lib.py, pulse and
                   window settings from nn_count_check.py

Run everything below from this directory (firmware/notebooks/qick_ml/ila_tools).

C model for analyze.py (bit-exact; see ../nn_model_accuracy_check):

  make -C ../nn_model_accuracy_check libnn_eval.so
  cp ../nn_model_accuracy_check/libnn_eval.so .

Analyze a capture of the nn_ila build (a directory made by the capture step
below):

  python3 analyze.py cap_woN

analyze.py needs the NN probes, so it does not apply to ila captures.

Capture. The host reaches the board's Vivado hw_server through an ssh tunnel
(localhost:3120 -> <hw_server host>:3121). The bitstream must be in the
board's checkout (make copy in firmware/tools) and the checkout on the same
commit as the host's. <B> is the board's checkout of this repo, e.g.
/home/xilinx/jupyter_notebooks/qick-ml-integration-tproc-v2-2026, and <OUT>
this design's out/ directory,
../../../projects/qick_tprocv2_216_standard_1ch/out.

  board: mkdir -m 777 /tmp/ila_capture/woN, then, as root in a login shell
    (bash -lc, for BOARD):
    /usr/local/share/pynq-venv/bin/python3 \
      <B>/firmware/notebooks/qick_ml/ila_tools/ila_shots_wo.py \
      --build nn_ila --shots 10 --dir /tmp/ila_capture/woN --window-offset N
  host (after source ../../../tools/envsetup.sh):
    vivado -mode batch -nojournal -nolog -source ila_capture.tcl -tclargs \
      localhost:3120 <OUT>/qick_216_tprocv2_dac230_nn_ila.ltx cap_woN 10 \
      /tmp/ila_capture/woN
  then scp the board's shots.json into cap_woN/.

For the ila build, pass --build ila on the board, and on the host its .ltx
(<OUT>/qick_216_tprocv2_dac230_ila.ltx) and probe0_1 as the sixth argument
of ila_capture.tcl.

For the nn_replay_ila build (readout replay player, in live mode after the
bitstream load), pass --build nn_replay_ila on the board and its .ltx
(<OUT>/qick_216_tprocv2_dac230_nn_replay_ila.ltx) on the host; the probes
and analyze.py are the same as for nn_ila.
