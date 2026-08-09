# Gummy Bear Walk Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Idle↔directional-walk animation blending driven by the bear's velocity, per spec `docs/superpowers/specs/2026-08-09-walk-controls-design.md`.

**Architecture:** Author 4 in-place walk loops on `GummyRig` in the root `gummy-bear.blend` (Blender MCP), relax the exporter to a 5-action contract, re-export `assets/bear.glb`, and drive a code-built `AnimationTree`/`BlendSpace2D` from `velocity` in `scripts/gummy_bear.gd`.

**Tech Stack:** Blender 5.2 (MCP `xd://mcp__blender_*`, every call needs `user_prompt`), glTF ACTIONS export, Godot 4.7.stable.mono (headless CLI + Godot MCP `xd://mcp__godot_*`).

## Global Constraints

- **Non-Fable models for Blender/asset tasks**: dispatch via `.omp/agents/blender-opus.md` (`model: anthropic/claude-opus-5:high`); fallback `openai-codex/gpt-5.4:high` if Opus 429s.
- **NEVER call `bpy.ops.ed.undo()`** in Blender MCP scripts (corrupted the armature once). Recovery source if disaster strikes: `gummy-bear.blend1`.
- Blender source of truth: `/Users/alex/gamedev/gummy-bear/gummy-bear.blend` (open in the live MCP session). `blender/gummy_bear.blend` is legacy — do not touch.
- `idle-loop` action (frames 1–48) must survive byte-for-byte: never rename, re-key, or delete it.
- Rig contract: 11 bones `root, body, head, ear.L, ear.R, arm.L, arm.R, leg.L, leg.R, foot.L, foot.R`; mesh `GummyBear` object-parented to `GummyRig`.
- Blender conventions: metric, Z-up, bear faces **+Y**, bear's right at **+X** (so its left is −X), feet at z≈0, scene fps 24.
- Clip contract (all four walks): frames 1–25, frame 25 = frame 1, left foot planted f1 / right foot planted f13, in place (zero horizontal root/body travel), CONSTANT f-curve extrapolation, stance foot solved onto z=0 from the evaluated pose.
- Action names exactly: `walk_fwd-loop`, `walk_back-loop`, `walk_left-loop`, `walk_right-loop`.
- Commit after each task (repo initialized at `4daea78`).

---

### Task 1: Author the four walk actions in Blender

**Agent:** `blender-opus` (Opus 5). **Files:**
- Create: `blender/walk_actions.py` (authoritative, idempotent authoring script — also executed chunk-wise through Blender MCP)
- Modify: `gummy-bear.blend` (via MCP; saved by the script)
- Create: `renders/walk_fwd_f{01,07,13,19}_CamSide.png`, `renders/walk_{back,left,right}_f07_Cam34.png`

**Interfaces:**
- Consumes: live Blender MCP session with `gummy-bear.blend` open; legacy gait source `blender/animate_bear.py` (read it fully first — it contains the stride tables, world-axes pose conjugation, and the `plant()` floor solver to port).
- Produces: `gummy-bear.blend` containing exactly 5 actions — untouched `idle-loop` (active) + the 4 walk loops, each walk stashed in its own **muted** NLA track on `GummyRig`.

- [ ] **Step 1: Introspect the rig before writing anything**

Run via `xd://mcp__blender_execute_blender_code` (small chunk):

```python
import bpy
rig = bpy.data.objects["GummyRig"]
print("file:", bpy.data.filepath)
print("bones:", [(b.name, b.parent.name if b.parent else None) for b in rig.data.bones])
print("actions:", [(a.name, tuple(a.frame_range)) for a in bpy.data.actions])
ad = rig.animation_data
print("active:", ad.action.name if ad and ad.action else None)
print("nla:", [(t.name, t.mute, [s.name for s in t.strips]) for t in (ad.nla_tracks if ad else [])])
print("fps:", bpy.context.scene.render.fps, bpy.context.scene.render.fps_base)
for n in ("foot.L", "foot.R", "leg.L", "leg.R", "body", "root"):
    b = rig.data.bones[n]
    print(n, "head_world_z=%.4f" % (rig.matrix_world @ b.head_local).z)
```

Record the bone parent chain (expected `root → body → {head, arm.L/R, leg.L/R}`, `leg.* → foot.*`, ears under head). The bone whose vertical offset the floor solver adjusts is the deepest bone that is an ancestor of both legs (expected `body`; use `root` if legs hang off `root`).

- [ ] **Step 2: Write `blender/walk_actions.py`**

Port from `blender/animate_bear.py` with these adaptations. Keep the legacy code's structure: `rest_basis`/`world_quat`/`world_loc` conjugation helpers, `make(name, keys)` keying every touched bone at every keyframe, `tidy()` setting CONSTANT extrapolation, `plant()` solving pelvis height off the evaluated pose, `stash()` into muted NLA tracks.

Required differences from legacy:
1. `BLEND = "/Users/alex/gamedev/gummy-bear/gummy-bear.blend"` and an opening guard `assert bpy.data.filepath == BLEND`.
2. **Do NOT wipe all actions/tracks.** Idempotency is scoped: remove only actions whose names start with `walk_` (and their NLA tracks/strips), keep `idle-loop` and its state untouched, keep `ad.action` pointing at `idle-loop` at the end.
3. Bone mapping — new rig has no knee: legacy `THIGH` curve drives `leg.L/R` world-pitch swing; legacy `KNEE` bend folds into `FOOT` pitch (add `bend * KNEE[i] * 0.35` to the foot pitch, sign chosen so the toe drops during swing) and into a slight amplitude boost on the leg swing during swing phase. Legacy arm/head/ear/spine channels map onto `arm.L/R`, `head`, `ear.L/R`, `body` directly.
4. Squash/hop and the solved floor height go on the solver bone found in Step 1 (`body` expected) via `world_loc` z-offsets; root gets no location keys (stays in place — the "in place" contract).
5. Author exactly four clips with the legacy parameter sets as starting points:
   - `walk_fwd-loop`: swing=26, bend=52, toe=13, arm=17, lean=-6, squash=0.16
   - `walk_back-loop`: swing=21, bend=44, toe=10, arm=14, lean=6, squash=0.14, reversed stride phase (legacy `back=True`)
   - `walk_left-loop`: swing=18, bend=44, toe=2, arm=10, lean=-2, squash=0.15, lateral=15, roll=-7
   - `walk_right-loop`: same but lateral=-15, roll=7
   Angles are degrees of world-axis rotation exactly as in the legacy tables; scale amplitudes down only if the visual review (Step 5) shows self-intersection.
6. No `bpy.ops.ed.undo()` anywhere. End with `bpy.ops.wm.save_mainfile(filepath=BLEND)`.
7. Final verification print (script must end with this, and you must check it):

```python
names = sorted(a.name for a in bpy.data.actions)
assert names == ["idle-loop", "walk_back-loop", "walk_fwd-loop", "walk_left-loop", "walk_right-loop"], names
assert ad.action and ad.action.name == "idle-loop"
for a in bpy.data.actions:
    if a.name.startswith("walk_"):
        fr = a.frame_range
        assert (round(fr[0]), round(fr[1])) == (1, 25), (a.name, fr)
bad = [(a.name, fc.data_path) for a in bpy.data.actions if a.name.startswith("walk_")
       for fc in fcurves(a) if fc.extrapolation != 'CONSTANT']
assert not bad, bad
print("WALK ACTIONS OK:", names)
```

- [ ] **Step 3: Execute the script through Blender MCP in chunks**

`execute_blender_code` truncates big payloads — run the file instead:

```python
exec(compile(open("/Users/alex/gamedev/gummy-bear/blender/walk_actions.py").read(),
             "walk_actions.py", "exec"))
```

If that single call still overruns MCP limits, split the file into numbered sections and exec them in order. Expected output: per-clip `plant` dip reports + `WALK ACTIONS OK: [...]`.

- [ ] **Step 4: Contact-frame floor check**

For each walk action: activate it, set frames 1/13/25, and verify with the sole-point sampler (port of legacy `sole_z`) that the stance foot's lowest sole point is within ±0.01 BU of z=0 (frame 1 & 25 → left foot, frame 13 → right foot). Print a table. Restore `ad.action` to `idle-loop` and frame 1 afterwards, then save again.

- [ ] **Step 5: Render pose checks**

Using existing camera `CamSide` (and `Cam34`): render `walk_fwd-loop` at frames 1, 7, 13, 19 → `renders/walk_fwd_f{01,07,13,19}_CamSide.png`; render frame 7 of each other clip → `renders/walk_{back,left,right}_f07_Cam34.png`. Restore idle-loop active + frame 1, save. Inspect the renders yourself: alternating leg swing, arms counter-swinging, no limb passing through the belly, feet not below floor. Fix amplitudes and re-run if wrong.

- [ ] **Step 6: Commit**

```bash
git add blender/walk_actions.py gummy-bear.blend renders/walk_*.png
git commit -m "feat(blender): author 4 in-place walk loops on GummyRig"
```

---

### Task 2: Relax the exporter to the 5-action contract and re-export

**Files:**
- Modify: `blender/export_bear.py:24-25` (constants), `blender/export_bear.py:110-130` (action validation block)
- Rewrite: `assets/bear.glb`

**Interfaces:**
- Consumes: Task 1's blend state (5 actions, walks NLA-stashed, `idle-loop` active).
- Produces: `assets/bear.glb` with animations `idle-loop, walk_fwd-loop, walk_back-loop, walk_left-loop, walk_right-loop`; mesh/skin contract unchanged (1 mesh, 1 skin, 11 joints, 193,380 tris, height Y=1.0).

- [ ] **Step 1: Replace the single-action constant**

`blender/export_bear.py` line 25 currently `ACTION_EXPORT_NAME = "idle-loop"`. Replace with:

```python
ACTIVE_ACTION_NAME = "idle-loop"
EXPECTED_ACTIONS = {
    "idle-loop",
    "walk_fwd-loop",
    "walk_back-loop",
    "walk_left-loop",
    "walk_right-loop",
}
```

- [ ] **Step 2: Replace the action-validation block (lines 110–130)**

The old block asserts exactly 1 action, renames it, and saves. New block (no rename, no pre-transform save):

```python
    # ── require the exact 5-action set with idle-loop active ─────────────────
    if rig.animation_data is None or rig.animation_data.action is None:
        raise RuntimeError(f"{RIG_NAME!r} has no active action")
    action_names = {a.name for a in bpy.data.actions}
    if action_names != EXPECTED_ACTIONS:
        raise RuntimeError(
            f"Action set mismatch: expected {sorted(EXPECTED_ACTIONS)}, "
            f"found {sorted(action_names)}"
        )
    active_action = rig.animation_data.action
    if active_action.name != ACTIVE_ACTION_NAME:
        raise RuntimeError(
            f"Active action must be {ACTIVE_ACTION_NAME!r}, got {active_action.name!r}"
        )
    print(f"Actions validated: {sorted(action_names)}  active={active_action.name!r}")
```

Also update the module docstring's contract line to mention 5 actions. Touch nothing else — rig-only scale/lift, SUBSURF suppression, `use_selection`, `export_animation_mode='ACTIONS'`, the `finally` restore, and the post-restore save all stay identical.

- [ ] **Step 3: Run the exporter through Blender MCP**

```python
exec(compile(open("/Users/alex/gamedev/gummy-bear/blender/export_bear.py").read(),
             "export_bear.py", "exec"))
```

Expected: `Actions validated: [...]`, bounds/scale prints matching previous run (scale 0.333167307, lift 0.007278821), `EXPORT OK`.

- [ ] **Step 4: Verify GLB contents**

```python
import json, struct
raw = open("/Users/alex/gamedev/gummy-bear/assets/bear.glb", "rb").read()
jlen = struct.unpack_from("<I", raw, 12)[0]
doc = json.loads(raw[20:20 + jlen])
print("animations:", sorted(a["name"] for a in doc["animations"]))
print("meshes:", len(doc["meshes"]), "skins:", len(doc["skins"]),
      "joints:", len(doc["skins"][0]["joints"]))
print("cameras:", len(doc.get("cameras", [])))
```

Expected: the 5 `-loop` names, 1 mesh, 1 skin, 11 joints, 0 cameras. Re-run exporter once more and confirm `EXPORT OK` again (idempotency; blend must be left with idle-loop active, original transforms).

- [ ] **Step 5: Commit**

```bash
git add blender/export_bear.py assets/bear.glb gummy-bear.blend
git commit -m "feat(export): 5-action contract, ship walk loops in bear.glb"
```

---

### Task 3: Godot — velocity-driven BlendSpace2D

**Files:**
- Modify: `scripts/gummy_bear.gd` (header comment lines 3–5, new const + field, new `_setup_locomotion_tree()`, one line in `_physics_process`, one call in `_ready`)

**Interfaces:**
- Consumes: `assets/bear.glb` from Task 2. Godot importer strips `-loop` and sets loop mode → animation names `idle`, `walk_fwd`, `walk_back`, `walk_left`, `walk_right`; existing `_resolve_animation(stem)` already tolerates both spellings.
- Produces: bear blends idle↔walks from `velocity`; wobble/colour features unchanged.

- [ ] **Step 1: Reimport**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --import --path /Users/alex/gamedev/gummy-bear --quit-after 1
```

Expected: exit 0, no import errors mentioning bear.glb.

- [ ] **Step 2: Edit `scripts/gummy_bear.gd`**

Replace header comment (lines 3–5):

```gdscript
## Gummy bear controller. WASD locomotion feeds a code-built
## AnimationTree/BlendSpace2D (idle + 4 directional walk loops); a damped
## spring drives the shader wobble and KEY_C cycles the gummy colour.
```

Add below the `GUMMY_MATERIAL` const:

```gdscript
## BlendSpace2D layout. x = strafe (left −, right +), y = fwd(−)/back(+):
## matches Vector2(velocity.x, velocity.z) with the bear facing −Z, unrotated.
const BLEND_POINTS := {
	"idle": Vector2.ZERO,
	"walk_fwd": Vector2(0.0, -1.0),
	"walk_back": Vector2(0.0, 1.0),
	"walk_left": Vector2(-1.0, 0.0),
	"walk_right": Vector2(1.0, 0.0),
}
```

Add field next to `var _anim`:

```gdscript
var _tree: AnimationTree
```

Add function after `_resolve_animation`:

```gdscript
## Builds the locomotion blend tree in code so animation names stay
## suffix-tolerant. On any missing clip the bear degrades to idle-only.
func _setup_locomotion_tree() -> void:
	var space := AnimationNodeBlendSpace2D.new()
	for stem: String in BLEND_POINTS:
		var anim_name := _resolve_animation(stem)
		if anim_name.is_empty():
			push_warning("GummyBear: no %s animation in %s; idle-only" %
					[stem, _anim.get_animation_list()])
			return
		var clip := AnimationNodeAnimation.new()
		clip.animation = anim_name
		space.add_blend_point(clip, BLEND_POINTS[stem])
	_tree = AnimationTree.new()
	_tree.name = "LocomotionTree"
	_tree.tree_root = space
	add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_anim)
	_tree.active = true
```

In `_ready()`, inside the `else` branch that plays idle, append after `_anim.play(idle)`:

```gdscript
			_setup_locomotion_tree()
```

In `_physics_process()`, after `move_and_slide()`:

```gdscript
	if _tree != null:
		_tree.set("parameters/blend_position",
				Vector2(velocity.x, velocity.z) / SPEED)
```

- [ ] **Step 3: Smoke-run via Godot MCP**

Write `{"projectPath":"/Users/alex/gamedev/gummy-bear","scene":"scenes/test_stage.tscn"}` to `xd://mcp__godot_run_project`, wait ~6 s, fetch `xd://mcp__godot_get_debug_output`, then `xd://mcp__godot_stop_project`. Expected: no `GummyBear:` warnings (especially no "no %s animation"), no AnimationTree errors.

- [ ] **Step 4: Deterministic harness capture**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --disable-vsync --fixed-fps 30 \
  --write-movie /Users/alex/gamedev/gummy-bear/.dev/frame.png \
  --path /Users/alex/gamedev/gummy-bear -- --shots
```

Harness injects movement and captures `.dev/shot_{1,2,3}.png` (t=1.5/2.1/4.0 s). Inspect: shot during movement shows a mid-stride pose (legs split, arms counter-swung) clearly different from idle; no mesh shredding (>4-influence artifacts) on limbs; bear still grounded. `.dev/frame*.png` sequence around the movement window should show the gait cycling.

- [ ] **Step 5: Commit**

```bash
git add scripts/gummy_bear.gd assets/bear.glb.import
git commit -m "feat(godot): drive idle/walk BlendSpace2D from velocity"
```
