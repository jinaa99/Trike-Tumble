class_name Track
extends Node3D
## A procedurally built downhill track.
##
## The centerline comes from `route_segments` (arcs and straights, see
## TrackRoute) or, if that is empty, straight from `control_points`. The
## road width can vary along the track (`width_profile`), and `zones` mark
## bridges, jump gaps, mud, overlooks and clearings. On _ready the track
## builds its road, walls, slopes, collision (in chunks), start/finish
## gates and finish trigger, then calls `build_for_track(track)` on any child
## that has it (props, decor, structures).
## Race logic asks the track for spawn/respawn transforms and bounds.

signal finish_crossed(body: Node3D)

const GATE_SCRIPT := preload("res://scripts/track/track_gate.gd")

## Used only when `route_segments` is empty.
@export var control_points := PackedVector3Array()
@export_group("Route")
## Vector3(length m, turn deg (+ = left), grade % downhill) per segment.
@export var route_segments := PackedVector3Array()
@export var route_start := Vector3(0.0, 120.0, 0.0)
## Starting heading (0 = toward -Z, + = turned left).
@export var route_heading_deg := 0.0
## Spacing of the generated control points (m).
@export var route_step := 8.0
@export_group("")
@export var sample_spacing := 2.0
## Default road width; `width_profile` overrides it along the track.
@export var road_width := 14.0
## (distance m, width m) keys, eased between keys. Empty = `road_width`.
@export var width_profile := PackedVector2Array()
## Track features: [start m, end m, kind, ...]. Kinds:
##   "bridge"            plank deck and parapets over an open gorge
##   "gap"               jump gap: no road (needs a kicker ramp before it)
##   "mud", u0, u1       mud band across the road (0 = left edge, 1 = right)
##   "overlook", side    viewpoint on one side (-1 left, 1 right): no trees there
##   "clearing"          no trees on either side
##   "rocks"             rock pillars right behind both barriers (narrows)
##   "ice", u0, u1       ice band across the road (low grip, see TrikeConfig)
##   "cliff", side       the slope on that side rises as a rock wall (-1 left, 1 right)
##   "wind", side, m/s²  gusty crosswind pushing toward that side (snow passes)
@export var zones: Array = []
## Look of the map (paint, scenery, sky); null = the default forest look.
@export var theme: TrackTheme
## Ground of the plain road (Snow Slide: SNOW) and of bridge decks
## (frozen bridges: ICE). Forest Rush and the test track: ROAD and WOOD.
@export var road_surface := TrackSurface.Kind.ROAD
@export var bridge_surface := TrackSurface.Kind.WOOD
## Cliff walls and wind fade in and out over this length (m).
@export var zone_blend := 16.0
## Gust cycle of "wind" zones (s); the push varies from 35 % to 100 %.
@export var wind_gust_period := 5.0
@export var wall_height := 1.1
@export var start_distance := 14.0
## Road left after the finish line (m). The real maps use 90 m, enough for a
## finished trike to brake to a stop before the end wall.
@export var finish_distance_from_end := 30.0
## Spacing between grid slots on the start line (for up to 5 racers).
@export var grid_slot_spacing := Vector2(2.6, 3.5)
## Ordered race checkpoints every this many meters after the start; the
## finish line is always the last one.
@export var checkpoint_spacing := 100.0
## No intermediate checkpoint closer than this to the finish line (m).
@export var checkpoint_finish_gap := 20.0
## Seconds the race keeps going after the first finisher (longer maps
## spread the field out more). RaceSession hands it to RaceController.
@export var finish_timeout := 45.0
## Falling this far below the road counts as out of bounds.
@export var out_of_bounds_depth := 12.0
## Horizontal distance from the centerline that counts as out of bounds.
@export var out_of_bounds_radius := 45.0
## No respawn this far before a jump gap (the run-up needs room to speed up).
@export var gap_unsafe_before := 45.0
## Nor just after it (the landing zone).
@export var gap_unsafe_after := 12.0
## Samples per mesh/collision chunk.
@export var chunk_samples := 60
## Item box rows (distance m); boxes are spread across the road.
@export var item_box_rows := PackedFloat32Array()
@export var item_box_columns := 3
@export_flags_3d_physics var collision_layer := 1

var path := TrackPath.new()
var builder := TrackMeshBuilder.new()
## Race clock for timed hazards (falling logs); RacerManager sets it each
## tick, so every computer sees hazards at the same race time.
var hazard_time := 0.0
## Milliseconds per build stage (profiling, map tests).
var build_timings := {}

var _checkpoints := PackedInt32Array()
var _unsafe := PackedByteArray()


func _ready() -> void:
	build()


func build() -> void:
	if theme == null:
		theme = TrackTheme.new()
	build_timings.clear()
	var t := Time.get_ticks_usec()
	if not route_segments.is_empty():
		control_points = TrackRoute.build_points(route_start, route_heading_deg, route_segments, route_step)
	path.build(control_points, sample_spacing, road_width, width_profile)
	t = _time_stage("path", t)
	_classify_samples()
	builder.road_width = road_width
	builder.wall_height = wall_height
	builder.chunk_samples = chunk_samples
	theme.apply_to_builder(builder)
	builder.build(path)
	t = _time_stage("geometry", t)
	_add_chunks()
	t = _time_stage("nodes", t)

	var body := get_node("TrackBody") as StaticBody3D
	_add_end_blocker(body, 0, 1.0)
	_add_end_blocker(body, path.size() - 1, -1.0)
	_add_gate("StartGate", path.index_at_distance(start_distance - 4.0), false, "TRIKE TUMBLE")
	var finish_index := path.index_at_distance(path.length - finish_distance_from_end)
	_add_gate("FinishGate", finish_index, true, "FINISH")
	_add_finish_trigger(finish_index)
	_build_checkpoints(finish_index)
	t = _time_stage("gates", t)

	for child in get_children():
		if child.has_method("build_for_track"):
			child.build_for_track(self)
			t = _time_stage(String(child.name), t)
	var total := 0.0
	for stage: String in build_timings:
		total += build_timings[stage]
	build_timings["total"] = total


# --- Queries ----------------------------------------------------------------

func get_start_index() -> int:
	return path.index_at_distance(start_distance)


## Grid slot 0 is the pole (center), then alternating left/right rows.
func get_start_transform(slot: int) -> Transform3D:
	@warning_ignore("integer_division")
	var row := (slot + 1) / 2
	var side := 0.0 if slot == 0 else (-1.0 if slot % 2 == 1 else 1.0)
	# Exact distance (not rounded to a path sample), so rows keep their spacing.
	var distance := maxf(start_distance - row * grid_slot_spacing.y, 0.0)
	var index := clampi(floori(distance / path.spacing), 0, path.size() - 1)
	var frame := path.get_frame(index)
	var remainder := distance - index * path.spacing
	frame.origin += -frame.basis.z * remainder
	frame.origin += frame.basis.x * side * grid_slot_spacing.x * (1.0 + row * 0.3) + frame.basis.y * 0.8
	return frame


func get_respawn_transform(index: int, lateral := 0.0) -> Transform3D:
	var frame := path.get_frame(index)
	frame.origin += frame.basis.x * lateral + frame.basis.y * 1.0
	return frame


## Half the road width at a sample (barrier to centerline).
func half_width_at(index: int) -> float:
	return path.widths[clampi(index, 0, path.size() - 1)] * 0.5


func is_on_road(position: Vector3, index: int) -> bool:
	if builder.sample_kinds[index] == TrackMeshBuilder.SampleKind.GAP:
		return false
	var offset := position - path.points[index]
	return absf(offset.dot(path.rights[index])) < half_width_at(index) + 0.5 \
			and absf(offset.dot(path.ups[index])) < 3.0


func is_out_of_bounds(position: Vector3, index: int) -> bool:
	var center := path.points[index]
	var flat := Vector2(position.x - center.x, position.z - center.z)
	return position.y < center.y - out_of_bounds_depth or flat.length() > out_of_bounds_radius


## False where a racer must not be put back: in and before jump gaps, and
## around obstacles and hazards on the road (props mark those).
func is_safe_index(index: int) -> bool:
	return _unsafe[clampi(index, 0, path.size() - 1)] == 0


## Marks a stretch of road as unsafe for respawns (meters along the track).
func mark_unsafe(from_distance: float, to_distance: float) -> void:
	for i in range(path.index_at_distance(from_distance), path.index_at_distance(to_distance) + 1):
		_unsafe[i] = 1


## Nearest safe sample at or before `index` (recovery point).
func get_recovery_index(index: int) -> int:
	for i in range(clampi(index, 0, path.size() - 1), -1, -1):
		if _unsafe[i] == 0:
			return i
	return get_start_index()


func get_sample_kind(index: int) -> TrackMeshBuilder.SampleKind:
	return builder.sample_kinds[clampi(index, 0, path.size() - 1)] as TrackMeshBuilder.SampleKind


## Road surface between sample `index` and the next one, `lateral` m from
## the centerline (map tests, AI).
func surface_at(index: int, lateral := 0.0) -> TrackSurface.Kind:
	match builder.quad_kind(clampi(index, 0, path.size() - 2)):
		TrackMeshBuilder.SampleKind.BRIDGE:
			return bridge_surface
		TrackMeshBuilder.SampleKind.GAP:
			return TrackSurface.Kind.GRASS
	var mud := builder.mud_bands[index]
	var u := 0.5 + lateral / (half_width_at(index) * 2.0)
	if mud.y > mud.x and u >= mud.x and u <= mud.y:
		return builder.band_kinds[index] as TrackSurface.Kind
	return road_surface


## Crosswind acceleration (m/s², horizontal) at sample `index` and the
## current race clock: zero outside "wind" zones. A pure function of
## `hazard_time`, so every computer pushes its own trikes identically.
func wind_at(index: int) -> Vector3:
	if index < 0 or index >= path.size():
		return Vector3.ZERO
	var distance := index * path.spacing
	for zone: Array in zones:
		if zone[2] != "wind" or distance < float(zone[0]) or distance > float(zone[1]):
			continue
		var fade := clampf(minf(distance - float(zone[0]), float(zone[1]) - distance) / maxf(zone_blend, 0.01), 0.0, 1.0)
		var gust := 0.35 + 0.65 * maxf(sin(TAU * hazard_time / maxf(wind_gust_period, 0.1) + float(zone[0]) * 0.01), 0.0)
		return path.rights[index] * signf(float(zone[3])) * float(zone[4]) * gust * fade
	return Vector3.ZERO


## Zones of one kind: [start m, end m, kind, ...] entries.
func get_zones(kind: String) -> Array:
	var found := []
	for zone: Array in zones:
		if zone[2] == kind:
			found.append(zone)
	return found


func in_zone(distance: float, kind: String, margin := 0.0) -> bool:
	for zone: Array in zones:
		if zone[2] == kind and distance >= float(zone[0]) - margin and distance <= float(zone[1]) + margin:
			return true
	return false


## Item box spawn points: `item_box_columns` boxes across the road per row.
func get_item_box_transforms() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for distance in item_box_rows:
		var index := path.index_at_distance(distance)
		var frame := path.get_frame(index)
		var usable := half_width_at(index) - 2.0
		for c in item_box_columns:
			var u := 0.0 if item_box_columns == 1 else lerpf(-1.0, 1.0, float(c) / (item_box_columns - 1))
			out.append(frame.translated_local(Vector3(u * usable, 1.0, 0.0)))
	return out


func get_finish_index() -> int:
	return path.index_at_distance(path.length - finish_distance_from_end)


## Ordered checkpoint path indices, strictly increasing; the last one is the
## finish line.
func get_checkpoints() -> PackedInt32Array:
	return _checkpoints


func _build_checkpoints(finish_index: int) -> void:
	_checkpoints.clear()
	var finish_distance := finish_index * path.spacing
	var distance := start_distance + checkpoint_spacing
	while distance < finish_distance - checkpoint_finish_gap:
		_checkpoints.append(path.index_at_distance(distance))
		distance += checkpoint_spacing
	_checkpoints.append(finish_index)


# --- Construction helpers ---------------------------------------------------

func _time_stage(stage: String, since_usec: int) -> int:
	var now := Time.get_ticks_usec()
	build_timings[stage] = (now - since_usec) / 1000.0
	return now


## Sample kinds, mud bands and unsafe stretches from `zones`.
func _classify_samples() -> void:
	var count := path.size()
	var kinds := PackedByteArray()
	kinds.resize(count)
	kinds.fill(TrackMeshBuilder.SampleKind.NORMAL)
	var mud := PackedVector2Array()
	mud.resize(count)
	mud.fill(Vector2.ZERO)
	var band_kinds := PackedByteArray()
	band_kinds.resize(count)
	band_kinds.fill(TrackSurface.Kind.MUD)
	var cliffs: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array()]
	for slot in 2:
		cliffs[slot].resize(count)
		cliffs[slot].fill(0.0)
	var blend := maxf(zone_blend / path.spacing, 1.0)
	_unsafe.resize(count)
	_unsafe.fill(0)
	for zone: Array in zones:
		var first := path.index_at_distance(zone[0])
		var last := path.index_at_distance(zone[1])
		match String(zone[2]):
			"bridge":
				for i in range(first, last + 1):
					kinds[i] = maxi(kinds[i], TrackMeshBuilder.SampleKind.BRIDGE)
			"gap":
				for i in range(first, last + 1):
					kinds[i] = TrackMeshBuilder.SampleKind.GAP
			"mud", "ice":
				for i in range(first, last + 1):
					mud[i] = Vector2(zone[3], zone[4])
					band_kinds[i] = TrackSurface.Kind.ICE if zone[2] == "ice" else TrackSurface.Kind.MUD
			"cliff":
				var slot := 0 if int(zone[3]) < 0 else 1
				for i in range(maxi(first - ceili(blend), 0), mini(last + ceili(blend), count - 1) + 1):
					var inside := minf(float(i - first), float(last - i))
					cliffs[slot][i] = maxf(cliffs[slot][i], clampf((inside + blend) / blend, 0.0, 1.0))
	builder.sample_kinds = kinds
	builder.mud_bands = mud
	builder.band_kinds = band_kinds
	builder.cliff_weights = cliffs
	for zone: Array in get_zones("gap"):
		mark_unsafe(float(zone[0]) - gap_unsafe_before, float(zone[1]) + gap_unsafe_after)


## Render chunks and the collision bodies (one per surface kind).
func _add_chunks() -> void:
	var bodies := {
		"road": _surface_body("TrackBody", TrackSurface.Kind.ROAD),
		"mud": _surface_body("MudBody", TrackSurface.Kind.MUD),
		"ice": _surface_body("IceBody", TrackSurface.Kind.ICE),
		"wood": _surface_body("BridgeBody", bridge_surface),
		"slope": _surface_body("SlopeBody", TrackSurface.Kind.GRASS),
	}
	# The plain road's own surface (snow on Snow Slide). Walls and cliffs
	# share its body; wheels only touch them in a crash.
	if road_surface != TrackSurface.Kind.ROAD:
		TrackSurface.tag(bodies["road"], road_surface)
	bodies["wall"] = bodies["road"]
	bodies["cliff"] = bodies["road"]
	var road_material := TrackMaterials.road()
	var wall_material := TrackMaterials.barrier()
	var grass_material := TrackMaterials.grass()
	for c in builder.chunks.size():
		var chunk: Dictionary = builder.chunks[c]
		var suffix := "" if builder.chunks.size() == 1 else "_%02d" % c
		_add_mesh("Road" + suffix, chunk["road"], road_material)
		_add_mesh("Walls" + suffix, chunk["walls"], wall_material)
		_add_mesh("Slopes" + suffix, chunk["slopes"], grass_material)
		var faces: Dictionary = chunk["faces"]
		for category: String in faces:
			var list: PackedVector3Array = faces[category]
			if list.is_empty():
				continue
			var shape := ConcavePolygonShape3D.new()
			shape.backface_collision = true
			shape.set_faces(list)
			var collider := CollisionShape3D.new()
			collider.name = "%s%s" % [category.capitalize(), suffix]
			collider.shape = shape
			(bodies[category] as StaticBody3D).add_child(collider)
	for key: String in ["mud", "ice", "wood", "slope"]:
		var body: StaticBody3D = bodies[key]
		if body.get_child_count() == 0:
			body.free()


func _surface_body(node_name: String, kind: TrackSurface.Kind) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = collision_layer
	body.collision_mask = 0
	if kind != TrackSurface.Kind.ROAD:
		TrackSurface.tag(body, kind)
	add_child(body)
	return body


func _add_mesh(node_name: String, mesh: ArrayMesh, material: Material) -> void:
	if mesh == null:
		return
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	add_child(instance)


## Invisible-ish wall closing the road at the start and end.
func _add_end_blocker(body: StaticBody3D, index: int, push_dir: float) -> void:
	var frame := path.get_frame(index)
	var shape := BoxShape3D.new()
	shape.size = Vector3(half_width_at(index) * 2.0 + 4.0, 4.0, 1.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.transform = frame
	collider.position += frame.basis.y * 1.5 + frame.basis.z * push_dir * 0.5
	body.add_child(collider)

	var mesh := BoxMesh.new()
	mesh.size = shape.size
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = theme.end_blocker_color
	material.albedo_texture = TrackMaterials.detail_texture(0.8, 0.2)
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	visual.material_override = material
	visual.transform = collider.transform
	add_child(visual)


func _add_gate(node_name: String, index: int, checkered: bool, title: String) -> void:
	var gate: Node3D = GATE_SCRIPT.new()
	gate.name = node_name
	gate.span = half_width_at(index) * 2.0 + 1.4
	gate.checkered = checkered
	gate.title = title
	gate.transform = path.get_frame(index)
	add_child(gate)


func _add_finish_trigger(index: int) -> void:
	var area := Area3D.new()
	area.name = "FinishTrigger"
	area.collision_layer = 0
	area.collision_mask = 2  # vehicles
	area.monitorable = false
	var shape := BoxShape3D.new()
	shape.size = Vector3(half_width_at(index) * 2.0 + 2.0, 6.0, 2.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 2.5
	area.add_child(collider)
	area.transform = path.get_frame(index)
	area.body_entered.connect(func(body: Node3D) -> void: finish_crossed.emit(body))
	add_child(area)
