extends "res://scripts/gummy_bear.gd"

## A green bear: the red player's target. It wanders slowly inside the candy
## fence, pausing now and then, and flees when the player comes close. It
## faces where it is heading (no strafe mode). A ball knocks it into a
## ragdoll (see gummy_bear.gd) and it stays down. Green bears stay green.

const WANDER_SPEED := 0.5
const FLEE_SPEED := 1.5
## The player is "close" inside this horizontal radius (m).
const FLEE_RADIUS := 4.0
## Wander targets stay inside this half-extent (the fence stands at 9.6 m).
const ROAM_HALF_EXTENT := 8.5
## A fleeing bear veers back inward within this distance of ROAM_HALF_EXTENT,
## so it slides along the fence instead of pinning itself against it.
const EDGE_MARGIN := 2.0
## Each wander leg goes 1..WANDER_REACH m, then pauses PAUSE_MIN..PAUSE_MAX s;
## a leg that hasn't arrived after WANDER_TIMEOUT s (blocked) is abandoned.
const WANDER_REACH := 4.0
const ARRIVE_RADIUS := 0.3
const PAUSE_MIN := 1.0
const PAUSE_MAX := 3.0
const WANDER_TIMEOUT := 8.0

## Seeds this bear's wandering, so harness runs repeat.
@export var wander_seed := 0

var _rng := RandomNumberGenerator.new()
var _wander_target := Vector3.ZERO
var _pause_left := 0.0
var _leg_left := 0.0


func _ready() -> void:
	super()
	add_to_group("green_bears")
	build_ragdoll()
	_rng.seed = wander_seed
	_pause_left = _rng.randf_range(0.0, PAUSE_MAX)
	_pick_wander_target()


func _steer(delta: float) -> Vector3:
	var wish := _flee()
	if wish == Vector3.ZERO:
		wish = _wander(delta)
	if wish != Vector3.ZERO:
		turn_toward(yaw_of(wish), YAW_LERP, delta)
	return wish


func _flee() -> Vector3:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return Vector3.ZERO
	var away := global_position - player.global_position
	away.y = 0.0
	if away.length() > FLEE_RADIUS:
		return Vector3.ZERO
	var direction := away.normalized() if not away.is_zero_approx() else global_basis.z
	var edge := ROAM_HALF_EXTENT - EDGE_MARGIN
	direction.x -= signf(global_position.x) * maxf(0.0, absf(global_position.x) - edge) / EDGE_MARGIN
	direction.z -= signf(global_position.z) * maxf(0.0, absf(global_position.z) - edge) / EDGE_MARGIN
	if direction.is_zero_approx():
		return Vector3.ZERO
	return direction.normalized() * FLEE_SPEED


func _wander(delta: float) -> Vector3:
	if _pause_left > 0.0:
		_pause_left -= delta
		return Vector3.ZERO
	_leg_left -= delta
	var to_target := _wander_target - global_position
	to_target.y = 0.0
	if to_target.length() < ARRIVE_RADIUS or _leg_left <= 0.0:
		_pause_left = _rng.randf_range(PAUSE_MIN, PAUSE_MAX)
		_pick_wander_target()
		return Vector3.ZERO
	return to_target.normalized() * WANDER_SPEED


func _pick_wander_target() -> void:
	var heading := _rng.randf_range(-PI, PI)
	var reach := _rng.randf_range(1.0, WANDER_REACH)
	var target := global_position + Vector3(sin(heading), 0.0, cos(heading)) * reach
	target.x = clampf(target.x, -ROAM_HALF_EXTENT, ROAM_HALF_EXTENT)
	target.z = clampf(target.z, -ROAM_HALF_EXTENT, ROAM_HALF_EXTENT)
	_wander_target = target
	_leg_left = WANDER_TIMEOUT
