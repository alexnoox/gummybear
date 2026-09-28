# Orbit camera adopts strafe mode, retiring the fixed-body invariant

**Context**: The bear previously never rotated — its body yaw stayed fixed, so world-space velocity and bear-local velocity were identical, and that identity fed straight into the animation blendspace. The stage used a static camera, so no camera-relative input was ever needed.

**Decision**: Replace the static stage camera with a mouse-driven orbit rig. The bear's body yaw now tracks camera yaw (with gummy lag), WASD input is camera-relative, and the animation blendspace is fed bear-local velocity instead of world velocity. This is strafe mode: the bear side-steps and back-pedals using its four directional walk clips rather than turning to face its velocity.

**Alternatives considered**:
- A fixed-offset chase camera that preserves the old never-rotates invariant — rejected because it doesn't give the player camera control.
- Turn-to-move facing (bear yaws to face its velocity) — rejected because it would orphan 3 of the 4 authored directional walk clips, leaving only the forward clip in use.

**Consequences**: The `--shots` harness has no mouse input, so it relies on the orbit rig defaulting to camera yaw 0 to reproduce today's framing (bear faces −Z, `move_right` strafes world +X). Any future code that assumes velocity is expressed in world space rather than bear-local space is a bug, not a valid reading of the old invariant.

**Amendment (2026-09-26)**: The body yaw now follows the camera only while movement input is held. An idle bear turning toward the camera slid its feet, because there is no turn-in-place clip. The `--shots` harness asserts this by orbiting the idle camera a quarter turn.

**Amendment (2026-09-28)**: An idle bear now turns, quickly, to face a throw (yaw lerp 15/s for 0.4 s). The ball leaves along the camera, so a bear throwing sideways or backwards looked wrong, and the kid playtesters need to see which way they threw. The brief foot slide this causes was accepted. An idle bear still doesn't turn when only the camera orbits. The `--shots` harness asserts both.
