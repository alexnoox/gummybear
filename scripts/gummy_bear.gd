extends CharacterBody3D

## Test-grade gummy bear controller.
## Phase 4 replaces the locomotion with an AnimationTree/BlendSpace2D driver;
## the wobble spring and colour cycling stay.

const SPEED := 3.0
## Horizontal velocity lerp rate (1/s). Low on purpose: gummy lag.
const ACCEL_LERP := 5.0

# Damped spring driving the shader's vertex wobble.
const STIFF := 300.0      # omega ~= 17 rad/s ~= 2.8 Hz
const DAMP := 12.0        # zeta ~= 0.35 -> settles in ~0.3 s
const ACCEL_GAIN := 0.004 # metres of sag per m/s^2 of body acceleration
const MAX_WOBBLE := 0.12  # metres, hard clamp so the mesh never shreds

const PALETTE: Array[Color] = [
	Color(0.9, 0.08, 0.15, 0.8),  # cherry
	Color(1.0, 0.45, 0.05, 0.8),  # orange
	Color(1.0, 0.85, 0.1, 0.8),   # lemon
	Color(0.15, 0.8, 0.25, 0.8),  # lime
	Color(0.95, 0.95, 0.95, 0.75) # pineapple/clear
]

const GUMMY_MATERIAL := preload("res://materials/gummy_material.tres")

var _mesh: MeshInstance3D
var _anim: AnimationPlayer
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

var _wob_pos := Vector3.ZERO
var _wob_vel := Vector3.ZERO
var _prev_vel := Vector3.ZERO
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
		var idle := _resolve_animation("idle")
		if idle.is_empty():
			push_warning("GummyBear: no idle animation in %s" % [_anim.get_animation_list()])
		else:
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


func _physics_process(delta: float) -> void:
	# Wobble first: reads whatever velocity this tick starts with, including
	# impulses injected by the test harness before children process.
	_update_wobble(delta)

	if not is_on_floor():
		velocity.y -= _gravity * delta

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var target := Vector3(input.x, 0.0, input.y) * SPEED
	var blend := clampf(ACCEL_LERP * delta, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, target.x, blend)
	velocity.z = lerpf(velocity.z, target.z, blend)

	move_and_slide()


func _update_wobble(delta: float) -> void:
	if _mesh == null or delta <= 0.0:
		return
	var accel := (velocity - _prev_vel) / delta
	_prev_vel = velocity
	_wob_vel += (-STIFF * _wob_pos - DAMP * _wob_vel - accel * ACCEL_GAIN * STIFF) * delta
	_wob_pos += _wob_vel * delta
	# The shader displaces model-space VERTEX, so undo the mesh's world basis.
	var local: Vector3 = _mesh.global_basis.inverse() * _wob_pos
	_mesh.set_instance_shader_parameter("wobble_offset", local.limit_length(MAX_WOBBLE))


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
