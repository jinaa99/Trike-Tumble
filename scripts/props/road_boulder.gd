class_name RoadBoulder
extends StaticBody3D
## A big rock lying on the road: racers have to steer around it. Low-poly
## mesh and a convex collider built from the same points.

@export var radius := 1.9
@export var height := 2.3
@export var color := Color(0.6, 0.58, 0.6)
@export var random_seed := 3


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var sphere := MeshKit.sphere(1.0, 8, 5)
	var arrays := sphere.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	# Lumpy, squashed and sunk a little into the road.
	var lumps := {}
	var points := PackedVector3Array()
	for v in vertices:
		var key := v.snapped(Vector3.ONE * 0.001)
		if not lumps.has(key):
			lumps[key] = rng.randf_range(0.85, 1.12)
		var p: Vector3 = Vector3(v.x * radius, v.y * height * 0.5 + height * 0.42, v.z * radius) * lumps[key]
		points.append(p)
	var batch := MeshBatch.new()
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for t in range(0, indices.size(), 3):
		var a := points[indices[t]]
		var b := points[indices[t + 1]]
		var c := points[indices[t + 2]]
		var shade := color.darkened(clampf(0.25 - (a.y + b.y + c.y) / (3.0 * height) * 0.3, 0.0, 0.3))
		var outward := (a + b + c) / 3.0 - Vector3(0, height * 0.42, 0)
		batch.quad(a, b, c, c, outward, [shade, shade, shade, shade], true)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = batch.commit()
	mesh.material_override = MeshKit.vertex_color_material(1.0)
	add_child(mesh)
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var collider := CollisionShape3D.new()
	collider.name = "Collision"
	collider.shape = shape
	add_child(collider)
