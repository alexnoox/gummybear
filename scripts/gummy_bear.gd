extends CharacterBody3D

## Gummy bear controller. Orbit-camera third person in strafe mode: WASD or
## the left stick is camera-relative and the body lazily yaws toward the orbit
## camera, feeding a code-built AnimationTree (a BlendSpace2D of idle + 4
## directional walk loops, then a TimeScale); Space or A jumps while grounded.
## The player is always cherry red.

## Top ground speed in m/s, reached at full stick (or any WASD key).
const SPEED := 2.5
## Ground speed at which the walk clips play at 1×. The clips' authored
## strides are slower (fwd 0.447 m/s, back 0.362, strafe 0.142), so they
## already glide a little here; that look was accepted. Above this speed the
## clips speed up in proportion rather than matching the strides, which would
## take ~5.6× playback at top speed and look frantic.
const STRIDE_SPEED := 1.0
## Horizontal velocity lerp rate (1/s). Low on purpose: gummy lag.
const ACCEL_LERP := 5.0
## Body yaw lerp rate (1/s) toward the camera yaw. Matches ACCEL_LERP so the
## turn has the same gummy lag character as the walk.
const YAW_LERP := 5.0
## Upward takeoff speed in metres per second.
const JUMP_VELOCITY := 2.8

const CHERRY := Color(0.9, 0.08, 0.15, 0.8)

const GUMMY_MATERIAL := preload("res://materials/gummy_material.tres")
## Preloaded rather than referenced by class_name: the global class cache
## only refreshes on editor import, so a bare `OrbitCamera` annotation
## breaks headless/CLI runs (e.g. the --shots harness) after a fresh edit.
const ORBIT_CAMERA := preload("res://scripts/orbit_camera.gd")

## BlendSpace2D layout, fed with body-local velocity (world velocity rotated
## by −rotation.y) over STRIDE_SPEED, capped at unit length. Clip names are bear-relative: the rig asset itself faces
## +Z, but scenes/gummy_bear.tscn yaws the `Model` node 180° about Y, so in
## body space −Z is the bear's forward and +X is its right. The body yaws
## toward the orbit camera (strafe mode), so the invariant is no longer that
## the body never rotates — it's that the blend is fed body-local velocity.
const BLEND_POINTS := {
	"idle": Vector2.ZERO,
	"walk_fwd": Vector2(0.0, -1.0),
	"walk_back": Vector2(0.0, 1.0),
	"walk_left": Vector2(-1.0, 0.0),
	"walk_right": Vector2(1.0, 0.0),
}

var _mesh: MeshInstance3D
var _anim: AnimationPlayer
var _tree: AnimationTree

@onready var _camera_rig: ORBIT_CAMERA = $CameraRig


func _ready() -> void:
	# owned = false: nodes inside the instanced .glb are owned by its own root.
	var meshes := find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		push_error("GummyBear: no MeshInstance3D found under Model")
	else:
		_mesh = meshes[0]
		_mesh.material_override = GUMMY_MATERIAL
		_apply_colour()

	var players := find_children("*", "AnimationPlayer", true, false)
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


func _physics_process(delta: float) -> void:
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY
	elif not is_on_floor():
		velocity += get_gravity() * delta

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Strafe mode: while the player drives, the body chases the camera yaw
	# with the same lazy lerp as the velocity below. Idle, it holds still:
	# there is no turn-in-place clip, so turning would slide the feet. The
	# camera rig is top_level, so this rotation never feeds back into mouse
	# look.
	if input != Vector2.ZERO:
		rotation.y = lerp_angle(rotation.y, _camera_rig.yaw,
				clampf(YAW_LERP * delta, 0.0, 1.0))
	# Camera-relative drive: with yaw 0 this reduces exactly to the old
	# world-axis movement.
	var dir3 := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, _camera_rig.yaw)
	var target := dir3 * SPEED
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


func _apply_colour() -> void:
	if _mesh != null:
		_mesh.set_instance_shader_parameter("gummy_color", CHERRY)
