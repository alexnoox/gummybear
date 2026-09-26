class_name OrbitCamera
extends Node3D

## Mouse-orbit third-person rig for the gummy bear. Lives under the
## CharacterBody3D but runs top-level so the body's yaw (which chases this
## rig's yaw) never compounds with mouse look; each physics tick it snaps to
## the bear's position. The rig is crisp on purpose: all the gummy lag lives
## in the body's velocity/yaw lerps. Esc toggles cursor capture (a left click also recaptures), the wheel
## zooms the spring arm, pitch is clamped so the camera neither dives under
## the stage nor flips over the bear.

## Radians of rotation per pixel of mouse travel.
const MOUSE_SENSITIVITY := 0.003
## Pitch limits in radians (−60°..+20°).
const PITCH_MIN := -PI / 3.0
const PITCH_MAX := PI / 9.0
## Spring-arm length limits and wheel step, in metres.
const ZOOM_MIN := 1.5
const ZOOM_MAX := 5.0
const ZOOM_STEP := 0.25
## Orbit pivot sits at the bear's chest rather than its feet, so pitching
## circles the body instead of the ground plane.
const PIVOT_HEIGHT := 0.6

## World-space camera yaw in radians; the bear steers toward this.
var yaw: float:
	get:
		return rotation.y

@onready var _body: CharacterBody3D = get_parent()
@onready var _arm: SpringArm3D = $SpringArm3D


func _ready() -> void:
	# Detach from the parent's transform: the body yaws toward this rig's
	# yaw every tick, so inheriting it would feed mouse look back into
	# itself and spin the camera.
	top_level = true
	# The arm should only shorten against the world, never against the
	# bear's own capsule sitting at the pivot.
	_arm.add_excluded_object(_body.get_rid())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_snap_to_body()


func _physics_process(_delta: float) -> void:
	_snap_to_body()


func _snap_to_body() -> void:
	global_position = _body.global_position + Vector3(0.0, PIVOT_HEIGHT, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# Esc frees the cursor for window/editor work; Esc again resumes.
		Input.mouse_mode = (Input.MOUSE_MODE_VISIBLE
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
				else Input.MOUSE_MODE_CAPTURED)
		get_viewport().set_input_as_handled()
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# Clicking back into the game resumes mouse look, like Esc does.
		var click := event as InputEventMouseButton
		if (click != null and click.pressed
				and click.button_index == MOUSE_BUTTON_LEFT):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
		return

	var motion := event as InputEventMouseMotion
	if motion != null:
		# Mouse right orbits right (negative yaw), mouse up looks up
		# (positive pitch); pitch lives on the arm, yaw on the rig root.
		rotation.y -= motion.relative.x * MOUSE_SENSITIVITY
		_arm.rotation.x = clampf(
				_arm.rotation.x - motion.relative.y * MOUSE_SENSITIVITY,
				PITCH_MIN, PITCH_MAX)
		return

	var button := event as InputEventMouseButton
	if button != null and button.pressed:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_arm.spring_length = clampf(
					_arm.spring_length - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_arm.spring_length = clampf(
					_arm.spring_length + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
