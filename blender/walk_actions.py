# Author the four in-place walk loops on GummyRig and stash each one in its own
# muted NLA track. Ported from blender/animate_bear.py (the legacy 15-bone rig)
# onto the rebuilt 11-bone rig in gummy-bear.blend.
#
# Idempotent, but *scoped*: only actions whose name starts with "walk_" (and the
# NLA tracks holding them) are dropped and re-authored. "idle-loop" and its
# animation-data state are never touched, and it is the active action again when
# the script finishes. There is no undo call anywhere in this file.
#
# Contracts honoured here (Phase 4 blending / the Godot exporter depend on them):
#   * scene fps 24
#   * every clip is exactly frames 1-25, frame 25 duplicating frame 1, and all
#     four share one contact pattern -- left foot down on frame 1, right foot
#     down on frame 13 -- so a BlendSpace2D can crossfade them without skating
#   * every clip is in place: no horizontal travel anywhere on the rig
#   * f-curve extrapolation CONSTANT
#
# Poses are written in *world* axes and conjugated into each bone's rest frame,
# so bone roll never has to be reasoned about. The angle convention is the
# legacy one, stated relative to the bear:
#   rx = pitch (positive tips the top backwards)
#   ry = roll  (positive leans to the bear's right)
#   rz = yaw   (positive turns left)
#
# Three things differ from the legacy rig and are handled by named constants:
#
# FACE  This bear's snout points -Y (legacy's pointed +Y), i.e. the whole rig is
#       the legacy rig turned 180 degrees about Z. Under that turn a world
#       rotation (rx, ry, rz) becomes (-rx, -ry, rz), so the single flip lives
#       inside world_quat() and every legacy table/formula -- including the
#       SIDES sign table -- is kept verbatim in the legacy convention.
#
# SOLVER  leg.L/leg.R hang off `root`, not off `body`, so `root` is the deepest
#       common ancestor of both legs and therefore the bone the floor solver
#       moves. It also carries the squash, which matches the existing
#       idle-loop's convention (root.scale for squash, root.location[1] -- the
#       bone's local Y, which is world +Z -- for the solved height). `root`
#       never receives a horizontal offset, so "in place" still holds.
#
# KNEE_*  The new rig has no knee: legacy thigh+shin collapse into one `leg`
#       bone, and legacy upperarm+forearm into one `arm` bone. The legacy KNEE
#       curve therefore has to drive surrogates instead of a shin rotation:
#
#       KNEE_LIFT  A flexing knee mostly *shortens* the leg, and that is what
#         lifted the swing foot clear of the floor. A single strut cannot fold,
#         so the shortening is applied as an axial offset on the leg bone --
#         which carries the foot with it and never disturbs the hip's horizontal
#         placement. The offset is the exact geometric shortening of a
#         two-segment leg whose knee flexes by `bend * KNEE[i]` degrees, scaled
#         by KNEE_LIFT. Without it the swing toe hangs 0.107 BU under the floor
#         from toe-off to mid-swing (measured on this rig), because the strut is
#         at full length exactly when the foot is pitched toe-down.
#       KNEE_TOE   A toe-down pitch on the foot, the visual echo of the heel
#         tucking up behind a flexing knee. The brief's starting value of 0.35
#         costs 18 degrees of extra toe-down at mid-swing and cannot be paid
#         for: the toe sticks 0.43 BU in front of the ankle, so it buries the
#         toe faster than any amount of lift or swing can dig it out. Measured
#         down to the value below, which keeps the legacy FOOT table's own
#         toe-drop through swing as the dominant read.
#       KNEE_SWING An amplitude boost on the leg swing, peaking where KNEE does
#         (mid-swing). A leg further from vertical is a leg whose foot rides
#         higher, so this is clearance too, not decoration.
import bpy
import math
import mathutils

BLEND = "/Users/alex/gamedev/gummy-bear/gummy-bear.blend"
assert bpy.data.filepath == BLEND, ("wrong blend open: %r" % bpy.data.filepath)

RIG_NAME = "GummyRig"
IDLE = "idle-loop"
WALK_PREFIX = "walk_"
SOLVER = "root"          # confirmed by introspection: leg.L/leg.R parent to it
FACE = -1.0              # snout on -Y; legacy tables assume +Y

KNEE_TOE = 0.06          # legacy KNEE -> foot toe-down pitch, in units of `bend`
KNEE_SWING = 0.45        # legacy KNEE -> extra leg swing, buys swing clearance
KNEE_LIFT = 2.10         # legacy KNEE -> axial leg shortening, buys clearance

rig = bpy.data.objects[RIG_NAME]
scene = bpy.context.scene
view_layer = bpy.context.view_layer
scene.render.fps = 24
scene.render.fps_base = 1.0

if view_layer.objects.active and bpy.context.object.mode != 'OBJECT':
    bpy.ops.object.mode_set(mode='OBJECT')

rig.animation_data_create()
ad = rig.animation_data

# --- scoped wipe: walk_* only -------------------------------------------------
# idle-loop is only kept alive by ad.action, so protect it while ad.action is
# borrowed for keying, and hand its original flag back before the file is saved.
idle = bpy.data.actions[IDLE]
idle_fake_user = idle.use_fake_user
idle.use_fake_user = True
idle_slot = ad.action_slot if ad.action is idle else None

if ad.action is not None and ad.action.name.startswith(WALK_PREFIX):
    ad.action = None
for tr in list(ad.nla_tracks):
    if tr.name.startswith(WALK_PREFIX) or any(
            s.action is not None and s.action.name.startswith(WALK_PREFIX)
            for s in tr.strips):
        ad.nla_tracks.remove(tr)
for a in list(bpy.data.actions):
    if a.name.startswith(WALK_PREFIX):
        a.use_fake_user = False
        bpy.data.actions.remove(a)


# --- pose plumbing ------------------------------------------------------------
def rest_basis(name):
    return rig.pose.bones[name].bone.matrix_local.to_3x3()


def world_quat(name, rx, ry, rz):
    """A rotation given in world axes, expressed in the bone's rest frame.
    Angles arrive in the legacy (+Y facing) convention; FACE turns them into
    this rig's world axes."""
    m = rest_basis(name)
    R = mathutils.Euler((math.radians(rx * FACE),
                         math.radians(ry * FACE),
                         math.radians(rz)), 'XYZ').to_matrix()
    return (m.inverted() @ R @ m).to_quaternion()


def world_loc(name, dz):
    """A world-space vertical offset, expressed in the bone's rest frame."""
    return rest_basis(name).inverted() @ mathutils.Vector((0.0, 0.0, dz))


# Every bone on this rig is in XYZ euler mode and idle-loop keys
# rotation_euler, so the walks key rotation_euler too -- rotation_mode is a
# single per-bone property, not per-action, so mixing the two representations
# would silently break whichever action lost the coin toss.
def apply(pose):
    for name, p in pose.items():
        pb = rig.pose.bones[name]
        q = world_quat(name, p.get("rx", 0.0), p.get("ry", 0.0),
                       p.get("rz", 0.0))
        pb.rotation_euler = q.to_euler('XYZ', pb.rotation_euler)
        sxz, sy = p.get("sxz", 1.0), p.get("sy", 1.0)
        pb.scale = (sxz, sy, sxz)
        pb.location = world_loc(name, p.get("lz", 0.0))


def fcurves(act):
    for layer in act.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                for fc in cb.fcurves:
                    yield fc


def rest_all():
    for pb in rig.pose.bones:
        pb.rotation_euler = (0.0, 0.0, 0.0)
        pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pb.scale = (1.0, 1.0, 1.0)
        pb.location = (0.0, 0.0, 0.0)


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

    rest_all()
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    ad.action = act
    for f, pose in keys:
        for b in touched:
            pb = rig.pose.bones[b]
            pb.rotation_euler = (0.0, 0.0, 0.0)
            pb.scale = (1.0, 1.0, 1.0)
            pb.location = (0.0, 0.0, 0.0)
        apply(pose)
        for b in touched:
            pb = rig.pose.bones[b]
            pb.keyframe_insert("rotation_euler", frame=f)
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


# Two points per foot that lie on the sole in the rest pose, cached in that
# foot bone's local space. Posing the rig and reading them back is what lets the
# solver height be solved instead of guessed, so the stance foot genuinely sits
# on z=0 through the whole stance instead of skating through it. The legacy rig
# had a leaf foot.*_end bone for the toe; here the foot bone's own tail is the
# toe, so the heel/toe pair comes off head_local/tail_local.
SOLE = {}
for _sfx in ("L", "R"):
    _fb = rig.pose.bones["foot.%s" % _sfx]
    _inv = _fb.bone.matrix_local.inverted()
    SOLE[_sfx] = (_fb, [
        _inv @ mathutils.Vector((_fb.bone.head_local.x,
                                 _fb.bone.head_local.y, 0.0)),
        _inv @ mathutils.Vector((_fb.bone.tail_local.x,
                                 _fb.bone.tail_local.y, 0.0)),
    ])


def sole_z(sfx):
    pb, pts = SOLE[sfx]
    m = rig.matrix_world @ pb.matrix
    return min((m @ p).z for p in pts)


def plant(act, end, stance):
    """Solve the solver bone's height frame by frame off the *evaluated* pose so
    the supporting sole rides on z=0. Solving only at the pose keys is not
    enough -- the leg is a rotating strut, so the bezier between two planted
    keys dips the foot several centimetres through the floor.

    `stance` names the foot that must carry each frame; that is what pins the
    contact pattern. Without it the solver would happily plant whichever foot
    happened to hang lowest and slide the whole cycle out of phase.

    The reported dip is how far the *swing* sole reaches below the floor -- the
    clearance the missing knee used to provide, and the number KNEE_SWING is
    tuned against.
    """
    activate(act)
    solver = rig.pose.bones[SOLVER]
    basis = rest_basis(SOLVER)
    need, slack = {}, 0.0
    for f in range(1, end + 1):
        scene.frame_set(f)
        view_layer.update()
        zl, zr = sole_z("L"), sole_z("R")
        low = zl if stance(f) == "L" else zr
        slack = min(slack, min(zl, zr) - low)
        need[f] = (basis @ solver.location).z - low
    for f in range(1, end + 1):
        scene.frame_set(f)
        solver.location = world_loc(SOLVER, need[f])
        solver.keyframe_insert("location", frame=f)
    tidy(act)
    ad.action = None
    print("  plant %-16s deepest swing-sole dip %+.4f BU" % (act.name, slack))


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

SIDES = ((-1.0, "L"), (1.0, "R"))     # legacy convention: sign is legacy world x

LEG_LEN = rig.data.bones["leg.L"].length


def knee_lift(bend, j):
    """How much a two-segment leg of this length shortens when its knee flexes
    by `bend * KNEE[j]` degrees. Standing in for the fold the single `leg` bone
    cannot perform."""
    return LEG_LEN * (1.0 - math.cos(math.radians(bend * KNEE[j]) / 2.0)) \
        * KNEE_LIFT


def loco(name, *, swing, bend, toe, arm, lean, squash,
         lateral=0.0, back=False, ear=6.0, roll=0.0):
    poses = []
    for f, i in FRAMES:
        pose = {}
        for sgn, sfx in SIDES:
            # left leg leads; the right leg is half a cycle behind it
            j = i if sfx == "L" else (i + 4) % 8
            k = (i + 4) % 8 if sfx == "L" else i          # opposite, for the arm
            sw = -THIGH[j] if back else THIGH[j]
            base = swing * 0.30 * sw if lateral else swing * sw
            # no knee: the strut reaches further through swing, which is where
            # KNEE peaks, and that is what lifts the swing sole off the floor
            lg_rx = base * (1.0 + KNEE_SWING * KNEE[j])
            # ...and it telescopes, because a knee that folds is a leg that is
            # briefly shorter. This is what actually clears the toe.
            leg = {"rx": lg_rx, "lz": knee_lift(bend, j)}
            if lateral:
                # a side shuffle: both legs sweep towards the travel direction,
                # alternating how far, so the stance opens and closes instead of
                # the legs pacing fore and aft
                ry = lateral * (0.55 + 0.45 * THIGH[j])
                leg["ry"] = ry
                # Abducting a strut swings its foot upwards, so the two legs of
                # a shuffle hang at different heights and the floor solver,
                # which only pins the stance foot, hands the whole difference to
                # the other one. Lifting every leg to the height it would have
                # at full abduction cancels that without touching the sweep.
                leg["lz"] += LEG_LEN * (math.cos(math.radians(ry))
                                        - math.cos(math.radians(abs(lateral))))
            pose["leg.%s" % sfx] = leg
            # FOOT is the sole's pitch against the *ground*, so subtract what
            # the leg above already contributes. Left as a plain local angle the
            # ankle inherits the whole chain -- at toe-off that stacked up to 60
            # degrees and speared the toe through the floor. The KNEE term on
            # top drops the toe through swing, standing in for the heel that
            # used to tuck up behind a flexing knee.
            pose["foot.%s" % sfx] = {
                "rx": toe * FOOT[j] - lg_rx - KNEE_TOE * bend * KNEE[j]}
            # one arm bone replaces legacy upperarm+forearm; it takes the
            # shoulder channels, and ry keeps the elbow swinging clear of the
            # belly instead of through it
            pose["arm.%s" % sfx] = {
                "rx": arm * (-THIGH[k] if back else THIGH[k]),
                "ry": -sgn * (10.0 + 6.0 * SQ[k]),
            }
            pose["ear.%s" % sfx] = {
                "rx": ear * (0.45 + 0.55 * SQ[(i + 7) % 8]),
                "ry": -sgn * 4.0 * SQ[(i + 7) % 8],
            }

        sy = 1.0 + squash * SQ[i]
        twist = 0.0 if lateral else 1.0
        # root: legacy hips pitch/yaw, plus the squash and the solved floor
        # height (lz is keyed at 0 here so plant() has a channel to solve into)
        pose["root"] = {"rx": lean * 0.35, "rz": 3.0 * SQ[(i + 2) % 8] * twist,
                        "lz": 0.0,
                        "sy": sy, "sxz": 1.0 - 0.55 * (sy - 1.0)}
        # body: legacy spine and chest merged onto the one torso bone
        pose["body"] = {"rx": lean * 1.4,
                        "ry": roll + 2.5 * SQ[(i + 2) % 8],
                        "rz": -4.0 * SQ[(i + 2) % 8] * twist}
        # the head lags the body by 3 frames -- the follow-through that sells a
        # body made of jelly
        lag = SQ[(i + 7) % 8]
        pose["head"] = {"rx": -lean * 0.75 + 5.0 * lag, "ry": roll * -0.5,
                        "sy": 1.0 + squash * 0.45 * lag,
                        "sxz": 1.0 - squash * 0.25 * lag}
        poses.append((f, pose))

    act = make(name, poses)
    plant(act, 25, stance_of)
    stash(act)
    return act


print("AUTHORING walks (FACE=%+.0f solver=%s KNEE_TOE=%.2f KNEE_SWING=%.2f)"
      % (FACE, SOLVER, KNEE_TOE, KNEE_SWING))
loco("walk_fwd-loop", swing=26, bend=52, toe=13, arm=17, lean=-6, squash=0.16)
loco("walk_back-loop", swing=21, bend=44, toe=10, arm=14, lean=6, squash=0.14,
     back=True)
loco("walk_left-loop", swing=18, bend=44, toe=2, arm=10, lean=-2, squash=0.15,
     lateral=15, roll=-7)
loco("walk_right-loop", swing=18, bend=44, toe=2, arm=10, lean=-2, squash=0.15,
     lateral=-15, roll=7)

# --- contact-frame floor check ------------------------------------------------
# The stance sole has to sit on z=0 at both contacts and at the loop seam.
print("CONTACTS  clip              frame stance  stance_z   swing_z")
worst_contact, worst_swing = 0.0, 0.0
for _a in sorted(bpy.data.actions, key=lambda a: a.name):
    if not _a.name.startswith(WALK_PREFIX):
        continue
    activate(_a)
    for _f in (1, 13, 25):
        scene.frame_set(_f)
        view_layer.update()
        _st = stance_of(_f)
        _sz = sole_z(_st)
        _wz = sole_z("R" if _st == "L" else "L")
        worst_contact = max(worst_contact, abs(_sz))
        worst_swing = min(worst_swing, _wz)
        print("          %-16s %5d %6s %+9.5f %+9.5f"
              % (_a.name, _f, _st, _sz, _wz))
ad.action = None
print("worst |stance_z| at contacts: %.6f BU" % worst_contact)
print("lowest swing sole at contacts: %+.5f BU" % worst_swing)
assert worst_contact <= 0.01, worst_contact

# --- hand the rig back to idle-loop -------------------------------------------
rest_all()
ad.action = idle
if idle_slot is not None:
    ad.action_slot = idle_slot
elif idle.slots:
    ad.action_slot = idle.slots[0]
idle.use_fake_user = idle_fake_user
scene.frame_set(1)
view_layer.update()

print("TRACKS:", [(t.name, t.mute, [s.name for s in t.strips])
                  for t in ad.nla_tracks])
for _a in sorted(bpy.data.actions, key=lambda a: a.name):
    _fr = _a.frame_range
    print("  %-16s frames %d-%d  curves %d"
          % (_a.name, round(_fr[0]), round(_fr[1]), len(list(fcurves(_a)))))

# --- verification, then save --------------------------------------------------
# Verify first: a blend that fails its own contract is not worth persisting.
names = sorted(a.name for a in bpy.data.actions)
assert names == ["idle-loop", "walk_back-loop", "walk_fwd-loop",
                 "walk_left-loop", "walk_right-loop"], names
assert ad.action and ad.action.name == "idle-loop"
for a in bpy.data.actions:
    if a.name.startswith("walk_"):
        fr = a.frame_range
        assert (round(fr[0]), round(fr[1])) == (1, 25), (a.name, fr)
bad = [(a.name, fc.data_path) for a in bpy.data.actions if a.name.startswith("walk_")
       for fc in fcurves(a) if fc.extrapolation != 'CONSTANT']
assert not bad, bad
stashed = sorted((t.name, t.mute, tuple(s.action.name for s in t.strips))
                 for t in ad.nla_tracks)
assert stashed == [(n, True, (n,)) for n in names if n != IDLE], stashed

bpy.ops.wm.save_mainfile(filepath=BLEND)
print("SAVED", bpy.data.filepath)
print("WALK ACTIONS OK:", names)
