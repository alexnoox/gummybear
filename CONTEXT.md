# Gummy Bear

A third-person platformer where a gelatinous bear character moves through a stage under a player-driven orbit camera.

## Language

**Gummy lag**:
The deliberate, low-rate smoothing that makes the bear feel gelatinous — velocity and body yaw ooze toward their targets rather than snapping. The camera is exempt: it stays crisp.
_Avoid_: Damping, easing, interpolation lag

**Strafe mode**:
The locomotion model where the bear's body yaw follows the camera yaw and WASD moves relative to the camera, so the bear side-steps/back-pedals using its four directional walk clips instead of turning to face its velocity.
_Avoid_: Camera-relative movement, relative controls

**Orbit rig**:
The player camera — a mouse-driven third-person rig that orbits and follows the bear (captured mouse, Esc releases).
_Avoid_: Chase camera, follow camera, third-person camera