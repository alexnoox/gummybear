# Gummy Bear Walk Controls — Design

Date: 2026-08-09. Approved by user (ask-menu): AnimationTree + BlendSpace2D; 4 walk clips, no run; fixed camera; strafe-style (no character rotation).

## Goal

Animation-driven walking for the gummy bear. WASD physics movement already exists
(`scripts/gummy_bear.gd`, `move_and_slide`, SPEED 3.0); this feature makes the rig
animate to match: idle when still, directional walk cycles when moving, smooth
blending in between. This is the "Phase 4" promised by the controller's header comment.

## Scope

In scope:
1. Author 4 walk loops on the new 11-bone `GummyRig` in the root `gummy-bear.blend`.
2. Relax `blender/export_bear.py` to export the 5-action set.
3. Re-export `assets/bear.glb`, reimport in Godot.
4. Drive animation from velocity via a code-built AnimationTree/BlendSpace2D in
   `scripts/gummy_bear.gd`.

Out of scope (user-declined or YAGNI): run/sprint clip, camera follow, character
rotation toward velocity, TimeScale-based stride matching, fixing the pre-existing
`gummy_bear.gd:65` shadow warning.

## Animation contract (per clip)

Identical to the legacy pipeline (`blender/animate_bear.py`) so BlendSpace2D can
crossfade without foot skating:

- Names: `walk_fwd-loop`, `walk_back-loop`, `walk_left-loop`, `walk_right-loop`
  (plus existing `idle-loop`, untouched: frames 1–48).
- Scene fps 24. Locomotion clips frames 1–25; frame 25 duplicates frame 1.
- Shared contact pattern: left foot planted on frame 1, right foot planted on frame 13.
- In place: no horizontal travel on root/body.
- Stance foot solved onto z=0 from the evaluated pose (port the legacy `plant()` solver),
  not guessed.
- F-curve extrapolation CONSTANT.
- Each action stashed in its own muted NLA track on `GummyRig`; `idle-loop` stays the
  active action. (glTF `ACTIONS` export mode picks up active + stashed actions.)

New-rig adaptation: legacy rig had thigh/knee chains; new rig has single `leg.L/R` +
`foot.L/R`. Knee-bend curves fold into leg swing amplitude and foot pitch. World-axes
pose authoring (conjugation through each bone's rest basis) carries over unchanged —
it makes bone roll irrelevant.

## Exporter change

`blender/export_bear.py`: replace the "exactly 1 action" assertion + rename-to-idle
block with validation that the action name set equals exactly
`{idle-loop, walk_fwd-loop, walk_back-loop, walk_left-loop, walk_right-loop}` and the
active action is `idle-loop`. Everything else stays: root-blend guard, 11-bone/vgroup
checks, rig-only temporary scale + lift, SUBSURF suppression, `export_animation_mode='ACTIONS'`,
try/finally restore, save-after-restore, no undo ever.

## GLB / import contract

`assets/bear.glb`: 1 mesh, 1 skin (11 joints), **5 animations**, 0 cameras/lights,
height Y = 1.0 m, feet at Y≈0. Godot importer strips the `-loop` suffix (and sets loop
mode from it) → animations `idle`, `walk_fwd`, `walk_back`, `walk_left`, `walk_right`.

## Godot wiring

`scripts/gummy_bear.gd` builds the tree in code in `_ready()` (keeps the
suffix-tolerant `_resolve_animation()` in the loop; no editor sub-resources):

- `AnimationNodeBlendSpace2D`, blend points: `idle` at (0,0), `walk_fwd` at (0,−1),
  `walk_back` at (0,+1), `walk_left` at (−1,0), `walk_right` at (+1,0).
- `AnimationTree` child of `GummyBear`, `anim_player` → discovered AnimationPlayer,
  `active = true`.
- `_physics_process`: `parameters/blend_position = Vector2(velocity.x, velocity.z) / SPEED`.
  Bear faces −Z and never rotates, so world velocity is model-local. ACCEL_LERP's
  velocity smoothing smooths the blend for free.
- If any clip fails to resolve: warn, skip tree creation, existing idle `play()`
  fallback keeps current behavior.
- Wobble spring, KEY_C colour cycling, capsule/physics: untouched.

## Error handling

- Blender authoring is guarded by post-author verification (action list, frame ranges,
  contact-frame foot heights, extrapolation) printed and checked before save.
- Exporter raises on any contract violation and restores state in `finally`.
- Godot side degrades to current idle-only behavior with a `push_warning` if
  animations are missing.

## Verification

1. Blender: verification printout + rendered walk frames (contact/passing poses) from
   existing cameras; visual gait check.
2. GLB: parse JSON chunk — 5 animations, unchanged mesh/skin contract, idempotency on
   re-run.
3. Godot: headless `--import` clean; deterministic harness
   (`--fixed-fps 30 --write-movie … -- --shots`) captures show a coherent walk during the
   movement window; no missing-animation warnings in debug output; watch for
   >4-joint-influence deformation artifacts now that limbs animate harder.

## Risks

- Single-bone legs → stiffer gait than legacy. Acceptable for a gummy bear; tune swing
  and toe amplitudes at visual review.
- In-place cycle at 3.0 m/s travel may read as slight foot skate; tune amplitude only
  if it looks bad (no TimeScale node).
- Blender MCP session state: never `bpy.ops.ed.undo()` (corrupted the armature once).
