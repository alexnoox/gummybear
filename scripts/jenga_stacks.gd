extends Node3D

## Three towers of blue Jenga blocks, built in code. Every block is a
## RigidBody3D on the props layer, so a ball, any bear walking into it (its
## pusher, see gummy_bear.gd) or a flopping ragdoll knocks the towers about. Each
## layer is three blocks side by side, turned a quarter each layer like the
## real game. Blocks start asleep, so an untouched tower stands perfectly
## still. Blue only: the --shots harness finds the player by red pixels.

const GUMMY_BEAR := preload("res://scripts/gummy_bear.gd")

## Tower spots on the ground, toward the far side of the stage (clear of the
## player's start and the --shots harness's throw).
const STACKS: Array[Vector3] = [
	Vector3(-3.5, 0.0, -5.5),
	Vector3(0.5, 0.0, -6.5),
	Vector3(4.0, 0.0, -5.0),
]
const LAYERS := 10
## One block: long side, width (three make a square layer), height (m).
const BLOCK_LENGTH := 0.6
const BLOCK_WIDTH := 0.2
const BLOCK_HEIGHT := 0.12
## Light next to the 0.4 kg ball, so a hit topples a tower rather than
## popping one block out.
const BLOCK_MASS := 0.2
## Three shades so the blocks read separately.
const BLUES := [
	Color(0.2, 0.45, 0.95),
	Color(0.3, 0.55, 1.0),
	Color(0.15, 0.38, 0.85),
]
## Green bears don't spawn within this distance of a tower (m).
const CLEAR_RADIUS := 1.5

## stack index -> Array of [block, starting position]
var _blocks: Array = []


func _enter_tree() -> void:
	# Before the green bear spawner's _ready, which keeps clear of these.
	add_to_group("keep_clear")


func _ready() -> void:
	var shape := BoxShape3D.new()
	shape.size = Vector3(BLOCK_LENGTH, BLOCK_HEIGHT, BLOCK_WIDTH)
	var mesh := BoxMesh.new()
	mesh.size = shape.size
	var materials: Array[StandardMaterial3D] = []
	for blue: Color in BLUES:
		var material := StandardMaterial3D.new()
		material.albedo_color = blue
		material.roughness = 0.45
		materials.append(material)
	var surface := PhysicsMaterial.new()
	surface.friction = 0.8
	surface.bounce = 0.05

	for spot in STACKS:
		var stack: Array = []
		for layer in LAYERS:
			# Even layers run along X, odd ones along Z.
			var turn := Basis(Vector3.UP, PI / 2.0) if layer % 2 == 1 else Basis()
			for i in 3:
				var across := (i - 1) * BLOCK_WIDTH
				var offset := Vector3(0.0, (layer + 0.5) * BLOCK_HEIGHT, across)
				var block := RigidBody3D.new()
				block.mass = BLOCK_MASS
				block.physics_material_override = surface
				block.collision_layer = GUMMY_BEAR.LAYER_PROPS
				block.collision_mask = (GUMMY_BEAR.LAYER_WORLD | GUMMY_BEAR.LAYER_PUSHERS
						| GUMMY_BEAR.LAYER_RAGDOLLS | GUMMY_BEAR.LAYER_BALLS
						| GUMMY_BEAR.LAYER_PROPS)
				block.transform = Transform3D(turn, spot + turn * offset)
				# Still until something touches it.
				block.sleeping = true
				var collider := CollisionShape3D.new()
				collider.shape = shape
				block.add_child(collider)
				var visual := MeshInstance3D.new()
				visual.mesh = mesh
				visual.material_override = materials[(layer + i) % materials.size()]
				block.add_child(visual)
				add_child(block)
				stack.append([block, block.position])
		_blocks.append(stack)


## Spots the green bear spawner keeps CLEAR_RADIUS away from.
func keep_clear_spots() -> Array[Vector3]:
	return STACKS


func keep_clear_radius() -> float:
	return CLEAR_RADIUS


func stack_count() -> int:
	return _blocks.size()


func block_count() -> int:
	var count := 0
	for stack: Array in _blocks:
		count += stack.size()
	return count


func stack_position(stack: int) -> Vector3:
	return global_transform * STACKS[stack]


## How many of `stack`'s blocks are more than `distance` from where they
## started.
func blocks_moved(stack: int, distance: float) -> int:
	var moved := 0
	for entry: Array in _blocks[stack]:
		var block: RigidBody3D = entry[0]
		if block.position.distance_to(entry[1]) > distance:
			moved += 1
	return moved
