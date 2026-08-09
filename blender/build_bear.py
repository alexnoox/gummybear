# Build the GummyBear mesh. Idempotent: wipes any previous bear/rig first.
#
# Conventions: meters, Z-up, front faces +Y, origin at feet, flat base on z=0,
# total height 1.0 m.
#
# Construction: one metaball family (soft, seamless candy-mould blending) ->
# mesh -> depth flatten -> voxel remesh (clean uniform topology) -> light
# smooth -> decimate to budget -> flat sole bisect -> normalize to 1.0 m ->
# shade smooth -> GummyPreview material.
import bpy
import bmesh

BLEND = "/Users/alex/gamedev/gummy-bear/blender/gummy_bear.blend"

# Metaball field for a BALL is s*(1-(d/R)^2)^3, surface where the sum hits
# THRESH, so an isolated ball's visible radius is R*sqrt(1-(THRESH/s)^(1/3)).
# STIFF is the blendiness dial: low stiffness needs a big support radius R for
# a given visible radius, and that big R is what smears neighbouring parts into
# one blob. High stiffness keeps the support tight to the visible surface, so
# parts union with just a soft fillet -- exactly the candy-mould look.
#   s=2 -> 0.571 (measured, mush)   s=5 -> 0.709 (measured)   s=8 -> ~0.755
THRESH = 0.6
STIFF = 8.0
K = 1.0 / 0.755          # design in visible radii, convert to element radii

YFLAT = 0.90             # candy moulds are shallower than they are wide
VOXEL = 0.013
TARGET_TRIS = 6200
HEIGHT = 1.0


# --- cleanup ----------------------------------------------------------------
def wipe():
    if bpy.context.view_layer.objects.active and bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    for name in ("GummyBear", "GummyRig", "GummyMeta", "Cube"):
        obj = bpy.data.objects.get(name)
        while obj is not None:
            bpy.data.objects.remove(obj, do_unlink=True)
            obj = bpy.data.objects.get(name)
    for coll in (bpy.data.meshes, bpy.data.armatures, bpy.data.metaballs):
        for block in list(coll):
            if block.users == 0:
                coll.remove(block)


wipe()

# --- metaball skeleton (front = +Y) -----------------------------------------
mball = bpy.data.metaballs.new("GummyMeta")
mball.resolution = 0.010
mball.render_resolution = 0.010
mball.threshold = THRESH
meta = bpy.data.objects.new("GummyMeta", mball)
bpy.context.scene.collection.objects.link(meta)


def ball(x, y, z, r, stiff=STIFF, negative=False):
    el = mball.elements.new(type='BALL')
    el.co = (x, y, z)
    el.radius = r * K
    el.stiffness = stiff
    el.use_negative = negative
    return el


# torso: soft pear -- narrow shoulders, wide low belly, broad hips.
# The hips ball is kept high and small so a crotch notch survives between the
# legs instead of the pelvis filling all the way down to the floor.
ball(0.000, 0.005, 0.565, 0.168)   # shoulders
ball(0.000, 0.022, 0.448, 0.196)   # chest
ball(0.000, 0.034, 0.336, 0.210)   # belly (widest point)
ball(0.000, 0.010, 0.255, 0.180)   # hips

# head: oversized and round, only lightly sunk into the shoulders so a shallow
# neck pinch reads without giving the bear an actual neck
ball(0.000, 0.012, 0.780, 0.222)
ball(0.000, 0.188, 0.700, 0.112)   # muzzle bump
ball(0.000, 0.282, 0.700, 0.048)   # nose tip
ball(0.000, 0.150, 0.628, 0.070)   # chin/jaw, sets the muzzle off the chest

# ears: round nubs set far enough out to pinch at the base and clear the skull
for s in (1, -1):
    ball(0.216 * s, -0.014, 0.930, 0.094)

# brow ridges + eye dimples: shallow negative craters, the way a candy mould
# stamps a face. Kept high and wide so they never bite into the profile.
for s in (1, -1):
    ball(0.100 * s, 0.148, 0.826, 0.074)             # cheek/brow swell
    ball(0.098 * s, 0.246, 0.832, 0.050, negative=True)

# arms: stubby cones angled out and gently down, paws above the belly line
for s in (1, -1):
    ball(0.198 * s, 0.010, 0.545, 0.092)   # upper arm
    ball(0.250 * s, 0.018, 0.498, 0.083)   # forearm
    ball(0.288 * s, 0.028, 0.458, 0.074)   # paw

# legs: short splayed stubs, feet nudged forward and sunk so that the sole cut
# crosses the surface steeply (a shallow cut leaves a ragged outline)
for s in (1, -1):
    ball(0.142 * s, 0.004, 0.192, 0.117)   # thigh
    ball(0.158 * s, 0.016, 0.100, 0.106)   # shin
    ball(0.170 * s, 0.038, 0.028, 0.108)   # foot

# --- metaball -> mesh --------------------------------------------------------
bpy.ops.object.select_all(action='DESELECT')
meta.select_set(True)
bpy.context.view_layer.objects.active = meta
bpy.ops.object.convert(target='MESH')
bear = bpy.context.active_object
bear.name = "GummyBear"
bear.data.name = "GummyBear"
if mball.users == 0:                    # convert leaves the metaball orphaned
    bpy.data.metaballs.remove(mball)

# candy-mould depth flatten
bear.scale = (1.0, YFLAT, 1.0)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

# --- clean uniform topology --------------------------------------------------
rm = bear.modifiers.new("remesh", 'REMESH')
rm.mode = 'VOXEL'
rm.voxel_size = VOXEL
rm.use_smooth_shade = True
bpy.ops.object.modifier_apply(modifier=rm.name)

sm = bear.modifiers.new("smooth", 'SMOOTH')
sm.factor = 0.5
sm.iterations = 3
bpy.ops.object.modifier_apply(modifier=sm.name)

# --- decimate to budget ------------------------------------------------------
bear.data.calc_loop_triangles()
tris = len(bear.data.loop_triangles)
if tris > TARGET_TRIS:
    dm = bear.modifiers.new("dec", 'DECIMATE')
    dm.decimate_type = 'COLLAPSE'
    dm.ratio = TARGET_TRIS / tris
    bpy.ops.object.modifier_apply(modifier=dm.name)

# --- flat sole exactly on z = 0 ---------------------------------------------
# Decimation leaves ~3 cm edges around the feet; slicing that directly gives a
# visibly faceted sole outline, so densify the strip the plane passes through
# first. Costs a few hundred triangles and buys a clean rim.
bpy.ops.object.mode_set(mode='EDIT')
bm = bmesh.from_edit_mesh(bear.data)
near = [e for e in bm.edges if min(v.co.z for v in e.verts) < 0.032]
if near:
    bmesh.ops.subdivide_edges(bm, edges=near, cuts=1, use_grid_fill=True)
res = bmesh.ops.bisect_plane(
    bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:],
    plane_co=(0, 0, 0), plane_no=(0, 0, 1), clear_inner=True)
cut_edges = [e for e in res['geom_cut'] if isinstance(e, bmesh.types.BMEdge)]
if cut_edges:
    bmesh.ops.holes_fill(bm, edges=cut_edges, sides=0)
for v in bm.verts:
    if abs(v.co.z) < 1e-4:
        v.co.z = 0.0
bmesh.update_edit_mesh(bear.data)
bpy.ops.object.mode_set(mode='OBJECT')

# --- normalize: height 1.0 m, feet on z=0, origin at feet -------------------
zs = [v.co.z for v in bear.data.vertices]
lo, hi = min(zs), max(zs)
scale = HEIGHT / (hi - lo)
for v in bear.data.vertices:
    v.co.x *= scale
    v.co.y *= scale
    v.co.z = (v.co.z - lo) * scale
bear.data.update()
bear.location = (0.0, 0.0, 0.0)

# rig_bear.py places bones in the same design space these metaballs use, so
# publish the design -> final transform instead of making it guess:
#   final = (x*S, y*YFLAT*S, (z - ZLO)*S)
bear["gb_yflat"] = YFLAT
bear["gb_scale"] = scale
bear["gb_zlo"] = lo

bpy.ops.object.shade_smooth()

# --- preview material --------------------------------------------------------
mat = bpy.data.materials.get("GummyPreview") or bpy.data.materials.new("GummyPreview")
mat.use_nodes = True
bsdf = mat.node_tree.nodes.get("Principled BSDF")
bsdf.inputs["Base Color"].default_value = (0.9, 0.08, 0.15, 1.0)
bsdf.inputs["Roughness"].default_value = 0.25
bsdf.inputs["Transmission Weight"].default_value = 0.7
bsdf.inputs["Subsurface Weight"].default_value = 0.3
bear.data.materials.clear()
bear.data.materials.append(mat)

# --- report + save -----------------------------------------------------------
bear.data.calc_loop_triangles()
print("TRIS:", len(bear.data.loop_triangles))
print("DIM:", tuple(round(d, 4) for d in bear.dimensions))
print("ZMIN:", round(min(v.co.z for v in bear.data.vertices), 6))
print("VERTS:", len(bear.data.vertices))
bpy.ops.wm.save_mainfile(filepath=BLEND)
print("SAVED")
