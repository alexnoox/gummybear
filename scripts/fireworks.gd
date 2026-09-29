extends Node3D

## A fireworks show: rockets rise from the ground with a sparkly trail and
## burst into a ball of coloured sparks with a flash of light, one every
## INTERVAL, scattered round a centre point, until the scene ends.

const INTERVAL := 0.4
## Rockets launch SIDE_MIN..SIDE_MAX m to the left or right of the centre
## (straight ahead, the bear would hide them), within DEPTH m nearer or
## farther, and burst this high.
const SIDE_MIN := 2.0
const SIDE_MAX := 6.0
const DEPTH := 2.0
const BURST_HEIGHT_MIN := 3.0
const BURST_HEIGHT_MAX := 5.5
const RISE_TIME := 0.9
const SPARKS := 90
const SPARK_LIFETIME := 1.6
const SPARK_SPEED_MIN := 4.0
const SPARK_SPEED_MAX := 5.5
const FLASH_ENERGY := 4.0
const FLASH_RANGE := 14.0
const FLASH_TIME := 0.5
const COLOURS := [
	Color(1.0, 0.85, 0.2),
	Color(0.3, 0.9, 1.0),
	Color(1.0, 0.3, 0.8),
	Color(0.5, 1.0, 0.3),
	Color(1.0, 0.55, 0.15),
	Color(0.65, 0.45, 1.0),
	Color(1.0, 0.25, 0.25),
]

var rockets_launched := 0

var _centre := Vector3.ZERO
var _right := Vector3.RIGHT
var _forward := Vector3.FORWARD
var _running := false
var _next_in := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# Everything here is moved per rendered frame by tweens, not by physics.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## Starts the show round `centre` (on the ground), facing along `forward`.
func start(centre: Vector3, forward: Vector3) -> void:
	_centre = centre
	_forward = forward
	_right = forward.cross(Vector3.UP).normalized()
	_running = true
	_next_in = 0.0


func _process(delta: float) -> void:
	if not _running:
		return
	_next_in -= delta
	if _next_in <= 0.0:
		_next_in = INTERVAL
		_launch()


func _launch() -> void:
	rockets_launched += 1
	var colour: Color = COLOURS[_rng.randi() % COLOURS.size()]
	var side := _rng.randf_range(SIDE_MIN, SIDE_MAX) * (1.0 if _rng.randf() < 0.5 else -1.0)
	var base := (_centre + _right * side
			+ _forward * _rng.randf_range(-DEPTH, DEPTH))
	var top := base + Vector3.UP * _rng.randf_range(BURST_HEIGHT_MIN, BURST_HEIGHT_MAX)

	var rocket := Node3D.new()
	rocket.position = base
	var head := MeshInstance3D.new()
	head.mesh = _spark_mesh(0.08, Color(1.0, 0.95, 0.8))
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rocket.add_child(head)
	var trail := CPUParticles3D.new()
	trail.name = "Trail"
	trail.amount = 24
	trail.lifetime = 0.45
	trail.direction = Vector3.DOWN
	trail.spread = 20.0
	trail.initial_velocity_min = 0.3
	trail.initial_velocity_max = 0.8
	trail.gravity = Vector3(0.0, -1.0, 0.0)
	trail.scale_amount_curve = _fade_curve()
	trail.mesh = _spark_mesh(0.035, Color(1.0, 0.9, 0.6))
	rocket.add_child(trail)
	add_child(rocket)

	var rise := rocket.create_tween()
	rise.tween_property(rocket, "position", top, RISE_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rise.tween_callback(_burst.bind(rocket, colour))


func _burst(rocket: Node3D, colour: Color) -> void:
	var at := rocket.position
	# Let the trail's last sparks fade before the rocket goes.
	(rocket.get_node("Trail") as CPUParticles3D).emitting = false
	rocket.get_child(0).queue_free()
	get_tree().create_timer(0.5).timeout.connect(rocket.queue_free)

	var sparks := CPUParticles3D.new()
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.amount = SPARKS
	sparks.lifetime = SPARK_LIFETIME
	sparks.direction = Vector3.UP
	sparks.spread = 180.0
	sparks.initial_velocity_min = SPARK_SPEED_MIN
	sparks.initial_velocity_max = SPARK_SPEED_MAX
	sparks.damping_min = 2.5
	sparks.damping_max = 3.5
	sparks.gravity = Vector3(0.0, -1.5, 0.0)
	sparks.scale_amount_curve = _fade_curve()
	sparks.mesh = _spark_mesh(0.09, colour)
	# Placed before entering the tree so the burst emits where it is.
	sparks.position = at
	sparks.emitting = false
	sparks.finished.connect(sparks.queue_free)
	add_child(sparks)
	sparks.emitting = true

	var flash := OmniLight3D.new()
	flash.light_color = colour
	flash.light_energy = FLASH_ENERGY
	flash.omni_range = FLASH_RANGE
	flash.position = at
	add_child(flash)
	var fade := flash.create_tween()
	fade.tween_property(flash, "light_energy", 0.0, FLASH_TIME)
	fade.tween_callback(flash.queue_free)


## Full size for most of a spark's life, then shrinking away: opaque sparks
## fade by size, since transparent ones would sort badly round the bears.
func _fade_curve() -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.6, 0.9))
	curve.add_point(Vector2(1.0, 0.0))
	return curve


func _spark_mesh(radius: float, colour: Color) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = colour
	mesh.material = material
	return mesh
