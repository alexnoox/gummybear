# Author the seven GummyBear actions and stash each one in its own muted NLA
# track. Idempotent: every existing action and track is dropped first.
#
# Contracts honoured here (Phase 4 blending depends on them):
#   * scene fps 24
#   * the six locomotion clips are exactly frames 1-25, frame 25 duplicating
#     frame 1, and they share one contact pattern -- left foot down on frame 1,
#     right foot down on frame 13 -- so a BlendSpace2D can crossfade them
#     without the feet skating
#   * every clip is in place: no horizontal travel on root or hips
#   * f-curve extrapolation CONSTANT
#
# Poses are written in *world* axes (bear faces +Y, up +Z, its right at +X) and
# conjugated into each bone's rest frame, so bone roll never has to be
# reasoned about:  rx = pitch (positive tips the top backwards), ry = roll
# (positive leans to the bear's right), rz = yaw (positive turns left).
import bpy
import math
import mathutils

BLEND = "/Users/alex/gamedev/gummy-bear/blender/gummy_bear.blend"

rig = bpy.data.objects["GummyRig"]
scene = bpy.context.scene
scene.render.fps = 24
scene.render.fps_base = 1.0

# --- wipe --------------------------------------------------------------------
if bpy.context.view_layer.objects.active and bpy.context.object.mode != 'OBJECT':
    bpy.ops.object.mode_set(mode='OBJECT')
rig.animation_data_create()
ad = rig.animation_data
for tr in list(ad.nla_tracks):
    ad.nla_tracks.remove(tr)
ad.action = None
for a in list(bpy.data.actions):
    a.use_fake_user = False
    bpy.data.actions.remove(a)


# --- pose plumbing ------------------------------------------------------------
def rest_basis(name):
    return rig.pose.bones[name].bone.matrix_local.to_3x3()


def world_quat(name, rx, ry, rz):
    """A rotation given in world axes, expressed in the bone's rest frame."""
    m = rest_basis(name)
    R = mathutils.Euler((math.radians(rx), math.radians(ry), math.radians(rz)),
                        'XYZ').to_matrix()
    return (m.inverted() @ R @ m).to_quaternion()


def world_loc(name, dz):
    """A world-space vertical offset, expressed in the bone's rest frame."""
    return rest_basis(name).inverted() @ mathutils.Vector((0.0, 0.0, dz))


def apply(pose):
    for name, p in pose.items():
        pb = rig.pose.bones[name]
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = world_quat(
            name, p.get("rx", 0.0), p.get("ry", 0.0), p.get("rz", 0.0))
        sxz, sy = p.get("sxz", 1.0), p.get("sy", 1.0)
        pb.scale = (sxz, sy, sxz)
        pb.location = world_loc(name, p.get("lz", 0.0))


def fcurves(act):
    for layer in act.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                for fc in cb.fcurves:
                    yield fc


def make(name, keys):
    """keys: list of (frame, pose-dict). Every bone the clip touches is keyed
    on every one of its frames, so a channel can never hold a stale value
    across the loop seam."""
    touched, scaled, moved = set(), set(), set()
    for _f, pose in keys:
        for b, p in pose.items():
            touched.add(b)
            if "sy" in p or "sxz" in p:
                scaled.add(b)
            if "lz" in p:
                moved.add(b)

    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    ad.action = act
    for f, pose in keys:
        for b in touched:
            pb = rig.pose.bones[b]
            pb.rotation_mode = 'QUATERNION'
            pb.rotation_quaternion = (1, 0, 0, 0)
            pb.scale = (1, 1, 1)
            pb.location = (0, 0, 0)
        apply(pose)
        for b in touched:
            pb = rig.pose.bones[b]
            pb.keyframe_insert("rotation_quaternion", frame=f)
            if b in scaled:
                pb.keyframe_insert("scale", frame=f)
            if b in moved:
                pb.keyframe_insert("location", frame=f)
    tidy(act)
    ad.action = None
    return act


def tidy(act):
    for fc in fcurves(act):
        fc.extrapolation = 'CONSTANT'
        for kp in fc.keyframe_points:
            kp.interpolation = 'BEZIER'
            kp.handle_left_type = kp.handle_right_type = 'AUTO_CLAMPED'
        fc.update()


def activate(act):
    ad.action = act
    if act.slots:
        ad.action_slot = act.slots[0]


def stance_of(f):
    """Left foot carries the first half of the stride, right foot the second.
    Frame 25 wraps back onto frame 1's left contact."""
    return "L" if ((f - 1) % 24) < 12 else "R"


def plant(act, end, stance=None, clamp=False, hop=0.0):
    """Solve the pelvis height frame by frame off the *evaluated* pose so the
    supporting sole rides on z=0. Solving only at the pose keys is not enough --
    the leg is a rotating strut, so the bezier between two planted keys dips
    the foot several centimetres through the floor.

    `stance` names the foot that must carry each frame; that is what pins the
    contact pattern. Without it the solver would happily plant whichever foot
    happened to hang lowest and slide the whole cycle out of phase.
    clamp=True only ever lifts the bear (used by getup, whose authored height
    is the point of the clip). hop adds airtime back on top, peaking at the
    passing poses where a run leaves the ground.
    """
    activate(act)
    hips = rig.pose.bones["hips"]
    basis = rest_basis("hips")
    need, slack = {}, 0.0
    for f in range(1, end + 1):
        scene.frame_set(f)
        bpy.context.view_layer.update()
        zl, zr = sole_z("L"), sole_z("R")
        low = min(zl, zr) if stance is None else (zl if stance(f) == "L" else zr)
        if clamp:
            low = min(low, 0.0)
        slack = min(slack, min(zl, zr) - low)
        lift = hop * abs(math.sin(math.pi * (f - 1) / 12.0)) if hop else 0.0
        need[f] = (basis @ hips.location).z - low + lift
    for f in range(1, end + 1):
        scene.frame_set(f)
        hips.location = world_loc("hips", need[f])
        hips.keyframe_insert("location", frame=f)
    tidy(act)
    ad.action = None
    print("  plant %-16s deepest non-stance dip %.4f m" % (act.name, slack))


def stash(act):
    tr = ad.nla_tracks.new()
    tr.name = act.name
    strip = tr.strips.new(act.name, 1, act)
    strip.name = act.name
    if hasattr(strip, "action_slot") and act.slots:
        strip.action_slot = act.slots[0]
    tr.mute = True


# --- locomotion ---------------------------------------------------------------
# One stride is 24 frames sampled every 3, so index i covers frame 1+3i and the
# right leg is simply the left leg read 4 indices (12 frames) later. Index 0 is
# the left contact (frame 1) and index 4 the right contact (frame 13), which is
# the contact pattern every locomotion clip has to share.
#
# Stance runs index 0->4 and swing 4->8, so the left leg carries the body for
# indices 0-3 and the right leg for 4-7.
FRAMES = [(1 + 3 * i, i % 8) for i in range(9)]      # ...frame 25 reuses index 0

#       contact  down  pass  push  toe-off  swing  fwd  reach
THIGH = [0.95, 0.45, 0.00, -0.70, -1.00, -0.50, 0.35, 1.00]
KNEE = [0.06, 0.34, 0.22, 0.10, 0.55, 1.00, 0.70, 0.18]    # scales a bend
FOOT = [0.55, 0.00, 0.00, -1.00, -0.85, -0.60, 0.10, 0.70]  # +toe up, -toe down
# Squash peaks just after each contact and stretch just before the next one.
SQ = [-0.8, -1.0, 0.6, 1.0, -0.8, -1.0, 0.6, 1.0]
# Extra lift at the passing poses; a run uses it to get airtime.
HOP = [0.0, 0.0, 1.0, 0.45, 0.0, 0.0, 1.0, 0.45]

SIDES = ((-1.0, "L"), (1.0, "R"))     # sign is the bone's world x direction

# Two points per foot that lie on the sole in the rest pose, cached in that
# foot bone's local space. Posing the rig and reading them back is what lets
# the hip height be solved instead of guessed, so the stance foot genuinely
# sits on z=0 through the whole stance instead of skating through it.
SOLE = {}
for _sfx in ("L", "R"):
    _fb = rig.pose.bones["foot.%s" % _sfx]
    _tip = rig.pose.bones["foot.%s_end" % _sfx].bone
    _inv = _fb.bone.matrix_local.inverted()
    SOLE[_sfx] = (_fb, [
        _inv @ mathutils.Vector((_fb.bone.head_local.x, _fb.bone.head_local.y, 0.0)),
        _inv @ mathutils.Vector((_tip.tail_local.x, _tip.tail_local.y, 0.0)),
    ])


def rest_all():
    for pb in rig.pose.bones:
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.scale = (1, 1, 1)
        pb.location = (0, 0, 0)


def sole_z(sfx):
    pb, pts = SOLE[sfx]
    m = rig.matrix_world @ pb.matrix
    return min((m @ p).z for p in pts)


def loco(name, *, swing, bend, toe, arm, lean, squash,
         lateral=0.0, back=False, ear=6.0, roll=0.0, hop=0.0):
    poses = []
    for f, i in FRAMES:
        pose = {}
        for sgn, sfx in SIDES:
            # left leg leads; the right leg is half a cycle behind it
            j = i if sfx == "L" else (i + 4) % 8
            k = (i + 4) % 8 if sfx == "L" else i          # opposite, for the arm
            sw = -THIGH[j] if back else THIGH[j]
            th_rx = swing * 0.30 * sw if lateral else swing * sw
            sh_rx = -bend * KNEE[j]
            thigh = {"rx": th_rx}
            if lateral:
                # a side shuffle: both thighs sweep towards the travel
                # direction, alternating how far, so the stance opens and
                # closes instead of the legs pacing fore and aft
                thigh["ry"] = lateral * (0.55 + 0.45 * THIGH[j])
            pose["thigh.%s" % sfx] = thigh
            pose["shin.%s" % sfx] = {"rx": sh_rx}
            # FOOT is the sole's pitch against the *ground*, so subtract what
            # the leg above already contributes. Left as a plain local angle
            # the ankle inherits the whole chain -- at toe-off that stacked up
            # to 60 degrees and speared the toe through the floor.
            pose["foot.%s" % sfx] = {"rx": toe * FOOT[j] - th_rx - sh_rx}
            pose["upperarm.%s" % sfx] = {
                "rx": arm * (-THIGH[k] if back else THIGH[k]),
                "ry": -sgn * (10.0 + 6.0 * SQ[k]),         # elbows swing clear
            }
            pose["forearm.%s" % sfx] = {"rx": arm * 0.35 * THIGH[k] - 8.0}
            pose["ear.%s" % sfx] = {
                "rx": ear * (0.45 + 0.55 * SQ[(i + 7) % 8]),
                "ry": -sgn * 4.0 * SQ[(i + 7) % 8],
            }

        sy = 1.0 + squash * SQ[i]
        twist = 0.0 if lateral else 1.0
        pose["hips"] = {"rx": lean * 0.35, "lz": 0.0,
                        "rz": 3.0 * SQ[(i + 2) % 8] * twist}
        pose["spine"] = {"rx": lean, "ry": roll + 2.5 * SQ[(i + 2) % 8],
                         "sy": sy, "sxz": 1.0 - 0.55 * (sy - 1.0)}
        pose["chest"] = {"rx": lean * 0.4, "rz": -4.0 * SQ[(i + 2) % 8] * twist}
        # head and belly lag the body by 3 frames -- the follow-through that
        # sells a body made of jelly
        lag = SQ[(i + 7) % 8]
        pose["head"] = {"rx": -lean * 0.75 + 5.0 * lag, "ry": roll * -0.5,
                        "sy": 1.0 + squash * 0.45 * lag,
                        "sxz": 1.0 - squash * 0.25 * lag}
        pose["belly"] = {"rx": -9.0 * lag, "sy": 1.0 + 0.11 * -lag}
        poses.append((f, pose))

    act = make(name, poses)
    plant(act, 25, stance=stance_of, hop=hop)
    stash(act)
    return act


loco("walk_fwd-loop", swing=26, bend=52, toe=13, arm=17, lean=-6, squash=0.16)
loco("run_fwd-loop", swing=44, bend=78, toe=19, arm=38, lean=-17,
     squash=0.27, ear=15, hop=0.055)
loco("walk_back-loop", swing=21, bend=44, toe=10, arm=14, lean=6, squash=0.14,
     back=True)
loco("walk_left-loop", swing=18, bend=44, toe=2, arm=10, lean=-2, squash=0.15,
     lateral=15, roll=-7)
loco("walk_right-loop", swing=18, bend=44, toe=2, arm=10, lean=-2, squash=0.15,
     lateral=-15, roll=7)

# --- idle ---------------------------------------------------------------------
# 48-frame breath, keyed every 6 frames. SIN/COS are one cycle over 8 steps.
SIN = [0.0, 0.707, 1.0, 0.707, 0.0, -0.707, -1.0, -0.707]
COS = [1.0, 0.707, 0.0, -0.707, -1.0, -0.707, 0.0, 0.707]

idle_keys = []
for n in range(9):
    j = n % 8
    a, b = SIN[(j - 1) % 8], SIN[(j - 2) % 8]      # 6- and 12-frame lag
    ca, cb = COS[(j - 1) % 8], COS[(j - 2) % 8]
    sy = 1.0 + 0.055 * SIN[j]
    pose = {
        "hips": {"ry": 1.2 * COS[j], "lz": 0.0},
        "spine": {"rx": -1.6 * SIN[j], "ry": 2.2 * COS[j],
                  "sy": sy, "sxz": 1.0 - 0.5 * (sy - 1.0)},
        "chest": {"rx": -1.2 * a, "ry": 1.4 * ca},
        "head": {"rx": 3.0 * a, "ry": -2.0 * ca, "rz": 2.4 * cb,
                 "sy": 1.0 + 0.03 * b, "sxz": 1.0 - 0.02 * b},
        "belly": {"rx": 6.0 * b, "sy": 1.0 + 0.055 * b},
    }
    for sgn, sfx in SIDES:
        pose[f"ear.{sfx}"] = {"rx": 6.0 * b, "ry": -sgn * 4.0 * cb}
        pose[f"upperarm.{sfx}"] = {"rx": 3.0 * a, "ry": -sgn * 3.5 * ca}
        pose[f"forearm.{sfx}"] = {"rx": 2.0 * b - 6.0}
        pose[f"thigh.{sfx}"] = {"rx": 1.5 * SIN[j]}
        pose[f"shin.{sfx}"] = {"rx": -2.5 * SIN[j]}
    idle_keys.append((1 + 6 * n, pose))

# breathing must not levitate the bear either
_idle = make("idle-loop", idle_keys)
plant(_idle, 49)
stash(_idle)

# --- getup --------------------------------------------------------------------
# One shot, 36 frames: flat on its back, rocks onto its haunches, springs up
# with a gelatinous overshoot and settles into the rest pose.
def G(hip_rx, hip_lz, sp_rx, sy, hd_rx, th, kn, ft, arm_rx, arm_ry, ear_rx,
      belly_rx=0.0):
    pose = {
        "hips": {"rx": hip_rx, "lz": hip_lz},
        "spine": {"rx": sp_rx, "sy": sy, "sxz": 1.0 - 0.55 * (sy - 1.0)},
        "chest": {"rx": sp_rx * 0.5},
        "head": {"rx": hd_rx},
        "belly": {"rx": belly_rx, "sy": 1.0 + 0.06 * (1.0 - sy) * 10.0},
    }
    for sgn, sfx in SIDES:
        pose[f"thigh.{sfx}"] = {"rx": th}
        pose[f"shin.{sfx}"] = {"rx": kn}
        pose[f"foot.{sfx}"] = {"rx": ft}
        pose[f"upperarm.{sfx}"] = {"rx": arm_rx, "ry": -sgn * arm_ry}
        pose[f"forearm.{sfx}"] = {"rx": arm_rx * 0.4 - 8.0}
        pose[f"ear.{sfx}"] = {"rx": ear_rx}
    return pose


# Pelvis heights are authored, not solved: lying on its back the hip sits about
# half a body-depth off the floor, and the spring-up is meant to leave the
# ground briefly. plant(clamp=True) then only ever lifts, so nothing sinks
# through the floor without flattening the authored arc.
getup_keys = [
    (1,  G(90, -0.078, 5, 1.02, -14, -22, -28, -6, 8, 42, -26, 12)),
    (5,  G(90, -0.086, 3, 0.92, -8, -8, -14, -2, 4, 48, -32, 16)),
    (10, G(78, -0.072, -6, 1.05, -26, -58, -70, 14, 26, 30, -12, 6)),
    (15, G(42, -0.058, -20, 1.00, -12, -74, -84, 20, 44, 16, 4, 0)),
    (20, G(10, -0.042, -26, 0.96, 14, 62, -96, 16, 56, 10, 14, -6)),
    (24, G(1, -0.022, -13, 0.94, 7, 30, -56, 8, 26, 8, 8, -4)),
    (28, G(0, 0.032, 4, 1.17, 9, -7, -2, -4, -19, 5, 24, 8)),
    (32, G(0, -0.016, -2, 0.93, -6, 7, -15, 3, 9, 3, -13, -5)),
    (36, G(0, 0.0, 0, 1.0, 0, 0, 0, 0, 0, 0, 0, 0)),
]
_getup = make("getup", getup_keys)
plant(_getup, 36, clamp=True)
stash(_getup)

# --- reset to rest and report --------------------------------------------------
for pb in rig.pose.bones:
    pb.rotation_mode = 'QUATERNION'
    pb.rotation_quaternion = (1, 0, 0, 0)
    pb.scale = (1, 1, 1)
    pb.location = (0, 0, 0)
scene.frame_set(1)

print("FPS:", scene.render.fps)
print("ACTIONS:", [a.name for a in bpy.data.actions])
for a in bpy.data.actions:
    fr = a.frame_range
    print("  %-16s frames %d-%d  curves %d"
          % (a.name, round(fr[0]), round(fr[1]), len(list(fcurves(a)))))
print("TRACKS:", [(t.name, t.mute, [s.name for s in t.strips])
                  for t in ad.nla_tracks])
bad = [fc.data_path for a in bpy.data.actions for fc in fcurves(a)
       if fc.extrapolation != 'CONSTANT']
print("NON_CONSTANT_EXTRAP:", len(bad))
bpy.ops.wm.save_mainfile(filepath=BLEND)
print("SAVED")
