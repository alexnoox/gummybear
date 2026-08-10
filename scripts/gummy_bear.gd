extends CharacterBody3D

## Gummy bear controller. WASD locomotion feeds a code-built
## AnimationTree/BlendSpace2D (idle + 4 directional walk loops); Space jumps
## while grounded and KEY_C cycles the gummy colour.

## Lowered from 3.0 to match the authored stride speeds measured off the
## exported clips (fwd 0.447 m/s, back 0.362, strafe 0.142). A residual glide
## remains on the strafes; accepted rather than adding a TimeScale node.
const SPEED := 1.0
## Horizontal velocity lerp rate (1/s). Low on purpose: gummy lag.
const ACCEL_LERP := 5.0
## Upward takeoff speed in metres per second.
const JUMP_VELOCITY := 2.8

const PALETTE: Array[Color] = [
	Color(0.9, 0.08, 0.15, 0.8),  # cherry
	Color(1.0, 0.45, 0.05, 0.8),  # orange
	Color(1.0, 0.85, 0.1, 0.8),   # lemon
	Color(0.15, 0.8, 0.25, 0.8),  # lime
	Color(0.95, 0.95, 0.95, 0.75) # pineapple/clear
]

const GUMMY_MATERIAL := preload("res://materials/gummy_material.tres")

## BlendSpace2D layout, fed with Vector2(velocity.x, velocity.z). Clip names are
## bear-relative: the rig asset itself faces +Z, but scenes/gummy_bear.tscn yaws
## the `Model` node 180° about Y, so the bear faces −Z in world (third-person,
## away from the default camera). The CharacterBody3D never rotates, so world
## velocity IS bear-relative: −Z is the bear's forward and +X is its right.
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
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

var _colour_index := 0


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
	_tree = AnimationTree.new()
	_tree.name = "LocomotionTree"
	_tree.tree_root = space
	add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_anim)
	_tree.active = true


func _physics_process(delta: float) -> void:
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY
	elif not is_on_floor():
		velocity.y -= _gravity * delta

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var target := Vector3(input.x, 0.0, input.y) * SPEED
	var blend := clampf(ACCEL_LERP * delta, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, target.x, blend)
	velocity.z = lerpf(velocity.z, target.z, blend)

	move_and_slide()

	if _tree != null:
		_tree.set("parameters/blend_position",
				Vector2(velocity.x, velocity.z) / SPEED)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_C:
		_colour_index = (_colour_index + 1) % PALETTE.size()
		_apply_colour()
		get_viewport().set_input_as_handled()


func _apply_colour() -> void:
	if _mesh != null:
		_mesh.set_instance_shader_parameter("gummy_color", PALETTE[_colour_index])
