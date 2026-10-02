extends Node3D

## Puts the green bears on the stage: as many as the pause menu's saved
## "green_bears" setting (DEFAULT_COUNT until it's set), at spots inside the
## candy fence, at least CLEAR_OF_START from the player's start (so none
## stand between the camera and the player as a round begins), SPACING
## apart, and clear of any "keep_clear" node's spots (the Jenga towers).
## The spots come from a fixed seed, so a given count always gives the same
## layout (and a bigger count only adds bears); bear i wanders with seed
## i + 1.

const GREEN_BEAR := preload("res://scenes/green_bear.tscn")
const SETTINGS := preload("res://scripts/settings.gd")

const SETTING := "green_bears"
const DEFAULT_COUNT := 15
const MIN_COUNT := 1
const MAX_COUNT := 40
## Spots stay inside this half-extent (the fence stands at 9.6 m).
const HALF_EXTENT := 8.3
const CLEAR_OF_START := 5.0
const SPACING := 1.2
const LAYOUT_SEED := 2026
## Gives up placing after this many tries (far more than 40 bears need).
const MAX_TRIES := 20000


func _ready() -> void:
	spawn(saved_count())


## The saved green bear count, clamped to MIN_COUNT..MAX_COUNT.
static func saved_count() -> int:
	return clampi(SETTINGS.load_value(SETTING, DEFAULT_COUNT), MIN_COUNT, MAX_COUNT)


## Replaces the green bears on the stage with `count` fresh ones.
func spawn(count: int) -> void:
	for bear in get_children():
		# Out of the tree (and the green_bears group) at once.
		remove_child(bear)
		bear.queue_free()
	var spots := _spots(clampi(count, MIN_COUNT, MAX_COUNT), _keep_clear())
	for i in spots.size():
		var bear := GREEN_BEAR.instantiate()
		bear.name = "GreenBear%d" % (i + 1)
		bear.set("wander_seed", i + 1)
		bear.position = spots[i]
		add_child(bear)


## [spot, radius] pairs from the "keep_clear" group.
func _keep_clear() -> Array:
	var zones := []
	for node in get_tree().get_nodes_in_group("keep_clear"):
		for spot: Vector3 in node.call("keep_clear_spots"):
			zones.append([spot, node.call("keep_clear_radius")])
	return zones


static func _spots(count: int, keep_clear: Array) -> Array[Vector3]:
	var rng := RandomNumberGenerator.new()
	rng.seed = LAYOUT_SEED
	var spots: Array[Vector3] = []
	for attempt in MAX_TRIES:
		if spots.size() == count:
			break
		var spot := Vector3(
				snappedf(rng.randf_range(-HALF_EXTENT, HALF_EXTENT), 0.1), 0.0,
				snappedf(rng.randf_range(-HALF_EXTENT, HALF_EXTENT), 0.1))
		if Vector2(spot.x, spot.z).length() < CLEAR_OF_START:
			continue
		if spots.any(func(other: Vector3) -> bool: return other.distance_to(spot) < SPACING):
			continue
		if keep_clear.any(func(zone: Array) -> bool:
				return (zone[0] as Vector3).distance_to(spot) < zone[1]):
			continue
		spots.append(spot)
	return spots
