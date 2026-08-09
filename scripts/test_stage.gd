extends Node3D

## Dev harness for the gummy-bear PoC.
##
## Interactive by default (WASD to slide, C to cycle colour).
## Launch with `-- --shots` to run the scripted autodrive, dump three PNGs into
## res://.dev/ and quit — that is the automated PoC check.

const SHOT_DIR := "res://.dev"
## seconds -> output file
const SHOT_SCHEDULE := {1.5: "shot_1.png", 2.1: "shot_2.png", 4.0: "shot_3.png"}
const DRIVE_START := 2.0
const DRIVE_END := 2.4
const DRIVE_VELOCITY := Vector3(2.5, 0.0, 0.0)
const QUIT_AT := 5.0

@onready var _bear: CharacterBody3D = $GummyBear

var _harness := false
var _elapsed := 0.0
var _pending: Array = []


func _ready() -> void:
	_harness = OS.get_cmdline_user_args().has("--shots")
	if not _harness:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	_pending = SHOT_SCHEDULE.keys()
	_pending.sort()


func _physics_process(_delta: float) -> void:
	if not _harness:
		return
	# Runs before the bear's own _physics_process (parents tick first), so this
	# reads as a hard acceleration spike to its wobble spring.
	if _elapsed >= DRIVE_START and _elapsed < DRIVE_END:
		_bear.velocity = DRIVE_VELOCITY


func _process(delta: float) -> void:
	if not _harness:
		return
	_elapsed += delta
	while not _pending.is_empty() and _elapsed >= _pending[0]:
		var due: float = _pending.pop_front()
		_capture(SHOT_SCHEDULE[due])
	if _elapsed >= QUIT_AT:
		get_tree().quit()


func _capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s" % [SHOT_DIR, filename]
	var err := image.save_png(path)
	print("[test_stage] t=%.2f -> %s (err %d)" % [_elapsed, path, err])
