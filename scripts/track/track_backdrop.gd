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
## Near the edge of the terrain grid (this many m) the ground eases down to
## the valley floor, so the mountain never ends in a cut-off wall.
@export var terrain_edge_blend := 260.0
## Terrain grid cells per mesh tile (culling).
@export var terrain_tile_cells := 32
## How far (m) the borders between terrain areas of different track
## sections wander (natural-looking cliffs between levels).
@export var cliff_warp := 110.0
## Pines on the terrain beyond the track slopes: grid spacing (m), chance per
## spot and how far beyond the slope edge they grow (m). 0 chance = none.
@export var far_forest_spacing := 9.0
@export_range(0.0, 1.0) var far_forest_chance := 0.0
@export var far_forest_depth := 70.0
@export var far_forest_view_distance := 900.0

var _rng := RandomNumberGenerator.new()
var _theme: TrackTheme
var _origin := Vector2.ZERO
var _cols := 0
var _rows := 0
var _heights := PackedFloat32Array()
var _nearest := PackedInt32Array()
var _warp := FastNoiseLite.new()


func build_for_track(track: Track) -> void:
	_rng.seed = random_seed
	_theme = track.theme if track.theme else TrackTheme.new()
	var bounds := _bounds(track)
	var center := bounds.get_center()
	var radius := maxf(bounds.size.x, bounds.size.z) * 0.5
	var floor_y := bounds.position.y - valley_depth
	_build_peaks("FarPeaks", far_peaks, center, radius + 520.0, 220.0, floor_y, Vector2(260, 420),
			_theme.far_peak_color, _theme.far_snow_line)
	_build_peaks("MidPeaks", mid_peaks, center, radius + 260.0, 140.0, floor_y, Vector2(170, 250),
			_theme.mid_peak_color, _theme.mid_snow_line)
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
		cap_colors.append(_theme.snow_color)
	add_child(MeshKit.batch(node_name + "Snow", cap, transforms, cap_colors, false))


## Heightfield that continues the grass slopes down to the valley floor.
## Height comes from the nearest track sample: the slope foot (22 m below
## the road, 32 m out) falls away by `terrain_falloff` per meter. The
## nearest sample per grid vertex comes from a two-pass sweep over the grid
## (each vertex tries its neighbors' nearest samples), which is linear in
## the grid size instead of grid size x track samples. Built in tiles so the
## renderer can cull what's out of view.
func _build_terrain(track: Track, bounds: AABB, floor_y: float) -> void:
	var path := track.path
	var edge_out := track.builder.road_width * 0.5 + track.builder.wall_thickness + 24.0
	var edge_drop := 22.4
	var noise := FastNoiseLite.new()
	noise.seed = random_seed
	noise.frequency = 0.012
	_warp.seed = random_seed + 1
	_warp.frequency = 0.004
	_origin = Vector2(bounds.position.x - terrain_margin, bounds.position.z - terrain_margin)
	_cols = int((bounds.size.x + terrain_margin * 2.0) / terrain_cell) + 1
	_rows = int((bounds.size.z + terrain_margin * 2.0) / terrain_cell) + 1
	var nearest := _nearest_samples(path, 0.0)
	# Away from the track, a noise-warped choice of section gives winding
	# cliffs between levels; close to it, the true nearest section is kept.
	var warped := _nearest_samples(path, cliff_warp) if cliff_warp > 0.0 else nearest
	var near_limit := edge_out + 60.0
	_heights = PackedFloat32Array()
	_heights.resize(_cols * _rows)
	for r in _rows:
		for c in _cols:
			var x := _origin.x + c * terrain_cell
			var z := _origin.y + r * terrain_cell
			var true_p := path.points[nearest[r * _cols + c]]
			if Vector2(true_p.x - x, true_p.z - z).length() > near_limit:
				nearest[r * _cols + c] = warped[r * _cols + c]
			var p := path.points[nearest[r * _cols + c]]
			var distance := Vector2(p.x - x, p.z - z).length()
			var local_edge := edge_out + track.half_width_at(nearest[r * _cols + c]) - track.builder.road_width * 0.5
			var h := p.y - edge_drop - maxf(distance - local_edge, 0.0) * terrain_falloff
			if distance < local_edge:
				# Continue just under the track slopes so there is no trench.
				h = p.y - edge_drop - (local_edge - distance) * 0.2
			else:
				h += noise.get_noise_2d(x, z) * minf((distance - local_edge) * 0.2, 6.0)
			var to_edge := minf(minf(c, _cols - 1 - c), minf(r, _rows - 1 - r)) * terrain_cell
			if to_edge < terrain_edge_blend:
				h = lerpf(floor_y - 0.6, h, smoothstep(0.0, 1.0, to_edge / terrain_edge_blend))
			_heights[r * _cols + c] = maxf(h, floor_y - 0.6)
	_nearest = nearest
	var material := TrackMaterials.grass()
	for tile_r in range(0, _rows - 1, terrain_tile_cells):
		for tile_c in range(0, _cols - 1, terrain_tile_cells):
			var batch := MeshBatch.new()
			for r in range(tile_r, mini(tile_r + terrain_tile_cells, _rows - 1)):
				for c in range(tile_c, mini(tile_c + terrain_tile_cells, _cols - 1)):
					_terrain_cell(batch, r, c, floor_y, noise)
			var terrain := MeshInstance3D.new()
			terrain.name = "Terrain_%d_%d" % [tile_r, tile_c]
			terrain.mesh = batch.commit()
			terrain.material_override = material
			terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(terrain)
	_build_far_forest(track, edge_out)


func _terrain_cell(batch: MeshBatch, r: int, c: int, floor_y: float, noise: FastNoiseLite) -> void:
	var p00 := _vertex(r, c)
	var p10 := _vertex(r, c + 1)
	var p01 := _vertex(r + 1, c)
	var p11 := _vertex(r + 1, c + 1)
	for tri: PackedVector3Array in [PackedVector3Array([p00, p10, p11]), PackedVector3Array([p00, p11, p01])]:
		var normal := (tri[2] - tri[0]).cross(tri[1] - tri[0]).normalized()
		if normal.y < 0.0:
			normal = -normal
		var steep := 1.0 - normal.y
		var center := (tri[0] + tri[1] + tri[2]) / 3.0
		var height_t := clampf((center.y - floor_y) / 140.0, 0.0, 1.0)
		var color := _theme.terrain_low_color.lerp(_theme.terrain_high_color, height_t)
		color = color.lerp(_theme.terrain_steep_color, clampf(steep * 2.5 - 0.5, 0.0, 0.7))
		color = color.lerp(_theme.terrain_patch_color, clampf(noise.get_noise_2d(center.z * 0.3, center.x * 0.3) * 0.6, 0.0, 0.3))
		batch.colors.append_array(PackedColorArray([color, color, color]))
		batch.normals.append_array(PackedVector3Array([normal, normal, normal]))
		# Clockwise front faces: order so the winding cross opposes the normal.
		if (tri[1] - tri[0]).cross(tri[2] - tri[0]).dot(normal) < 0.0:
			batch.vertices.append_array(tri)
		else:
			batch.vertices.append_array(PackedVector3Array([tri[0], tri[2], tri[1]]))


func _vertex(r: int, c: int) -> Vector3:
	return Vector3(_origin.x + c * terrain_cell, _heights[r * _cols + c], _origin.y + r * terrain_cell)


## Terrain height at (x, z), on the same triangles as the mesh.
func terrain_height(x: float, z: float) -> float:
	var fc := clampf((x - _origin.x) / terrain_cell, 0.0, _cols - 1.001)
	var fr := clampf((z - _origin.y) / terrain_cell, 0.0, _rows - 1.001)
	var c := floori(fc)
	var r := floori(fr)
	var u := fc - c
	var v := fr - r
	var h00 := _heights[r * _cols + c]
	var h10 := _heights[r * _cols + c + 1]
	var h01 := _heights[(r + 1) * _cols + c]
	var h11 := _heights[(r + 1) * _cols + c + 1]
	if u >= v:  # triangle p00, p10, p11
		return h00 + (h10 - h00) * u + (h11 - h10) * v
	return h00 + (h11 - h01) * u + (h01 - h00) * v


## Nearest track sample (every 2nd) for each grid vertex: seed the vertex
## under each sample, then sweep forward and backward taking a neighbor's
## nearest sample whenever it is closer.
func _nearest_samples(path: TrackPath, warp: float) -> PackedInt32Array:
	var count := _cols * _rows
	var nearest := PackedInt32Array()
	nearest.resize(count)
	nearest.fill(-1)
	var best := PackedFloat32Array()
	best.resize(count)
	best.fill(INF)
	for i in range(0, path.size(), 2):
		var p := path.points[i]
		var c := clampi(roundi((p.x - _origin.x) / terrain_cell), 0, _cols - 1)
		var r := clampi(roundi((p.z - _origin.y) / terrain_cell), 0, _rows - 1)
		var d := _flat_distance_sq(p, r, c, warp)
		if d < best[r * _cols + c]:
			best[r * _cols + c] = d
			nearest[r * _cols + c] = i
	var forward: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]
	var backward: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1)]
	for pass_index in 2:
		var offsets := forward if pass_index == 0 else backward
		var rows := range(_rows) if pass_index == 0 else range(_rows - 1, -1, -1)
		var cols := range(_cols) if pass_index == 0 else range(_cols - 1, -1, -1)
		for r: int in rows:
			for c: int in cols:
				var here := r * _cols + c
				for offset in offsets:
					var nc := c + offset.x
					var nr := r + offset.y
					if nc < 0 or nr < 0 or nc >= _cols or nr >= _rows:
						continue
					var candidate := nearest[nr * _cols + nc]
					if candidate < 0 or candidate == nearest[here]:
						continue
					var d := _flat_distance_sq(path.points[candidate], r, c, warp)
					if d < best[here]:
						best[here] = d
						nearest[here] = candidate
	return nearest


## Distance used to pick the nearest sample. The grid point is warped by
## noise, so where two track sections at different heights meet, the cliff
## between them winds like a natural rock face instead of a straight wall.
func _flat_distance_sq(p: Vector3, r: int, c: int, warp: float) -> float:
	var x := _origin.x + c * terrain_cell
	var z := _origin.y + r * terrain_cell
	var dx := p.x - x
	var dz := p.z - z
	if warp > 0.0:
		dx -= _warp.get_noise_2d(x, z) * warp
		dz -= _warp.get_noise_2d(z + 1000.0, x) * warp
	return dx * dx + dz * dz


## Pines on the terrain just beyond the track slopes (no collision: a trike
## out there has left the course and respawns). Kept off overlook and
## clearing zones so those keep their view.
func _build_far_forest(track: Track, edge_out: float) -> void:
	if far_forest_chance <= 0.0:
		return
	var pine := MeshKit.combine([
		[MeshKit.cylinder(0.2, 0.3, 1.6, 5), MeshKit.at(Vector3(0, 0.8, 0)), Color(0.48, 0.32, 0.2)],
		[MeshKit.cone(2.1, 2.6, 6), MeshKit.at(Vector3(0, 2.4, 0)), Color(0.86, 0.86, 0.86)],
		[MeshKit.cone(1.6, 2.2, 6), MeshKit.at(Vector3(0, 3.8, 0), Vector3(0, 30, 0)), Color(0.94, 0.94, 0.94)],
		[MeshKit.cone(1.1, 1.9, 6), MeshKit.at(Vector3(0, 5.1, 0), Vector3(0, 60, 0)), Color(1, 1, 1)],
	])
	if _theme.scenery_style == TrackTheme.SceneryStyle.SNOW:
		# Frosted far pines: bright snowy tiers over dark ones. With the snow
		# theme's pale pine tint they read as snow-covered from a distance.
		pine = MeshKit.combine([
			[MeshKit.cylinder(0.2, 0.3, 1.6, 5), MeshKit.at(Vector3(0, 0.8, 0)), Color(0.48, 0.32, 0.2)],
			[MeshKit.cone(2.1, 2.6, 6), MeshKit.at(Vector3(0, 2.4, 0)), Color(0.5, 0.5, 0.5)],
			[MeshKit.cone(1.6, 2.2, 6), MeshKit.at(Vector3(0, 3.8, 0), Vector3(0, 30, 0)), Color(1, 1, 1)],
			[MeshKit.cone(1.1, 1.9, 6), MeshKit.at(Vector3(0, 5.1, 0), Vector3(0, 60, 0)), Color(1, 1, 1)],
		])
	pine.surface_set_material(0, MeshKit.vertex_color_material(0.9))
	var path := track.path
	var groups := {}
	var step := far_forest_spacing
	var x := _origin.x
	while x < _origin.x + (_cols - 1) * terrain_cell:
		var z := _origin.y
		while z < _origin.y + (_rows - 1) * terrain_cell:
			var px := x + _rng.randf_range(-0.4, 0.4) * step
			var pz := z + _rng.randf_range(-0.4, 0.4) * step
			z += step
			if _rng.randf() > far_forest_chance:
				continue
			var c := clampi(roundi((px - _origin.x) / terrain_cell), 0, _cols - 1)
			var r := clampi(roundi((pz - _origin.y) / terrain_cell), 0, _rows - 1)
			var index := _nearest[r * _cols + c]
			var p := path.points[index]
			var distance := Vector2(p.x - px, p.z - pz).length()
			var local_edge := edge_out + track.half_width_at(index) - track.builder.road_width * 0.5
			if distance < local_edge + 3.0 or distance > local_edge + far_forest_depth:
				continue
			var along := index * path.spacing
			var side := 1 if (Vector3(px, p.y, pz) - p).dot(path.rights[index]) > 0.0 else -1
			if track.in_zone(along, "clearing", 30.0) or _overlook_side(track, along, side) \
					or track.get_sample_kind(index) != TrackMeshBuilder.SampleKind.NORMAL:
				continue
			var y := terrain_height(px, pz)
			var s := _rng.randf_range(0.9, 1.6)
			@warning_ignore("integer_division")
			var key := index / 150
			if not groups.has(key):
				groups[key] = {"transforms": [] as Array[Transform3D], "colors": [] as Array[Color]}
			(groups[key]["transforms"] as Array[Transform3D]).append(
					MeshKit.at(Vector3(px, y - 0.3, pz), Vector3(0, _rng.randf() * 360.0, 0), Vector3.ONE * s))
			(groups[key]["colors"] as Array[Color]).append(
					_theme.pine_greens[_rng.randi() % _theme.pine_greens.size()].darkened(_rng.randf_range(0.0, 0.15)))
		x += step
	for key: int in groups:
		var transforms: Array[Transform3D] = groups[key]["transforms"]
		var center := Vector3.ZERO
		for xf in transforms:
			center += xf.origin
		center /= transforms.size()
		var local: Array[Transform3D] = []
		for xf in transforms:
			local.append(xf.translated(-center))
		var batch := MeshKit.batch("FarForest_%02d" % key, pine, local, groups[key]["colors"], false)
		batch.position = center
		batch.set_meta(&"lod_range", far_forest_view_distance)
		batch.add_to_group(&"scenery_lod")
		batch.visibility_range_end = far_forest_view_distance
		batch.visibility_range_end_margin = far_forest_view_distance * 0.15
		batch.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(batch)


func _overlook_side(track: Track, along: float, side: int) -> bool:
	for zone: Array in track.get_zones("overlook"):
		if int(zone[3]) == side and along >= float(zone[0]) - 20.0 and along <= float(zone[1]) + 20.0:
			return true
	return false


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
		colors.append(_theme.hill_colors[0].lerp(_theme.hill_colors[-1], _rng.randf()))
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
	material.emission = _theme.cloud_emission
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
	material.albedo_color = _theme.valley_color
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
	water.albedo_color = _theme.lake_color
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
