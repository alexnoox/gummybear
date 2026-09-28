extends RigidBody3D

## A thrown yellow dodgeball. Any touch on a standing bear knocks it down
## (even after a bounce), and a touch on a downed bear's ragdoll shoves it.
## Every touch counts as a bounce; the ball pops with a small burst after
## MAX_BOUNCES, or after LIFETIME if it rolls or falls off the stage. The
## thrower adds a collision exception so the ball passes through the player.

const RADIUS := 0.15
const MAX_BOUNCES := 3
const LIFETIME := 5.0
const FALL_LIMIT := -3.0
## Contacts closer together than this (s) are one bounce: a ball landing on
## a ragdoll touches several bones at once.
const BOUNCE_DEBOUNCE := 0.1
## Extra shove on a downed bear's bone, as a fraction of the ball's velocity
## (kg), on top of the plain collision.
const BONE_SHOVE := 0.4
## Yellow keeps the harness's red-keyed silhouette detector blind to it.
const COLOUR := Color(1.0, 0.85, 0.1)

## Physics layer bits live on the bear body.
const GUMMY_BEAR := preload("res://scripts/gummy_bear.gd")

var _age := 0.0
var _bounces := 0
var _last_bounce_at := -INF
## Velocity before this tick's physics step: body_entered fires after the
## bounce, when linear_velocity already points back out.
var _incoming := Vector3.ZERO


func _init() -> void:
	name = "Ball"
	mass = 0.4
	collision_layer = GUMMY_BEAR.LAYER_BALLS
	collision_mask = (GUMMY_BEAR.LAYER_WORLD | GUMMY_BEAR.LAYER_BEARS
			| GUMMY_BEAR.LAYER_RAGDOLLS)
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.05
	var surface := PhysicsMaterial.new()
	surface.bounce = 0.7
	surface.friction = 0.6
	physics_material_override = surface

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	shape.shape = sphere
	add_child(shape)

	var mesh := SphereMesh.new()
	mesh.radius = RADIUS
	mesh.height = RADIUS * 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = COLOUR
	material.roughness = 0.45
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	add_child(visual)

	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_age += delta
	_incoming = linear_velocity
	if _age > LIFETIME or global_position.y < FALL_LIMIT:
		_pop()


func _on_body_entered(body: Node) -> void:
	# Deferred: body_entered fires while the physics server flushes, where
	# starting a ragdoll or changing layers is not allowed.
	if body.has_method("knock"):
		body.knock.call_deferred(_incoming)
	elif body is PhysicalBone3D:
		(body as PhysicalBone3D).apply_central_impulse.call_deferred(_incoming * BONE_SHOVE)
	if _age - _last_bounce_at < BOUNCE_DEBOUNCE:
		return
	_last_bounce_at = _age
	_bounces += 1
	if _bounces >= MAX_BOUNCES:
		_pop.call_deferred()


func _pop() -> void:
	if is_queued_for_deletion():
		return
	var burst := CPUParticles3D.new()
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = 14
	burst.lifetime = 0.45
	burst.direction = Vector3.UP
	burst.spread = 180.0
	burst.initial_velocity_min = 1.5
	burst.initial_velocity_max = 2.5
	burst.scale_amount_min = 0.6
	burst.scale_amount_max = 1.0
	var bit := SphereMesh.new()
	bit.radius = 0.035
	bit.height = 0.07
	bit.radial_segments = 8
	bit.rings = 4
	var material := StandardMaterial3D.new()
	material.albedo_color = COLOUR
	material.emission_enabled = true
	material.emission = COLOUR * 0.4
	bit.material = material
	burst.mesh = bit
	burst.finished.connect(burst.queue_free)
	# Placed before it enters the tree, and held until it's there: an emitter
	# that enters at the origin and is moved afterwards emits every burst at
	# the origin under physics interpolation.
	burst.emitting = false
	burst.position = get_parent().to_local(global_position)
	get_parent().add_child(burst)
	burst.reset_physics_interpolation()
	burst.emitting = true
	queue_free()
