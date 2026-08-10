extends Node3D

## Dev harness for the gummy-bear PoC.
##
## Interactive by default (WASD to walk, Space to jump, C to cycle colour).
## Launch with `-- --shots` to exercise jump and walk through real input actions,
## capture evidence into res://.dev/, validate the jump contract, and quit.

const SHOT_DIR := "res://.dev"
## seconds -> output file
const SHOT_SCHEDULE := {
	0.65: "jump_takeoff.png",
	0.78: "jump_apex.png",
	1.15: "jump_landed.png",
	2.20: "walk.png",
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
const QUIT_AT := 3.0

@onready var _bear: CharacterBody3D = $GummyBear

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
		Input.action_release("move_right")
		_drive_released = true


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


func _finish() -> void:
	Input.action_release("jump")
	Input.action_release("move_right")
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
	for window: String in SILHOUETTE_LIMITS:
		_validate_silhouette(window, failures)
	print("[test_stage] jump rise=%.3f air_dx=%.3f airborne=%s landed=%s double_boost=%s" %
			[rise, air_distance, _airborne_seen, _landed, _second_boost])
	if not failures.is_empty():
		for failure in failures:
			push_error("[test_stage] " + failure)
		get_tree().quit(1)
	else:
		get_tree().quit()
