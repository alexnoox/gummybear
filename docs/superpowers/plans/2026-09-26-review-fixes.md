# Code Review Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix every finding from the 2026-09-26 whole-repo review: dead Blender pipeline, machine-specific paths, repo bloat, and six Godot runtime issues.

**Architecture:** Each task is one self-contained commit. Blender tasks are verified by running the scripts headless against a *scratch copy* of the repo (never the real `.blend`). Godot tasks are verified by the existing `--shots` harness (`scripts/test_stage.gd`), extended where a behaviour can be asserted automatically, plus a short manual check where it can't (mouse capture, judder).

**Tech Stack:** Godot 4.7 (Forward+, Jolt), GDScript, Godot shading language, Blender 5.2 Python (`bpy`).

**Spec:** The review findings, reproduced in "Findings" below.

## Global Constraints

- Godot binary: `GODOT=/Applications/Godot_mono.app/Contents/MacOS/Godot`
- Blender binary: `BLENDER=/Applications/Blender.app/Contents/MacOS/Blender`
- Harness command (run from repo root): `$GODOT --path . -- --shots; echo "exit=$?"`
- Baseline harness result before any task (2026-09-26): `exit=0`, `jump rise=0.421 air_dx=0.081`, idle silhouette `width 1.000 / height 1.016`, walk silhouette `width 1.093 / height 1.016`. Every task must end with `exit=0`, and the jump rise must stay within 0.41–0.43 m unless the task says otherwise.
- **Never run a Blender script against the repo's own `gummy-bear.blend`.** Both `walk_actions.py` and `export_bear.py` save over the open blend. Use a scratch copy.
- Do not rewrite git history (no filter-repo); only untrack files going forward.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Match existing style: tabs in GDScript, `##` doc comments explaining *why*, typed `:=` declarations.

## Findings (the spec)

1. `build_bear.py`, `rig_bear.py`, `animate_bear.py` target `blender/gummy_bear.blend` and build a 27-bone rig / ~6.2k-tri mesh, while `walk_actions.py` + `export_bear.py` require the root `gummy-bear.blend` with 11 bones / 96,690 faces. The legacy pipeline is dead and the README describes a build→rig→animate→export flow that cannot produce the shipped asset.
2. Absolute `/Users/alex/...` paths in `export_bear.py:26` and `walk_actions.py:65`; path comparison is inconsistent (`==` vs `normpath`).
3. The gummy shader draws one transparent self-overlapping mesh with `depth_draw_always` and no pre-pass → order-dependent self-overlap. (`depth_prepass_alpha` is *not* the fix: it discards fragments below the opaque-prepass threshold, and the bear's alpha is 0.8.)
4. Gravity read once from ProjectSettings instead of `get_gravity()`.
5. The C key uses the layout-dependent `keycode` rather than an input action using `physical_keycode`; the harness silently assumes a red bear.
6. The camera follows at physics rate → judder on high-refresh displays.
7. The idle bear turns in place (feet sliding) when the camera orbits.
8. After Esc, only Esc captures the mouse again; clicking doesn't.
9. `renders/` tracks ~44 iteration PNGs + `.import` files (22 MB) that Godot imports.

**Out of scope:** the walk blend still cycling while airborne. The stable-silhouette spec (`docs/specs/2026-08-10-stable-silhouette-space-jump.md`) deliberately has no jump animation, and a proper fix is a jump/fall state, which is a feature rather than a fix.

## File map

| File | Tasks | Responsibility |
|---|---|---|
| `blender/{build,rig,animate}_bear.py`, `blender/gummy_bear.blend` | 1 | deleted |
| `README.md`, `AGENTS.md` | 1, 6 | docs match reality |
| `blender/export_bear.py`, `blender/walk_actions.py` | 1, 2 | portable paths |
| `.gitignore`, `renders/.gdignore` | 3 | render hygiene |
| `scripts/gummy_bear.gd` | 4, 5, 7 | controller |
| `project.godot` | 5, 8 | input map, physics interpolation |
| `scripts/test_stage.gd` | 5, 7 | harness assertions |
| `scripts/orbit_camera.gd` | 6, 8 | camera rig |
| `CONTEXT.md`, `docs/adr/0001-orbit-camera-strafe-mode.md` | 7 | strafe-mode definition |
| `shaders/gummy_depth.gdshader` (new), `materials/gummy_material.tres` | 9 | two-pass gummy material |

---

### Task 1: Retire the legacy Blender pipeline

**Files:**
- Delete: `blender/build_bear.py`, `blender/rig_bear.py`, `blender/animate_bear.py`, `blender/gummy_bear.blend`
- Modify: `blender/walk_actions.py:1-3`, `README.md`, `AGENTS.md`

**Interfaces:** Produces the fact, which later docs rely on, that the only Blender scripts are `walk_actions.py` and `export_bear.py`.

- [ ] **Step 1: Delete the legacy files**

```bash
git rm blender/build_bear.py blender/rig_bear.py blender/animate_bear.py blender/gummy_bear.blend
```

- [ ] **Step 2: Fix the walk_actions header's reference**

In `blender/walk_actions.py`, replace lines 2–3:

```python
# muted NLA track. Ported from blender/animate_bear.py (the legacy 15-bone rig)
# onto the rebuilt 11-bone rig in gummy-bear.blend.
```

with:

```python
# muted NLA track. Ported from the legacy animate_bear.py (removed; see git
# history) onto the rebuilt 11-bone rig in gummy-bear.blend.
```

- [ ] **Step 3: Rewrite README sections that describe the dead pipeline**

Replace the intro paragraph (lines 3–6) with:

```markdown
A rigged, animated gummy bear character PoC. The mesh and 11-bone rig live in
`gummy-bear.blend`; scripts author the walk loops and export a GLB that Godot
drives with a code-built locomotion blend tree under a mouse-orbit camera.
```

Replace the `Layout` code block with:

```
blender/            Asset pipeline scripts (run inside Blender against gummy-bear.blend)
  walk_actions.py     Four in-place walk loops (24 fps, frames 1-25, shared contact phase)
  export_bear.py      Exports assets/bear.glb (idle + 4 walk clips, nothing else)
gummy-bear.blend    Source mesh, rig and idle action (hand-maintained)
assets/bear.glb     Exported character consumed by Godot
scenes/             gummy_bear.tscn (character), test_stage.tscn (main scene)
scripts/            gummy_bear.gd (controller), orbit_camera.gd (camera rig),
                    test_stage.gd (dev harness)
shaders/            gummy.gdshader (translucent candy look, rim light, contact fade)
docs/               Specs, ADRs, plans
renders/            README hero render
```

In "How it works", replace `Blend position is fed directly from
  horizontal velocity;` with `Blend position is fed body-local horizontal
  velocity (strafe mode, see docs/adr/0001-orbit-camera-strafe-mode.md);`.

Replace the whole "Rebuilding the asset" section body with:

```markdown
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
```

- [ ] **Step 4: Update AGENTS.md**

Replace the intro paragraph with:

```markdown
Godot 4 third-person character project. The bear's mesh, rig and idle action
are hand-maintained in Blender (`gummy-bear.blend`); `blender/walk_actions.py`
authors the walk loops and `blender/export_bear.py` exports `assets/bear.glb`.
Gameplay lives in `scripts/gummy_bear.gd` and `scripts/orbit_camera.gd`.
```

- [ ] **Step 5: Verify no live references remain**

Run: `git grep -n "build_bear\|rig_bear\|animate_bear\|blender/gummy_bear"`
Expected: matches only under `docs/superpowers/` (historical plans and specs, which stay as-is) and the "see git history" line in `walk_actions.py`.

- [ ] **Step 6: Commit**

```bash
git add -A blender README.md AGENTS.md
git commit -m "chore(blender): retire legacy build/rig/animate pipeline

The scripts targeted blender/gummy_bear.blend and a 27-bone rig that the
exporter rejects; gummy-bear.blend is the hand-maintained source of truth."
```

---

### Task 2: Portable Blender script paths

**Files:**
- Modify: `blender/export_bear.py:21-28,96-101,313`
- Modify: `blender/walk_actions.py:61-66`

**Interfaces:** Both scripts now derive the repo root from `bpy.data.filepath` and require its basename to be `gummy-bear.blend`. `export_bear.py` writes to `<dir of blend>/assets/bear.glb`.

- [ ] **Step 1: Build a scratch copy of the repo (this is the test fixture)**

```bash
S=$(mktemp -d) && cp gummy-bear.blend "$S/" && cp -R blender "$S/" && echo "$S"
```

- [ ] **Step 2: Run both scripts against the copy to prove they fail today**

```bash
$BLENDER -b "$S/gummy-bear.blend" --python "$S/blender/walk_actions.py" 2>&1 | grep -E "Error|WALK ACTIONS OK"
$BLENDER -b "$S/gummy-bear.blend" --python "$S/blender/export_bear.py" 2>&1 | grep -E "Error|EXPORT OK"
```

Expected: `AssertionError: wrong blend open: '/var/.../gummy-bear.blend'`, then `RuntimeError: Wrong file open: expected '/Users/alex/...`.

- [ ] **Step 3: Fix export_bear.py**

Replace lines 25–28:

```python
# ── paths ─────────────────────────────────────────────────────────────────────
ROOT = "/Users/alex/gamedev/gummy-bear"
OUT = os.path.join(ROOT, "assets", "bear.glb")
EXPECTED_BLEND = os.path.join(ROOT, "gummy-bear.blend")
```

with:

```python
# ── paths: everything is relative to the open blend, which sits at repo root ──
BLEND_NAME = "gummy-bear.blend"
EXPECTED_BLEND = os.path.normpath(bpy.data.filepath)
ROOT = os.path.dirname(EXPECTED_BLEND)
OUT = os.path.join(ROOT, "assets", "bear.glb")
```

Replace the guard (lines 96–101):

```python
# ── guard: must be operating on the recovered root blend ─────────────────────
actual = bpy.data.filepath
if os.path.normpath(actual) != os.path.normpath(EXPECTED_BLEND):
    raise RuntimeError(
        f"Wrong file open: expected {EXPECTED_BLEND!r}, got {actual!r}"
    )
```

with:

```python
# ── guard: must be operating on the recovered root blend ─────────────────────
if os.path.basename(EXPECTED_BLEND) != BLEND_NAME:
    raise RuntimeError(
        f"Wrong file open: expected {BLEND_NAME!r}, got {bpy.data.filepath!r}"
    )
```

Line 313 (`bpy.ops.wm.save_mainfile(filepath=EXPECTED_BLEND)`) stays as is and now saves to the open file.

- [ ] **Step 4: Fix walk_actions.py**

Replace lines 61–66:

```python
import bpy
import math
import mathutils

BLEND = "/Users/alex/gamedev/gummy-bear/gummy-bear.blend"
assert bpy.data.filepath == BLEND, ("wrong blend open: %r" % bpy.data.filepath)
```

with:

```python
import bpy
import math
import mathutils
import os

BLEND = os.path.normpath(bpy.data.filepath)
assert os.path.basename(BLEND) == "gummy-bear.blend", (
    "wrong blend open: %r" % bpy.data.filepath)
```

- [ ] **Step 5: Re-copy the fixed scripts and re-run against the scratch copy**

```bash
cp blender/*.py "$S/blender/"
$BLENDER -b "$S/gummy-bear.blend" --python "$S/blender/walk_actions.py" 2>&1 | grep -E "Error|WALK ACTIONS OK"
$BLENDER -b "$S/gummy-bear.blend" --python "$S/blender/export_bear.py" 2>&1 | grep -E "Error|EXPORT OK|GLB written"
ls -l "$S/assets/bear.glb"; git status --short assets gummy-bear.blend
```

Expected: `WALK ACTIONS OK: [...5 names...]`, `GLB written: $S/assets/bear.glb`, `EXPORT OK`, the file exists, and `git status` shows **no** change to the repo's `assets/` or `gummy-bear.blend`.

- [ ] **Step 6: Commit**

```bash
git add blender/export_bear.py blender/walk_actions.py
git commit -m "fix(blender): derive paths from the open blend instead of /Users/alex"
```

---

### Task 3: Stop tracking iteration renders

**Files:**
- Create: `renders/.gdignore` (empty)
- Modify: `.gitignore`
- Untrack: every `renders/*` except `renders/final_Cam34.png` (the README hero image)

- [ ] **Step 1: Add the ignore rules**

Create an empty `renders/.gdignore` (Godot stops importing the folder).

Append to `.gitignore`:

```gitignore

# Blender iteration renders stay local; only the README hero image is tracked
/renders/*
!/renders/final_Cam34.png
!/renders/.gdignore
```

- [ ] **Step 2: Untrack the PNGs but keep them on disk, and delete the now-useless .import files**

```bash
git rm --cached -q $(git ls-files 'renders/*.png' | grep -v '^renders/final_Cam34.png$')
git rm -q $(git ls-files 'renders/*.import')
```

- [ ] **Step 3: Verify**

Run: `git ls-files renders; ls renders | wc -l`
Expected: `git ls-files` lists only `renders/.gdignore` (after `git add`) and `renders/final_Cam34.png`; the local count is still about 45 PNGs.

Run the harness. Expected: `exit=0`, and no import errors for `renders/`.

- [ ] **Step 4: Commit**

```bash
git add .gitignore renders/.gdignore
git commit -m "chore: untrack Blender iteration renders and hide them from Godot"
```

---

### Task 4: Use `get_gravity()`

**Files:** Modify `scripts/gummy_bear.gd:51,128`

- [ ] **Step 1: Replace the cached gravity**

Delete line 51:

```gdscript
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
```

Change line 128 from `velocity.y -= _gravity * delta` to:

```gdscript
		velocity += get_gravity() * delta
```

(`get_gravity()` returns the full vector, so this also respects `Area3D` gravity overrides.)

- [ ] **Step 2: Run the harness**

Expected: `exit=0`, `jump rise=0.421` (±0.01), `double_boost=false`.

- [ ] **Step 3: Commit**

```bash
git add scripts/gummy_bear.gd
git commit -m "refactor(bear): take gravity from get_gravity() so Area3D overrides apply"
```

---

### Task 5: `cycle_colour` input action

**Files:**
- Modify: `project.godot` (`[input]`)
- Modify: `scripts/gummy_bear.gd:155-162`
- Modify: `scripts/test_stage.gd:34-36`

**Interfaces:** Produces the input action `cycle_colour` (physical C key).

- [ ] **Step 1: Add the action**

In `project.godot`, after the `jump={...}` block, add:

```ini
cycle_colour={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":67,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```

- [ ] **Step 2: Use it in the controller**

Replace `_unhandled_key_input` (lines 155–162) with:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cycle_colour"):
		_colour_index = (_colour_index + 1) % PALETTE.size()
		_apply_colour()
		get_viewport().set_input_as_handled()
```

(`is_action_pressed` ignores echoes by default.) Update the header comment on line 6: `KEY_C cycles` → `cycle_colour (C) cycles`.

- [ ] **Step 3: Document the harness's colour assumption**

In `scripts/test_stage.gd`, above `const BEAR_RED_MIN`, add:

```gdscript
## The silhouette detector keys on the default cherry colour (PALETTE[0] in
## gummy_bear.gd). The harness never presses cycle_colour; if it ever does,
## these thresholds stop finding the bear.
```

- [ ] **Step 4: Verify**

Run the harness. Expected: `exit=0`.
Manual: run `$GODOT --path .`, press C five times, and confirm it goes cherry → orange → lemon → lime → clear → cherry. Holding C must not auto-repeat.

- [ ] **Step 5: Commit**

```bash
git add project.godot scripts/gummy_bear.gd scripts/test_stage.gd
git commit -m "feat(input): bind colour cycling to a physical-key cycle_colour action"
```

---

### Task 6: Click to recapture the mouse

**Files:** Modify `scripts/orbit_camera.gd:8-10,62-63`, `README.md` (Controls table)

- [ ] **Step 1: Recapture on left click**

Replace lines 62–63:

```gdscript
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
```

with:

```gdscript
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# Clicking back into the game resumes mouse look, like Esc does.
		var click := event as InputEventMouseButton
		if (click != null and click.pressed
				and click.button_index == MOUSE_BUTTON_LEFT):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
		return
```

In the header comment, change `Esc toggles cursor capture,` to `Esc toggles cursor capture (a left click also recaptures),`.

- [ ] **Step 2: Document the camera controls in the README**

Add these rows to the Controls table:

```markdown
| Mouse | Orbit camera (bear turns to follow while walking) |
| Wheel | Zoom |
| Esc   | Release / recapture mouse (left click also recaptures) |
```

- [ ] **Step 3: Verify**

Harness: `exit=0`.
Manual: run the game, press Esc (cursor appears), then click in the window. The cursor should be captured and mouse look should work, and the click must not also trigger any other action.

- [ ] **Step 4: Commit**

```bash
git add scripts/orbit_camera.gd README.md
git commit -m "feat(camera): left click recaptures the mouse after Esc"
```

---

### Task 7: The bear only turns toward the camera while driven

**Files:**
- Modify: `scripts/test_stage.gd` (new idle-yaw assertion + side-view shot)
- Modify: `scripts/gummy_bear.gd:130-139`
- Modify: `CONTEXT.md` (Strafe mode), `docs/adr/0001-orbit-camera-strafe-mode.md` (amendment)

**Interfaces:** Produces the harness shot `.dev/side.png` (camera yaw π/2 at t=2.5 s), which Task 9 uses as evidence.

- [ ] **Step 1: Write the failing harness assertion**

In `scripts/test_stage.gd`:

Add to `SHOT_SCHEDULE`: `2.70: "side.png",`

Add constants after `QUIT_AT`:

```gdscript
## After all world-axis checks, orbit the idle bear's camera a quarter turn:
## the body must stay put (no turn-in-place clip exists), and side.png shows
## the bear side-on for the shader's self-overlap check.
const ORBIT_AT := 2.5
const YAW_CHECK_AT := 2.9
const MAX_IDLE_YAW := 0.05
```

Add vars after `_air_drive_end_x`:

```gdscript
var _orbited := false
var _idle_yaw := 0.0
var _idle_yaw_checked := false
```

Append to the end of `_physics_process`:

```gdscript
	if not _orbited and _elapsed >= ORBIT_AT:
		_bear.get_node("CameraRig").rotation.y = PI / 2.0
		_orbited = true
	if _orbited and not _idle_yaw_checked and _elapsed >= YAW_CHECK_AT:
		_idle_yaw = absf(angle_difference(0.0, _bear.rotation.y))
		_idle_yaw_checked = true
```

In `_finish()`, before the silhouette loop, add:

```gdscript
	if not _idle_yaw_checked:
		failures.append("idle yaw was never checked")
	elif _idle_yaw > MAX_IDLE_YAW:
		failures.append("idle bear turned %.3f rad toward the camera" % _idle_yaw)
```

and add `idle_yaw=%.3f` with `_idle_yaw` to the summary `print`.

- [ ] **Step 2: Run the harness and confirm it fails**

Expected: `exit=1` with `idle bear turned ~1.3 rad toward the camera`, since after 0.4 s at lerp rate 5 the body covers most of π/2.

- [ ] **Step 3: Gate the yaw chase on player input**

In `scripts/gummy_bear.gd`, replace lines 130–136:

```gdscript
	# Strafe mode: the body chases the camera yaw with the same lazy lerp
	# as the velocity below. The camera rig is top_level, so this rotation
	# never feeds back into mouse look.
	rotation.y = lerp_angle(rotation.y, _camera_rig.yaw,
			clampf(YAW_LERP * delta, 0.0, 1.0))

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
```

with:

```gdscript
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Strafe mode: while the player drives, the body chases the camera yaw
	# with the same lazy lerp as the velocity below. Idle, it holds still:
	# there is no turn-in-place clip, so turning would slide the feet. The
	# camera rig is top_level, so this rotation never feeds back into mouse
	# look.
	if input != Vector2.ZERO:
		rotation.y = lerp_angle(rotation.y, _camera_rig.yaw,
				clampf(YAW_LERP * delta, 0.0, 1.0))
```

- [ ] **Step 4: Run the harness and confirm it passes**

Expected: `exit=0`, `idle_yaw=0.000`, and `.dev/side.png` shows the bear side-on. The jump and silhouette numbers are unchanged from baseline.

- [ ] **Step 5: Update the domain docs**

In `CONTEXT.md`, replace the Strafe mode definition sentence with:

```markdown
The locomotion model where, while the player is moving, the bear's body yaw follows the camera yaw and WASD moves relative to the camera, so the bear side-steps/back-pedals using its four directional walk clips instead of turning to face its velocity. An idle bear does not turn when the camera orbits.
```

Append to `docs/adr/0001-orbit-camera-strafe-mode.md`:

```markdown

**Amendment (2026-09-26)**: The body yaw now follows the camera only while movement input is held. An idle bear turning toward the camera slid its feet, because there is no turn-in-place clip. The `--shots` harness asserts this by orbiting the idle camera a quarter turn.
```

- [ ] **Step 6: Commit**

```bash
git add scripts/test_stage.gd scripts/gummy_bear.gd CONTEXT.md docs/adr/0001-orbit-camera-strafe-mode.md
git commit -m "fix(bear): don't turn in place when the camera orbits an idle bear"
```

---

### Task 8: Physics interpolation with a render-rate camera

**Files:**
- Modify: `project.godot` (`[physics]`)
- Modify: `scripts/orbit_camera.gd:4-10,34-51`

- [ ] **Step 1: Enable interpolation**

In `project.godot`, under `[physics]`, add:

```ini
common/physics_interpolation=true
```

- [ ] **Step 2: Make the rig follow the interpolated body every frame**

In `scripts/orbit_camera.gd`, change the header sentence `each physics tick it snaps to the bear's position.` to `every rendered frame it snaps to the bear's interpolated position, with automatic interpolation off, so mouse look stays frame-rate crisp.`

In `_ready()`, after `top_level = true`, add:

```gdscript
	# Mouse look lands between physics ticks, so this rig (and its arm and
	# camera, which inherit the mode) is positioned by hand every frame
	# instead of being auto-interpolated.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
```

Replace `_physics_process` and `_snap_to_body` (lines 46–51) with:

```gdscript
func _process(_delta: float) -> void:
	_snap_to_body()


func _snap_to_body() -> void:
	global_position = (_body.get_global_transform_interpolated().origin
			+ Vector3(0.0, PIVOT_HEIGHT, 0.0))
```

- [ ] **Step 3: Verify**

Harness: `exit=0`. Silhouette ratios must stay within limits (the harness enforces this), and the jump rise is 0.421 ± 0.01, because it is measured from the physics position, which isn't interpolated.
Manual: run `$GODOT --path .` on the high-refresh display, then walk while orbiting. The bear should stay steady in frame with no 60 Hz stepping, and mouse look should feel as immediate as before.

- [ ] **Step 4: Commit**

```bash
git add project.godot scripts/orbit_camera.gd
git commit -m "feat: enable physics interpolation; camera follows the interpolated bear"
```

---

### Task 9: Deterministic self-overlap in the gummy shader

**Files:**
- Create: `shaders/gummy_depth.gdshader`
- Modify: `materials/gummy_material.tres`

**Interfaces:** Consumes `.dev/side.png` from Task 7. `scripts/gummy_bear.gd` keeps preloading `res://materials/gummy_material.tres`, which becomes a depth-only pass whose `next_pass` is the existing colour shader. `set_instance_shader_parameter("gummy_color", …)` must still reach the colour pass.

- [ ] **Step 1: Reproduce first**

Run the harness, then inspect `.dev/side.png` and `.dev/walk.png`. Also run interactively and orbit to a 3/4 front view. Look for order-dependent overlap: a far limb showing through the torso in some triangles but not others (patchy or triangle-shaped see-through regions), or regions that pop while the bear walks.
**If no artifact is visible from any angle: stop, skip this task, and note "Finding 3 not reproduced" in the final report.**

- [ ] **Step 2: Create the depth-only pass**

`shaders/gummy_depth.gdshader`:

```glsl
shader_type spatial;
// First pass of the gummy material: writes the bear's nearest-surface depth
// and no colour, so the translucent colour pass (next_pass) only shades the
// front-most surface instead of blending limbs in triangle order.
render_mode blend_mix, depth_draw_always, cull_back, unshaded, shadows_disabled;

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
```

- [ ] **Step 3: Chain the passes**

Replace `materials/gummy_material.tres` with:

```
[gd_resource type="ShaderMaterial" load_steps=4 format=3]

[ext_resource type="Shader" path="res://shaders/gummy_depth.gdshader" id="1_depth"]
[ext_resource type="Shader" path="res://shaders/gummy.gdshader" id="2_colour"]

[sub_resource type="ShaderMaterial" id="ShaderMaterial_colour"]
render_priority = 0
shader = ExtResource("2_colour")

[resource]
render_priority = 0
next_pass = SubResource("ShaderMaterial_colour")
shader = ExtResource("1_depth")
```

- [ ] **Step 4: Verify**

Harness: `exit=0`. The silhouette checks also prove the bear is still visible and still red, which means the instance colour reached the colour pass.
Compare the new `.dev/side.png` with the Step 1 capture: the overlap artifact is gone, and there is no z-fighting noise on the bear's front surface.
Manual: press C and confirm the colour still cycles, and confirm the soft contact fade at the feet still shows.
**If the front surface z-fights** (the colour pass loses an equal-depth test against the depth pass), revert this task and record the finding as "needs a sorted-mesh or dithered-opacity approach". Do not ship a flickering bear.

- [ ] **Step 5: Commit**

```bash
git add shaders/gummy_depth.gdshader materials/gummy_material.tres
git commit -m "fix(shader): depth pre-pass so the translucent bear shades only its front surface"
```

---

## Final check

- [ ] Harness `exit=0`, and the printed numbers match the baseline except for the new `idle_yaw=0.000`.
- [ ] `git status` is clean, and `git log --oneline` shows one commit per task (8 or 9).
- [ ] Report which manual checks were done, and whether Task 9 was applied or skipped as not reproduced.
