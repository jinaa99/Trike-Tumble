extends RefCounted
## Racer registry and AI driver tests (final-demo milestone 02).
## Run as part of tests/test_runner.gd; uses its _check/_wait helpers.

const MAIN_SCENE := preload("res://scenes/main/main.tscn")
const TRACK_SCENE := preload("res://scenes/tracks/test_track.tscn")
const AI_CONFIGS: Array[AIDriverConfig] = [
	preload("res://resources/ai/ai_easy.tres"),
	preload("res://resources/ai/ai_medium.tres"),
	preload("res://resources/ai/ai_hard.tres"),
]
const EASY := AIDriverConfig.Difficulty.EASY
const MEDIUM := AIDriverConfig.Difficulty.MEDIUM
const HARD := AIDriverConfig.Difficulty.HARD

var runner: Node


func _init(test_runner: Node) -> void:
	runner = test_runner


func run() -> void:
	await _test_one_human_racer()
	await _test_five_racers()
	await _test_launch_options()
	await _test_input_isolation()
	await _test_one_ai_racer_drives()
	await _test_ai_steering()
	await _test_ai_path_following()
	await _test_corner_braking()
	await _test_difficulty_differences()
	await _test_vehicle_collisions()
	await _test_ai_eject_recover_mount()
	await _test_ai_on_foot_detour()
	await _test_ai_unstuck()
	await _test_ai_finishing()


# --- Helpers ----------------------------------------------------------------

func _check(condition: bool, test_name: String, detail := "") -> void:
	runner._check(condition, test_name, detail)


func _tree() -> SceneTree:
	return runner.get_tree()


func _wait(seconds: float) -> void:
	await runner._wait(seconds)


func _ticks(seconds: float) -> int:
	return int(seconds * Engine.physics_ticks_per_second)


## The race scene with `ai_count` AI racers, the local player held still.
func _load_race(ai_count: int, difficulty := 1, keep_keyboard := false) -> RaceSession:
	await _clear_arena()
	var main: RaceSession = MAIN_SCENE.instantiate()
	main.ai_racer_count = ai_count
	main.ai_difficulty = difficulty
	main.auto_start = false  # wait in the lobby until the test starts the race
	runner.add_child(main)
	if not keep_keyboard:
		main.trike.input_source = null
		main.rider.input_source = null
	return main


## A track with a RacerManager and no human player.
func _ai_only_race(track_scene_or_points: Variant = null) -> Dictionary:
	await _clear_arena()
	var world := Node3D.new()
	world.name = "AIWorld"
	runner.add_child(world)
	var track: Track
	if track_scene_or_points is PackedVector3Array:
		track = Track.new()
		track.control_points = track_scene_or_points
	else:
		track = TRACK_SCENE.instantiate()
	world.add_child(track)
	var manager := RacerManager.new()
	manager.ai_configs = AI_CONFIGS.duplicate()
	world.add_child(manager)
	manager.setup(track)
	return {"world": world, "track": track, "manager": manager}


## Removes the runner's flat test arena (it would overlap the track).
func _clear_arena() -> void:
	if runner._arena:
		runner._arena.queue_free()
		runner._arena = null
	await _tree().process_frame


func track_size(race: Dictionary) -> int:
	return (race["track"] as Track).path.size()


func _free(node: Node) -> void:
	node.queue_free()
	await _tree().process_frame


func _lateral(track: Track, position: Vector3, index: int) -> float:
	return (position - track.path.points[index]).dot(track.path.rights[index])


## Runs until `racer` reaches path sample `index` (or `seconds` pass); returns the time taken.
func _drive_to_index(racer: Racer, index: int, seconds: float) -> float:
	var t := 0.0
	while racer.progress.current_index < index and t < seconds:
		await _tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	return t


# --- Registry ---------------------------------------------------------------

func _test_one_human_racer() -> void:
	print("\n[Racers: one human]")
	var main := await _load_race(0)
	await _wait(0.5)
	var racers := main.racers.get_racers()
	var human := main.get_local_racer()
	_check(racers.size() == 1 and human != null, "default race has exactly one racer", "(%d)" % racers.size())
	_check(human.type == Racer.Type.HUMAN and human.id == RaceSession.LOCAL_PLAYER_ID, "it is the human, id 1")
	_check(human.trike == main.trike and human.rider == main.rider and main.rider.trike == main.trike,
			"human owns the scene's trike and rider")
	_check(human.input_source is PlayerInputSource, "human gets keyboard control (PlayerInputSource)")
	_check(human.progress == main.get_progress() and human.spawn_slot == 0, "human has its own progress and pole slot")
	await _free(main)


func _test_five_racers() -> void:
	print("\n[Racers: five racers, ids, ownership, spawns, limit]")
	var main := await _load_race(4, 3)
	await _wait(1.5)
	var manager := main.racers
	var racers := manager.get_racers()
	var ai_count := 0
	var ids := {}
	var slots := {}
	var trikes := {}
	for racer in racers:
		ai_count += 1 if racer.is_ai() else 0
		ids[racer.id] = true
		slots[racer.spawn_slot] = true
		trikes[racer.trike] = true
	_check(racers.size() == 5 and ai_count == 4, "1 human + 4 AI racers", "(%d racers, %d AI)" % [racers.size(), ai_count])
	_check(ids.size() == 5 and slots.size() == 5 and trikes.size() == 5, "unique ids, grid slots and trikes",
			"(ids %s)" % str(ids.keys()))

	var owned := true
	var tracked := true
	for racer in racers:
		owned = owned and racer.rider.trike == racer.trike and racer.rider.is_attached() \
				and runner._impact_links(racer.trike, racer.rider) == 1
		for other in racers:
			if other != racer and runner._impact_links(racer.trike, other.rider) != 0:
				owned = false
		tracked = tracked and manager.finish_tracker.get_owner_id(racer.trike) == racer.id \
				and manager.get_racer_for_body(racer.trike) == racer \
				and manager.get_racer_for_body(racer.rider.on_foot) == racer \
				and racer.progress != null and racer.progress.track == main.track
	_check(owned, "each rider is bound to its own trike only (impact signal wired once)")
	_check(tracked, "each trike/rider body and finish entry resolves to its owner")
	var progresses := {}
	for racer in racers:
		progresses[racer.progress] = true
	_check(progresses.size() == 5, "each racer has its own progress tracker")

	var min_gap := INF
	var on_road := true
	var facing := true
	for racer in racers:
		var trike := racer.trike
		var index := main.track.path.find_nearest(trike.global_position)
		on_road = on_road and main.track.is_on_road(trike.global_position, index) \
				and trike.grounded_wheel_count == 3 and trike.global_basis.y.y > 0.95
		facing = facing and (-trike.global_basis.z).dot(main.track.path.forwards[index]) > 0.97
		for other in racers:
			if other != racer:
				min_gap = minf(min_gap, trike.global_position.distance_to(other.trike.global_position))
	_check(on_road, "every racer spawns upright on the road, all wheels down")
	_check(facing, "every racer faces down the track")
	_check(min_gap > 2.5, "no overlapping spawns", "(closest pair %.2f m apart)" % min_gap)
	var still := true
	for racer in racers:
		still = still and racer.trike.linear_velocity.length() < 0.5
	_check(still, "AI racers wait on the grid until the race starts")

	var extra := manager.add_ai_racer(MEDIUM)
	var human_again := manager.add_human_racer(main.trike, main.rider)
	_check(extra == null and human_again == null and manager.get_racer_count() == 5,
			"a 6th racer is refused (max 5)")
	_check(manager.get_child_count() == 4, "no stray nodes from refused racers", "(%d racer roots)" % manager.get_child_count())
	await _free(main)

	# Duplicate ids are refused too.
	var race := await _ai_only_race()
	var manager2: RacerManager = race["manager"]
	var first := manager2.add_ai_racer(MEDIUM, "A", 3)
	var duplicate := manager2.add_ai_racer(MEDIUM, "B", 3)
	_check(first != null and first.id == 3 and duplicate == null and manager2.get_racer_count() == 1,
			"a duplicate racer id is refused")
	await _free(race["world"])


## The five-racer scene and the command-line options give 1 human + 4 AI.
func _test_launch_options() -> void:
	print("\n[Racers: five-racer launch options]")
	await _clear_arena()
	var scene: RaceSession = (load("res://scenes/main/race_five.tscn") as PackedScene).instantiate()
	runner.add_child(scene)
	await _wait(0.3)
	var difficulties: Array[String] = []
	for racer in scene.racers.get_racers():
		if racer.is_ai():
			difficulties.append(racer.get_ai_driver().config.display_name)
	_check(scene.racers.get_racer_count() == 5 and difficulties == ["Hard", "Medium", "Medium", "Easy"],
			"race_five.tscn: 1 human + 4 mixed AI", "(%s)" % ", ".join(difficulties))
	await _free(scene)
	var main: RaceSession = MAIN_SCENE.instantiate()
	main._apply_command_line(PackedStringArray(["--ai=4", "--difficulty=hard", "res://ignored"]))
	runner.add_child(main)
	await _wait(0.3)
	var all_hard := true
	for racer in main.racers.get_racers():
		if racer.is_ai():
			all_hard = all_hard and racer.get_ai_driver().config.difficulty == HARD
	_check(main.racers.get_racer_count() == 5 and all_hard, "-- --ai=4 --difficulty=hard gives 4 hard AI")
	await _free(main)


func _test_input_isolation() -> void:
	print("\n[Racers: input isolation]")
	var main := await _load_race(4, 1, true)
	await _wait(0.5)
	var ai_racers: Array[Racer] = []
	var keyboard_free := true
	for racer in main.racers.get_racers():
		if racer.is_ai():
			ai_racers.append(racer)
			keyboard_free = keyboard_free and racer.trike.get_node_or_null(^"PlayerInputSource") == null \
					and racer.rider.get_node_or_null(^"PlayerInputSource") == null \
					and racer.trike.input_source is AIDriver and racer.rider.input_source == racer.trike.input_source
	_check(keyboard_free, "AI trikes and riders have no keyboard source, only their AIDriver")
	_check(main.trike.input_source is PlayerInputSource and main.rider.input_source is PlayerInputSource,
			"the human trike and rider read the keyboard")

	# Lobby: controls are locked for everyone, and W no longer starts the race.
	await runner._send_key(KEY_W, true)
	await runner._send_key(KEY_D, true)
	await _wait(0.3)
	_check(main.trike.input.throttle == 0.0 and main.trike.input.steer == 0.0 and not main.racers.is_race_started,
			"keys in the lobby neither move the human nor start the race")
	await runner._send_key(KEY_W, false)
	await runner._send_key(KEY_D, false)

	# Racing, with the AI brains paused so any key leak would show.
	main.race.start_immediately()
	for racer in ai_racers:
		racer.get_ai_driver().active = false
	await runner._send_key(KEY_D, true)
	await runner._send_key(KEY_E, true)
	await _wait(0.1)
	var ai_untouched := true
	for racer in ai_racers:
		ai_untouched = ai_untouched and racer.trike.input.steer == 0.0 and racer.trike.input.throttle == 0.0 \
				and not racer.rider.input.interact_pressed
	_check(main.trike.input.steer == 1.0, "D key steers the human trike once racing")
	_check(ai_untouched, "keyboard input never reaches AI racers")
	await runner._send_key(KEY_D, false)
	await runner._send_key(KEY_E, false)

	# AI drive; the human trike stays idle without keys.
	for racer in ai_racers:
		racer.get_ai_driver().start()
	await _wait(1.5)
	var ai_driving := true
	for racer in ai_racers:
		ai_driving = ai_driving and racer.trike.forward_speed > 5.0
	_check(ai_driving, "AI racers drive off once the race starts")
	_check(main.trike.input.throttle == 0.0 and main.trike.input.steer == 0.0,
			"AI input never reaches the human trike", "(human speed %.1f m/s)" % main.trike.forward_speed)
	await _free(main)


# --- Driving ----------------------------------------------------------------

func _test_one_ai_racer_drives() -> void:
	print("\n[AI: one AI racer, acceleration]")
	var race := await _ai_only_race()
	var manager: RacerManager = race["manager"]
	var racer := manager.add_ai_racer(MEDIUM)
	await _wait(1.5)
	_check(manager.get_racer_count() == 1 and racer.is_ai() and racer.id == 1, "a race can have one AI racer and no human")
	_check(racer.trike.linear_velocity.length() < 0.3, "AI holds still before the start")
	manager.start_race()
	await _wait(2.0)
	var speed := racer.trike.forward_speed
	_check(speed > 12.0, "AI accelerates through TrikeInput after the start", "(%.1f m/s after 2 s)" % speed)
	_check(racer.trike.input.throttle > 0.0 and racer.rider.is_riding(), "AI throttle is the trike's input")
	await _free(race["world"])


func _test_ai_steering() -> void:
	print("\n[AI: steering back onto the line]")
	var race := await _ai_only_race()
	var manager: RacerManager = race["manager"]
	var track: Track = race["track"]
	var racer := manager.add_ai_racer(MEDIUM)
	var driver := racer.get_ai_driver()
	var index := 40
	# Point the trike 35° to the left of the road.
	var frame := track.path.get_frame(index)
	frame.basis = frame.basis.rotated(frame.basis.y, deg_to_rad(35.0))
	racer.trike.teleport(frame.translated_local(Vector3(0.0, 0.8, 0.0)), false)
	racer.progress.reset(index)
	await _wait(0.5)
	manager.start_race()
	var first_steer := 0.0
	for i in _ticks(0.4):
		await _tree().physics_frame
		if absf(racer.trike.input.steer) > absf(first_steer):
			first_steer = racer.trike.input.steer
	await _wait(1.6)
	var forward := -racer.trike.global_basis.z
	var road := track.path.forwards[driver.path_index]
	var error := rad_to_deg(Vector2(forward.x, forward.z).angle_to(Vector2(road.x, road.z)))
	_check(first_steer > 0.2, "AI steers right toward the road direction", "(steer %.2f)" % first_steer)
	_check(absf(error) < 10.0, "heading lines up with the road within 2 s", "(%.1f° off)" % error)
	_check(track.is_on_road(racer.trike.global_position, driver.path_index) and racer.rider.is_riding(),
			"still on the road and riding")
	await _free(race["world"])


func _test_ai_path_following() -> void:
	print("\n[AI: path following]")
	var race := await _ai_only_race()
	var manager: RacerManager = race["manager"]
	var track: Track = race["track"]
	var racer := manager.add_ai_racer(MEDIUM)
	var driver := racer.get_ai_driver()
	await _wait(0.5)
	manager.start_race()
	var ticks := _ticks(25.0)
	var on_road := 0
	var error_sum := 0.0
	var max_error := 0.0
	var backwards := 0
	var airtime := 0.0
	var lined_up := false
	var landing_error := 0.0
	var was_airborne := false
	var last_index := racer.progress.current_index
	for i in ticks:
		await _tree().physics_frame
		lined_up = lined_up or driver.lining_up_ramp
		var airborne := racer.trike.grounded_wheel_count == 0
		if airborne:
			airtime += 1.0 / Engine.physics_ticks_per_second
		elif was_airborne:
			var heading := -racer.trike.global_basis.z
			var road := track.path.forwards[driver.path_index]
			landing_error = maxf(landing_error, rad_to_deg(Vector2(heading.x, heading.z).angle_to(Vector2(road.x, road.z))))
		was_airborne = airborne
		var index := driver.path_index
		var position := racer.trike.global_position
		on_road += 1 if track.is_on_road(position, index) else 0
		var error := absf(_lateral(track, position, index) - driver.planned_lateral)
		error_sum += error
		max_error = maxf(max_error, error)
		if racer.progress.current_index < last_index - 1:
			backwards += 1
		last_index = racer.progress.current_index
	var distance := racer.progress.get_distance()
	_check(distance > 450.0, "AI covers the track at race pace", "(%.0f m in 25 s)" % distance)
	_check(on_road == ticks, "AI never leaves the road", "(%d/%d ticks on road)" % [on_road, ticks])
	_check(error_sum / ticks < 0.8 and max_error < 4.5, "AI stays on its planned line (dodges included)",
			"(mean %.2f m, max %.2f m off the line)" % [error_sum / ticks, max_error])
	_check(backwards == 0 and racer.respawn_count == 0 and racer.rider.eject_count == 0,
			"no going backwards, no respawns, no crashes")
	_check(lined_up and airtime > 0.5, "AI lines up with the ramps and jumps them", "(%.1f s airtime)" % airtime)
	_check(absf(landing_error) < 20.0, "AI lands pointing down the road", "(worst landing %.0f° off)" % absf(landing_error))
	await _free(race["world"])


## A sharp 90° bend after a long straight: the AI must brake before it.
func _test_corner_braking() -> void:
	print("\n[AI: corner braking, all difficulties]")
	var points := PackedVector3Array([
		Vector3(0, 0, 0), Vector3(0, -10, -120), Vector3(6, -11, -136),
		Vector3(22, -12, -142), Vector3(120, -18, -142), Vector3(200, -22, -142),
	])
	var corner_speeds: Array[float] = []
	for difficulty in [EASY, MEDIUM, HARD]:
		var race := await _ai_only_race(points)
		var manager: RacerManager = race["manager"]
		var racer := manager.add_ai_racer(difficulty)
		var driver := racer.get_ai_driver()
		var apex := 0
		for i in track_size(race):
			if absf(driver.get_curvature(i)) > absf(driver.get_curvature(apex)):
				apex = i
		await _wait(0.5)
		manager.start_race()
		var braked := false
		var approach_speed := 0.0
		var corner_speed := INF
		var t := 0.0
		while not racer.finished and t < 30.0:
			await _tree().physics_frame
			t += 1.0 / Engine.physics_ticks_per_second
			var index := driver.path_index
			if index < apex:
				approach_speed = maxf(approach_speed, racer.trike.forward_speed)
				braked = braked or (racer.trike.input.brake > 0.0 and racer.trike.forward_speed > 1.0)
			if absf(index - apex) <= 6:
				corner_speed = minf(corner_speed, racer.trike.forward_speed)
		var name := driver.config.display_name
		_check(braked and corner_speed < approach_speed - 3.0, "%s AI brakes before the sharp corner" % name,
				"(%.1f -> %.1f m/s)" % [approach_speed, corner_speed])
		_check(racer.finished and racer.rider.eject_count == 0 and racer.respawn_count == 0,
				"%s AI gets round cleanly and finishes" % name, "(%.1f s)" % racer.finish_time)
		corner_speeds.append(corner_speed)
		await _free(race["world"])
	_check(corner_speeds[0] < corner_speeds[1] and corner_speeds[1] < corner_speeds[2],
			"harder AI carries more speed through the corner",
			"(easy %.1f, medium %.1f, hard %.1f m/s)" % [corner_speeds[0], corner_speeds[1], corner_speeds[2]])


func _test_difficulty_differences() -> void:
	print("\n[AI: difficulty changes driving]")
	var easy := AI_CONFIGS[0]
	var medium := AI_CONFIGS[1]
	var hard := AI_CONFIGS[2]
	_check(easy.top_speed_ratio < medium.top_speed_ratio and medium.top_speed_ratio < hard.top_speed_ratio,
			"top speed: easy < medium < hard")
	_check(easy.reaction_time > medium.reaction_time and medium.reaction_time > hard.reaction_time
			and easy.avoid_distance < medium.avoid_distance and medium.avoid_distance < hard.avoid_distance,
			"reactions and obstacle look-ahead improve with difficulty")
	_check(easy.drift_chance == 0.0 and medium.drift_chance > 0.0 and hard.drift_chance > medium.drift_chance,
			"easy never drifts, medium sometimes, hard more often")
	_check(easy.steer_noise > medium.steer_noise and medium.steer_noise > hard.steer_noise,
			"steering gets more accurate with difficulty")

	var times: Array[float] = []
	var wobble: Array[float] = []
	for difficulty in [EASY, MEDIUM, HARD]:
		var race := await _ai_only_race()
		var manager: RacerManager = race["manager"]
		var track: Track = race["track"]
		var racer := manager.add_ai_racer(difficulty)
		var driver := racer.get_ai_driver()
		await _wait(0.5)
		manager.start_race()
		var target := track.path.index_at_distance(500.0)
		var t := 0.0
		var error_sum := 0.0
		var samples := 0
		var steady_time := 0.0
		var last_plan := driver.planned_lateral
		while racer.progress.current_index < target and t < 60.0:
			await _tree().physics_frame
			var dt := 1.0 / Engine.physics_ticks_per_second
			t += dt
			# Accuracy = holding a line: only measured once the planned line
			# (lane, corner cut, dodge) has been steady for a second.
			steady_time = steady_time + dt if absf(driver.planned_lateral - last_plan) < 0.01 else 0.0
			last_plan = driver.planned_lateral
			if racer.trike.forward_speed > 10.0 and steady_time > 1.0:
				error_sum += absf(_lateral(track, racer.trike.global_position, driver.path_index) - driver.planned_lateral)
				samples += 1
		times.append(t)
		wobble.append(error_sum / maxi(samples, 1))
		await _free(race["world"])
	_check(times[2] < times[1] and times[1] < times[0], "hard is quickest, easy slowest over 500 m",
			"(easy %.1f s, medium %.1f s, hard %.1f s)" % [times[0], times[1], times[2]])
	_check(wobble[2] < wobble[0], "hard drives a tighter line than easy",
			"(mean line error easy %.2f m, hard %.2f m)" % [wobble[0], wobble[2]])


# --- Collisions, ejection, recovery, mounting --------------------------------

## Racer vs racer through the existing impact -> ejection path (arena rigs).
func _test_vehicle_collisions() -> void:
	print("\n[Racers: vehicle collisions]")
	await runner._new_arena()
	var victim: Dictionary = runner._rider_rig(Vector3(0.0, 0.9, 0.0))
	var bumper: Dictionary = runner._rider_rig(Vector3(0.0, 0.9, 12.0))
	var victim_trike: Trike = victim["trike"]
	var victim_rider: RiderController = victim["rider"]
	var bumper_trike: Trike = bumper["trike"]
	var bumper_rider: RiderController = bumper["rider"]
	_check(victim_trike.collision_mask & 2 != 0 and victim_trike.collision_layer & 2 != 0, "trikes collide with each other")
	await _wait(0.8)
	var max_impact := [0.0]
	victim_trike.impact.connect(func(strength: float, _v: Vector3) -> void: max_impact[0] = maxf(max_impact[0], strength))
	# Gentle bump: roll into the parked trike at ~4 m/s.
	await _ram(bumper_trike, victim_trike, 4.0)
	await _wait(0.6)
	_check(max_impact[0] > 0.0 and victim_rider.is_riding() and bumper_rider.is_riding(),
			"a slow bump nudges but ejects nobody", "(victim impact %.1f)" % max_impact[0])

	# Hard rear-end at ~20 m/s into a stationary trike.
	await runner._new_arena()
	victim = runner._rider_rig(Vector3(0.0, 0.9, 0.0))
	bumper = runner._rider_rig(Vector3(0.0, 0.9, 45.0))
	victim_trike = victim["trike"]
	victim_rider = victim["rider"]
	bumper_trike = bumper["trike"]
	await _wait(0.8)
	var hard_impact := [0.0]
	victim_trike.impact.connect(func(strength: float, _v: Vector3) -> void: hard_impact[0] = maxf(hard_impact[0], strength))
	await _ram(bumper_trike, victim_trike, 20.0)
	await _wait(0.3)
	_check(victim_rider.eject_count == 1, "a hard rear-end ejects the stationary rider",
			"(victim trike impact %.1f)" % hard_impact[0])
	await runner._new_arena()


## Drives `trike` straight into `target` at about `speed` m/s.
func _ram(trike: Trike, target: Trike, speed: float) -> void:
	var t := 0.0
	while t < 6.0 and trike.global_position.distance_to(target.global_position) > 2.6:
		trike.input.throttle = 1.0 if trike.forward_speed < speed else 0.0
		await _tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	trike.input.throttle = 0.0
	await _wait(0.4)
	trike.input.clear()


## Real crash into an unavoidable wall, then the whole rider loop with no teleport.
func _test_ai_eject_recover_mount() -> void:
	print("\n[AI: ejection, recovery, mounting]")
	var race := await _ai_only_race()
	var manager: RacerManager = race["manager"]
	var track: Track = race["track"]
	var world: Node3D = race["world"]
	var racer := manager.add_ai_racer(MEDIUM)
	var driver := racer.get_ai_driver()
	var rider := racer.rider
	var trike := racer.trike
	var states: Array[String] = []
	rider.state_changed.connect(func(_old: int, new_state: int) -> void:
		states.append(RiderController.STATE_NAMES[new_state]))
	var teleports := [0]
	trike.respawned.connect(func() -> void: teleports[0] += 1)
	var mounted := [0]
	rider.mounted.connect(func() -> void: mounted[0] += 1)
	await _wait(0.5)
	manager.start_race()
	await _wait(3.5)
	# A wall right across the road, a few meters ahead: no way to dodge it.
	var index := driver.path_index + roundi(maxf(racer.trike.forward_speed, 10.0) * 0.3 / track.path.spacing) + 2
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(track.road_width + 2.0, 3.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	world.add_child(wall)
	wall.global_transform = track.path.get_frame(index).translated_local(Vector3(0.0, 1.4, 0.0))
	var speed_before := trike.forward_speed
	var t := 0.0
	while rider.is_riding() and t < 2.0:
		await _tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	_check(rider.eject_count == 1, "AI rider is thrown off by a real crash", "(%.1f m/s into a wall)" % speed_before)
	_check(not trike.has_rider and trike.input.throttle == 0.0, "the empty trike gets no AI input")
	wall.queue_free()

	var trike_start := trike.global_position
	await runner._wait_for_state(rider, RiderController.State.ON_FOOT, 5.0)
	_check(rider.state == RiderController.State.ON_FOOT, "ragdoll settles and the AI gets up",
			"(%s)" % " → ".join(states))
	var foot_start := rider.on_foot.global_position
	var start_gap := foot_start.distance_to(trike.global_position)
	var closest := start_gap
	var walked := 0.0
	var last := foot_start
	t = 0.0
	while rider.state == RiderController.State.ON_FOOT and t < 10.0:
		await _tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		walked += rider.on_foot.global_position.distance_to(last)
		last = rider.on_foot.global_position
		closest = minf(closest, rider.on_foot.global_position.distance_to(trike.global_position))
	_check(rider.state == RiderController.State.MOUNTING or rider.is_riding(), "AI reaches its trike and starts mounting",
			"(after %.1f s on foot)" % t)
	_check(closest <= rider.config.mount_distance and walked >= maxf(start_gap - rider.config.mount_distance - 0.3, 0.0),
			"AI walked to mounting range", "(%.1f m from the trike, walked %.1f m)" % [start_gap, walked])
	await runner._wait_for_state(rider, RiderController.State.RIDING, 2.0)
	var expected := ["EJECTED", "RAGDOLL", "GETTING_UP", "ON_FOOT", "MOUNTING", "RIDING"]
	_check(states == expected, "full state sequence through the rider state machine", "(%s)" % " → ".join(states))
	_check(mounted[0] == 1 and driver.mount_count >= 1 and driver.emergency_count == 0,
			"mounted with E, no emergency recovery")
	_check(teleports[0] == 0 and racer.respawn_count == 0 and trike.global_position.distance_to(trike_start) < 6.0,
			"neither trike nor rider was teleported")
	var index_before := racer.progress.current_index
	await _wait(5.0)
	_check(rider.is_riding() and trike.forward_speed > 8.0 and racer.progress.current_index > index_before + 10,
			"AI resumes racing after remounting",
			"(%.1f m/s, +%d m)" % [trike.forward_speed, (racer.progress.current_index - index_before) * 2])
	await _free(world)


## Rider on foot with a wall between it and the trike: walks around it.
func _test_ai_on_foot_detour() -> void:
	print("\n[AI: on foot around an obstacle]")
	var race := await _ai_only_race()
	var manager: RacerManager = race["manager"]
	var track: Track = race["track"]
	var world: Node3D = race["world"]
	var racer := manager.add_ai_racer(MEDIUM)
	var driver := racer.get_ai_driver()
	var rider := racer.rider
	var trike := racer.trike
	await _wait(1.0)
	manager.start_race()
	rider.eject()
	await runner._wait_for_state(rider, RiderController.State.ON_FOOT, 5.0)
	# Trike parked on the road, rider 7 m behind it, a 4 m wide wall 3.4 m
	# behind the trike (outside the mount distance).
	var index := track.path.find_nearest(trike.global_position)
	var frame := track.path.get_frame(index)
	var behind := frame.basis.z * 7.0
	rider.on_foot.activate(trike.global_position + behind + Vector3.UP * 0.3, -behind)
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 2.5, 0.4)
	shape.shape = box
	wall.add_child(shape)
	world.add_child(wall)
	wall.global_transform = Transform3D(frame.basis, trike.global_position + behind.normalized() * 3.4 + frame.basis.y * 0.8)
	await _tree().physics_frame
	var query := PhysicsRayQueryParameters3D.create(rider.on_foot.global_position, trike.global_position, 1)
	var walled_off := not world.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	_check(rider.state == RiderController.State.ON_FOOT and walled_off
			and rider.on_foot.global_position.distance_to(trike.global_position) > rider.config.mount_distance,
			"setup: rider on foot, out of reach, wall in the way")
	var t := 0.0
	while rider.state == RiderController.State.ON_FOOT and t < 10.0:
		await _tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	_check(rider.state == RiderController.State.MOUNTING or rider.is_riding(), "AI walks around the wall to its trike",
			"(%.1f s, %d side-steps)" % [t, driver.detour_count])
	_check(driver.emergency_count == 0 and racer.respawn_count == 0, "no emergency recovery needed")
	await _free(world)


## Nose against the barrier at a standstill: reverses out and drives on.
func _test_ai_unstuck() -> void:
	print("\n[AI: recovering from a mistake]")
	var race := await _ai_only_race()
	var manager: RacerManager = race["manager"]
	var track: Track = race["track"]
	var racer := manager.add_ai_racer(MEDIUM)
	var driver := racer.get_ai_driver()
	var index := 60
	var frame := track.path.get_frame(index)
	# Facing the right-hand barrier, 1.3 m from it.
	var facing := Basis.looking_at(frame.basis.x, frame.basis.y)
	var spot := frame.origin + frame.basis.x * (track.road_width * 0.5 - 1.3) + frame.basis.y * 0.8
	racer.trike.teleport(Transform3D(facing, spot), false)
	racer.progress.reset(index)
	driver.path_index = index
	await _wait(1.0)
	manager.start_race()
	var reversed := false
	var t := 0.0
	while t < 12.0 and racer.progress.current_index < index + 20:
		await _tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		reversed = reversed or driver.is_reversing
	_check(racer.progress.current_index >= index + 20, "AI turns away from the barrier and carries on",
			"(%.1f s, reversed: %s)" % [t, reversed])
	_check(driver.reset_count == 0 and racer.respawn_count == 0 and racer.rider.is_riding(),
			"no reset or respawn needed")
	await _free(race["world"])


# --- Full race --------------------------------------------------------------

## 4 AI race the whole track around a human who never moves off the grid.
func _test_ai_finishing() -> void:
	print("\n[AI: five-racer race to the finish]")
	var main := await _load_race(4, 3)
	await _wait(0.5)
	main.race.start_immediately()
	var ai_racers: Array[Racer] = []
	for racer in main.racers.get_racers():
		if racer.is_ai():
			ai_racers.append(racer)
	var t := 0.0
	var all_done := false
	var worst_physics := 0.0
	while not all_done and t < 150.0:
		var started := Time.get_ticks_usec()
		await _tree().physics_frame
		worst_physics = maxf(worst_physics, (Time.get_ticks_usec() - started) / 1000.0)
		t += 1.0 / Engine.physics_ticks_per_second
		all_done = true
		for racer in ai_racers:
			all_done = all_done and racer.finished
	var positions := {}
	var summary := ""
	var ejects := 0
	var resets := 0
	for racer in ai_racers:
		positions[racer.finish_position] = true
		ejects += racer.rider.eject_count
		resets += racer.get_ai_driver().reset_count + racer.get_ai_driver().emergency_count
		summary += "%s(%s) %s %.1fs  " % [racer.display_name, racer.get_ai_driver().config.display_name,
				RaceSession.ordinal(racer.finish_position), racer.finish_time]
	_check(all_done, "all 4 AI racers finish the race", "(%s)" % summary.strip_edges())
	_check(positions.size() == 4 and positions.has(1) and positions.has(4), "AI finishing positions are 1st-4th, no ties")
	_check(not main.get_local_racer().finished and not main.is_race_finished(),
			"the idle human is not finished by anyone else's trike")
	_check(resets == 0, "no AI needed a reset or emergency recovery", "(%d crashes, all self-recovered)" % ejects)
	await _wait(3.0)
	var stopped := true
	for racer in ai_racers:
		stopped = stopped and racer.trike.linear_velocity.length() < 2.0
	_check(stopped, "finished AI pull over and stop")
	print("        info: worst headless frame during the 5-racer race %.1f ms" % worst_physics)
	await _free(main)
