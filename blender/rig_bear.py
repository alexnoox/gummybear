# Build the GummyRig armature and skin GummyBear to it. Idempotent: drops any
# previous rig, armature modifier and vertex groups first.
#
# Bones are authored in build_bear.py's *design* space (the metaball coordinate
# system) and mapped through the transform that script published on the mesh,
# so the rig follows the model automatically if the model is retuned.
import bpy

BLEND = "/Users/alex/gamedev/gummy-bear/blender/gummy_bear.blend"

bear = bpy.data.objects["GummyBear"]
YFLAT = bear["gb_yflat"]
S = bear["gb_scale"]
ZLO = bear["gb_zlo"]


def P(x, y, z):
    """design space -> final model space"""
    return (x * S, y * YFLAT * S, (z - ZLO) * S)


# --- cleanup ----------------------------------------------------------------
if bpy.context.view_layer.objects.active and bpy.context.object.mode != 'OBJECT':
    bpy.ops.object.mode_set(mode='OBJECT')

old = bpy.data.objects.get("GummyRig")
if old:
    bpy.data.objects.remove(old, do_unlink=True)
for arm in list(bpy.data.armatures):
    if arm.users == 0:
        bpy.data.armatures.remove(arm)
for m in list(bear.modifiers):
    if m.type == 'ARMATURE':
        bear.modifiers.remove(m)
bear.vertex_groups.clear()
bear.parent = None
bear.matrix_world.identity()

# --- bone table --------------------------------------------------------------
# name, parent, head(design), tail(design), connected
#
# Leaf bones (*_end) are the jiggle handles Phase 5 hangs SpringBoneSimulator3D
# off. They deform like every other bone so the spring actually shows in the
# mesh; only `root` is a pure transform bone.
B = []


def bone(name, parent, head, tail, connect=False):
    B.append((name, parent, head, tail, connect))


bone("root", None, (0, 0.0, 0.0), (0, 0.30, 0.0))

# spine chain, pelvis up through the skull
bone("hips", "root", (0, 0.010, 0.235), (0, 0.018, 0.330))
bone("spine", "hips", (0, 0.018, 0.330), (0, 0.022, 0.440), True)
bone("chest", "spine", (0, 0.022, 0.440), (0, 0.012, 0.585), True)
bone("head", "chest", (0, 0.012, 0.585), (0, 0.012, 0.860), True)

# belly: points forward into the gut so it can wobble independently
bone("belly", "spine", (0, 0.060, 0.330), (0, 0.190, 0.330))
bone("belly_end", "belly", (0, 0.190, 0.330), (0, 0.232, 0.330), True)

# The bear faces +Y and up is +Z, so its right hand is at +X and its left at
# -X. glTF maps Blender +X -> Godot +X and +Y -> Godot -Z (forward), so the
# same handedness survives the export.
for s, sfx in ((-1.0, "L"), (1.0, "R")):
    # ears: aimed along the skull -> ear-nub axis so a spring swings them out
    bone(f"ear.{sfx}", "head",
         (0.131 * s, -0.004, 0.871), (0.245 * s, -0.017, 0.950))
    bone(f"ear.{sfx}_end", f"ear.{sfx}",
         (0.245 * s, -0.017, 0.950), (0.286 * s, -0.022, 0.979), True)

    # arms: shoulder -> elbow -> wrist -> paw tip
    bone(f"upperarm.{sfx}", "chest",
         (0.145 * s, 0.006, 0.562), (0.225 * s, 0.014, 0.512))
    bone(f"forearm.{sfx}", f"upperarm.{sfx}",
         (0.225 * s, 0.014, 0.512), (0.272 * s, 0.024, 0.476), True)
    bone(f"hand.{sfx}", f"forearm.{sfx}",
         (0.272 * s, 0.024, 0.476), (0.312 * s, 0.030, 0.446), True)
    bone(f"hand.{sfx}_end", f"hand.{sfx}",
         (0.312 * s, 0.030, 0.446), (0.340 * s, 0.034, 0.425), True)

    # legs: hip -> knee -> ankle, then a forward-pointing foot
    bone(f"thigh.{sfx}", "hips",
         (0.128 * s, 0.008, 0.235), (0.150 * s, 0.012, 0.120))
    bone(f"shin.{sfx}", f"thigh.{sfx}",
         (0.150 * s, 0.012, 0.120), (0.163 * s, 0.016, 0.048), True)
    bone(f"foot.{sfx}", f"shin.{sfx}",
         (0.163 * s, 0.016, 0.048), (0.170 * s, 0.090, 0.030), True)
    bone(f"foot.{sfx}_end", f"foot.{sfx}",
         (0.170 * s, 0.090, 0.030), (0.170 * s, 0.130, 0.026), True)

# --- build the armature ------------------------------------------------------
arm_data = bpy.data.armatures.new("GummyRig")
rig = bpy.data.objects.new("GummyRig", arm_data)
bpy.context.scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')

eb = arm_data.edit_bones
for name, parent, head, tail, connect in B:
    b = eb.new(name)
    b.head = P(*head)
    b.tail = P(*tail)
    b.use_deform = name != "root"
for name, parent, head, tail, connect in B:
    if parent:
        eb[name].parent = eb[parent]
        eb[name].use_connect = connect

bpy.ops.armature.select_all(action='SELECT')
bpy.ops.armature.calculate_roll(type='GLOBAL_POS_Z')
bpy.ops.object.mode_set(mode='OBJECT')

# --- skin --------------------------------------------------------------------
bpy.ops.object.select_all(action='DESELECT')
bear.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.parent_set(type='ARMATURE_AUTO')

# Bone heat gives a clean but slightly blotchy result on a blob this smooth;
# relaxing the weights removes the pinching at the shoulder and crotch and
# suits a body that is meant to deform like jelly anyway.
bpy.ops.object.select_all(action='DESELECT')
bear.select_set(True)
bpy.context.view_layer.objects.active = bear
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.object.vertex_group_smooth(group_select_mode='ALL', factor=0.5, repeat=4)
bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.object.vertex_group_normalize_all(lock_active=False)

# --- report + save -----------------------------------------------------------
deform = [b.name for b in arm_data.bones if b.use_deform]
print("BONES:", len(arm_data.bones), "DEFORM:", len(deform))
print("NAMES:", sorted(b.name for b in arm_data.bones))
print("NONDEFORM:", sorted(b.name for b in arm_data.bones if not b.use_deform))
print("VGROUPS:", len(bear.vertex_groups))
unweighted = [v.index for v in bear.data.vertices if not v.groups]
print("UNWEIGHTED_VERTS:", len(unweighted))
print("PARENT:", bear.parent.name if bear.parent else None,
      "MOD:", [m.type for m in bear.modifiers])
bpy.ops.wm.save_mainfile(filepath=BLEND)
print("SAVED")
