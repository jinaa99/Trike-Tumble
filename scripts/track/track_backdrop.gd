extends Node3D
## Distant scenery for depth: a mountainside terrain the track is carved
## into, layered mountain ranges (far = bluer, fog does the rest), rolling
## hills, puffy clouds, a valley floor and a lake.
## No collision: the terrain starts below the track's out-of-bounds depth, so
## a falling trike respawns before reaching it. No shadow casting, so it's cheap.

@export var random_seed := 4321
@export var far_peaks := 18
@export var mid_peaks := 16
@export var hills := 26
@export var clouds := 26
@export var valley_depth := 45.0
## Terrain grid cell size (m) and how steeply it falls away from the track.
@export var terrain_cell := 12.0
@export var terrain_margin := 320.0
@export var terrain_falloff := 0.55

var _rng := RandomNumberGenerator.new()


func build_for_track(track: Track) -> void:
	_rng.seed = random_seed
	var bounds := _bounds(track)
	var center := bounds.get_center()
	var radius := maxf(bounds.size.x, bounds.size.z) * 0.5
	var floor_y := bounds.position.y - valley_depth
	_build_peaks("FarPeaks", far_peaks, center, radius + 520.0, 220.0, floor_y, Vector2(260, 420),
			Color(0.56, 0.6, 0.86), 0.62)
	_build_peaks("MidPeaks", mid_peaks, center, radius + 260.0, 140.0, floor_y, Vector2(170, 250),
			Color(0.38, 0.6, 0.66), 0.7)
	_build_terrain(track, bounds, floor_y)
	_build_hills(center, radius + 90.0, floor_y)
	_build_clouds(center, radius, bounds.end.y)
	_build_valley(center, floor_y)


func _build_peaks(node_name: String, count: int, center: Vector3, ring: float, spread: float, floor_y: float,
		height_range: Vector2, color: Color, snow_line: float) -> void:
	var peak := MeshKit.combine([
		[MeshKit.cone(1.0, 1.0, 7), MeshKit.at(Vector3(0, 0.5, 0)), Color.WHITE],
	])
	var cap_height := 1.0 - snow_line
	var cap := MeshKit.combine([
		[MeshKit.cone(cap_height + 0.01, cap_height + 0.01, 7), MeshKit.at(Vector3(0, snow_line + cap_height * 0.5, 0)), Color.WHITE],
	])
	var material := MeshKit.vertex_color_material(1.0)
	peak.surface_set_material(0, material)
	cap.surface_set_material(0, material)
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for i in count:
		var angle := TAU * i / count + _rng.randf_range(-0.12, 0.12)
		var distance := ring + _rng.randf_range(0.0, spread)
		var height := _rng.randf_range(height_range.x, height_range.y)
		var width := height * _rng.randf_range(0.75, 1.05)
		var spot := Vector3(center.x + cos(angle) * distance, floor_y - 5.0, center.z + sin(angle) * distance)
		transforms.append(MeshKit.at(spot, Vector3(0, _rng.randf() * 360.0, 0), Vector3(width, height, width)))
		colors.append(color.lerp(Color.WHITE, _rng.randf_range(0.0, 0.1)))
	add_child(MeshKit.batch(node_name, peak, transforms, colors, false))
	var cap_colors: Array[Color] = []
	for i in count:
		cap_colors.append(Color(0.97, 0.98, 1.0))
	add_child(MeshKit.batch(node_name + "Snow", cap, transforms, cap_colors, false))


## Heightfield that continues the grass slopes down to the valley floor.
## Height comes from the nearest track sample: the slope foot (22 m below
## the road, 32 m out) falls away by `terrain_falloff` per meter.
func _build_terrain(track: Track, bounds: AABB, floor_y: float) -> void:
	var path := track.path
	var edge_out := track.road_width * 0.5 + track.builder.wall_thickness + 24.0
	var edge_drop := 22.4
	var noise := FastNoiseLite.new()
	noise.seed = random_seed
	noise.frequency = 0.012
	var origin := Vector2(bounds.position.x - terrain_margin, bounds.position.z - terrain_margin)
	var cols := int((bounds.size.x + terrain_margin * 2.0) / terrain_cell) + 1
	var rows := int((bounds.size.z + terrain_margin * 2.0) / terrain_cell) + 1
	var samples := PackedVector3Array()
	for i in range(0, path.size(), 3):
		samples.append(path.points[i])
	var heights := PackedFloat32Array()
	heights.resize(cols * rows)
	for r in rows:
		for c in cols:
			var x := origin.x + c * terrain_cell
			var z := origin.y + r * terrain_cell
			var best := INF
			var best_y := 0.0
			for p in samples:
				var d := (p.x - x) * (p.x - x) + (p.z - z) * (p.z - z)
				if d < best:
					best = d
					best_y = p.y
			var distance := sqrt(best)
			var h := best_y - edge_drop - maxf(distance - edge_out, 0.0) * terrain_falloff
			if distance < edge_out:
				# Continue just under the track slopes so there is no trench.
				h = best_y - edge_drop - (edge_out - distance) * 0.2
			else:
				h += noise.get_noise_2d(x, z) * minf((distance - edge_out) * 0.2, 6.0)
			heights[r * cols + c] = maxf(h, floor_y - 0.6)
	var parts := SurfaceTool.new()
	parts.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in rows - 1:
		for c in cols - 1:
			var p00 := Vector3(origin.x + c * terrain_cell, heights[r * cols + c], origin.y + r * terrain_cell)
			var p10 := Vector3(p00.x + terrain_cell, heights[r * cols + c + 1], p00.z)
			var p01 := Vector3(p00.x, heights[(r + 1) * cols + c], p00.z + terrain_cell)
			var p11 := Vector3(p00.x + terrain_cell, heights[(r + 1) * cols + c + 1], p00.z + terrain_cell)
			for tri: PackedVector3Array in [PackedVector3Array([p00, p10, p11]), PackedVector3Array([p00, p11, p01])]:
				var normal := (tri[2] - tri[0]).cross(tri[1] - tri[0]).normalized()
				if normal.y < 0.0:
					normal = -normal
				var steep := 1.0 - normal.y
				var center := (tri[0] + tri[1] + tri[2]) / 3.0
				var height_t := clampf((center.y - floor_y) / 140.0, 0.0, 1.0)
				var color := Color(0.46, 0.7, 0.33).lerp(Color(0.32, 0.58, 0.36), height_t)
				color = color.lerp(Color(0.58, 0.57, 0.54), clampf(steep * 2.5 - 0.5, 0.0, 0.7))
				color = color.lerp(Color(0.58, 0.76, 0.36), clampf(noise.get_noise_2d(center.z * 0.3, center.x * 0.3) * 0.6, 0.0, 0.3))
				# Clockwise front faces: order so the winding cross opposes the normal.
				var ordered := tri if (tri[1] - tri[0]).cross(tri[2] - tri[0]).dot(normal) < 0.0 \
						else PackedVector3Array([tri[0], tri[2], tri[1]])
				for v in ordered:
					parts.set_color(color)
					parts.set_normal(normal)
					parts.add_vertex(v)
	var terrain := MeshInstance3D.new()
	terrain.name = "Terrain"
	terrain.mesh = parts.commit()
	terrain.material_override = TrackMaterials.grass()
	terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(terrain)


func _build_hills(center: Vector3, ring: float, floor_y: float) -> void:
	var hill := MeshKit.combine([[MeshKit.sphere(1.0, 9, 5), Transform3D.IDENTITY, Color.WHITE]])
	hill.surface_set_material(0, MeshKit.vertex_color_material(1.0))
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for i in hills:
		var angle := TAU * i / hills + _rng.randf_range(-0.1, 0.1)
		var distance := ring + _rng.randf_range(0.0, 160.0)
		var r := _rng.randf_range(60.0, 120.0)
		var spot := Vector3(center.x + cos(angle) * distance, floor_y, center.z + sin(angle) * distance)
		transforms.append(MeshKit.at(spot, Vector3(0, _rng.randf() * 360.0, 0), Vector3(r, r * _rng.randf_range(0.35, 0.6), r)))
		colors.append(Color(0.36, 0.64, 0.36).lerp(Color(0.55, 0.75, 0.35), _rng.randf()))
	add_child(MeshKit.batch("Hills", hill, transforms, colors, false))


func _build_clouds(center: Vector3, radius: float, top_y: float) -> void:
	var puff := MeshKit.combine([
		[MeshKit.sphere(1.0, 9, 5), MeshKit.at(Vector3(0, 0, 0)), Color.WHITE],
		[MeshKit.sphere(0.75, 9, 5), MeshKit.at(Vector3(0.9, -0.15, 0.2)), Color.WHITE],
		[MeshKit.sphere(0.7, 9, 5), MeshKit.at(Vector3(-0.95, -0.2, -0.1)), Color.WHITE],
		[MeshKit.sphere(0.6, 9, 5), MeshKit.at(Vector3(0.3, 0.45, -0.3)), Color.WHITE],
	])
	var material := MeshKit.vertex_color_material(1.0)
	material.emission_enabled = true
	material.emission = Color(0.55, 0.6, 0.7)
	puff.surface_set_material(0, material)
	var transforms: Array[Transform3D] = []
	for i in clouds:
		var angle := _rng.randf() * TAU
		var distance := _rng.randf_range(0.2, 1.6) * (radius + 300.0)
		var s := _rng.randf_range(14.0, 30.0)
		var spot := Vector3(center.x + cos(angle) * distance, top_y + _rng.randf_range(60.0, 160.0), center.z + sin(angle) * distance)
		transforms.append(MeshKit.at(spot, Vector3(0, _rng.randf() * 360.0, 0), Vector3(s * 1.6, s * 0.7, s)))
	add_child(MeshKit.batch("Clouds", puff, transforms, [], false))


func _build_valley(center: Vector3, floor_y: float) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(5000.0, 5000.0)
	var valley := MeshInstance3D.new()
	valley.name = "Valley"
	valley.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.42, 0.66, 0.34)
	material.albedo_texture = TrackMaterials.detail_texture(0.75)
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE * 0.004
	material.roughness = 1.0
	valley.material_override = material
	valley.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	valley.position = Vector3(center.x, floor_y, center.z)
	add_child(valley)

	var lake_mesh := CylinderMesh.new()
	lake_mesh.top_radius = 140.0
	lake_mesh.bottom_radius = 140.0
	lake_mesh.height = 0.2
	lake_mesh.radial_segments = 24
	var lake := MeshInstance3D.new()
	lake.name = "Lake"
	lake.mesh = lake_mesh
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.25, 0.6, 0.85)
	water.roughness = 0.08
	water.metallic_specular = 0.8
	lake.material_override = water
	lake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lake.scale = Vector3(1.6, 1.0, 1.0)
	lake.position = Vector3(center.x + 260.0, floor_y + 0.15, center.z + 120.0)
	add_child(lake)


func _bounds(track: Track) -> AABB:
	var aabb := AABB(track.path.points[0], Vector3.ZERO)
	for p in track.path.points:
		aabb = aabb.expand(p)
	return aabb
