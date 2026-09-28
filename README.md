# Gummy Bear

A rigged, animated gummy bear character PoC. The mesh and 11-bone rig live in
`gummy-bear.blend`; scripts author the walk loops and export a GLB that Godot
drives with a code-built locomotion blend tree under a mouse-orbit camera.

![Gummy bear render](renders/final_Cam34.png)

## Stack

- **Godot 4.7** (Forward+, Jolt Physics) — runtime, character controller, gummy shader
- **Blender** (scripted, headless-friendly) — mesh construction, rigging, animation, GLB export

## Controls

| Keyboard / mouse | Xbox pad | Action |
|------------------|----------|--------|
| WASD  | Left stick | Walk (forward / back / strafe); the stick is analog, up to 2.5 m/s |
| Space | A | Jump (grounded only, no double jump) |
| Mouse | Right stick | Orbit camera (bear turns to follow while walking); the stick's up/down is inverted |
| Wheel | — | Zoom |
| Esc   | — | Release / recapture mouse (left click also recaptures) |

## Layout

```
blender/            Asset pipeline scripts (run inside Blender against gummy-bear.blend)
  walk_actions.py     Four in-place walk loops (24 fps, frames 1-25, shared contact phase)
  export_bear.py      Exports assets/bear.glb (idle + 4 walk clips, nothing else)
gummy-bear.blend    Source mesh, rig and idle action (hand-maintained)
assets/bear.glb     Exported character consumed by Godot
scenes/             gummy_bear.tscn (character), test_stage.tscn (main scene)
scripts/            gummy_bear.gd (controller), orbit_camera.gd (camera rig),
                    test_stage.gd (dev harness)
shaders/            gummy_depth.gdshader (depth pre-pass), gummy.gdshader
                    (translucent candy look, rim light, contact fade)
docs/               Specs, ADRs, plans
renders/            README hero render
```

## How it works

- `scripts/gummy_bear.gd` finds the GLB's `AnimationPlayer` at runtime and
  builds an `AnimationTree` in code: a `BlendSpace2D` (idle at the origin,
  the four walk loops on the axes) feeding a `TimeScale`. Blend position is fed
  body-local horizontal velocity (strafe mode, see
  docs/adr/0001-orbit-camera-strafe-mode.md); above 1 m/s the walks play
  proportionally faster instead. `SYNC_MODE_INDEPENDENT` keeps the
  phase-locked walk cycles from popping on direction changes.
- Movement is a plain `CharacterBody3D`: lerped horizontal velocity (deliberate
  gummy lag), gravity, and a physics-only grounded jump — no jump animation,
  by design (see `docs/specs/2026-08-10-stable-silhouette-space-jump.md`).
- The gummy look is two shader passes on one material
  (`materials/gummy_material.tres`): a depth-only pre-pass
  (`shaders/gummy_depth.gdshader`) writes the bear's nearest-surface depth,
  then its `next_pass` (`shaders/gummy.gdshader`, `render_priority = 1` so it
  draws after the depth pass) shades only the front-most surface, with a
  per-instance colour parameter (the player is cherry red).

## Running

Open the project in Godot 4.7 and run — `scenes/test_stage.tscn` is the main
scene.

Headless evidence run (captures screenshots to `.dev/` and validates the jump
contract, the idle/walk silhouettes, top speed, stick look direction, and that
an idle bear doesn't turn when the camera orbits):

```
godot -- --shots
```

## Rebuilding the asset

The mesh, rig and idle action are hand-maintained in `gummy-bear.blend`; there
is no script that rebuilds them. With that file open in Blender, run
`blender/walk_actions.py` (re-authors the four walk loops) and then
`blender/export_bear.py` (writes `assets/bear.glb`). Both scripts validate
their contracts before writing and **save over `gummy-bear.blend`**, so commit
or back up first. Headless:

    blender -b gummy-bear.blend --python blender/walk_actions.py
    blender -b gummy-bear.blend --python blender/export_bear.py

Contract: bear is 1 m tall, feet on the floor, exactly five exported actions
(`idle-loop` plus `walk_{fwd,back,left,right}-loop`), no scale animation.
