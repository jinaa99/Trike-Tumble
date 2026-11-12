extends Node3D
## Natural scenery beside the road, in the style of the track's theme
## (TrackTheme.scenery_style): forest pines, round trees, bushes, boulders and
## flowers; canyon rock spires, dry trees and shrubs; or snow-covered pines,
## snow mounds and snowy boulders, on the slopes outside the barriers. Meshes are batched with
## MultiMesh, one batch per kind and per `batch_length` meters of track, so
## the renderer can cull what is out of view; small things also fade out
## with distance. Solid things (tree trunks, boulders) get matching collision
## so a trike that flies over a barrier can't pass through them. Soft
## foliage (canopies, bushes, flowers) has none.
##
## Nothing grows on bridges, over jump gaps, next to gorge cliffs, on
## "clearing" zones or on the open side of an "overlook" zone.

@export var random_seed := 1234
@export var tree_spacing_samples := 3
@export_range(0.0, 1.0) var tree_chance := 0.8
## Random tree size range (1 = about 5 m tall pine).
@export var tree_scale := Vector2(0.8, 1.45)
## Share of pines (tall + short) among trees; the rest are round trees.
@export_range(0.0, 1.0) var pine_share := 0.7
@export var bush_spacing_samples := 3
@export_range(0.0, 1.0) var bush_chance := 0.55
@export var boulder_spacing_samples := 7
@export_range(0.0, 1.0) var boulder_chance := 0.4
@export var flowers_per_sample := 2
## Grass tufts on the slopes per sample (forest: green, canyon: dry; none on
## snow). Own random sequence, so the other scenery never changes with it.
@export var tufts_per_sample := 3
@export var tuft_view_distance := 110.0
## Track length per MultiMesh batch (m): trees and boulders, and the small
## things that fade out early (bushes, flowers).
@export var batch_length := 300.0
@export var small_batch_length := 60.0
## Fade-out distances (m); 0 = always drawn.
@export var tree_view_distance := 900.0
@export var flower_view_distance := 140.0
@export var bush_view_distance := 260.0
@export var boulder_view_distance := 600.0
## Samples kept free of scenery next to a bridge or gap (gorge cliffs).
@export var cliff_clearance_samples := 4
@export_flags_3d_physics var collision_layer := 1

## No trees on a side whose slope is this much of a cliff wall...
const CLIFF_BLOCK := 0.3
## ...and no bushes, boulders or flowers stuck to the rock face at all.
const CLIFF_LEFT := 8
const CLIFF_RIGHT := 16

## _blocked bits: 1 no trees left, 2 no trees right, 4 no slope at all.
const NO_GROUND := 4

var _rng := RandomNumberGenerator.new()
var _theme: TrackTheme
var _collision: Node3D
var _bodies := {}
var _batch_samples := 150
var _small_batch_samples := 30
var _group_samples := 150
var _blocked := PackedByteArray()


func build_for_track(track: Track) -> void:
	_rng.seed = random_seed
	_theme = track.theme if track.theme else TrackTheme.new()
	_batch_samples = maxi(roundi(batch_length / track.path.spacing), 1)
	_small_batch_samples = maxi(roundi(small_batch_length / track.path.spacing), 1)
	_collision = Node3D.new()
	_collision.name = "SceneryCollision"
	add_child(_collision)
	_build_blocked(track)
	_build_trees(track)
	_build_bushes(track)
	_build_boulders(track)
	_build_flowers(track)
	_build_tufts(track)


## True if no tree may grow at sample i on that side (clearings, overlooks).
func is_blocked(index: int, side: int) -> bool:
	var bit := 1 if side < 0 else 2
	return _blocked[index] & (bit | NO_GROUND) != 0


## True if that side of sample i is (partly) a cliff wall.
func on_cliff(index: int, side: int) -> bool:
	return _blocked[index] & (CLIFF_LEFT if side < 0 else CLIFF_RIGHT) != 0


## True if there is no slope at sample i (bridge, gap, next to a cliff).
func has_no_ground(index: int) -> bool:
	return _blocked[index] & NO_GROUND != 0


func _build_blocked(track: Track) -> void:
	var path := track.path
	_blocked.resize(path.size())
	_blocked.fill(0)
	for i in path.size():
		var distance := i * path.spacing
		if track.in_zone(distance, "clearing"):
			_blocked[i] = 3
	for zone: Array in track.get_zones("overlook"):
		var bit := 1 if int(zone[3]) < 0 else 2
		for i in range(path.index_at_distance(zone[0]), path.index_at_distance(zone[1]) + 1):
			_blocked[i] |= bit
	for i in path.size():
		if track.builder.cliff_weight(i, -1) > CLIFF_BLOCK:
			_blocked[i] |= 1
		if track.builder.cliff_weight(i, 1) > CLIFF_BLOCK:
			_blocked[i] |= 2
		if track.builder.cliff_weight(i, -1) > 0.0:
			_blocked[i] |= CLIFF_LEFT
		if track.builder.cliff_weight(i, 1) > 0.0:
			_blocked[i] |= CLIFF_RIGHT
	for i in path.size():
		if track.get_sample_kind(i) != TrackMeshBuilder.SampleKind.NORMAL:
			for k in range(maxi(i - cliff_clearance_samples, 0), mini(i + cliff_clearance_samples + 1, path.size())):
				_blocked[k] |= NO_GROUND


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
	var style := _theme.scenery_style
	if style == TrackTheme.SceneryStyle.CANYON:
		meshes = {"spire": _spire_mesh(), "dry": _dry_tree_mesh()}
	elif style == TrackTheme.SceneryStyle.SNOW:
		meshes.merge(_snow_cap_meshes())
	var groups := {}
	_group_samples = _batch_samples
	for i in range(0, path.size(), tree_spacing_samples):
		for side: int in [-1, 1]:
			if _rng.randf() > tree_chance or is_blocked(i, side):
				continue
			var s := _rng.randf_range(tree_scale.x, tree_scale.y)
			# Bigger trees stand further out, so canopies never hang over the road.
			var spot := builder.slope_point(path, i, side, _rng.randf_range(maxf(3.0, 2.2 * s), 21.0))
			if _near_road(track, spot, track.half_width_at(i) + 3.0):
				continue
			var roll := _rng.randf()
			var kind := "round" if roll >= pine_share else ("pine_tall" if roll < pine_share * 0.7 else "pine_short")
			var palette := _theme.leaf_greens if kind == "round" else _theme.pine_greens
			if style == TrackTheme.SceneryStyle.CANYON:
				kind = "spire" if roll < pine_share else "dry"
				palette = _theme.boulder_colors if kind == "spire" else _theme.leaf_greens
			var xf := MeshKit.at(spot - Vector3.UP * 0.15, Vector3(0, _rng.randf() * 360.0, 0), Vector3.ONE * s)
			_add(groups, kind, i, xf, palette[_rng.randi() % palette.size()].lightened(_rng.randf_range(0.0, 0.12)))
			if kind == "spire":
				_add_cylinder_collider(i, spot + Vector3.UP * 3.0 * s, 1.1 * s, 6.0 * s)
			else:
				_add_cylinder_collider(i, spot + Vector3.UP * 1.0 * s, 0.3 * s, 2.0 * s)
			if style == TrackTheme.SceneryStyle.SNOW:
				_add(groups, "snow_" + kind, i, xf, _theme.snow_color)
	var material := MeshKit.vertex_color_material(0.9)
	for kind: String in meshes:
		(meshes[kind] as ArrayMesh).surface_set_material(0, material)
	_emit_batches("Trees_", meshes, groups, tree_view_distance)


func _build_bushes(track: Track) -> void:
	var path := track.path
	var bush := MeshKit.combine([
		[MeshKit.sphere(0.7, 7, 4), MeshKit.at(Vector3(0, 0.35, 0), Vector3.ZERO, Vector3(1, 0.8, 1)), Color(1, 1, 1)],
		[MeshKit.sphere(0.55, 7, 4), MeshKit.at(Vector3(0.6, 0.3, 0.2), Vector3.ZERO, Vector3(1, 0.8, 1)), Color(0.9, 0.9, 0.9)],
		[MeshKit.sphere(0.5, 7, 4), MeshKit.at(Vector3(-0.5, 0.28, -0.25), Vector3.ZERO, Vector3(1, 0.8, 1)), Color(0.95, 0.95, 0.95)],
	])
	bush.surface_set_material(0, MeshKit.vertex_color_material(0.9))
	var groups := {}
	_group_samples = _small_batch_samples
	for i in range(0, path.size(), bush_spacing_samples):
		for side: int in [-1, 1]:
			if _rng.randf() > bush_chance or has_no_ground(i) or on_cliff(i, side):
				continue
			var spot := track.builder.slope_point(path, i, side, _rng.randf_range(0.5, 3.0))
			if _near_road(track, spot, track.half_width_at(i) + 1.0):
				continue
			_add(groups, "Bushes", i, MeshKit.at(spot - Vector3.UP * 0.1, Vector3(0, _rng.randf() * 360.0, 0), Vector3.ONE * _rng.randf_range(0.7, 1.2)),
					_bush_color())
	_emit_batches("", {"Bushes": bush}, groups, bush_view_distance)


func _bush_color() -> Color:
	# Same random draws, in the same order, as before themes (forest unchanged).
	var tone := _rng.randi() % 2
	var shade := _rng.randf_range(0.0, 0.2)
	if _theme.scenery_style == TrackTheme.SceneryStyle.SNOW:
		return _theme.snow_color.darkened(shade * 0.3)  # snow mounds
	return _theme.leaf_greens[tone % _theme.leaf_greens.size()].darkened(shade)


func _build_boulders(track: Track) -> void:
	var path := track.path
	var rock_shape_mesh := MeshKit.sphere(1.0, 7, 4)
	var rock := MeshKit.combine([[rock_shape_mesh, Transform3D.IDENTITY, Color(1, 1, 1)]])
	rock.surface_set_material(0, MeshKit.vertex_color_material(1.0))
	var rock_points: PackedVector3Array = rock_shape_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var groups := {}
	_group_samples = _batch_samples
	for i in range(0, path.size(), boulder_spacing_samples):
		for side: int in [-1, 1]:
			if _rng.randf() > boulder_chance or has_no_ground(i) or on_cliff(i, side):
				continue
			var spot := track.builder.slope_point(path, i, side, _rng.randf_range(2.0, 20.0))
			if _near_road(track, spot, track.half_width_at(i) + 3.0):
				continue
			var size := Vector3(_rng.randf_range(0.9, 2.2), _rng.randf_range(0.6, 1.4), _rng.randf_range(0.9, 2.0))
			var xf := MeshKit.at(spot, Vector3(_rng.randf_range(-15, 15), _rng.randf() * 360.0, _rng.randf_range(-15, 15)), size)
			_add(groups, "Boulders", i, xf, _theme.boulder_colors[0].lerp(_theme.boulder_colors[-1], _rng.randf()))
			if _theme.scenery_style == TrackTheme.SceneryStyle.SNOW:
				_add(groups, "BoulderSnow", i, xf, _theme.snow_color)
			var shape := ConvexPolygonShape3D.new()
			var points := PackedVector3Array()
			for p in rock_points:
				points.append(xf.basis * p)
			shape.points = points
			var collider := CollisionShape3D.new()
			collider.shape = shape
			collider.position = xf.origin
			_body_for(i).add_child(collider)
	var snow_cap := MeshKit.combine([[MeshKit.sphere(1.0, 7, 4), MeshKit.at(Vector3(0, 0.35, 0), Vector3.ZERO,
			Vector3(0.92, 0.7, 0.92)), Color(1, 1, 1)]])
	snow_cap.surface_set_material(0, MeshKit.vertex_color_material(0.6))
	_emit_batches("", {"Boulders": rock, "BoulderSnow": snow_cap}, groups, boulder_view_distance)


func _build_flowers(track: Track) -> void:
	if _theme.flower_colors.is_empty():
		return
	var path := track.path
	var flower := MeshKit.combine([
		[MeshKit.cylinder(0.015, 0.015, 0.3, 3), MeshKit.at(Vector3(0, 0.15, 0)), Color(0.3, 0.6, 0.25)],
		[MeshKit.sphere(0.09, 6, 3), MeshKit.at(Vector3(0, 0.32, 0), Vector3.ZERO, Vector3(1, 0.6, 1)), Color(1, 1, 1)],
	])
	flower.surface_set_material(0, MeshKit.vertex_color_material(0.8))
	var groups := {}
	_group_samples = _small_batch_samples
	for i in path.size():
		for n in flowers_per_sample:
			var side := -1 if _rng.randf() < 0.5 else 1
			var outward := _rng.randf_range(0.3, 12.0)
			if has_no_ground(i) or on_cliff(i, side):
				continue
			var spot := track.builder.slope_point(path, i, side, outward)
			_add(groups, "Flowers", i, MeshKit.at(spot, Vector3(0, _rng.randf() * 360.0, 0), Vector3.ONE * _rng.randf_range(0.8, 1.6)),
					_theme.flower_colors[_rng.randi() % _theme.flower_colors.size()])
	_emit_batches("", {"Flowers": flower}, groups, flower_view_distance, false)


func _build_tufts(track: Track) -> void:
	if tufts_per_sample <= 0 or _theme.scenery_style == TrackTheme.SceneryStyle.SNOW:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed + 77
	var blades := []
	for k in 5:
		var angle := k * TAU / 5.0
		blades.append([MeshKit.cone(0.05, 0.34 + 0.08 * (k % 2), 3),
				MeshKit.at(Vector3(cos(angle) * 0.06, 0.15, sin(angle) * 0.06), Vector3(cos(angle) * 18.0, 0, sin(angle) * 18.0)),
				Color(1, 1, 1) if k % 2 == 0 else Color(0.85, 0.85, 0.85)])
	var tuft := MeshKit.combine(blades)
	tuft.surface_set_material(0, MeshKit.vertex_color_material(0.9))
	var dry := _theme.scenery_style == TrackTheme.SceneryStyle.CANYON
	var tones: Array[Color] = [_theme.grass_colors[0].darkened(0.08), _theme.grass_colors[1].darkened(0.12)]
	if dry:
		tones = [Color(0.86, 0.74, 0.42), Color(0.74, 0.62, 0.36)]
	var groups := {}
	_group_samples = _small_batch_samples
	var path := track.path
	for i in path.size():
		if has_no_ground(i):
			continue
		for n in tufts_per_sample:
			var side := -1 if rng.randf() < 0.5 else 1
			if on_cliff(i, side):
				continue
			var spot := track.builder.slope_point(path, i, side, rng.randf_range(0.4, 9.0))
			_add(groups, "Tufts", i, MeshKit.at(spot, Vector3(0, rng.randf() * 360.0, 0), Vector3.ONE * rng.randf_range(0.8, 1.5)),
					tones[rng.randi() % tones.size()])
	_emit_batches("", {"Tufts": tuft}, groups, tuft_view_distance, false)


# --- Theme meshes (white/gray vertex colors, tinted per instance) ---------------

## Canyon hoodoo: stacked, tapering rock drums with light and dark layers.
func _spire_mesh() -> ArrayMesh:
	var parts := []
	var y := 0.0
	var radius := 1.25
	for k in 5:
		var height := 1.9 - k * 0.15
		var top := radius * 0.82
		parts.append([MeshKit.cylinder(top, radius, height, 7), MeshKit.at(Vector3(0, y + height * 0.5, 0), Vector3(0, k * 23.0, 0)),
				Color(1, 1, 1) if k % 2 == 0 else Color(0.8, 0.78, 0.76)])
		y += height
		radius = top
	parts.append([MeshKit.box(Vector3(1.5, 0.35, 1.3)), MeshKit.at(Vector3(0.1, y + 0.15, 0), Vector3(0, 15, 6)), Color(0.88, 0.86, 0.84)])
	return MeshKit.combine(parts)


## Canyon dry tree: thin crooked trunk with a few small leaf clumps.
func _dry_tree_mesh() -> ArrayMesh:
	return MeshKit.combine([
		[MeshKit.cylinder(0.1, 0.18, 2.2, 5), MeshKit.at(Vector3(0, 1.1, 0), Vector3(0, 0, 8)), Color(0.55, 0.42, 0.32)],
		[MeshKit.cylinder(0.06, 0.09, 1.2, 4), MeshKit.at(Vector3(0.45, 2.1, 0), Vector3(0, 0, -40)), Color(0.55, 0.42, 0.32)],
		[MeshKit.sphere(0.75, 6, 4), MeshKit.at(Vector3(0.1, 2.5, 0), Vector3.ZERO, Vector3(1.2, 0.6, 1.0)), Color(1, 1, 1)],
		[MeshKit.sphere(0.55, 6, 4), MeshKit.at(Vector3(0.9, 2.55, 0.2), Vector3.ZERO, Vector3(1.1, 0.6, 1.0)), Color(0.9, 0.9, 0.9)],
	])


## White snow layers that sit on the forest tree meshes (same transforms).
func _snow_cap_meshes() -> Dictionary:
	return {
		"snow_pine_tall": MeshKit.combine([
			[MeshKit.cone(1.45, 0.75), MeshKit.at(Vector3(0, 2.62, 0)), Color(1, 1, 1)],
			[MeshKit.cone(1.12, 0.65), MeshKit.at(Vector3(0, 3.62, 0), Vector3(0, 25, 0)), Color(1, 1, 1)],
			[MeshKit.cone(0.75, 0.65), MeshKit.at(Vector3(0, 4.55, 0), Vector3(0, 50, 0)), Color(1, 1, 1)],
		]),
		"snow_pine_short": MeshKit.combine([
			[MeshKit.cone(1.18, 0.7), MeshKit.at(Vector3(0, 2.1, 0)), Color(1, 1, 1)],
			[MeshKit.cone(0.8, 0.65), MeshKit.at(Vector3(0, 2.95, 0), Vector3(0, 30, 0)), Color(1, 1, 1)],
		]),
		"snow_round": MeshKit.combine([
			[MeshKit.sphere(1.0), MeshKit.at(Vector3(0, 3.55, 0), Vector3.ZERO, Vector3(1.05, 0.5, 1.05)), Color(1, 1, 1)],
		]),
	}


# --- Batching ----------------------------------------------------------------

func _add(groups: Dictionary, kind: String, index: int, xf: Transform3D, color: Color) -> void:
	@warning_ignore("integer_division")
	var batch := index / _group_samples
	var key := Vector2i(hash(kind), batch)
	if not groups.has(key):
		groups[key] = {"kind": kind, "batch": batch, "transforms": [] as Array[Transform3D], "colors": [] as Array[Color]}
	var group: Dictionary = groups[key]
	(group["transforms"] as Array[Transform3D]).append(xf)
	(group["colors"] as Array[Color]).append(color)


func _emit_batches(prefix: String, meshes: Dictionary, groups: Dictionary, view_distance: float, shadows := true) -> void:
	for key: Vector2i in groups:
		var group: Dictionary = groups[key]
		var kind: String = group["kind"]
		# Batch node at the center of its instances: culling and fade
		# distances are measured from there.
		var transforms: Array[Transform3D] = group["transforms"]
		var center := Vector3.ZERO
		for xf in transforms:
			center += xf.origin
		center /= transforms.size()
		var local: Array[Transform3D] = []
		for xf in transforms:
			local.append(xf.translated(-center))
		var instance := MeshKit.batch("%s%s_%02d" % [prefix, kind, group["batch"]], meshes[kind],
				local, group["colors"], shadows)
		instance.position = center
		if view_distance > 0.0:
			set_view_distance(instance, view_distance)
		add_child(instance)


## Fades `instance` out beyond `distance`. The graphics quality setting
## scales it (GameSettings.apply_graphics, group "scenery_lod").
static func set_view_distance(instance: GeometryInstance3D, distance: float) -> void:
	instance.set_meta(&"lod_range", distance)
	instance.add_to_group(&"scenery_lod")
	instance.visibility_range_end = distance
	instance.visibility_range_end_margin = distance * 0.15
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


func _body_for(index: int) -> StaticBody3D:
	@warning_ignore("integer_division")
	var batch := index / _batch_samples
	if not _bodies.has(batch):
		var body := StaticBody3D.new()
		body.name = "Scenery_%02d" % batch
		body.collision_layer = collision_layer
		body.collision_mask = 0
		_collision.add_child(body)
		_bodies[batch] = body
	return _bodies[batch]


func _add_cylinder_collider(index: int, center: Vector3, radius: float, height: float) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = center
	_body_for(index).add_child(collider)


## True if `spot` is close (horizontally) to any road sample at a similar
## height, so scenery never sits on or hovers over another road section.
func _near_road(track: Track, spot: Vector3, clearance: float) -> bool:
	var path := track.path
	for i in path.samples_near(spot, clearance + 8.0):
		var p := path.points[i]
		if absf(spot.y - p.y) < 25.0 and Vector2(spot.x - p.x, spot.z - p.z).length() < maxf(clearance, track.half_width_at(i) + 3.0):
			return true
	return false
