extends Node3D

## Dev harness for the gummy-bear PoC.
##
## Interactive by default (WASD or left stick to walk, Space or A to jump,
## left click or right trigger to throw). Launch with `-- --shots` to exercise
## jump, walk, stick look and a throw through real input actions, capture
## evidence into res://.dev/, validate the contracts, and quit.

const SHOT_DIR := "res://.dev"
## seconds -> output file
const SHOT_SCHEDULE := {
	0.65: "jump_takeoff.png",
	0.78: "jump_apex.png",
	1.15: "jump_landed.png",
	2.20: "walk.png",
	2.70: "side.png",
	3.30: "throw.png",
	4.00: "knock.png",
	4.45: "seethrough.png",
	6.60: "fireworks.png",
	9.40: "restart.png",
	9.57: "menu.png",
}
## seconds -> silhouette window sampled after the frame is drawn
const SILHOUETTE_SCHEDULE := {
	0.10: "idle",
	0.20: "idle",
	0.30: "idle",
	0.40: "idle",
	2.05: "walk",
	2.15: "walk",
	2.25: "walk",
	2.35: "walk",
}
## Vector2(width ratio, height ratio).
const SILHOUETTE_LIMITS := {
	"idle": Vector2(1.05, 1.08),
	"walk": Vector2(1.15, 1.08),
}
const SILHOUETTE_IMAGE_SIZE := Vector2i(288, 162)
## The silhouette detector keys on the player's cherry colour (the `colour`
## default in gummy_bear.gd); if the player's colour changes, these
## thresholds stop finding the bear. Nothing else on the stage may be red or
## pink (the green bears, ball, marker and fence aren't).
const BEAR_RED_MIN := 0.2
const BEAR_RED_OVER_GREEN := 1.55
const BEAR_RED_OVER_BLUE := 1.2
const MAX_AIRBORNE_REPRESS_GAIN := 0.1
const MIN_JUMP_RISE := 0.35
const MIN_AIR_DISTANCE := 0.01
const JUMP_AT := 0.50
const SECOND_JUMP_AT := 0.70
const AIR_DRIVE_START := 0.55
const AIR_DRIVE_END := 0.75
const DRIVE_START := 1.6
const DRIVE_END := 2.4
const QUIT_AT := 10.0
## After all world-axis checks, orbit the idle bear's camera a quarter turn:
## the body must stay put (no turn-in-place clip exists), and side.png shows
## the bear side-on for the shader's self-overlap check.
const ORBIT_AT := 2.5
const YAW_CHECK_AT := 2.9
const MAX_IDLE_YAW := 0.05
## A full move_right press must bring the bear near its 2.5 m/s top speed
## before release (gummy lag makes it approach asymptotically).
const MIN_DRIVE_SPEED := 2.2
## Hold the right stick up-right briefly: both axes must follow the mouse
## convention (right orbits right, yaw falls; up looks up, arm pitch rises).
const LOOK_AT := 2.92
const LOOK_END := 3.0
## Then a throw: one green bear is teleported THROW_TARGET_DISTANCE ahead
## along the camera and the idle player presses `throw`. The bear must be
## knocked down within KNOCK_DEADLINE, its ragdoll must stay on the 20×20 m
## stage, the ball must not shove the player, and the idle player must have
## turned to face the throw (ADR 0001, 2026-09-28 amendment).
const THROW_SETUP_AT := 3.05
const THROW_AT := 3.15
const THROW_TARGET_DISTANCE := 3.0
const KNOCK_DEADLINE := 1.2
const TURN_CHECK_AT := 3.65
const MAX_THROW_TURN_ERROR := 0.25
const MAX_PLAYER_DRIFT := 0.05
const STAGE_HALF_EXTENT := 10.0
const STAGE_MIN_Y := -0.3
## Then see-through: a standing green bear is put SEETHROUGH_DISTANCE behind
## the player along the camera. The translucent red bear must not hide it:
## the green bear's colour pass has to draw before the red bear's depth-only
## pass, whose depth would otherwise mask everything behind it.
const SEETHROUGH_AT := 4.3
const SEETHROUGH_CHECK_AT := 4.45
const SEETHROUGH_DISTANCE := 1.2
## Then the win: the harness knocks the remaining green bears down itself.
## The round must be won at once, fireworks must go up, and the restart
## button must be showing, focused (so A presses it) and clickable (mouse
## free) by the end.
const WIN_AT := 4.6
const MAX_WIN_DELAY := 0.2
## Last, the pause menu, through real pad buttons, one step every MENU_STEP
## s: Start opens it (pausing the game, freeing the mouse, focusing the
## first toggle); for each toggle in turn, A flips it on (checked on the
## node and in the saved settings), A flips it back, and D-pad down moves to
## the next; B closes it (unpausing, putting the mouse back as it was).
## The player's saved settings file is backed up first and restored after.
const MENU_START := 9.45
const MENU_STEP := 0.05
## [node path under the player, property]; the settings key is the property.
const MENU_TOGGLES := [
	["CameraRig", "invert_stick_y"],
]
const SETTINGS_PATH := "user://settings.cfg"
const JOY_A := 0
const JOY_B := 1
const JOY_START := 6
const JOY_DPAD_DOWN := 12

@onready var _bear: CharacterBody3D = $Player

var _harness := false
var _elapsed := 0.0
var _pending: Array = []
var _silhouette_pending: Array = []
var _silhouette_sizes := {}
var _jump_pressed := false
var _jump_released := false
var _second_jump_pressed := false
var _second_jump_released := false
var _air_drive_pressed := false
var _air_drive_released := false
var _drive_pressed := false
var _drive_released := false
var _airborne_seen := false
var _landed := false
var _second_boost := false
var _check_second_velocity := false
var _second_velocity_before := 0.0
var _start_y := 0.0
var _start_y_captured := false
var _apex_y := 0.0
var _air_drive_start_x := 0.0
var _air_drive_end_x := 0.0
var _orbited := false
var _idle_yaw := 0.0
var _idle_yaw_checked := false
var _drive_speed := 0.0
var _look_pressed := false
var _look_released := false
var _look_start := Vector2.ZERO
var _look_delta := Vector2.ZERO
var _throw_setup_done := false
var _target: CharacterBody3D
var _throw_pressed := false
var _throw_released := false
var _throw_yaw := 0.0
var _player_start := Vector3.ZERO
var _knocked_after := -1.0
var _turn_error := -1.0
var _behind: Node3D
var _seethrough_order := ""
var _menu_step := 0
var _menu_failures: Array[String] = []
var _menu_before: Array = []
var _settings_backup: PackedByteArray
var _settings_existed := false
var _win_forced := false
var _won_after := -1.0


func _ready() -> void:
	_harness = OS.get_cmdline_user_args().has("--shots")
	if not _harness:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	_pending = SHOT_SCHEDULE.keys()
	_pending.sort()
	_silhouette_pending = SILHOUETTE_SCHEDULE.keys()
	_silhouette_pending.sort()
	for window: String in SILHOUETTE_LIMITS:
		_silhouette_sizes[window] = []
	_settings_existed = FileAccess.file_exists(SETTINGS_PATH)
	if _settings_existed:
		_settings_backup = FileAccess.get_file_as_bytes(SETTINGS_PATH)
	# The pause menu pauses the tree; the harness has to keep ticking to
	# close it, but the stage's children must still pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for child in get_children():
		if child.process_mode == Node.PROCESS_MODE_INHERIT:
			child.process_mode = Node.PROCESS_MODE_PAUSABLE


## The evidence run drives everything through actions; a real mouse
## moving over the window (the cursor is captured) would orbit the camera
## and wreck the silhouette and look checks, so it's swallowed here, before
## the orbit rig's _unhandled_input sees it.
func _input(event: InputEvent) -> void:
	if _harness and event is InputEventMouse:
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if not _harness:
		return
	_elapsed += delta
	if not _start_y_captured and _bear.is_on_floor():
		_start_y = _bear.global_position.y
		_apex_y = _start_y
		_start_y_captured = true
	if not _jump_pressed and _elapsed >= JUMP_AT:
		Input.action_press("jump")
		_jump_pressed = true
	elif _jump_pressed and not _jump_released:
		Input.action_release("jump")
		_jump_released = true

	if not _second_jump_pressed and _elapsed >= SECOND_JUMP_AT:
		_second_velocity_before = _bear.velocity.y
		Input.action_press("jump")
		_second_jump_pressed = true
		_check_second_velocity = true
	elif _second_jump_pressed and not _second_jump_released:
		Input.action_release("jump")
		_second_jump_released = true
	if not _air_drive_pressed and _elapsed >= AIR_DRIVE_START:
		_air_drive_start_x = _bear.global_position.x
		Input.action_press("move_right")
		_air_drive_pressed = true
	elif (_air_drive_pressed and not _air_drive_released
			and _elapsed >= AIR_DRIVE_END):
		_air_drive_end_x = _bear.global_position.x
		Input.action_release("move_right")
		_air_drive_released = true


	if not _drive_pressed and _elapsed >= DRIVE_START:
		Input.action_press("move_right")
		_drive_pressed = true
	elif _drive_pressed and not _drive_released and _elapsed >= DRIVE_END:
		_drive_speed = Vector2(_bear.velocity.x, _bear.velocity.z).length()
		Input.action_release("move_right")
		_drive_released = true

	if not _orbited and _elapsed >= ORBIT_AT:
		_bear.get_node("CameraRig").rotation.y = PI / 2.0
		_orbited = true
	if _orbited and not _idle_yaw_checked and _elapsed >= YAW_CHECK_AT:
		_idle_yaw = absf(angle_difference(0.0, _bear.rotation.y))
		_idle_yaw_checked = true
	if not _look_pressed and _elapsed >= LOOK_AT:
		_look_start = _look_angles()
		Input.action_press("look_right")
		Input.action_press("look_up")
		_look_pressed = true
	elif _look_pressed and not _look_released and _elapsed >= LOOK_END:
		_look_delta = _look_angles() - _look_start
		Input.action_release("look_right")
		Input.action_release("look_up")
		_look_released = true

	if not _throw_setup_done and _elapsed >= THROW_SETUP_AT:
		_setup_throw_target()
	if _target != null and not _throw_pressed and _elapsed >= THROW_AT:
		var to_target := _target.global_position - _bear.global_position
		_throw_yaw = atan2(-to_target.x, -to_target.z)
		Input.action_press("throw")
		_throw_pressed = true
	elif _throw_pressed and not _throw_released:
		Input.action_release("throw")
		_throw_released = true
	if (_throw_pressed and _knocked_after < 0.0
			and _target.call("is_down")):
		_knocked_after = _elapsed - THROW_AT
	if _throw_pressed and _turn_error < 0.0 and _elapsed >= TURN_CHECK_AT:
		_turn_error = absf(angle_difference(_throw_yaw, _bear.rotation.y))

	if _behind == null and _elapsed >= SEETHROUGH_AT:
		_place_behind_player()
	if (_behind != null and _seethrough_order.is_empty()
			and _elapsed >= SEETHROUGH_CHECK_AT):
		_seethrough_order = _draw_order_check()

	if (_menu_step <= _menu_last_step()
			and _elapsed >= MENU_START + _menu_step * MENU_STEP):
		_run_menu_step(_menu_step)
		_menu_step += 1

	if not _win_forced and _elapsed >= WIN_AT:
		for green: Node in get_tree().get_nodes_in_group("green_bears"):
			green.call("knock", Vector3(0.0, 0.0, -1.0))
		_win_forced = true
	if (_win_forced and _won_after < 0.0 and $Round.has_method("is_won")
			and $Round.call("is_won")):
		_won_after = _elapsed - WIN_AT


func _process(_delta: float) -> void:
	if not _harness:
		return
	if _start_y_captured:
		_apex_y = maxf(_apex_y, _bear.global_position.y)
	if not _bear.is_on_floor() and _bear.velocity.y > 0.0:
		_airborne_seen = true
	if _airborne_seen and _bear.is_on_floor():
		_landed = true
	if _check_second_velocity:
		var after := _bear.velocity.y
		_second_boost = after > _second_velocity_before + MAX_AIRBORNE_REPRESS_GAIN
		print("[test_stage] airborne re-press vy %.3f -> %.3f" %
				[_second_velocity_before, after])
		_check_second_velocity = false

	while not _pending.is_empty() and _elapsed >= _pending[0]:
		var due: float = _pending.pop_front()
		_capture(SHOT_SCHEDULE[due])
	while (not _silhouette_pending.is_empty()
			and _elapsed >= _silhouette_pending[0]):
		var sample_due: float = _silhouette_pending.pop_front()
		_sample_silhouette(SILHOUETTE_SCHEDULE[sample_due])
	if _elapsed >= QUIT_AT:
		_finish()


## Puts the first green bear THROW_TARGET_DISTANCE ahead of the idle player,
## along the camera's horizontal forward.
func _setup_throw_target() -> void:
	_throw_setup_done = true
	var greens := get_tree().get_nodes_in_group("green_bears")
	if greens.is_empty():
		return
	_target = greens[0]
	var yaw: float = _look_angles().x
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	_player_start = _bear.global_position
	_target.global_position = (_bear.global_position
			+ forward * THROW_TARGET_DISTANCE)
	_target.velocity = Vector3.ZERO
	_target.reset_physics_interpolation()


## Puts the second green bear right behind the player, from the camera.
func _place_behind_player() -> void:
	var greens := get_tree().get_nodes_in_group("green_bears")
	if greens.size() < 2:
		_behind = self  # nothing to place; the check below reports it
		return
	_behind = greens[1]
	var yaw: float = _look_angles().x
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	_behind.global_position = _bear.global_position + forward * SEETHROUGH_DISTANCE
	(_behind as CharacterBody3D).velocity = Vector3.ZERO
	_behind.reset_physics_interpolation()


## "ok", or why the red bear's passes would hide the green bear behind it.
func _draw_order_check() -> String:
	if not _behind.has_method("is_down"):
		return "no second green bear to put behind the player"
	var red := _gummy_passes(_bear)
	var green := _gummy_passes(_behind)
	if red.is_empty() or green.is_empty():
		return "a bear has no two-pass gummy material"
	if green[1] >= red[0]:
		return ("green colour pass (priority %d) doesn't draw before the red depth pass (%d)"
				% [green[1], red[0]])
	return "ok"


## [depth pass priority, colour pass priority] of a bear's gummy material.
func _gummy_passes(bear: Node) -> Array[int]:
	var meshes := bear.get_node("Model").find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		return []
	var depth := (meshes[0] as MeshInstance3D).material_override
	if depth == null or depth.next_pass == null:
		return []
	return [depth.render_priority, depth.next_pass.render_priority]


func _press_pad(button: int) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = 0
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
	# Deliver now: buffered, they'd land at the next frame's flush, which can
	# come after the next menu step when frames run slower than ticks.
	Input.flush_buffered_events()


## Open, first A, then two steps per toggle, then the closed check.
func _menu_last_step() -> int:
	return 2 * MENU_TOGGLES.size() + 2


func _toggle_value(index: int) -> bool:
	var toggle: Array = MENU_TOGGLES[index]
	return _bear.get_node(toggle[0]).get(toggle[1])


func _saved_value(index: int) -> Variant:
	var saved := ConfigFile.new()
	saved.load(SETTINGS_PATH)
	return saved.get_value("controls", MENU_TOGGLES[index][1], "missing")


func _run_menu_step(step: int) -> void:
	var menu := get_node_or_null("PauseMenu")
	if menu == null or not menu.has_method("is_open"):
		if step == 0:
			_menu_failures.append("no PauseMenu with is_open()")
		return
	var toggles := MENU_TOGGLES.size()
	if step == 0:
		_menu_before.clear()
		for i in toggles:
			_menu_before.append(_toggle_value(i))
		_press_pad(JOY_START)
	elif step == 1:
		if not menu.call("is_open"):
			_menu_failures.append("Start didn't open the menu")
		if not get_tree().paused:
			_menu_failures.append("the open menu didn't pause the game")
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_menu_failures.append("the open menu left the mouse captured")
		_press_pad(JOY_A)
	elif step < _menu_last_step():
		var index := (step - 2) / 2
		var name: String = MENU_TOGGLES[index][1]
		if (step - 2) % 2 == 0:
			if _toggle_value(index) == _menu_before[index]:
				_menu_failures.append("A didn't flip %s" % name)
			if _saved_value(index) != (not _menu_before[index]):
				_menu_failures.append("the flipped %s wasn't saved" % name)
			_press_pad(JOY_A)
		else:
			if _toggle_value(index) != _menu_before[index]:
				_menu_failures.append("a second A didn't flip %s back" % name)
			if index + 1 < toggles:
				_press_pad(JOY_DPAD_DOWN)
				_press_pad(JOY_A)
			else:
				_press_pad(JOY_B)
	else:
		if menu.call("is_open"):
			_menu_failures.append("B didn't close the menu")
		if get_tree().paused:
			_menu_failures.append("closing the menu didn't unpause the game")


## Puts the player's settings file back as it was before the run.
func _restore_settings() -> void:
	if _settings_existed:
		var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
		file.store_buffer(_settings_backup)
	elif FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))


## (rig yaw, arm pitch) in radians.
func _look_angles() -> Vector2:
	var rig: Node3D = _bear.get_node("CameraRig")
	var arm: Node3D = rig.get_node("SpringArm3D")
	return Vector2(rig.rotation.y, arm.rotation.x)


func _capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s" % [SHOT_DIR, filename]
	var err := image.save_png(path)
	print("[test_stage] t=%.2f -> %s (err %d)" % [_elapsed, path, err])


func _sample_silhouette(window: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.resize(SILHOUETTE_IMAGE_SIZE.x, SILHOUETTE_IMAGE_SIZE.y,
			Image.INTERPOLATE_NEAREST)
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			if (pixel.r > BEAR_RED_MIN
					and pixel.r > pixel.g * BEAR_RED_OVER_GREEN
					and pixel.r > pixel.b * BEAR_RED_OVER_BLUE):
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < 0:
		_silhouette_sizes[window].append(Vector2i.ZERO)
	else:
		_silhouette_sizes[window].append(
				Vector2i(max_x - min_x + 1, max_y - min_y + 1))


func _validate_silhouette(window: String, failures: Array[String]) -> void:
	var sizes: Array = _silhouette_sizes[window]
	var expected := SILHOUETTE_SCHEDULE.values().count(window)
	if sizes.size() != expected or sizes.has(Vector2i.ZERO):
		failures.append("%s silhouette captured %d/%d valid samples" %
				[window, sizes.size(), expected])
		return
	var min_width: int = sizes[0].x
	var max_width: int = sizes[0].x
	var min_height: int = sizes[0].y
	var max_height: int = sizes[0].y
	for size: Vector2i in sizes:
		min_width = mini(min_width, size.x)
		max_width = maxi(max_width, size.x)
		min_height = mini(min_height, size.y)
		max_height = maxi(max_height, size.y)
	var width_ratio := float(max_width) / min_width
	var height_ratio := float(max_height) / min_height
	print("[test_stage] %s silhouette width=%d-%d (%.3f) height=%d-%d (%.3f)" %
			[window, min_width, max_width, width_ratio,
			min_height, max_height, height_ratio])
	var limits: Vector2 = SILHOUETTE_LIMITS[window]
	if width_ratio > limits.x:
		failures.append("%s silhouette width ratio %.3f exceeds %.3f" %
				[window, width_ratio, limits.x])
	if height_ratio > limits.y:
		failures.append("%s silhouette height ratio %.3f exceeds %.3f" %
				[window, height_ratio, limits.y])


func _validate_throw(failures: Array[String]) -> void:
	if _target == null or not _target.has_method("is_down"):
		failures.append("no green bear to throw at")
		return
	if not _throw_pressed:
		failures.append("throw was never pressed")
		return
	if _knocked_after < 0.0:
		failures.append("green bear was never knocked down")
	elif _knocked_after > KNOCK_DEADLINE:
		failures.append("green bear went down after %.2f s (want <= %.2f s)" %
				[_knocked_after, KNOCK_DEADLINE])
	var off_stage := 0
	var bones: Array = _target.call("ragdoll_bones")
	for bone: Node3D in bones:
		var p := bone.global_position
		if (absf(p.x) > STAGE_HALF_EXTENT or absf(p.z) > STAGE_HALF_EXTENT
				or p.y < STAGE_MIN_Y):
			off_stage += 1
	if bones.is_empty():
		failures.append("green bear has no ragdoll bones")
	elif off_stage > 0:
		failures.append("%d ragdoll bones left the stage" % off_stage)
	var drift := _bear.global_position - _player_start
	drift.y = 0.0
	if drift.length() > MAX_PLAYER_DRIFT:
		failures.append("player drifted %.3f m during the throw" % drift.length())
	if _turn_error < 0.0:
		failures.append("throw turn was never checked")
	elif _turn_error > MAX_THROW_TURN_ERROR:
		failures.append("idle player is %.3f rad off the throw direction" % _turn_error)
	print("[test_stage] knocked_after=%.2f turn_error=%.3f drift=%.3f ragdoll_off_stage=%d" %
			[_knocked_after, _turn_error, drift.length(), off_stage])


func _validate_win(failures: Array[String]) -> void:
	# A failed call doesn't stop GDScript, it just yields null, so a broken
	# Round script must fail here rather than pass by accident.
	for method in ["is_won", "rockets_launched", "restart_ready"]:
		if not $Round.has_method(method):
			failures.append("Round has no %s() (did round.gd fail to load?)" % method)
			return
	var rockets: int = $Round.call("rockets_launched")
	var restart_ready: bool = $Round.call("restart_ready")
	if _won_after < 0.0:
		failures.append("round was never won with every green bear down")
	elif _won_after > MAX_WIN_DELAY:
		failures.append("round was won %.2f s after the last knock" % _won_after)
	if rockets == 0:
		failures.append("no fireworks went up")
	if not restart_ready:
		failures.append("restart button is not showing and focused")
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		failures.append("mouse is still captured, so the restart button can't be clicked")
	print("[test_stage] won_after=%.2f rockets=%d restart_ready=%s greens=%d fps=%d" %
			[_won_after, rockets, restart_ready,
			get_tree().get_nodes_in_group("green_bears").size(),
			Engine.get_frames_per_second()])


func _finish() -> void:
	Input.action_release("jump")
	Input.action_release("move_right")
	Input.action_release("look_right")
	Input.action_release("look_up")
	Input.action_release("throw")
	var look_delta := _look_delta
	var rise := _apex_y - _start_y
	var failures: Array[String] = []
	if not _start_y_captured:
		failures.append("ground height was never captured")
	if not _airborne_seen:
		failures.append("jump never became airborne")
	if rise < MIN_JUMP_RISE:
		failures.append("apex rise %.3f m is below %.2f m" % [rise, MIN_JUMP_RISE])
	if not _landed:
		failures.append("bear did not land")
	if _second_boost:
		failures.append("airborne Space press increased vertical velocity")
	var air_distance := absf(_air_drive_end_x - _air_drive_start_x)
	if air_distance < MIN_AIR_DISTANCE:
		failures.append("airborne move_right travelled only %.3f m" % air_distance)
	if not _idle_yaw_checked:
		failures.append("idle yaw was never checked")
	elif _idle_yaw > MAX_IDLE_YAW:
		failures.append("idle bear turned %.3f rad toward the camera" % _idle_yaw)
	if _drive_speed < MIN_DRIVE_SPEED:
		failures.append("drive reached only %.3f m/s" % _drive_speed)
	if not _look_released:
		failures.append("stick look was never pressed")
	else:
		if look_delta.x >= 0.0:
			failures.append("look_right changed yaw by %+.3f rad (want < 0)" % look_delta.x)
		if look_delta.y <= 0.0:
			failures.append("look_up changed pitch by %+.3f rad (want > 0)" % look_delta.y)
	_validate_throw(failures)
	if _seethrough_order.is_empty():
		failures.append("see-through draw order was never checked")
	elif _seethrough_order != "ok":
		failures.append(_seethrough_order)
	_validate_win(failures)
	if _menu_step <= _menu_last_step():
		failures.append("pause menu steps never finished")
	failures.append_array(_menu_failures)
	_restore_settings()
	for window: String in SILHOUETTE_LIMITS:
		_validate_silhouette(window, failures)
	print("[test_stage] jump rise=%.3f air_dx=%.3f airborne=%s landed=%s double_boost=%s idle_yaw=%.3f" %
			[rise, air_distance, _airborne_seen, _landed, _second_boost, _idle_yaw])
	print("[test_stage] drive_speed=%.3f look_dyaw=%+.3f look_dpitch=%+.3f" %
			[_drive_speed, look_delta.x, look_delta.y])
	if not failures.is_empty():
		for failure in failures:
			push_error("[test_stage] " + failure)
		get_tree().quit(1)
	else:
		get_tree().quit()
