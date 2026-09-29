extends CharacterBody3D

## Shared gummy bear body, used by the red player bear and the green bears.
## Subclasses decide where to go through `_steer()` (a horizontal target
## velocity; they turn the body with `turn_toward()`); this base does gravity,
## the gummy-lag velocity lerp, `move_and_slide()`, and feeds a code-built
## AnimationTree (a BlendSpace2D of idle + 4 directional walk loops, then a
## TimeScale) with body-local velocity. `knock()` flops the bear into a
## code-built ragdoll that stays down. Every frame the bears are re-sorted
## by camera distance so each one's translucent gummy draws back to front.

## Ground speed at which the walk clips play at 1×. The clips' authored
## strides are slower (fwd 0.447 m/s, back 0.362, strafe 0.142), so they
## already glide a little here; that look was accepted. Above this speed the
## clips speed up in proportion rather than matching the strides, which would
## take ~5.6× playback at top speed and look frantic.
const STRIDE_SPEED := 1.0
## Horizontal velocity lerp rate (1/s). Low on purpose: gummy lag.
const ACCEL_LERP := 5.0
## Body yaw lerp rate (1/s). Matches ACCEL_LERP so a turn has the same gummy
## lag character as the walk.
const YAW_LERP := 5.0

## Physics layer bits (named in project.godot).
const LAYER_WORLD := 1
const LAYER_BEARS := 2
const LAYER_RAGDOLLS := 4
const LAYER_BALLS := 8

## Knock: the whole ragdoll is launched at this speed along the ball's
## horizontal path, plus an upward pop, and the head gets an extra shove so
## the bear topples rather than sliding upright.
const KNOCK_SPEED := 2.5
const KNOCK_POP := 2.0
const KNOCK_TOPPLE := 1.5

## Ragdoll bone shapes in metres: [radius, capsule length] per bone, the
## capsule running up the bone's +Y from its head; length 0 means a sphere.
const RAGDOLL_SHAPES := {
	"root": [0.12, 0.10], "body": [0.18, 0.30], "head": [0.17, 0.0],
	"arm.L": [0.05, 0.18], "arm.R": [0.05, 0.18],
	"leg.L": [0.07, 0.20], "leg.R": [0.07, 0.20],
	"foot.L": [0.06, 0.0], "foot.R": [0.06, 0.0],
	"ear.L": [0.04, 0.0], "ear.R": [0.04, 0.0],
}
const RAGDOLL_CONE_BONES := ["body", "head", "arm.L", "arm.R", "leg.L", "leg.R"]

const GUMMY_MATERIAL := preload("res://materials/gummy_material.tres")

## BlendSpace2D layout, fed with body-local velocity (world velocity rotated
## by −rotation.y) over STRIDE_SPEED, capped at unit length. Clip names are
## bear-relative: the rig asset itself faces +Z, but scenes/gummy_bear.tscn
## yaws the `Model` node 180° about Y, so in body space −Z is the bear's
## forward and +X is its right. The body yaws (strafe mode for the player,
## facing its velocity for green bears), so the invariant is that the blend is
## fed body-local velocity.
const BLEND_POINTS := {
	"idle": Vector2.ZERO,
	"walk_fwd": Vector2(0.0, -1.0),
	"walk_back": Vector2(0.0, 1.0),
	"walk_left": Vector2(-1.0, 0.0),
	"walk_right": Vector2(1.0, 0.0),
}


## The GummyRig's 0.333 scale leaks into the simulated bone bases, so a
## ragdolled bear would render 3× too big. Runs after the simulator and
## strips the scale from every bone's global pose while simulating.
class ScaleFix extends SkeletonModifier3D:
	var simulator: PhysicalBoneSimulator3D

	func _process_modification_with_delta(_delta: float) -> void:
		if simulator == null or not simulator.is_simulating_physics():
			return
		var skeleton := get_skeleton()
		var poses: Array[Transform3D] = []
		for i in skeleton.get_bone_count():
			poses.append(skeleton.get_bone_global_pose(i))
		for i in skeleton.get_bone_count():
			skeleton.set_bone_global_pose(i,
					Transform3D(poses[i].basis.orthonormalized(), poses[i].origin))


## Candy colour, fed to the gummy shader as a per-instance parameter.
@export var colour := Color(0.9, 0.08, 0.15, 0.8)

var _mesh: MeshInstance3D
var _anim: AnimationPlayer
var _tree: AnimationTree
var _skeleton: Skeleton3D
var _ragdoll: PhysicalBoneSimulator3D
var _down := false
var _depth_pass: ShaderMaterial
var _colour_pass: ShaderMaterial

## The Engine process frame the bears were last sorted on (shared by all).
static var _sorted_frame := -1


func _ready() -> void:
	# owned = false: nodes inside the instanced .glb are owned by its own root.
	var model := $Model
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		push_error("GummyBear: no MeshInstance3D found under Model")
	else:
		_mesh = meshes[0]
		# Each bear owns its pair of passes (sharing the shaders) so its
		# draw order can be set on its own; see _sort_draw_order().
		_depth_pass = GUMMY_MATERIAL.duplicate()
		_colour_pass = GUMMY_MATERIAL.next_pass.duplicate()
		_depth_pass.next_pass = _colour_pass
		_mesh.material_override = _depth_pass
		_mesh.set_instance_shader_parameter("gummy_color", colour)

	add_to_group("gummy_bears")

	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		_skeleton = skeletons[0]

	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		push_warning("GummyBear: no AnimationPlayer found under Model")
	else:
		_anim = players[0]
		_setup_locomotion_tree()
		if _tree == null:
			var idle := _resolve_animation("idle")
			if idle.is_empty():
				push_warning("GummyBear: no idle animation in %s" % [_anim.get_animation_list()])
			else:
				# Exactly one driver on the skeleton. The AnimationTree owns the
				# AnimationPlayer once active, so an AnimationPlayer.play() beside
				# it would be a second mixer racing on the same bones. Only fall
				# back to a bare idle loop when the tree could not be built.
				_anim.play(idle)


## Godot's importer may keep `idle-loop` or strip the `-loop` suffix.
func _resolve_animation(stem: String) -> String:
	var names := _anim.get_animation_list()
	for candidate in [stem + "-loop", stem]:
		if names.has(candidate):
			return candidate
	for name in names:
		if name.begins_with(stem):
			return name
	return ""


## Builds the locomotion blend tree in code so animation names stay
## suffix-tolerant. On any missing clip the bear degrades to idle-only.
func _setup_locomotion_tree() -> void:
	var space := AnimationNodeBlendSpace2D.new()
	# Default sync (SYNC_MODE_NONE) freezes inactive blend points, so a
	# direction change would crossfade two 1 s walk cycles at arbitrary
	# relative phase (leg pop). All four walks share one length, so letting
	# every clip advance keeps them phase-locked for free.
	space.sync_mode = AnimationNodeBlendSpace2D.SYNC_MODE_INDEPENDENT
	for stem: String in BLEND_POINTS:
		var anim_name := _resolve_animation(stem)
		if anim_name.is_empty():
			push_warning("GummyBear: no %s animation in %s; idle-only" %
					[stem, _anim.get_animation_list()])
			return
		var clip := AnimationNodeAnimation.new()
		clip.animation = anim_name
		space.add_blend_point(clip, BLEND_POINTS[stem], -1, stem)
	# Above STRIDE_SPEED the blend sits on the unit circle (idle weight 0), so
	# scaling time after the blend only ever speeds up the walks.
	var root := AnimationNodeBlendTree.new()
	root.add_node("locomotion", space)
	root.add_node("speed", AnimationNodeTimeScale.new())
	root.connect_node("speed", 0, "locomotion")
	root.connect_node("output", 0, "speed")
	_tree = AnimationTree.new()
	_tree.name = "LocomotionTree"
	_tree.tree_root = root
	add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_anim)
	_tree.active = true


## Virtual: the horizontal velocity (m/s) the bear wants this tick. Turn the
## body from here with `turn_toward()`; set `velocity.y` here to jump.
func _steer(_delta: float) -> Vector3:
	return Vector3.ZERO


## Lerps the body yaw toward `yaw` at `rate` (1/s), gummy style.
func turn_toward(yaw: float, rate: float, delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, yaw, clampf(rate * delta, 0.0, 1.0))


## The body yaw that faces a horizontal world direction (forward is −Z).
static func yaw_of(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


func _physics_process(delta: float) -> void:
	if _down:
		# The ragdoll carries the skeleton now; the body just stays put.
		return
	if not is_on_floor():
		velocity += get_gravity() * delta
	var target := _steer(delta)
	var blend := clampf(ACCEL_LERP * delta, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, target.x, blend)
	velocity.z = lerpf(velocity.z, target.z, blend)

	move_and_slide()

	if _tree != null:
		# Un-rotate into body space so the blend axes stay glued to the bear
		# no matter where it is facing.
		var local := velocity.rotated(Vector3.UP, -rotation.y)
		var stride := Vector2(local.x, local.z) / STRIDE_SPEED
		_tree.set("parameters/locomotion/blend_position", stride.limit_length(1.0))
		_tree.set("parameters/speed/scale", maxf(1.0, stride.length()))


func _process(_delta: float) -> void:
	_sort_draw_order()


## Both gummy passes are transparent, and Godot draws transparent objects in
## render_priority order before depth. With one shared material every bear's
## depth-only pass drew before every bear's colour pass, so a near bear's
## depth hid the bears behind it (they vanished through its translucency).
## Instead each bear gets two consecutive priorities, farthest from the
## camera lowest: every bear draws depth then colour, back to front. Done
## once per frame for all bears, by whichever bear processes first.
func _sort_draw_order() -> void:
	var frame := Engine.get_process_frames()
	if _sorted_frame == frame:
		return
	_sorted_frame = frame
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var eye := camera.global_position
	var bears := get_tree().get_nodes_in_group("gummy_bears")
	bears.sort_custom(func(a: Node, b: Node) -> bool:
		return a.call("draw_distance", eye) > b.call("draw_distance", eye))
	for i in bears.size():
		bears[i].call("set_draw_slot", i)


## Distance from `eye` to where this bear is drawn: its ragdoll's body once
## knocked down (the CharacterBody3D stays behind), its middle otherwise.
func draw_distance(eye: Vector3) -> float:
	var centre := global_position + Vector3.UP * 0.5
	if _down:
		for bone: PhysicalBone3D in ragdoll_bones():
			if bone.bone_name == "body":
				centre = bone.global_position
	return eye.distance_to(centre)


## Slot 0 draws first. 128 slots fit Godot's render_priority range.
func set_draw_slot(slot: int) -> void:
	if _depth_pass == null:
		return
	var priority := mini(Material.RENDER_PRIORITY_MIN + 2 * slot,
			Material.RENDER_PRIORITY_MAX - 1)
	_depth_pass.render_priority = priority
	_colour_pass.render_priority = priority + 1


func is_down() -> bool:
	return _down


## The ragdoll's PhysicalBone3D nodes (empty if none was built).
func ragdoll_bones() -> Array:
	if _ragdoll == null:
		return []
	return _ragdoll.get_children().filter(func(n): return n is PhysicalBone3D)


## Builds an inert ragdoll: the simulator stays active so its kinematic bones
## track the animated pose (and a knock starts from the right place), but
## they sit on no layer and mask nothing until `knock()`, because active
## kinematic bones would otherwise shove this bear's own CharacterBody3D.
func build_ragdoll() -> void:
	if _skeleton == null or _ragdoll != null:
		return
	_ragdoll = PhysicalBoneSimulator3D.new()
	_ragdoll.name = "Ragdoll"
	_skeleton.add_child(_ragdoll)
	var bones: Array[PhysicalBone3D] = []
	for i in _skeleton.get_bone_count():
		var bone_name := _skeleton.get_bone_name(i)
		if not RAGDOLL_SHAPES.has(bone_name):
			continue
		var bone := PhysicalBone3D.new()
		bone.name = "PB_" + bone_name
		# bone_name must be set before the bone enters the tree.
		bone.bone_name = bone_name
		bone.mass = 1.0
		bone.joint_type = (PhysicalBone3D.JOINT_TYPE_CONE
				if bone_name in RAGDOLL_CONE_BONES
				else PhysicalBone3D.JOINT_TYPE_PIN)
		bone.collision_layer = 0
		bone.collision_mask = 0
		var radius: float = RAGDOLL_SHAPES[bone_name][0]
		var length: float = RAGDOLL_SHAPES[bone_name][1]
		var shape := CollisionShape3D.new()
		if length > 0.0:
			var capsule := CapsuleShape3D.new()
			capsule.radius = radius
			capsule.height = maxf(length, 2.0 * radius)
			shape.shape = capsule
			# Offset the shape in metres (body_offset would pick up the
			# rig's 0.333 scale).
			shape.position = Vector3(0.0, capsule.height * 0.5, 0.0)
		else:
			var sphere := SphereShape3D.new()
			sphere.radius = radius
			shape.shape = sphere
		bone.add_child(shape)
		_ragdoll.add_child(bone)
		bones.append(bone)
	# Jolt joints don't stop the two bones they join from colliding, so the
	# bones of one bear ignore each other (and the bear's own capsule).
	for a in bones.size():
		bones[a].add_collision_exception_with(self)
		for b in range(a + 1, bones.size()):
			bones[a].add_collision_exception_with(bones[b])
	var fix := ScaleFix.new()
	fix.name = "RagdollScaleFix"
	fix.simulator = _ragdoll
	_skeleton.add_child(fix)


## Flops the bear: shoved along `hit_velocity`'s horizontal direction with an
## upward pop, then limp. It stays down (the stand-up reset is cycle 2b).
func knock(hit_velocity: Vector3) -> void:
	if _down or _ragdoll == null:
		return
	_down = true
	velocity = Vector3.ZERO
	collision_layer = 0
	$CollisionShape3D.set_deferred("disabled", true)
	# Godot #101823: with physics interpolation on, a ragdolled skeleton's
	# mesh drifts away from its bones. Only while down: walking needs it.
	_skeleton.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var push := Vector3(hit_velocity.x, 0.0, hit_velocity.z)
	push = push.normalized() if push.length() > 0.01 else global_basis.z
	var launch := push * KNOCK_SPEED + Vector3.UP * KNOCK_POP
	for bone: PhysicalBone3D in ragdoll_bones():
		bone.collision_layer = LAYER_RAGDOLLS
		bone.collision_mask = LAYER_WORLD | LAYER_RAGDOLLS
	_ragdoll.physical_bones_start_simulation()
	# Impulses land in the same frame the simulation starts.
	for bone: PhysicalBone3D in ragdoll_bones():
		var shove := launch
		if bone.bone_name == "head":
			shove += push * KNOCK_TOPPLE
		bone.apply_central_impulse(shove * bone.mass)
