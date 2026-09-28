extends StaticBody3D

## A low candy fence round the stage that keeps the green bears in: striped
## mint-and-white posts under a sky-blue rail, built in code. Pastels only,
## never red or pink: the --shots harness finds the player by its red pixels.

## Distance from the stage centre to the fence line, per axis (the ground is
## 20×20 m, so this leaves a 0.4 m verge).
const HALF_EXTENT := 9.6
const HEIGHT := 0.5
const THICKNESS := 0.15
const POST_SPACING := 0.6
const POST_RADIUS := 0.07
const RAIL_HEIGHT := 0.08
const POST_COLOURS := [Color(0.55, 0.95, 0.75), Color(0.97, 0.97, 0.97)]
const RAIL_COLOUR := Color(0.55, 0.75, 1.0)


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var length := HALF_EXTENT * 2.0
	# One collider and rail per side: north, south, east, west.
	for side in 4:
		var along_x := side < 2
		var offset := HALF_EXTENT * (1.0 if side % 2 == 0 else -1.0)
		var centre := (Vector3(0.0, HEIGHT * 0.5, offset) if along_x
				else Vector3(offset, HEIGHT * 0.5, 0.0))
		var size := (Vector3(length + THICKNESS, HEIGHT, THICKNESS) if along_x
				else Vector3(THICKNESS, HEIGHT, length + THICKNESS))
		var box := BoxShape3D.new()
		box.size = size
		var shape := CollisionShape3D.new()
		shape.shape = box
		shape.position = centre
		add_child(shape)

		var rail := BoxMesh.new()
		rail.size = Vector3(size.x, RAIL_HEIGHT, size.z)
		rail.material = _material(RAIL_COLOUR)
		var rail_instance := MeshInstance3D.new()
		rail_instance.mesh = rail
		rail_instance.position = Vector3(centre.x, HEIGHT - RAIL_HEIGHT * 0.5, centre.z)
		add_child(rail_instance)

	# Posts round the perimeter, alternating colours, one MultiMesh each.
	var posts: Array[Vector3] = []
	var per_side := roundi(length / POST_SPACING)
	for i in per_side:
		var t := -HALF_EXTENT + i * POST_SPACING
		posts.append(Vector3(t, 0.0, -HALF_EXTENT))
		posts.append(Vector3(HALF_EXTENT, 0.0, t))
		posts.append(Vector3(-t, 0.0, HALF_EXTENT))
		posts.append(Vector3(-HALF_EXTENT, 0.0, -t))
	for c in POST_COLOURS.size():
		var post := CylinderMesh.new()
		post.top_radius = POST_RADIUS
		post.bottom_radius = POST_RADIUS
		post.height = HEIGHT - RAIL_HEIGHT
		post.radial_segments = 12
		post.material = _material(POST_COLOURS[c])
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = post
		var mine: Array[Vector3] = []
		for i in posts.size():
			if (i / 4) % POST_COLOURS.size() == c:
				mine.append(posts[i])
		multimesh.instance_count = mine.size()
		for i in mine.size():
			multimesh.set_instance_transform(i, Transform3D(Basis(),
					mine[i] + Vector3.UP * post.height * 0.5))
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		add_child(instance)


func _material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.35
	return material
