extends Node3D
## Natural scenery beside the road: pines, round trees, bushes, boulders and
## flowers on the slopes outside the barriers. Meshes are batched with
## MultiMesh. Solid things (tree trunks, boulders) get matching collision so
## a trike that flies over a barrier can't pass through them. Soft foliage
## (canopies, bushes, flowers) has none.

@export var random_seed := 1234
@export var tree_spacing_samples := 3
@export_range(0.0, 1.0) var tree_chance := 0.8
@export var bush_spacing_samples := 3
@export_range(0.0, 1.0) var bush_chance := 0.55
@export var boulder_spacing_samples := 7
@export_range(0.0, 1.0) var boulder_chance := 0.4
@export var flowers_per_sample := 2
@export_flags_3d_physics var collision_layer := 1

const PINE_GREENS: Array[Color] = [Color(0.16, 0.52, 0.38), Color(0.2, 0.6, 0.4), Color(0.13, 0.45, 0.4)]
const LEAF_GREENS: Array[Color] = [Color(0.45, 0.75, 0.28), Color(0.6, 0.8, 0.3), Color(0.98, 0.62, 0.22), Color(0.36, 0.68, 0.3)]
const FLOWER_COLORS: Array[Color] = [Color(1, 1, 1), Color(1.0, 0.85, 0.25), Color(1.0, 0.55, 0.7), Color(0.75, 0.6, 1.0)]

var _rng := RandomNumberGenerator.new()
var _body: StaticBody3D


func build_for_track(track: Track) -> void:
	_rng.seed = random_seed
	_body = StaticBody3D.new()
	_body.name = "SceneryCollision"
	_body.collision_layer = collision_layer
	_body.collision_mask = 0
	add_child(_body)
	_build_trees(track)
	_build_bushes(track)
	_build_boulders(track)
	_build_flowers(track)


func _build_trees(track: Track) -> void:
	var path := track.path
	var builder := track.builder
	var pine_tall := MeshKit.combine([
		[MeshKit.cylinder(0.16, 0.24, 1.4, 6), MeshKit.at(Vector3(0, 0.7, 0)), Color(0.48, 0.32, 0.2)],
		[MeshKit.cone(1.7, 2.0), MeshKit.at(Vector3(0, 2.0, 0)), Color(0.85, 0.85, 0.85)],
		[MeshKit.cone(1.35, 1.7), MeshKit.at(Vector3(0, 3.1, 0), Vector3(0, 25, 0)), Color(0.93, 0.93, 0.93)],
		[MeshKit.cone(0.95, 1.5), MeshKit.at(Vector3(0, 4.1, 0), Vector3(0, 50, 0)), Color(1, 1, 1)],
	])
	var pine_short := MeshKit.combine([
		[MeshKit.cylinder(0.14, 0.2, 1.0, 6), MeshKit.at(Vector3(0, 0.5, 0)), Color(0.48, 0.32, 0.2)],
		[MeshKit.cone(1.4, 1.8), MeshKit.at(Vector3(0, 1.6, 0)), Color(0.88, 0.88, 0.88)],
		[MeshKit.cone(1.0, 1.5), MeshKit.at(Vector3(0, 2.5, 0), Vector3(0, 30, 0)), Color(1, 1, 1)],
	])
	var round_tree := MeshKit.combine([
		[MeshKit.cylinder(0.14, 0.22, 2.0, 6), MeshKit.at(Vector3(0, 1.0, 0)), Color(0.5, 0.34, 0.22)],
		[MeshKit.sphere(1.25), MeshKit.at(Vector3(0, 2.7, 0)), Color(1, 1, 1)],
		[MeshKit.sphere(0.85), MeshKit.at(Vector3(0.75, 2.3, 0.35)), Color(0.9, 0.9, 0.9)],
		[MeshKit.sphere(0.8), MeshKit.at(Vector3(-0.6, 3.2, -0.3)), Color(0.95, 0.95, 0.95)],
	])
	var meshes := {"pine_tall": pine_tall, "pine_short": pine_short, "round": round_tree}
	var transforms := {"pine_tall": [] as Array[Transform3D], "pine_short": [] as Array[Transform3D], "round": [] as Array[Transform3D]}
	var colors := {"pine_tall": [] as Array[Color], "pine_short": [] as Array[Color], "round": [] as Array[Color]}
	var clearance := track.road_width * 0.5 + 3.0
	for i in range(0, path.size(), tree_spacing_samples):
		for side: int in [-1, 1]:
			if _rng.randf() > tree_chance:
				continue
			var spot := builder.slope_point(path, i, side, _rng.randf_range(3.0, 21.0))
			if _near_road(path, spot, clearance):
				continue
			var roll := _rng.randf()
			var kind := "pine_tall" if roll < 0.5 else ("round" if roll < 0.8 else "pine_short")
			var s := _rng.randf_range(0.8, 1.45)
			(transforms[kind] as Array[Transform3D]).append(
					MeshKit.at(spot - Vector3.UP * 0.15, Vector3(0, _rng.randf() * 360.0, 0), Vector3.ONE * s))
			var palette := LEAF_GREENS if kind == "round" else PINE_GREENS
			(colors[kind] as Array[Color]).append(palette[_rng.randi() % palette.size()].lightened(_rng.randf_range(0.0, 0.12)))
			_add_cylinder_collider(spot + Vector3.UP * 1.0 * s, 0.3 * s, 2.0 * s)
	var material := MeshKit.vertex_color_material(0.9)
	for kind: String in meshes:
		var mesh: ArrayMesh = meshes[kind]
		mesh.surface_set_material(0, material)
		add_child(MeshKit.batch("Trees_" + kind, mesh, transforms[kind], colors[kind]))


func _build_bushes(track: Track) -> void:
	var path := track.path
	var bush := MeshKit.combine([
		[MeshKit.sphere(0.7, 7, 4), MeshKit.at(Vector3(0, 0.35, 0), Vector3.ZERO, Vector3(1, 0.8, 1)), Color(1, 1, 1)],
		[MeshKit.sphere(0.55, 7, 4), MeshKit.at(Vector3(0.6, 0.3, 0.2), Vector3.ZERO, Vector3(1, 0.8, 1)), Color(0.9, 0.9, 0.9)],
		[MeshKit.sphere(0.5, 7, 4), MeshKit.at(Vector3(-0.5, 0.28, -0.25), Vector3.ZERO, Vector3(1, 0.8, 1)), Color(0.95, 0.95, 0.95)],
	])
	bush.surface_set_material(0, MeshKit.vertex_color_material(0.9))
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for i in range(0, path.size(), bush_spacing_samples):
		for side: int in [-1, 1]:
			if _rng.randf() > bush_chance:
				continue
			var spot := track.builder.slope_point(path, i, side, _rng.randf_range(0.5, 3.0))
			if _near_road(path, spot, track.road_width * 0.5 + 1.0):
				continue
			transforms.append(MeshKit.at(spot - Vector3.UP * 0.1, Vector3(0, _rng.randf() * 360.0, 0), Vector3.ONE * _rng.randf_range(0.7, 1.2)))
			colors.append(LEAF_GREENS[_rng.randi() % 2].darkened(_rng.randf_range(0.0, 0.2)))
	add_child(MeshKit.batch("Bushes", bush, transforms, colors))


func _build_boulders(track: Track) -> void:
	var path := track.path
	var rock_shape_mesh := MeshKit.sphere(1.0, 7, 4)
	var rock := MeshKit.combine([[rock_shape_mesh, Transform3D.IDENTITY, Color(1, 1, 1)]])
	rock.surface_set_material(0, MeshKit.vertex_color_material(1.0))
	var rock_points: PackedVector3Array = rock_shape_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for i in range(0, path.size(), boulder_spacing_samples):
		for side: int in [-1, 1]:
			if _rng.randf() > boulder_chance:
				continue
			var spot := track.builder.slope_point(path, i, side, _rng.randf_range(2.0, 20.0))
			if _near_road(path, spot, track.road_width * 0.5 + 3.0):
				continue
			var size := Vector3(_rng.randf_range(0.9, 2.2), _rng.randf_range(0.6, 1.4), _rng.randf_range(0.9, 2.0))
			var xf := MeshKit.at(spot, Vector3(_rng.randf_range(-15, 15), _rng.randf() * 360.0, _rng.randf_range(-15, 15)), size)
			transforms.append(xf)
			colors.append(Color(0.6, 0.6, 0.64).lerp(Color(0.72, 0.66, 0.58), _rng.randf()))
			var shape := ConvexPolygonShape3D.new()
			var points := PackedVector3Array()
			for p in rock_points:
				points.append(xf.basis * p)
			shape.points = points
			var collider := CollisionShape3D.new()
			collider.shape = shape
			collider.position = xf.origin
			_body.add_child(collider)
	add_child(MeshKit.batch("Boulders", rock, transforms, colors))


func _build_flowers(track: Track) -> void:
	var path := track.path
	var flower := MeshKit.combine([
		[MeshKit.cylinder(0.015, 0.015, 0.3, 3), MeshKit.at(Vector3(0, 0.15, 0)), Color(0.3, 0.6, 0.25)],
		[MeshKit.sphere(0.09, 6, 3), MeshKit.at(Vector3(0, 0.32, 0), Vector3.ZERO, Vector3(1, 0.6, 1)), Color(1, 1, 1)],
	])
	flower.surface_set_material(0, MeshKit.vertex_color_material(0.8))
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for i in path.size():
		for n in flowers_per_sample:
			var side := -1 if _rng.randf() < 0.5 else 1
			var spot := track.builder.slope_point(path, i, side, _rng.randf_range(0.3, 12.0))
			transforms.append(MeshKit.at(spot, Vector3(0, _rng.randf() * 360.0, 0), Vector3.ONE * _rng.randf_range(0.8, 1.6)))
			colors.append(FLOWER_COLORS[_rng.randi() % FLOWER_COLORS.size()])
	add_child(MeshKit.batch("Flowers", flower, transforms, colors, false))


func _add_cylinder_collider(center: Vector3, radius: float, height: float) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = center
	_body.add_child(collider)


## True if `spot` is close (horizontally) to any road sample at a similar
## height, so scenery never sits on or hovers over another road section.
func _near_road(path: TrackPath, spot: Vector3, clearance: float) -> bool:
	for i in range(0, path.size(), 2):
		var p := path.points[i]
		if absf(spot.y - p.y) < 25.0 and Vector2(spot.x - p.x, spot.z - p.z).length() < clearance:
			return true
	return false
