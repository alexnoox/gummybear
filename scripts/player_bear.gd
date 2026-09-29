extends "res://scripts/gummy_bear.gd"

## The red player bear. Orbit-camera third person in strafe mode: WASD or the
## left stick is camera-relative and the body lazily yaws toward the orbit
## camera while driving; Space or X jumps while grounded. Left click (mouse
## captured), A or the right trigger throws a dodgeball along the camera, with
## strong aim assist toward the best-aligned standing green bear, which a
## bouncing marker points out. An idle bear quickly turns to face its throw.
## The left stick's forward/back and left/right can each be inverted (pause
## menu).
## The player is always cherry red.

## Top ground speed in m/s, reached at full stick (or any WASD key).
const SPEED := 2.5
## Upward takeoff speed in metres per second.
const JUMP_VELOCITY := 2.8

## Seconds between throws; throwing is otherwise unlimited.
const THROW_COOLDOWN := 0.3
## Unassisted throws leave along the camera's forward at this speed (m/s),
## tipped up by THROW_LOFT (added to the direction's y before normalising) so
## the downward-looking camera doesn't bounce every ball at the bear's feet.
const THROW_SPEED := 11.0
const THROW_LOFT := 0.2
## The ball leaves the chest, a little ahead of the body.
const THROW_HEIGHT := 0.6
const THROW_REACH := 0.3
## An idle bear turns to face its throw at this yaw rate (1/s) for this long.
## Quick on purpose; the brief foot slide was accepted (ADR 0001).
const FACE_LERP := 15.0
const FACE_TIME := 0.4

## Aim assist: the standing green bear best aligned with the camera, within
## this half-angle (radians, ±30°) and horizontal range (m), is the target.
const ASSIST_ANGLE := PI / 6.0
const ASSIST_RANGE := 10.0
## Assisted throws fly at this horizontal speed (m/s) at the target's chest,
## leading its velocity.
const ASSIST_SPEED := 10.0
const TARGET_HEIGHT := 0.45

## The marker hovers this high over the target's feet, bobbing.
const MARKER_HEIGHT := 1.3
const MARKER_BOB := 0.08
const MARKER_BOB_RATE := 6.0
const MARKER_SPIN := 2.0
const MARKER_COLOUR := Color(1.0, 0.85, 0.1)

## Preloaded rather than referenced by class_name: the global class cache
## only refreshes on editor import, so a bare `OrbitCamera` annotation
## breaks headless/CLI runs (e.g. the --shots harness) after a fresh edit.
const ORBIT_CAMERA := preload("res://scripts/orbit_camera.gd")
const BALL := preload("res://scripts/ball.gd")
const SETTINGS := preload("res://scripts/settings.gd")
const GUMMY_BEAR := preload("res://scripts/gummy_bear.gd")

## Flip the walk input's forward/back and left/right. These are the
## defaults; values saved from the pause menu win.
@export var invert_move_y := false
@export var invert_move_x := false

var _cooldown := 0.0
var _face_yaw := 0.0
var _face_time_left := 0.0
var _aim_target: GUMMY_BEAR
var _marker: MeshInstance3D

@onready var _camera_rig: ORBIT_CAMERA = $CameraRig
@onready var _camera: Camera3D = $CameraRig/SpringArm3D/Camera3D


func _ready() -> void:
	super()
	add_to_group("player")
	invert_move_y = SETTINGS.load_value("invert_move_y", invert_move_y)
	invert_move_x = SETTINGS.load_value("invert_move_x", invert_move_x)
	_build_marker()


func _steer(delta: float) -> Vector3:
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if invert_move_x:
		input.x = -input.x
	if invert_move_y:
		input.y = -input.y
	# Strafe mode: while the player drives, the body chases the camera yaw.
	# Idle, it holds still (no turn-in-place clip), except for a quick turn
	# to face a throw. The camera rig is top_level, so this rotation never
	# feeds back into mouse look.
	if input != Vector2.ZERO:
		turn_toward(_camera_rig.yaw, YAW_LERP, delta)
	elif _face_time_left > 0.0:
		turn_toward(_face_yaw, FACE_LERP, delta)
	_face_time_left = maxf(0.0, _face_time_left - delta)
	# Camera-relative drive: with yaw 0 this is world-axis movement.
	return Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, _camera_rig.yaw) * SPEED


func _physics_process(delta: float) -> void:
	super(delta)
	_cooldown = maxf(0.0, _cooldown - delta)
	_aim_target = _pick_target()
	if Input.is_action_just_pressed("throw") and _cooldown == 0.0:
		_throw()


func _process(delta: float) -> void:
	super(delta)
	var show := _aim_target != null and not _aim_target.is_down()
	_marker.visible = show
	if show:
		var time := Time.get_ticks_msec() / 1000.0
		_marker.global_position = (
				_aim_target.get_global_transform_interpolated().origin
				+ Vector3.UP * (MARKER_HEIGHT + MARKER_BOB * sin(time * MARKER_BOB_RATE)))
		_marker.rotation.y = time * MARKER_SPIN


## The round is won: look up at the fireworks.
func celebrate() -> void:
	_camera_rig.look_to_sky()


## The camera's horizontal forward.
func _camera_forward() -> Vector3:
	var yaw := _camera_rig.yaw
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## The standing green bear best aligned with the camera, or null.
func _pick_target() -> GUMMY_BEAR:
	var forward := _camera_forward()
	var best: GUMMY_BEAR = null
	var best_angle := ASSIST_ANGLE
	for bear: GUMMY_BEAR in get_tree().get_nodes_in_group("green_bears"):
		if bear.is_down():
			continue
		var to_bear := bear.global_position - global_position
		to_bear.y = 0.0
		if to_bear.length() > ASSIST_RANGE or to_bear.is_zero_approx():
			continue
		var angle := forward.angle_to(to_bear)
		if angle <= best_angle:
			best = bear
			best_angle = angle
	return best


func _throw() -> void:
	_cooldown = THROW_COOLDOWN
	var origin := (global_position + Vector3.UP * THROW_HEIGHT
			+ _camera_forward() * THROW_REACH)
	var launch: Vector3
	if _aim_target != null:
		launch = _lob_at(origin, _aim_target)
	else:
		var aim := -_camera.global_basis.z
		aim.y += THROW_LOFT
		launch = aim.normalized() * THROW_SPEED
	_face_yaw = yaw_of(launch)
	_face_time_left = FACE_TIME

	var ball: RigidBody3D = BALL.new()
	get_parent().add_child(ball)
	ball.global_position = origin
	ball.linear_velocity = launch
	ball.reset_physics_interpolation()
	# The ball passes through its thrower.
	ball.add_collision_exception_with(self)


## Launch velocity that lands on `bear`'s chest after a flight at
## ASSIST_SPEED across the ground, leading the bear's horizontal velocity.
func _lob_at(origin: Vector3, bear: GUMMY_BEAR) -> Vector3:
	var chest := bear.global_position + Vector3.UP * TARGET_HEIGHT
	var drift := Vector3(bear.velocity.x, 0.0, bear.velocity.z)
	var flight := 0.0
	# A few refinements settle the lead: the flight time depends on where
	# the bear will be, which depends on the flight time.
	for i in 3:
		var across := chest + drift * flight - origin
		across.y = 0.0
		flight = maxf(across.length() / ASSIST_SPEED, 0.1)
	var aim := chest + drift * flight
	return (aim - origin) / flight - 0.5 * get_gravity() * flight


## A yellow down-arrow that floats over the next throw's target.
func _build_marker() -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.14
	cone.bottom_radius = 0.0
	cone.height = 0.26
	cone.radial_segments = 16
	cone.rings = 1
	var material := StandardMaterial3D.new()
	# Opaque: the bears' colour pass draws late (render_priority 1), so a
	# transparent marker would sort behind them.
	material.albedo_color = MARKER_COLOUR
	material.emission_enabled = true
	material.emission = MARKER_COLOUR * 0.3
	cone.material = material
	_marker = MeshInstance3D.new()
	_marker.name = "AimMarker"
	_marker.mesh = cone
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.top_level = true
	# Placed by hand every rendered frame from the target's interpolated
	# transform.
	_marker.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_marker.visible = false
	add_child(_marker)
