"""Export the rigged, animated GummyBear to assets/bear.glb.

Safe: does NOT delete scene objects, does NOT save over blender/gummy_bear.blend,
does NOT include cameras, lights, or backdrop in the GLB, and restores the live
scene state in a finally block before saving the recovered root blend.

Animation contract:
- Exactly 5 actions ship in the GLB: ``idle-loop`` plus the four ``walk_*-loop``
  clips. ``idle-loop`` must be the rig's active action; the walk loops ride in
  muted NLA tracks and are picked up by ``export_animation_mode='ACTIONS'``.
- Checked twice: on the source actions before export, and on the written GLB's
  own JSON chunk afterwards, so a silently dropped clip cannot ship.

Scale normalisation:
- Export the base rigged mesh at exactly one metre tall.
- Keep the feet on the origin plane after Blender's Z-up → glTF Y-up conversion.
- Exclude the redundant Subdivision modifier: the base mesh already has 96,690
  faces, so exporting the subdivided evaluated mesh only bloats the GLB.
"""
import bpy
import json
import os
import struct
# ── paths ─────────────────────────────────────────────────────────────────────
ROOT = "/Users/alex/gamedev/gummy-bear"
OUT = os.path.join(ROOT, "assets", "bear.glb")
EXPECTED_BLEND = os.path.join(ROOT, "gummy-bear.blend")

MESH_NAME = "GummyBear"
RIG_NAME = "GummyRig"
BONE_COUNT = 11
EXPECTED_BASE_FACE_COUNT = 96_690
ACTIVE_ACTION_NAME = "idle-loop"
EXPECTED_ACTIONS = {
    "idle-loop",
    "walk_fwd-loop",
    "walk_back-loop",
    "walk_left-loop",
    "walk_right-loop",
}


def world_vertex_bounds(obj):
    coords = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    min_x = min(co.x for co in coords)
    min_y = min(co.y for co in coords)
    min_z = min(co.z for co in coords)
    max_x = max(co.x for co in coords)
    max_y = max(co.y for co in coords)
    max_z = max(co.z for co in coords)
    return (min_x, min_y, min_z), (max_x, max_y, max_z)


def restore_mode(mode_name, active_obj):
    if active_obj is None or mode_name == 'OBJECT':
        return

    mode_map = {
        'EDIT_MESH': 'EDIT',
        'EDIT_ARMATURE': 'EDIT',
        'EDIT_CURVE': 'EDIT',
        'POSE': 'POSE',
        'SCULPT': 'SCULPT',
        'WEIGHT_PAINT': 'WEIGHT_PAINT',
        'VERTEX_PAINT': 'VERTEX_PAINT',
        'TEXTURE_PAINT': 'TEXTURE_PAINT',
    }
    target_mode = mode_map.get(mode_name)
    if target_mode is not None:
        bpy.ops.object.mode_set(mode=target_mode)


# ── guard: must be operating on the recovered root blend ─────────────────────
actual = bpy.data.filepath
if os.path.normpath(actual) != os.path.normpath(EXPECTED_BLEND):
    raise RuntimeError(
        f"Wrong file open: expected {EXPECTED_BLEND!r}, got {actual!r}"
    )

# ── resolve required objects ─────────────────────────────────────────────────
mesh = bpy.data.objects.get(MESH_NAME)
rig = bpy.data.objects.get(RIG_NAME)
if mesh is None:
    raise RuntimeError(f"Mesh object {MESH_NAME!r} not found in scene")
if rig is None:
    raise RuntimeError(f"Armature object {RIG_NAME!r} not found in scene")

# ── capture scene state before any mutation ──────────────────────────────────
context = bpy.context
original_mode = context.mode
selected_names = [obj.name for obj in context.selected_objects]
active_name = getattr(context.view_layer.objects.active, "name", None)
mesh_matrix_basis = mesh.matrix_basis.copy()
rig_matrix_basis = rig.matrix_basis.copy()
subsurf_states = [
    (modifier, modifier.show_viewport, modifier.show_render)
    for modifier in mesh.modifiers
    if modifier.type == 'SUBSURF'
]

if context.object and context.object.mode != 'OBJECT':
    bpy.ops.object.mode_set(mode='OBJECT')
try:
    # ── assert 11 rig bones and matching vertex groups ───────────────────────
    bones = list(rig.data.bones.keys())
    if len(bones) != BONE_COUNT:
        raise RuntimeError(
            f"Expected {BONE_COUNT} bones, found {len(bones)}: {bones}"
        )

    vgroups = {vg.name for vg in mesh.vertex_groups}
    bone_set = set(bones)
    if vgroups != bone_set:
        raise RuntimeError(
            f"Vertex groups {sorted(vgroups)} don't match bones {sorted(bone_set)}"
        )

    if mesh.parent != rig or mesh.parent_type != 'OBJECT':
        raise RuntimeError(
            f"Expected {MESH_NAME!r} to be object-parented to {RIG_NAME!r}, "
            f"got parent={getattr(mesh.parent, 'name', None)!r} "
            f"type={mesh.parent_type!r}"
        )

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

    # ── verify base mesh size and compute one-metre export transform ─────────
    base_face_count = len(mesh.data.polygons)
    if base_face_count != EXPECTED_BASE_FACE_COUNT:
        raise RuntimeError(
            f"Expected base mesh face count {EXPECTED_BASE_FACE_COUNT}, found {base_face_count}"
        )
    (min_x, min_y, min_z), (max_x, max_y, max_z) = world_vertex_bounds(mesh)
    base_height = max_z - min_z
    if base_height <= 0.0:
        raise RuntimeError(f"Invalid base mesh height: {base_height}")
    scale_factor = 1.0 / base_height
    rig_lift = -min_z * scale_factor
    print(
        "Base mesh bounds:"
        f" min=({min_x:.4f}, {min_y:.4f}, {min_z:.4f})"
        f" max=({max_x:.4f}, {max_y:.4f}, {max_z:.4f})"
    )
    print(
        f"Base mesh faces: {base_face_count:,}  →  "
        f"height: {base_height:.6f} m  →  export scale: {scale_factor:.9f}  "
        f"→  rig lift: {rig_lift:.9f}"
    )

    # ── temporarily suppress Subdivision and apply export-only rig transform ─
    for modifier, _, _ in subsurf_states:
        modifier.show_viewport = False
        modifier.show_render = False
        print(f"Temporarily disabled modifier: {modifier.name!r}")

    rig.scale = tuple(component * scale_factor for component in rig.scale)
    rig.location.z += rig_lift
    context.view_layer.update()
    print(
        "Temporary rig transform:"
        f" location={tuple(round(v, 9) for v in rig.location)}"
        f" scale={tuple(round(v, 9) for v in rig.scale)}"
    )

    # ── export only GummyBear + GummyRig ──────────────────────────────────────
    bpy.ops.object.select_all(action='DESELECT')
    mesh.select_set(True)
    rig.select_set(True)
    context.view_layer.objects.active = rig

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=OUT,
        export_format='GLB',
        use_selection=True,
        export_skins=True,
        export_animations=True,
        export_animation_mode='ACTIONS',
        export_apply=False,
        export_cameras=False,
        export_lights=False,
    )

    size = os.path.getsize(OUT)
    print(f"GLB written: {OUT}  ({size:,} bytes)")
    if size == 0:
        raise RuntimeError("Export produced empty GLB file")

    # ── verify the written GLB, not just the source actions ──────────────────
    with open(OUT, "rb") as glb:
        blob = glb.read()
    if len(blob) < 20:
        raise RuntimeError("Export produced truncated GLB header")
    json_length, json_chunk_type = struct.unpack_from("<I4s", blob, 12)
    if json_chunk_type != b"JSON":
        raise RuntimeError(f"Expected JSON chunk at offset 12, got {json_chunk_type!r}")
    if len(blob) < 20 + json_length:
        raise RuntimeError("Export produced truncated GLB JSON chunk")
    doc = json.loads(blob[20:20 + json_length].decode("utf-8"))
    shipped_actions = {animation["name"] for animation in doc.get("animations", [])}
    if shipped_actions != EXPECTED_ACTIONS:
        raise RuntimeError(
            f"GLB animation set mismatch: expected {sorted(EXPECTED_ACTIONS)},"
            f" got {sorted(shipped_actions)}"
        )
    print(f"GLB animations verified: {sorted(shipped_actions)}")
finally:
    # ── restore transforms, modifier visibility, selection, and mode ─────────
    mesh.matrix_basis = mesh_matrix_basis
    rig.matrix_basis = rig_matrix_basis
    for modifier, show_viewport, show_render in subsurf_states:
        modifier.show_viewport = show_viewport
        modifier.show_render = show_render

    bpy.ops.object.select_all(action='DESELECT')
    for name in selected_names:
        obj = bpy.data.objects.get(name)
        if obj is not None:
            obj.select_set(True)

    active_obj = bpy.data.objects.get(active_name) if active_name else None
    if active_obj is not None:
        context.view_layer.objects.active = active_obj
    context.view_layer.update()
    restore_mode(original_mode, active_obj)
    context.view_layer.update()

# ── save the recovered root blend only after full restoration ────────────────
bpy.ops.wm.save_mainfile(filepath=EXPECTED_BLEND)
print(f"Saved restored root state: {EXPECTED_BLEND}")
print("EXPORT OK")
