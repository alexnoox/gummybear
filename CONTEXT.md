# Gummy Bear

A third-person platformer where a gelatinous bear character moves through a stage under a player-driven orbit camera.

## Language

**Gummy lag**:
The deliberate, low-rate smoothing that makes the bear feel gelatinous — velocity and body yaw ooze toward their targets rather than snapping. The camera is exempt: it stays crisp.
_Avoid_: Damping, easing, interpolation lag

**Strafe mode**:
The locomotion model where, while the player is moving, the bear's body yaw follows the camera yaw and WASD moves relative to the camera, so the bear side-steps/back-pedals using its four directional walk clips instead of turning to face its velocity. An idle bear does not turn when the camera orbits; it only turns, quickly, to face a throw.
_Avoid_: Camera-relative movement, relative controls

**Orbit rig**:
The player camera — a third-person rig that orbits and follows the bear, driven by the mouse (captured mouse, Esc releases, a left click recaptures) or the pad's right stick (up/down inverted).
_Avoid_: Chase camera, follow camera, third-person camera

**Player bear**:
The red bear the player drives. Always cherry red.
_Avoid_: Hero, avatar, red bear (as a type name)

**Green bear**:
A target bear: the same gummy bear body in lime, which wanders inside the candy fence and flees when the player bear comes within about 4 m. Green bears stay green; a hit knocks them down, it never converts them.
_Avoid_: Enemy, NPC, tagged bear

**Knocked down**:
The state of a green bear hit by a ball: shoved along the ball's path with an upward pop, then a limp ragdoll that stays down until the round resets. A knocked-down bear is never an aim assist target, but balls still shove it around.
_Avoid_: Dead, killed, tagged, eliminated

**Aim assist**:
The bend a throw takes toward the standing green bear best aligned with the camera (within about ±30° and 10 m), leading that bear's velocity. Deliberately strong: the player is a small child.
_Avoid_: Auto-aim, lock-on, homing

**Marker**:
The bouncing yellow down-arrow floating over the green bear that aim assist will throw the next ball at.
_Avoid_: Reticle, crosshair, target indicator

**Candy fence**:
The low pastel fence round the stage that keeps the green bears in.
_Avoid_: Wall, boundary

**Round**:
One game, from every green bear standing (30 of them) to all of them knocked down. The win brings fireworks, then a restart button (no words) that starts a fresh round.
_Avoid_: Level, match, game over
