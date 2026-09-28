# Cycle 1: Controller Support and Faster Movement

Date: 2026-09-28. Agreed in chat (grilling session). The first of four
feature cycles for the red bear's game (tagging green bears with thrown balls):
1. controller and speed
2. throwing and tag
3. platforming stage
4. jump/fall animation and a squash on landing

**Goal:** the user's son can play the current bear on an Xbox pad, and the
bear moves fast enough to feel like a game.

## Decisions

- **Xbox pad.** The left stick moves the bear, and its speed is proportional
  to how far the stick is pushed. The right stick orbits the camera, with its
  up/down **inverted**. A jumps. There is no zoom on the pad. Keyboard and mouse
  keep working as today, and mouse look stays non-inverted.
- **Top speed is 2.5 m/s** (`SPEED`). The walk clips play at 1× up to 1.0 m/s
  (`STRIDE_SPEED`, the accepted look until now). Above that, their rate scales
  in proportion to ground speed, which keeps the foot glide already accepted
  instead of matching the authored strides (0.45 m/s forward, which would need
  about 5.6× playback). The blend position is velocity divided by
  `STRIDE_SPEED`, capped at length 1, so the blend between idle and walk below
  1 m/s is unchanged.
- **Strafe mode is kept** (ADR 0001 is unchanged).
- **The player is fixed cherry red.** The `cycle_colour` action, the C key and
  the palette cycling are removed.
- Gummy lag, jump height and the camera pitch limits are unchanged. Speed and
  stick-look rate are each one constant, tuned in playtest.

## Tasks

1. **Input map** (`project.godot`): add joypad axis events to the
   `move_*` actions (left stick, axes 0 and 1) and the A button (0) to `jump`.
   Add `look_left`, `look_right`, `look_up` and `look_down` on the right stick
   (axes 2 and 3). Remove `cycle_colour`.
2. **Locomotion** (`scripts/gummy_bear.gd`):
   - `SPEED := 2.5`, plus a new `STRIDE_SPEED := 1.0`.
   - The tree root becomes an `AnimationNodeBlendTree` wired
     `locomotion (BlendSpace2D) → speed (TimeScale) → output`.
   - Each tick, feed `parameters/locomotion/blend_position` and
     `parameters/speed/scale`.
   - Drop the colour cycling.
3. **Stick look** (`scripts/orbit_camera.gd`): in `_process`, before the
   snap, read `Input.get_vector("look_left", "look_right", "look_up", "look_down")`.
   - Yaw matches the mouse: right orbits right.
   - Pitch is inverted: pushing up tilts the view down.
   - It works whether or not the mouse is captured.
   - Rate constant: `STICK_SPEED` in rad/s.
4. **Harness** (`scripts/test_stage.gd`): cheap new assertions.
   - The drive reaches at least 2.2 m/s horizontal speed.
   - Pressing `look_right` lowers yaw.
   - Pressing `look_up` lowers arm pitch (inverted).
   - The old checks stay green; widen the walk silhouette limit only if the
     faster clips need it, and say so.
5. **Docs:** the README controls table, the "How it works" colour line, the
   script header comments, and the `CONTEXT.md` orbit rig entry (mouse or right
   stick).

## Verify

- `$GODOT --path . -- --shots; echo "exit=$?"` → `exit=0`, rise still 0.41–0.43 m.
- Manual (you and your son, with the Xbox pad): the move speed feels right, the
  scurry looks acceptable, the inverted camera feels right, and A jumps.
