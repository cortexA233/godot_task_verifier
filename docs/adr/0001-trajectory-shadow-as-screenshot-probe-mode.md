# Keep Trajectory Shadow Evidence In The Screenshot Probe

Accepted. The side-oblique trajectory shadow run will be added as a mode of the existing screenshot probe rather than as a separate verifier CLI. This keeps render-capable evidence behind one auxiliary entry point, preserves the formal grader as the only official score command, and avoids teaching users a second screenshot command for evidence that is still `used_for_score: false`.

The trajectory shadow mode should be requested explicitly while it is being calibrated instead of being folded into the existing `both` mode. That keeps current debug-arena plus main-scene screenshot evidence stable and prevents the new multi-heading trajectory artifacts from changing the meaning, runtime, or output size of existing screenshot probe runs.
