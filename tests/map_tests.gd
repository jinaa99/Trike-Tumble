extends RefCounted
## Map tests for every playable map (Forest Rush since milestone 06, Rocky
## Canyon and Snow Slide since milestone 08): build and profile, route layout,
## spawns, checkpoints, item box points, recovery points, collision coverage
## and surfaces, road boundaries, scenery clearance, jumps, bridges, timed
## hazards, the map's sky, one hard AI driving the whole route, plus each
## map's own features (Forest mud and off-road; Canyon cliffs and rocks; Snow
## ice, snow grip and wind). Run as part of tests/test_runner.gd
## (`-- --only=map`; `-- --only=map --map=snow_slide` for one map). Full
## five-racer races at every difficulty and timings: tests/map_test_runner.tscn.

const AI_CONFIGS: Array[AIDriverConfig] = [
	preload("res://resources/ai/ai_easy.tres"),
	preload("res://resources/ai/ai_medium.tres"),
	preload("res://resources/ai/ai_hard.tres"),
]
## Every playable map and what its data must contain.
const MAPS: Array[Dictionary] = [
	{"id": "forest_rush", "name": "Forest Rush", "node": "ForestRush", "length": Vector2(6500, 8000),
		"race": preload("res://scenes/main/forest_rush.tscn"), "track": preload("res://scenes/tracks/forest_rush.tscn"),
		"bridges": 2, "gaps": 1, "offroad_at": 1400.0},
	{"id": "rocky_canyon", "name": "Rocky Canyon", "node": "RockyCanyon", "length": Vector2(6500, 8000),
		"race": preload("res://scenes/main/rocky_canyon.tscn"), "track": preload("res://scenes/tracks/rocky_canyon.tscn"),
		"bridges": 2, "gaps": 2, "offroad_at": 1280.0},
	{"id": "snow_slide", "name": "Snow Slide", "node": "SnowSlide", "length": Vector2(6500, 8000),
		"race": preload("res://scenes/main/snow_slide.tscn"), "track": preload("res://scenes/tracks/snow_slide.tscn"),
		"bridges": 2, "gaps": 1, "offroad_at": 1290.0},
]
## Road collision bodies (drivable surfaces).
const ROAD_BODIES: Array[String] = ["TrackBody", "MudBody", "IceBody", "BridgeBody"]

var runner: Node
## The map being tested (one of MAPS) and its name for the output.
var spec: Dictionary
var label := ""


func _init(test_runner: Node) -> void:
	runner = test_runner


func run() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			only = arg.trim_prefix("--map=")
	for map_spec in MAPS:
		if only.is_empty() or only == map_spec["id"]:
			await _run_map(map_spec)


func _run_map(map_spec: Dictionary) -> void:
	spec = map_spec
	label = spec["name"]
	var main := await _load_race()
	await _test_build_and_profile(main)
	_test_route_layout(main.track)
	match spec["id"]:
		"forest_rush":
			_test_forest_sections(main.track)
		"rocky_canyon":
			_test_canyon_sections(main.track)
		"snow_slide":
			_test_snow_sections(main.track)
	_test_sky(main)
	await _test_spawns(main)
	await _test_checkpoints(main.track)
	await _test_item_boxes(main.track)
	_test_item_boxes_in_race(main)
	await _test_recovery_points(main.track)
	await _test_collision_coverage(main.track)
	await _test_road_boundaries(main.track)
	_test_scenery_clearance(main.track)
	main.race.start_immediately()
	match spec["id"]:
		"forest_rush":
			await _test_mud(main)
		"rocky_canyon":
			await _test_cliff_walls(main)
		"snow_slide":
			await _test_ice(main)
			await _test_snow_road(main)
			await _test_wind(main)
	await _test_offroad(main)
	await _test_big_jumps(main)
	await _test_jump_too_slow(main)
	await _test_bridges(main)
	await _test_hazards(main)
	await _test_finish_runoff(main)
	await _free(main)
	await _test_ai_full_route()


# --- Helpers ----------------------------------------------------------------

func _check(condition: bool, test_name: String, detail := "") -> void:
	runner._check(condition, test_name, detail)


func _tree() -> SceneTree:
	return runner.get_tree()


func _wait(seconds: float) -> void:
	await runner._wait(seconds)


func _free(node: Node) -> void:
	node.queue_free()
	await _tree().process_frame


## The map's race scene: the local racer plus 4 AI, waiting in the lobby.
func _load_race() -> RaceSession:
	if runner._arena:
		runner._arena.queue_free()
		runner._arena = null
		await _tree().process_frame
	var main: RaceSession = (spec["race"] as PackedScene).instantiate()
	main.auto_start = false
	runner.add_child(main)
	main.trike.input_source = null
	main.rider.input_source = null
	await _tree().physics_frame
	await _tree().physics_frame
	return main


## Straight down from `from`: {position, collider} or {} if nothing within
## `depth`. `track_only` ignores props standing on the road.
func _ray_down(track: Track, from: Vector3, depth := 6.0, track_only := false) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * depth, 1)
	if track_only:
		var exclude: Array[RID] = []
		for child in track.get_node("Props").get_children():
			if child is CollisionObject3D:
				exclude.append((child as CollisionObject3D).get_rid())
		query.exclude = exclude
	return track.get_world_3d().direct_space_state.intersect_ray(query)


func _ray(track: Track, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	return track.get_world_3d().direct_space_state.intersect_ray(query)


func _is_road_body(collider: Object) -> bool:
	return collider is Node and ROAD_BODIES.has(String((collider as Node).name))


func _solid_props(track: Track) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for child in track.get_node("Props").get_children():
		# Props a racer must not be put down next to.
		if child is RoadBoulder or child is RoadTree or child is FallingLog or child is RollingRock or child is Ramp:
			found.append(child)
	return found


## Puts the local trike (rider aboard) on the road `distance` m along the
## track, at rest.
func _place(main: RaceSession, distance: float, lateral := 0.0) -> int:
	if not main.rider.is_riding():
		main.rider.force_mount()
	var index := main.track.path.index_at_distance(distance)
	main.trike.teleport(main.track.path.get_frame(index).translated_local(Vector3(lateral, 0.8, 0.0)))
	main.get_progress().reset(index)
	main.get_local_racer().checkpoints.force_passed_through(index)
	await _tree().physics_frame
	await _tree().physics_frame
	return index


## Drives the local trike along the centerline at full throttle (steering
## only) until it passes `to_distance` or `seconds` run out. Returns
## {"time", "max_impact", "respawns", "surfaces": {kind: ticks}, "min_speed"}.
func _drive(main: RaceSession, to_distance: float, seconds: float, target_speed := 40.0) -> Dictionary:
	var pilot := TrackAutopilot.new(main.track, main.trike)
	pilot.target_speed = target_speed
	var result := {"time": 0.0, "max_impact": 0.0, "respawns": 0, "surfaces": {}, "speeds": []}
	var respawns_before := main.get_local_racer().respawn_count
	var to_index := main.track.path.index_at_distance(to_distance)
	var t := 0.0
	while t < seconds and main.get_progress().current_index < to_index:
		pilot.drive()
		await _tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		result["max_impact"] = maxf(result["max_impact"], main.trike.last_impact_strength)
		if main.trike.is_grounded():
			var kind := TrackSurface.name_of(main.trike.surface)
			result["surfaces"][kind] = int(result["surfaces"].get(kind, 0)) + 1
		(result["speeds"] as Array).append([main.get_progress().current_index * main.track.path.spacing, main.trike.forward_speed])
	main.trike.input.clear()
	result["time"] = t
	result["respawns"] = main.get_local_racer().respawn_count - respawns_before
	result["arrived"] = main.get_progress().current_index >= to_index
	return result


## Highest / lowest speed recorded between two distances.
static func _speed_between(speeds: Array, from: float, to: float, highest: bool) -> float:
	var value := -INF if highest else INF
	for entry: Array in speeds:
		if entry[0] >= from and entry[0] <= to:
			value = maxf(value, entry[1]) if highest else minf(value, entry[1])
	return value


# --- Build, layout, sections -------------------------------------------------

func _test_build_and_profile(main: RaceSession) -> void:
	print("\n[%s: build and profile]" % label)
	var track := main.track
	var timings := track.build_timings
	var stages := ""
	for stage: String in timings:
		if stage != "total":
			stages += "%s %.0f, " % [stage, timings[stage]]
	var info := MapCatalog.get_map(spec["id"])
	var length_range: Vector2 = spec["length"]
	_check(track.name == spec["node"] and info and info.race_scene == (spec["race"] as PackedScene).resource_path and info.is_playable()
			and info.status == MapInfo.Status.READY, "%s is a READY map in the catalog" % label,
			"(%s, %s)" % [info.get_status_text() if info else "missing", info.race_scene if info else ""])
	_check(track.path.length > length_range.x and track.path.length < length_range.y, "the route is a long downhill run",
			"(%.0f m, %.0f m drop)" % [track.path.length, track.path.points[0].y - track.path.points[-1].y])
	_check(timings["total"] < 3000.0, "the whole map builds in under 3 s (headless)",
			"(%.0f ms: %s)" % [timings["total"], stages.trim_suffix(", ")])
	var chunks := 0
	for child in track.get_children():
		if child.name.begins_with("Road_"):
			chunks += 1
	_check(chunks == track.builder.chunks.size() and chunks >= 20, "road geometry is split into chunks for culling",
			"(%d chunks of %d m)" % [chunks, roundi(track.chunk_samples * track.path.spacing)])
	# Unhinted nearest-sample lookups go through the grid: compare with a scan.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var mismatches := 0
	var t0 := Time.get_ticks_usec()
	var probes := 400
	for k in probes:
		var i := rng.randi_range(0, track.path.size() - 1)
		var p := track.path.points[i] + Vector3(rng.randf_range(-30, 30), rng.randf_range(-5, 5), rng.randf_range(-30, 30))
		var fast := track.path.find_nearest(p)
		var slow := track.path._scan(p, 0, track.path.size() - 1)
		if fast != slow and absf(track.path.points[fast].distance_to(p) - track.path.points[slow].distance_to(p)) > 0.001:
			mismatches += 1
	var per_lookup := (Time.get_ticks_usec() - t0) / float(probes)
	_check(mismatches == 0, "grid nearest-sample lookup matches a full scan", "(%d probes, %.0f µs each incl. the scan)" % [probes, per_lookup])


func _test_route_layout(track: Track) -> void:
	print("\n[%s: route layout]" % label)
	var radius := TrackRoute.min_radius(track.route_segments)
	_check(radius >= 18.0, "no impossible corners: tightest corner radius >= 18 m", "(%.1f m)" % radius)
	# Measured on the built path too (heading change over 10 m windows).
	var tightest := INF
	var path := track.path
	for i in range(3, path.size() - 3):
		var angle := absf(path.turn_angle(i, 2))
		if angle > 0.001:
			tightest = minf(tightest, (4.0 * path.spacing) / angle)
	_check(tightest >= 16.0, "built centerline has no kinks", "(tightest %.1f m)" % tightest)
	var longest_straight := 0.0
	for segment in track.route_segments:
		if absf(segment.y) < 0.01:
			longest_straight = maxf(longest_straight, segment.x)
	_check(longest_straight <= 160.0, "no long repetitive straights", "(longest straight %.0f m)" % longest_straight)
	# Downhill all the way, never steeper than 20 % over 20 m.
	var steepest := 0.0
	var climb := 0.0
	for i in range(0, path.size() - 10, 5):
		var grade := (path.points[i].y - path.points[i + 10].y) / (10.0 * path.spacing)
		steepest = maxf(steepest, grade)
		climb = maxf(climb, -grade)
	_check(steepest <= 0.2 and climb <= 0.01, "a continuous downhill route", "(steepest %.0f %%, steepest climb %.1f %%)" % [steepest * 100.0, climb * 100.0])
	# Sections far apart along the route never come close: no shortcuts,
	# no overlapping slopes.
	var closest_far := INF
	var closest_near := INF
	for i in range(0, path.size(), 3):
		for j in range(i + roundi(120.0 / path.spacing), path.size(), 3):
			var a := path.points[i]
			var b := path.points[j]
			var d := Vector2(a.x - b.x, a.z - b.z).length()
			if (j - i) * path.spacing > 250.0:
				closest_far = minf(closest_far, d)
			else:
				closest_near = minf(closest_near, d)
	_check(closest_far >= 2.0 * track.out_of_bounds_radius, "no hidden shortcuts: parts > 250 m apart along the route stay >= 90 m apart",
			"(closest %.0f m)" % closest_far)
	_check(closest_near >= 40.0, "hairpin legs stay apart", "(closest %.0f m between parts 120-250 m apart)" % closest_near)


## Props by type: script class name, else scene name; big kickers apart.
func _prop_counts(track: Track) -> Dictionary:
	var counts := {}
	for child in track.get_node("Props").get_children():
		var key: String = String((child as Node).get_script().get_global_name()) if child.get_script() \
				else child.scene_file_path.get_file().get_basename()
		if child is Ramp and (child as Ramp).width > 8.0:
			key = "BigRamp"
		elif child is RollingRock:
			key = "FallingRock" if (child as RollingRock).mode == RollingRock.Mode.FALL else "RollingRock"
		counts[key] = int(counts.get(key, 0)) + 1
	return counts


func _decor_count(track: Track, prefix: String) -> int:
	var total := 0
	for node_name: String in ["Decor", "Backdrop"]:
		for child in track.get_node(node_name).get_children():
			if child is MultiMeshInstance3D and child.name.begins_with(prefix):
				total += (child as MultiMeshInstance3D).multimesh.instance_count
	return total


func _test_forest_sections(track: Track) -> void:
	print("\n[Forest Rush: sections and features]")
	var bridges := track.get_zones("bridge")
	var gaps := track.get_zones("gap")
	var muds := track.get_zones("mud")
	var overlooks := track.get_zones("overlook")
	var counts := _prop_counts(track)
	_check(bridges.size() >= 2 and track.get_node_or_null("BridgeBody") != null, "wooden bridge section", "(%d bridges)" % bridges.size())
	_check(muds.size() >= 4 and track.get_node_or_null("MudBody") != null, "mud section", "(%d mud stretches)" % muds.size())
	_check(counts.get("RoadBoulder", 0) >= 3 and counts.get("RoadTree", 0) >= 2 and counts.get("FallingLog", 0) >= 2,
			"large rocks, tree obstacles and falling logs on the road", "(%s)" % str(counts))
	_check(gaps.size() == 1 and counts.get("BigRamp", 0) == 1 and counts.get("Ramp", 0) >= 6, "large jump and small ramps",
			"(gap %.0f m)" % (float(gaps[0][1]) - float(gaps[0][0]) if gaps.size() > 0 else 0.0))
	var narrow := INF
	for w in track.path.widths:
		narrow = minf(narrow, w)
	_check(narrow <= 10.0 and track.get_zones("rocks").size() >= 1, "narrow passages", "(narrowest %.1f m)" % narrow)
	_check(overlooks.size() >= 3 and track.get_node("Structures").get_children().any(
			func(n: Node) -> bool: return n.name.begins_with("Overlook")), "mountain overlooks", "(%d)" % overlooks.size())
	var trees := _decor_count(track, "Trees_pine") + _decor_count(track, "FarForest")
	_check(trees > 3000, "pine forests", "(%d pines)" % trees)


# --- Spawns, checkpoints, item boxes, recovery --------------------------------

func _test_spawns(main: RaceSession) -> void:
	print("\n[%s: five spawn positions]" % label)
	var track := main.track
	var points: Array[Vector3] = []
	var on_road := true
	for slot in 5:
		var xf := track.get_start_transform(slot)
		points.append(xf.origin)
		var hit := _ray_down(track, xf.origin + Vector3.UP * 0.5, 3.0)
		var index := track.path.find_nearest(xf.origin)
		on_road = on_road and not hit.is_empty() and _is_road_body(hit["collider"]) \
				and absf((xf.origin - track.path.points[index]).dot(track.path.rights[index])) < track.half_width_at(index) - 1.2
	var closest := INF
	for a in 5:
		for b in range(a + 1, 5):
			closest = minf(closest, points[a].distance_to(points[b]))
	_check(on_road, "all 5 grid slots are on solid road, clear of the barriers")
	_check(closest >= 2.5, "grid slots don't overlap", "(closest %.1f m apart)" % closest)
	await _wait(1.5)
	var settled := 0
	for racer in main.racers.get_racers():
		var trike := racer.trike
		if trike.grounded_wheel_count == 3 and trike.global_basis.y.y > 0.95 and trike.linear_velocity.length() < 0.5 \
				and racer.rider.is_riding():
			settled += 1
	_check(main.racers.get_racer_count() == 5 and settled == 5, "5 racers spawn, settle upright and hold still on the grid",
			"(%d/%d settled)" % [settled, main.racers.get_racer_count()])


func _test_checkpoints(track: Track) -> void:
	print("\n[%s: checkpoints]" % label)
	var checkpoints := track.get_checkpoints()
	var ordered := true
	var widest := 0.0
	var solid := true
	for k in checkpoints.size():
		if k > 0:
			ordered = ordered and checkpoints[k] > checkpoints[k - 1]
			widest = maxf(widest, (checkpoints[k] - checkpoints[k - 1]) * track.path.spacing)
		var frame := track.path.get_frame(checkpoints[k])
		var hit := _ray_down(track, frame.origin + frame.basis.y * 1.0, 3.0)
		solid = solid and not hit.is_empty() and _is_road_body(hit["collider"])
	_check(checkpoints.size() >= 20 and ordered and checkpoints[-1] == track.get_finish_index(),
			"ordered checkpoints end at the finish line", "(%d checkpoints)" % checkpoints.size())
	_check(widest <= track.checkpoint_spacing + 4.0, "a checkpoint at least every %.0f m" % track.checkpoint_spacing, "(widest gap %.0f m)" % widest)
	_check(solid, "every checkpoint lies on solid road (none in the jump gap)")


func _test_item_boxes(track: Track) -> void:
	print("\n[%s: item box spawn points]" % label)
	var boxes := track.get_item_box_transforms()
	var props := _solid_props(track)
	var bad := 0
	var detail := ""
	for xf in boxes:
		var hit := _ray_down(track, xf.origin, 3.0)
		var index := track.path.find_nearest(xf.origin)
		var near_prop := false
		for prop in props:
			near_prop = near_prop or prop.global_position.distance_to(xf.origin) < 8.0
		if hit.is_empty() or not _is_road_body(hit["collider"]) or near_prop or not track.is_safe_index(index):
			bad += 1
			detail = "(bad box at %.0f m)" % (index * track.path.spacing)
	var first := track.path.find_nearest(boxes[0].origin) * track.path.spacing if not boxes.is_empty() else INF
	var last := track.path.find_nearest(boxes[-1].origin) * track.path.spacing if not boxes.is_empty() else 0.0
	_check(boxes.size() >= 30 and bad == 0, "item box points sit on the road, away from obstacles and the jump",
			detail if bad > 0 else "(%d boxes in %d rows)" % [boxes.size(), track.item_box_rows.size()])
	_check(first < 600.0 and last > track.path.length - 1200.0, "item boxes spread over the whole route", "(%.0f m to %.0f m)" % [first, last])


## The race scene turns the map's spawn points into real boxes, all clear
## of the grid (a box never appears inside a racer at the start).
func _test_item_boxes_in_race(main: RaceSession) -> void:
	var points := main.track.get_item_box_transforms()
	var boxes := main.items.boxes
	var placed := boxes.size() == points.size()
	for i in mini(boxes.size(), points.size()):
		placed = placed and boxes[i].global_position.is_equal_approx(points[i].origin) and boxes[i].active
	var closest := INF
	for racer in main.racers.get_racers():
		for box in boxes:
			closest = minf(closest, racer.trike.global_position.distance_to(box.global_position))
	_check(placed and closest > 20.0, "%s race places an active item box on every spawn point" % label,
			"(%d boxes, nearest to a racer %.0f m)" % [boxes.size(), closest])


func _test_recovery_points(track: Track) -> void:
	print("\n[%s: safe recovery points]" % label)
	var props := _solid_props(track)
	var checked := 0
	var bad := 0
	var detail := ""
	for i in range(track.get_start_index(), track.get_finish_index(), 5):
		if not track.is_safe_index(i):
			continue
		var half := track.half_width_at(i) - 2.0
		for lateral: float in [-half, 0.0, half]:
			var xf := track.get_respawn_transform(i, lateral)
			var hit := _ray_down(track, xf.origin, 2.5)
			var blocked := false
			for prop in props:
				var flat := prop.global_position - xf.origin
				flat.y = 0.0
				blocked = blocked or flat.length() < 5.0
			checked += 1
			if hit.is_empty() or not _is_road_body(hit["collider"]) or blocked:
				bad += 1
				detail = "(bad recovery point at %.0f m, lateral %.1f)" % [i * track.path.spacing, lateral]
	var expected := (track.get_finish_index() - track.get_start_index()) / 5 * 3 * 0.6
	_check(checked > expected and bad == 0, "every recovery point is on solid road with no obstacle there",
			detail if bad > 0 else "(%d points checked)" % checked)
	var gap: Array = track.get_zones("gap")[0]
	var in_gap := track.path.index_at_distance((float(gap[0]) + float(gap[1])) * 0.5)
	var back := track.get_recovery_index(in_gap) * track.path.spacing
	_check(back <= float(gap[0]) - track.gap_unsafe_before + 1.0, "falling into the jump gap puts you back before the run-up",
			"(gap at %.0f m, recovery at %.0f m)" % [float(gap[0]), back])


# --- Collision geometry -------------------------------------------------------

func _test_collision_coverage(track: Track) -> void:
	print("\n[%s: collision geometry]" % label)
	var path := track.path
	var holes := 0
	var wrong_surface := 0
	var detail := ""
	var samples := 0
	for i in range(0, path.size() - 1):
		if track.get_sample_kind(i) == TrackMeshBuilder.SampleKind.GAP \
				or track.builder.quad_kind(i) == TrackMeshBuilder.SampleKind.GAP:
			continue
		# Middle of the quad between sample i and i + 1.
		var center := (path.points[i] + path.points[i + 1]) * 0.5
		var right := path.rights[i]
		var half := minf(track.half_width_at(i), track.half_width_at(i + 1)) - 0.6
		for lateral: float in [-half, -half * 0.5, 0.0, half * 0.5, half]:
			var p := center + right * lateral
			var hit := _ray_down(track, p + path.ups[i] * 2.0, 4.0, true)
			samples += 1
			if hit.is_empty() or not _is_road_body(hit["collider"]) or absf((hit["position"] as Vector3).y - p.y) > 0.35:
				holes += 1
				detail = "(hole at %.0f m, lateral %.1f)" % [i * path.spacing, lateral]
				continue
			# A probe right on the edge of a mud/ice band could land on either side.
			var band := track.builder.mud_bands[i]
			var u := 0.5 + lateral / (track.half_width_at(i) * 2.0)
			var edge := minf(absf(u - band.x), absf(u - band.y)) * track.half_width_at(i) * 2.0
			if band.y > band.x and edge < 0.1:
				continue
			if TrackSurface.of(hit["collider"]) != track.surface_at(i, lateral):
				wrong_surface += 1
				detail = "(%s instead of %s at %.0f m, lateral %.1f)" % [TrackSurface.name_of(TrackSurface.of(hit["collider"])),
						TrackSurface.name_of(track.surface_at(i, lateral)), i * path.spacing, lateral]
	_check(holes == 0, "no holes in the road collision", detail if holes > 0 else "(%d probes)" % samples)
	_check(wrong_surface == 0, "road collision surface matches the map (road, mud, ice, bridge decks)",
			"(%d mismatches %s)" % [wrong_surface, detail if wrong_surface > 0 else ""])


func _test_road_boundaries(track: Track) -> void:
	print("\n[%s: road boundaries]" % label)
	var path := track.path
	var missing := 0
	var detail := ""
	var probes := 0
	for i in range(2, path.size() - 2, 5):
		if track.builder.quad_kind(i) == TrackMeshBuilder.SampleKind.GAP \
				or track.builder.quad_kind(i - 1) == TrackMeshBuilder.SampleKind.GAP:
			continue
		var center := path.points[i] + path.ups[i] * 0.6
		for side: float in [-1.0, 1.0]:
			var half := track.half_width_at(i)
			var hit := _ray(track, center, center + path.rights[i] * side * (half + 3.0))
			probes += 1
			var distance := INF if hit.is_empty() else (hit["position"] as Vector3).distance_to(center)
			# Props standing on the road may answer first; only a missing wall counts.
			var is_wall := not hit.is_empty() and String((hit["collider"] as Node).name) == "TrackBody"
			if hit.is_empty() or (is_wall and absf(distance - half) > 0.5):
				missing += 1
				detail = "(at %.0f m, side %d)" % [i * path.spacing, int(side)]
	_check(missing == 0, "barriers line both sides of the road everywhere (except the jump gap)",
			detail if missing > 0 else "(%d probes)" % probes)


func _test_scenery_clearance(track: Track) -> void:
	print("\n[%s: scenery stays off the road]" % label)
	var shapes: Array[CollisionShape3D] = runner.scenery_colliders(track)
	var intrusions: int = runner.count_road_intrusions(track, shapes)
	_check(shapes.size() > 1000 and intrusions == 0, "no scenery, landmark or structure collider inside the road corridor",
			"(%d colliders, %d intrusions)" % [shapes.size(), intrusions])


# --- Driving: surfaces, jump, bridges, hazards ---------------------------------

func _test_mud(main: RaceSession) -> void:
	print("\n[Forest Rush: mud]")
	var mud: Array = main.track.get_zones("mud")[0]
	var start := float(mud[0])
	var end := float(mud[1])
	await _place(main, start - 140.0)
	var run := await _drive(main, end + 60.0, 25.0)
	var before := _speed_between(run["speeds"], start - 30.0, start - 2.0, true)
	var late := _speed_between(run["speeds"], end - 15.0, end - 2.0, true)
	var after := _speed_between(run["speeds"], end + 30.0, end + 60.0, true)
	var cap := main.trike.config.max_speed * main.trike.config.mud_speed_factor
	var surfaces: Dictionary = run["surfaces"]
	_check(surfaces.get("mud", 0) > 30, "wheels report mud in the mud section", "(%s ticks)" % str(surfaces))
	_check(before > 22.0 and late < cap + 2.5 and after > late + 4.0, "mud slows the trike, firm road gives the speed back",
			"(%.1f m/s before, %.1f late in the mud (cap %.1f), %.1f after)" % [before, late, cap, after])
	_check(run["respawns"] == 0 and main.rider.is_riding(), "driving through mud keeps the rider aboard")


func _test_offroad(main: RaceSession) -> void:
	print("\n[%s: off-road]" % label)
	var track := main.track
	# A straight stretch of the fast descent: put the trike on the grass
	# beside the barrier, facing downhill.
	var index := track.path.index_at_distance(float(spec["offroad_at"]))
	var frame := track.path.get_frame(index)
	var spot := track.builder.slope_point(track.path, index, 1, 2.0)
	main.trike.teleport(Transform3D(frame.basis, spot + Vector3.UP * 0.8))
	main.get_progress().reset(index)
	await _wait(0.4)
	var top := 0.0
	var grass_ticks := 0
	for k in runner._ticks(3.0):
		main.trike.input.throttle = 1.0
		await _tree().physics_frame
		if main.trike.is_grounded() and main.trike.surface == TrackSurface.Kind.GRASS:
			grass_ticks += 1
			top = maxf(top, main.trike.forward_speed)
	main.trike.input.clear()
	var cap := main.trike.config.max_speed * main.trike.config.grass_speed_factor
	_check(grass_ticks > 60, "the slopes beside the road are grass", "(%d grass ticks)" % grass_ticks)
	_check(top < cap + 2.0, "off-road the trike is slower than on the road", "(top %.1f m/s, grass cap %.1f, road %.1f)" % [top, cap, main.trike.config.max_speed])
	# Leaving the course entirely: back on the road at the last safe point.
	var safe := main.get_progress().last_safe_index
	main.trike.teleport(Transform3D(frame.basis, spot + track.path.rights[index] * 60.0 - Vector3.UP * 30.0))
	await _wait(1.0)
	var now := track.path.find_nearest(main.trike.global_position)
	_check(track.is_on_road(main.trike.global_position, now) and track.is_safe_index(now),
			"falling off the mountain respawns on the road", "(last safe %.0f m, now %.0f m)" % [safe * 2.0, now * 2.0])


func _test_big_jumps(main: RaceSession) -> void:
	print("\n[%s: big jumps]" % label)
	var gaps: Array = main.track.get_zones("gap")
	for gap: Array in gaps:
		var start := float(gap[0])
		var end := float(gap[1])
		await _place(main, start - 120.0)
		var ejects := main.rider.eject_count
		var run := await _drive(main, end + 40.0, 15.0)
		var takeoff := _speed_between(run["speeds"], start - 12.0, start, true)
		_check(run["arrived"] and run["respawns"] == 0, "a full-speed trike clears the jump at %.0f m" % start,
				"(take-off %.1f m/s, %.1f s)" % [takeoff, run["time"]])
		_check(main.rider.eject_count == ejects and main.rider.is_riding(), "the landing at %.0f m doesn't throw the rider off" % end,
				"(hardest hit %.1f, eject at %.0f)" % [run["max_impact"], main.rider.config.eject_impact_strength])


func _test_jump_too_slow(main: RaceSession) -> void:
	print("\n[%s: falling into the gap]" % label)
	var gap: Array = main.track.get_zones("gap")[0]
	var start := float(gap[0])
	await _place(main, start - 14.0)
	var respawns := main.get_local_racer().respawn_count
	var pilot := TrackAutopilot.new(main.track, main.trike)
	pilot.target_speed = 5.0
	for k in runner._ticks(8.0):
		pilot.drive()
		if main.trike.forward_speed > 5.0:
			main.trike.input.throttle = 0.0
		await _tree().physics_frame
		if main.get_local_racer().respawn_count > respawns:
			break
	main.trike.input.clear()
	await _wait(1.0)
	var at := main.get_progress().current_index * main.track.path.spacing
	_check(main.get_local_racer().respawn_count > respawns, "rolling off the lip too slowly drops into the gap and respawns")
	_check(at <= start - main.track.gap_unsafe_before + 2.0 and main.track.is_on_road(main.trike.global_position, main.get_progress().current_index),
			"the respawn is on the road before the run-up", "(at %.0f m, lip at %.0f m)" % [at, start])
	main.rider.force_mount()


func _test_bridges(main: RaceSession) -> void:
	var deck := TrackSurface.name_of(main.track.bridge_surface)
	print("\n[%s: bridges (%s decks)]" % [label, deck])
	var bridges: Array = main.track.get_zones("bridge")
	_check(bridges.size() == int(spec["bridges"]), "%d bridges" % int(spec["bridges"]))
	for bridge: Array in bridges:
		var start := float(bridge[0])
		var end := float(bridge[1])
		await _place(main, start - 90.0)
		var run := await _drive(main, end + 30.0, 20.0)
		var surfaces: Dictionary = run["surfaces"]
		_check(run["arrived"] and run["respawns"] == 0 and surfaces.get(deck, 0) > 20,
				"crossing the %.0f m bridge at %.0f m on its %s deck" % [end - start, start, deck],
				"(%s ticks, %.1f s)" % [str(surfaces), run["time"]])
		_check(run["max_impact"] < 4.0, "smooth joins on and off the %.0f m bridge" % (end - start),
				"(hardest bump %.1f)" % run["max_impact"])


## Every kind of timed hazard on the map (falling logs, falling and rolling
## rocks): waits off the road, crosses it, moves with race time only, and
## hits a trike parked in its way.
func _test_hazards(main: RaceSession) -> void:
	var track := main.track
	var kinds := {}
	for child in track.get_node("Props").get_children():
		if child.has_method(&"mid_crossing_time"):
			var key := (child as Node).scene_file_path.get_file().get_basename()
			if not kinds.has(key):
				kinds[key] = child
	if kinds.is_empty():
		return
	for key: String in kinds:
		print("\n[%s: %s hazard]" % [label, key])
		var hazard: Node3D = kinds[key]
		var period: float = hazard.get(&"period")
		var phase: float = hazard.get(&"phase")
		var index := track.path.find_nearest(hazard.global_position)
		var mid: float = hazard.call(&"mid_crossing_time")
		track.hazard_time = period * 3.0 - phase - 0.3
		await _tree().physics_frame
		await _tree().physics_frame
		var waiting_off: bool = not hazard.call(&"is_active") and not track.is_on_road(hazard.global_position, index)
		track.hazard_time = period * 3.0 - phase + mid
		await _tree().physics_frame
		await _tree().physics_frame
		var now := track.path.find_nearest(hazard.global_position, index)
		var lateral := (hazard.global_position - track.path.points[now]).dot(track.path.rights[now])
		_check(waiting_off and hazard.call(&"is_active") and absf(lateral) < 2.5 and track.is_on_road(hazard.global_position, now),
				"a %s waits off the road, then crosses it" % key.replace("_", " "), "(mid-crossing %.1f m from the center)" % lateral)
		var a := hazard.global_transform
		track.hazard_time -= 1.0 / Engine.physics_ticks_per_second
		await _tree().physics_frame
		_check(hazard.global_transform.origin.distance_to(a.origin) < 0.15, "%s motion is a function of race time only" % key.replace("_", " "))
		# Park a ridden trike where it crosses the centerline, just before.
		main.trike.teleport(track.path.get_frame(now).translated_local(Vector3(0.0, 0.8, 0.0)))
		main.get_progress().reset(now)
		await _wait(0.6)
		var before := main.trike.global_position
		var ejects := main.rider.eject_count
		var hardest := 0.0
		track.hazard_time = period * 5.0 - phase + mid - 1.0
		for k in runner._ticks(2.5):
			await _tree().physics_frame
			hardest = maxf(hardest, main.trike.last_impact_strength)
		var pushed := main.trike.global_position.distance_to(before)
		_check(hardest > 3.0 or pushed > 1.5 or main.rider.eject_count > ejects, "a %s hits a trike in its way" % key.replace("_", " "),
				"(impact %.1f, pushed %.1f m, %s)" % [hardest, pushed, "rider thrown off" if main.rider.eject_count > ejects else "rider held on"])
		main.rider.force_mount()


## Crossing the line at full speed and letting go: the finished trike brakes
## to a stop on the run-off, before the wall at the end of the road, and the
## rider stays on (celebrating).
func _test_finish_runoff(main: RaceSession) -> void:
	print("\n[%s: finish run-off]" % label)
	var track := main.track
	var finish := track.get_finish_index() * track.path.spacing
	var index := await _place(main, finish - 150.0)
	var racer := main.get_local_racer()
	racer.checkpoints.force_passed_through(index)
	var ejects := main.rider.eject_count
	var pilot := TrackAutopilot.new(track, main.trike)
	pilot.target_speed = 40.0
	var crossing_speed := 0.0
	var t := 0.0
	while not racer.finished and t < 15.0:
		pilot.drive()
		await _tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		crossing_speed = main.trike.forward_speed
	var hardest := 0.0
	for k in runner._ticks(8.0):
		main.trike.input.clear()  # a player who just lets go
		await _tree().physics_frame
		hardest = maxf(hardest, main.trike.last_impact_strength)
	var left := (track.path.size() - 1 - main.get_progress().current_index) * track.path.spacing
	_check(racer.finished and crossing_speed > 18.0, "finishing at full speed", "(%.1f m/s over the line)" % crossing_speed)
	_check(main.trike.linear_velocity.length() < 0.5 and main.rider.eject_count == ejects and main.rider.is_riding() and hardest < 4.0,
			"the finished trike brakes to a stop before the end of the road, rider aboard",
			"(%.0f m of road left, hardest bump %.1f)" % [left, hardest])


# --- Map-specific features -----------------------------------------------------

func _test_canyon_sections(track: Track) -> void:
	print("\n[Rocky Canyon: sections and features]")
	var counts := _prop_counts(track)
	var cliffs := track.get_zones("cliff")
	var cliff_samples := 0
	for i in track.path.size():
		if track.builder.cliff_weight(i, -1) > 0.99 or track.builder.cliff_weight(i, 1) > 0.99:
			cliff_samples += 1
	_check(cliffs.size() >= 4 and cliff_samples * track.path.spacing > 1500.0, "high cliff roads (rock wall on one side)",
			"(%d cliff stretches, %.0f m)" % [cliffs.size(), cliff_samples * track.path.spacing])
	_check(counts.get("FallingRock", 0) >= 8 and counts.get("RollingRock", 0) >= 3, "falling boulders and rolling rock hazards",
			"(%s)" % str(counts))
	_check(track.get_zones("gap").size() == 2 and counts.get("BigRamp", 0) == 2 and counts.get("Ramp", 0) >= 5,
			"two large jumps and wooden ramps", "(%d ramps)" % counts.get("Ramp", 0))
	var narrow := INF
	for w in track.path.widths:
		narrow = minf(narrow, w)
	_check(narrow <= 10.0 and track.get_zones("rocks").size() >= 1, "narrow rock passage", "(narrowest %.1f m)" % narrow)
	var radius := TrackRoute.min_radius(track.route_segments)
	var hairpins := 0
	for segment in track.route_segments:
		if absf(segment.y) >= 110.0:
			hairpins += 1
	_check(hairpins >= 14 and radius < 21.0, "more technical than Forest Rush: three switchback descents",
			"(%d hairpins, tightest %.1f m)" % [hairpins, radius])
	_check(_decor_count(track, "Trees_spire") > 300 and _decor_count(track, "Trees_pine") == 0,
			"canyon scenery: rock spires instead of pines", "(%d spires)" % _decor_count(track, "Trees_spire"))


func _test_snow_sections(track: Track) -> void:
	print("\n[Snow Slide: sections and features]")
	var counts := _prop_counts(track)
	var ice_length := 0.0
	for zone: Array in track.get_zones("ice"):
		ice_length += float(zone[1]) - float(zone[0])
		_check(float(zone[4]) - float(zone[3]) <= 0.6, "ice at %.0f m covers part of the road (a grippy line stays)" % float(zone[0]),
				"(%.0f %% of the width)" % ((float(zone[4]) - float(zone[3])) * 100.0))
	var bridge_length := 0.0
	for zone: Array in track.get_zones("bridge"):
		bridge_length += float(zone[1]) - float(zone[0])
	var share := (ice_length * 0.5 + bridge_length) / track.path.length
	_check(track.get_zones("ice").size() >= 4 and share < 0.08, "ice sections, but most of the map has grip",
			"(%.0f m of ice bands + %.0f m frozen bridges ≈ %.1f %% of the route)" % [ice_length, bridge_length, share * 100.0])
	_check(track.road_surface == TrackSurface.Kind.SNOW and track.bridge_surface == TrackSurface.Kind.ICE
			and track.get_node_or_null("IceBody") != null, "snow roads, ice patches and frozen bridges")
	_check(track.get_zones("wind").size() >= 2, "windy mountain turns", "(%d wind stretches)" % track.get_zones("wind").size())
	_check(counts.get("snowman", 0) >= 15 and counts.get("RoadBoulder", 0) >= 4, "snow obstacles: snowmen and snowbanks",
			"(%s)" % str(counts))
	var big := 0
	for child in track.get_node("Props").get_children():
		if child is Ramp and (child as Ramp).width < 8.0 and (child as Ramp).height >= 1.6:
			big += 1
	_check(big >= 6 and counts.get("BigRamp", 0) == 1, "large ramps and a big jump", "(%d large ramps)" % big)
	_check(_decor_count(track, "Trees_snow_pine") > 3000, "snow-covered pine forests",
			"(%d snowy pines)" % _decor_count(track, "Trees_snow_pine"))


## The map's own sky and sun are applied (forest keeps the scene's).
func _test_sky(main: RaceSession) -> void:
	var theme := main.track.theme
	var environment := (main.get_node("WorldEnvironment") as WorldEnvironment).environment
	var sky := environment.sky.sky_material as ProceduralSkyMaterial
	var sun := main.get_node("Sun") as DirectionalLight3D
	if theme.apply_environment:
		_check(sky.sky_top_color.is_equal_approx(theme.sky_top_color) and sun.light_color.is_equal_approx(theme.sun_color)
				and is_equal_approx(environment.fog_density, theme.fog_density), "%s has its own sky, fog and sun" % label)
	else:
		_check(sky.sky_top_color.is_equal_approx(Color(0.26, 0.53, 0.95)), "%s keeps the race scene's sky" % label)


## Rocky Canyon: the cliff side of a cliff road is a rock wall above the
## barrier (no falling off that side), the other side drops away.
func _test_cliff_walls(main: RaceSession) -> void:
	print("\n[Rocky Canyon: cliff walls]")
	var track := main.track
	var zone: Array = track.get_zones("cliff")[0]
	var side := int(zone[3])
	var index := track.path.index_at_distance((float(zone[0]) + float(zone[1])) * 0.5)
	var wall := track.builder.slope_point(track.path, index, side, 6.0)
	var drop := track.builder.slope_point(track.path, index, -side, 6.0)
	var road_y := track.path.points[index].y
	_check(wall.y > road_y + 15.0 and drop.y < road_y, "rock wall rises on the cliff side, the slope drops on the other",
			"(wall top %.0f m above the road, far side %.0f m below)" % [wall.y - road_y, road_y - drop.y])
	# Level with a flying trike's rider (3 m up), from the road center out.
	var center := track.path.points[index] + Vector3.UP * 3.0
	var outward := track.path.rights[index] * float(side)
	var hit := _ray(track, center, center + outward * (track.half_width_at(index) + 12.0))
	var face := INF if hit.is_empty() else ((hit["position"] as Vector3) - center).dot(outward) - track.half_width_at(index)
	_check(not hit.is_empty() and face < 3.0, "the cliff wall is solid right behind the barrier (collision matches the rock face)",
			"(rock face %.1f m past the barrier)" % face)
	await _place(main, float(zone[0]) - 60.0)
	var run := await _drive(main, float(zone[1]) + 20.0, 60.0)
	_check(run["arrived"] and run["respawns"] == 0 and main.rider.is_riding(), "a whole cliff road can be driven cleanly",
			"(%.0f m in %.1f s)" % [float(zone[1]) - float(zone[0]) + 80.0, run["time"]])


## Snow Slide: ice has much less sideways grip than the snow road, so the
## same steering at the same speed slides wider; the trike stays upright.
func _test_ice(main: RaceSession) -> void:
	print("\n[Snow Slide: ice]")
	var track := main.track
	var zone: Array = track.get_zones("ice")[0]
	var u := (float(zone[3]) + float(zone[4])) * 0.5
	var ice_index := track.path.index_at_distance(float(zone[0]) + 20.0)
	var ice_lateral := (u - 0.5) * track.half_width_at(ice_index) * 2.0
	var ice_slip := await _slide_test(main, ice_index, ice_lateral)
	# Reference: a clear, windless snow straight.
	var snow_index := track.path.index_at_distance(1300.0)
	var snow_slip := await _slide_test(main, snow_index, 0.0)
	_check(track.surface_at(ice_index, ice_lateral) == TrackSurface.Kind.ICE and ice_slip["surface"] == "ice",
			"wheels report ice on the ice band", "(%s)" % ice_slip["surface"])
	_check(ice_slip["turned"] < snow_slip["turned"] * 0.6, "on ice the trike slides on instead of turning (much less grip than snow)",
			"(direction of travel turned %.0f° on ice vs %.0f° on snow in 1.2 s)" % [ice_slip["turned"], snow_slip["turned"]])
	_check(ice_slip["upright"] and ice_slip["riding"], "sliding on ice doesn't flip the trike or throw the rider off")


## 15 m/s, then hard left for 1.2 s: how far the direction of travel turned.
func _slide_test(main: RaceSession, index: int, lateral: float) -> Dictionary:
	var track := main.track
	if not main.rider.is_riding():
		main.rider.force_mount()
	main.trike.teleport(track.path.get_frame(index).translated_local(Vector3(lateral, 0.8, 0.0)))
	main.get_progress().reset(index)
	await _wait(0.3)
	# Launched like an item hit: not a crash, so the rider stays aboard.
	main.trike.apply_item_hit(-main.trike.global_basis.z * 15.0)
	await _tree().physics_frame
	await _tree().physics_frame
	var heading := Vector2(main.trike.linear_velocity.x, main.trike.linear_velocity.z)
	var surface := ""
	for k in runner._ticks(1.2):
		main.trike.input.steer = -1.0
		main.trike.input.throttle = 0.5
		await _tree().physics_frame
		if k == 5:
			surface = TrackSurface.name_of(main.trike.surface)
	var travel := Vector2(main.trike.linear_velocity.x, main.trike.linear_velocity.z)
	main.trike.input.clear()
	var result := {"turned": rad_to_deg(absf(heading.angle_to(travel))), "surface": surface, "upright": main.trike.global_basis.y.y > 0.6, "riding": main.rider.is_riding()}
	main.rider.force_mount()
	return result


## Snow Slide: the snow road has a little less grip than dirt but stays
## controllable: top speed close to dirt, corners at race speed without
## sliding off.
func _test_snow_road(main: RaceSession) -> void:
	print("\n[Snow Slide: snow road]")
	var config := main.trike.config
	_check(config.snow_grip_factor >= 0.7 and config.snow_speed_factor >= 0.9 and config.ice_grip_factor < config.snow_grip_factor * 0.5,
			"snow: a little less grip and speed than dirt; ice: much less grip",
			"(snow grip %.2f, speed %.2f; ice grip %.2f)" % [config.snow_grip_factor, config.snow_speed_factor, config.ice_grip_factor])
	await _place(main, 330.0)
	var run := await _drive(main, 1300.0, 70.0, 30.0)
	var surfaces: Dictionary = run["surfaces"]
	var top := _speed_between(run["speeds"], 330.0, 1300.0, true)
	_check(surfaces.get("snow", 0) > 600 and run["arrived"] and run["respawns"] == 0 and main.rider.is_riding(),
			"the fast snowy descent drives cleanly on snow", "(%s ticks, top %.1f m/s, %.1f s)" % [str(surfaces), top, run["time"]])
	_check(top > config.max_speed * config.snow_speed_factor - 2.5, "snow keeps most of the speed", "(top %.1f m/s)" % top)


## Snow Slide: gusts push a trike sideways in a wind stretch, never outside,
## identically for the same race time.
func _test_wind(main: RaceSession) -> void:
	print("\n[Snow Slide: crosswind]")
	var track := main.track
	var zone: Array = track.get_zones("wind")[0]
	var index := track.path.index_at_distance((float(zone[0]) + float(zone[1])) * 0.5)
	track.hazard_time = 10.0
	var a := track.wind_at(index)
	var b := track.wind_at(index)
	var outside := track.wind_at(track.path.index_at_distance(float(zone[0]) - 50.0))
	var strongest := 0.0
	var gust_at := 0.0
	for k in 60:
		track.hazard_time = k * 0.1
		if track.wind_at(index).length() > strongest:
			strongest = track.wind_at(index).length()
			gust_at = k * 0.1
	_check(a == b and outside == Vector3.ZERO and strongest > 2.0 and strongest <= float(zone[4]) + 0.01,
			"gusty crosswind only in its stretch, a function of race time", "(up to %.1f m/s²)" % strongest)
	# A trike rolling straight through the wind drifts toward the zone's side.
	main.trike.teleport(track.path.get_frame(index).translated_local(Vector3(0.0, 0.8, 0.0)))
	main.get_progress().reset(index)
	await _wait(0.3)
	track.hazard_time = gust_at + track.wind_gust_period - 0.75  # the 1.5 s window centred on a gust
	var start := main.trike.global_position
	var drift := 0.0
	for k in runner._ticks(1.5):
		main.trike.input.throttle = 0.3
		await _tree().physics_frame
	main.trike.input.clear()
	drift = (main.trike.global_position - start).dot(track.path.rights[index]) * signf(float(zone[3]))
	_check(drift > 0.6 and drift < 4.0 and main.rider.is_riding(), "a gust pushes a trike sideways, but not off the road (steer against it)",
			"(%.1f m in 1.5 s)" % drift)
	track.hazard_time = 0.0


# --- AI on the whole route ----------------------------------------------------

func _test_ai_full_route() -> void:
	print("\n[%s: AI drives the whole route]" % label)
	var world := Node3D.new()
	world.name = "MapWorld"
	runner.add_child(world)
	var track: Track = (spec["track"] as PackedScene).instantiate()
	world.add_child(track)
	var manager := RacerManager.new()
	manager.ai_configs = AI_CONFIGS.duplicate()
	world.add_child(manager)
	manager.setup(track)
	var racer := manager.add_ai_racer(AIDriverConfig.Difficulty.HARD)
	await _tree().physics_frame
	manager.start_race()
	var passed_in_order := true
	var last_passed := 0
	var t := 0.0
	while not racer.finished and t < 600.0:
		await _tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		var passed := racer.checkpoints.get_passed_count()
		passed_in_order = passed_in_order and passed >= last_passed and passed - last_passed <= 1
		last_passed = passed
	var driver := racer.get_ai_driver()
	_check(racer.finished and last_passed == track.get_checkpoints().size() and passed_in_order,
			"a hard AI completes the full route through every checkpoint in order",
			"(%d/%d checkpoints, finish %s)" % [last_passed, track.get_checkpoints().size(), Hud.format_time(racer.finish_time) if racer.finished else "none"])
	_check(racer.finish_time >= 300.0 and racer.finish_time <= 600.0, "the expert (hard AI) run takes 5-10 minutes",
			"(%.1f s)" % racer.finish_time)
	_check(driver.reset_count + driver.emergency_count == 0 and racer.respawn_count == 0, "no resets or respawns needed on the way",
			"(%d wipeouts, %d resets, %d respawns)" % [racer.rider.eject_count, driver.reset_count + driver.emergency_count, racer.respawn_count])
	await _free(world)
