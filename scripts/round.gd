extends Node

## One round of the game: once every green bear is knocked down, the player
## has won. The camera tilts up to the sky, fireworks go up in front of it,
## and after a moment a big restart button appears (icons only: the player
## can't read yet). Restarting reloads the stage, so every bear stands back
## where it started.

## Lets the last flop land before the show starts.
const CELEBRATE_DELAY := 0.8
## Seconds after the win before the restart button appears; the fireworks
## keep going behind it.
const RESTART_DELAY := 4.0
## The fireworks go up this far ahead of the camera (m).
const SHOW_DISTANCE := 9.0

const FIREWORKS := preload("res://scripts/fireworks.gd")
const RESTART_BUTTON := preload("res://scripts/restart_button.gd")

var _won := false
## (The timers below pass process_always = false so the pause menu holds
## the show.)
var _fireworks: FIREWORKS
var _restart: RESTART_BUTTON


func _ready() -> void:
	_fireworks = FIREWORKS.new()
	add_child(_fireworks)
	_restart = RESTART_BUTTON.new()
	add_child(_restart)
	_restart.pressed.connect(_on_restart)


func is_won() -> bool:
	return _won


func rockets_launched() -> int:
	return _fireworks.rockets_launched


## The restart button is up and focused, so A (or Enter/Space) presses it.
func restart_ready() -> bool:
	return _restart.is_ready()


func _physics_process(_delta: float) -> void:
	if _won:
		return
	var greens := get_tree().get_nodes_in_group("green_bears")
	if greens.is_empty():
		return
	for green: Node in greens:
		if not green.call("is_down"):
			return
	_win()


func _win() -> void:
	_won = true
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null:
		player.call("celebrate")
	await get_tree().create_timer(CELEBRATE_DELAY, false).timeout
	var camera := get_viewport().get_camera_3d()
	var forward := -camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if not forward.is_zero_approx() else Vector3.FORWARD
	var origin := player.global_position if player != null else Vector3.ZERO
	var centre := origin + forward * SHOW_DISTANCE
	centre.y = 0.0
	_fireworks.start(centre, forward)
	await get_tree().create_timer(RESTART_DELAY - CELEBRATE_DELAY, false).timeout
	_restart.appear()


func _on_restart() -> void:
	get_tree().reload_current_scene()
