extends Node
## Long driving tests: whole races on every full map, timed.
##   Godot --headless --path . --fixed-fps 60 --scene res://tests/map_test_runner.tscn
##   ... -- --map=snow_slide   (one map; also --player-only, --item-seed=N, --verbose)
## Exit code 0 = all passed. Writes user://map_tests/<map>_report.json per map.
##
## Races (simulated time; headless runs much faster than real time):
##   mixed   five AI: hard, medium, medium, easy, hard
##   easy    five easy AI (the slowest field)
##   hard    five hard AI (dense pack: collisions, overtaking)
##   player  the real race scene: countdown, a simple "player" driver (no
##           drifting, brakes for corners, never uses boosts) for the local
##           racer and four mixed AI, through to the results screen
## Every racer must finish through every checkpoint, without being stuck.

const MAPS: Array[Dictionary] = [
	{"id": "forest_rush", "track": preload("res://scenes/tracks/forest_rush.tscn"), "race": preload("res://scenes/main/forest_rush.tscn")},
	{"id": "rocky_canyon", "track": preload("res://scenes/tracks/rocky_canyon.tscn"), "race": preload("res://scenes/main/rocky_canyon.tscn")},
	{"id": "snow_slide", "track": preload("res://scenes/tracks/snow_slide.tscn"), "race": preload("res://scenes/main/snow_slide.tscn")},
]
const AI_CONFIGS: Array[AIDriverConfig] = [
	preload("res://resources/ai/ai_easy.tres"),
	preload("res://resources/ai/ai_medium.tres"),
	preload("res://resources/ai/ai_hard.tres"),
]
const EASY := AIDriverConfig.Difficulty.EASY
const MEDIUM := AIDriverConfig.Difficulty.MEDIUM
const HARD := AIDriverConfig.Difficulty.HARD
## Longest simulated race before giving up (s).
const RACE_LIMIT := 900.0
## The design target for one racer's run (s).
const TARGET := Vector2(300.0, 600.0)

var _passed := 0
var _failed := 0
var _report := {}
var _map: Dictionary


func _ready() -> void:
	GameSettings.use_test_profile("user://test_settings.cfg")
	_run.call_deferred()


func _run() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			only = arg.trim_prefix("--map=")
	for map in MAPS:
		if only.is_empty() or only == map["id"]:
			await _run_map(map)
	print("\n=== RESULT: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _run_map(map: Dictionary) -> void:
	_map = map
	_report = {"map": map["id"], "races": []}
	print("\n=== %s MAP RACES ===" % String(map["id"]).to_upper().replace("_", " "))
	if not OS.get_cmdline_user_args().has("--player-only"):
		await _ai_race("mixed", [HARD, MEDIUM, MEDIUM, EASY, HARD])
		await _ai_race("easy", [EASY, EASY, EASY, EASY, EASY])
		await _ai_race("hard", [HARD, HARD, HARD, HARD, HARD])
	await _player_race()
	DirAccess.make_dir_recursive_absolute("user://map_tests")
	var path := "user://map_tests/%s_report.json" % map["id"]
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(_report, "  "))
	file.close()
	print("\nreport: %s" % ProjectSettings.globalize_path(path))


func _check(condition: bool, test_name: String, detail := "") -> void:
	test_name = "%s %s" % [_map.get("id", ""), test_name]
	if condition:
		_passed += 1
		print("  PASS  %s  %s" % [test_name, detail])
	else:
		_failed += 1
		print("  FAIL  %s  %s" % [test_name, detail])


## One racer's numbers for the report and the summary line.
func _racer_row(racer: Racer, label: String) -> Dictionary:
	var driver := racer.get_ai_driver()
	return {
		"name": racer.display_name, "driver": label, "finished": racer.finished,
		"time": snappedf(racer.finish_time, 0.01) if racer.finished else -1.0,
		"position": racer.finish_position, "checkpoints": racer.checkpoints.get_passed_count(),
		"wipeouts": racer.rider.eject_count, "respawns": racer.respawn_count,
		"ai_resets": (driver.reset_count + driver.emergency_count) if driver else 0,
	}


func _summarize(race_name: String, rows: Array, total_checkpoints: int, wall_seconds: float) -> void:
	var all_finished := true
	var all_checkpoints := true
	var stuck := 0
	var line := ""
	var times := []
	for row: Dictionary in rows:
		all_finished = all_finished and row["finished"]
		all_checkpoints = all_checkpoints and row["checkpoints"] == total_checkpoints
		stuck += int(row["ai_resets"])
		line += "\n        %-8s %-7s %s  wipeouts %d, respawns %d" % [row["name"], row["driver"],
				Hud.format_time(row["time"]) if row["finished"] else "DNF", row["wipeouts"], row["respawns"]]
		if row["finished"]:
			times.append(row["time"])
	times.sort()
	print("  [%s] (%.0f s real)%s" % [race_name, wall_seconds, line])
	_check(all_finished and all_checkpoints, "%s: every racer finishes through all %d checkpoints" % [race_name, total_checkpoints])
	_check(stuck == 0, "%s: no AI got stuck (no reset or emergency recovery)" % race_name, "(%d)" % stuck)
	if not times.is_empty():
		_check(times[0] >= TARGET.x and times[-1] <= TARGET.y, "%s: every run takes 5-10 minutes" % race_name,
				"(%s to %s)" % [Hud.format_time(times[0]), Hud.format_time(times[-1])])
	_report["races"].append({"race": race_name, "racers": rows, "real_seconds": snappedf(wall_seconds, 0.1)})


## Five AI racers on the bare map (no local player).
func _ai_race(race_name: String, difficulties: Array) -> void:
	print("\n[%s race: %s]" % [race_name, ", ".join(difficulties.map(func(d: int) -> String: return AI_CONFIGS[d].display_name))])
	var started := Time.get_ticks_msec()
	var world := Node3D.new()
	add_child(world)
	var track: Track = (_map["track"] as PackedScene).instantiate()
	world.add_child(track)
	var manager := RacerManager.new()
	manager.ai_configs = AI_CONFIGS.duplicate()
	world.add_child(manager)
	manager.setup(track)
	var racers: Array[Racer] = []
	for d: int in difficulties:
		racers.append(manager.add_ai_racer(d))
	await get_tree().physics_frame
	manager.start_race()
	var t := 0.0
	while t < RACE_LIMIT and not manager.is_everyone_finished():
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	var rows := []
	for racer in racers:
		rows.append(_racer_row(racer, racer.get_ai_driver().config.display_name))
	_summarize(race_name, rows, track.get_checkpoints().size(), (Time.get_ticks_msec() - started) / 1000.0)
	world.queue_free()
	await get_tree().process_frame


## The real race scene with countdown, results and a simple player driver.
func _player_race() -> void:
	print("\n[player race: race scene, simple player driver + 4 mixed AI]")
	var started := Time.get_ticks_msec()
	player_resets = 0
	_stuck_time = 0.0
	var main: RaceSession = (_map["race"] as PackedScene).instantiate()
	# Repeatable item rolls (`-- --item-seed=N` tries another sequence).
	(main.get_node("Items") as ItemManager).rng_seed = _item_seed()
	add_child(main)
	main.trike.input_source = null
	main.rider.input_source = null
	main.race.finish_timeout = 0.0  # wait for everyone, so every time is measured
	var pilot := TrackAutopilot.new(main.track, main.trike)
	pilot.target_speed = 20.0
	var me := main.get_local_racer()
	var item_log: Array[String] = []
	main.items.event_applied.connect(func(event: Array) -> void:
		item_log.append("%.1f %s %s" % [main.racers.race_time, ItemManager.EVENT_NAMES[int(event[1])], str(event.slice(2))]))
	main.racers.racer_respawned.connect(func(racer: Racer) -> void:
		item_log.append("%.1f RESPAWN %s (%s)" % [main.racers.race_time, racer.display_name,
				"AI reset" if racer.get_ai_driver() and racer.get_ai_driver().reset_count + racer.get_ai_driver().emergency_count > 0 else "auto"]))
	for racer in main.racers.get_racers():
		racer.rider.ejected.connect(func(strength: float) -> void:
			item_log.append("%.1f EJECTED %s (%.1f)" % [main.racers.race_time, racer.display_name, strength]))
	var countdown_seen := false
	var t := 0.0
	while t < RACE_LIMIT + 10.0 and main.race.get_state() != RaceStateMachine.State.RESULTS:
		countdown_seen = countdown_seen or main.race.get_state() == RaceStateMachine.State.COUNTDOWN
		if main.race.is_racing() and not me.finished:
			if main.rider.is_riding():
				pilot.lateral_offset = _dodge(main, pilot.lateral_offset)
				pilot.drive()
				_reset_when_stuck(main)
			else:
				_walk_back(main)
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		if OS.get_cmdline_user_args().has("--verbose") and fmod(t, 5.0) < 1.0 / 60.0:
			print("   t=%.0f d=%.0f %s speed %.1f cp %d" % [t, me.progress.current_index * 2.0, main.rider.get_state_name(),
					main.trike.forward_speed, me.checkpoints.get_passed_count()])
	var rows := []
	for racer in main.racers.get_racers():
		rows.append(_racer_row(racer, "player" if racer == me else racer.get_ai_driver().config.display_name))
	_check(countdown_seen and main.race.get_state() == RaceStateMachine.State.RESULTS,
			"player race: countdown, race and results screen", "(%s)" % main.race.get_state_name())
	_check(main.results_screen.row_texts.size() == 5, "player race: results list all five racers",
			"(%s)" % " / ".join(main.results_screen.row_texts))
	print("        info: the player driver pressed reset %d times" % player_resets)
	var counts := {}
	for event_name: String in ["BOX_TAKEN", "TURBO_USED", "BANANA_DROPPED", "BOMB_THROWN", "PUNCH", "BANANA_HIT", "EJECTED"]:
		counts[event_name] = item_log.filter(func(line: String) -> bool: return line.contains(" %s " % event_name)).size()
	var punch_hits := item_log.filter(func(line: String) -> bool: return line.contains(" PUNCH ") and not line.contains(", 0, (0.0")).size()
	var bomb_hits := item_log.filter(func(line: String) -> bool:
		return line.contains(" BOMB_LANDED ") and not line.contains("), 0, ")).size()
	print("        info: item seed %d: %d pickups; used %d turbo, %d banana, %d mud bomb, %d punch; hits: %d slips, %d bombs, %d punches; %d wipeouts" % [
			_item_seed(), counts["BOX_TAKEN"], counts["TURBO_USED"], counts["BANANA_DROPPED"], counts["BOMB_THROWN"],
			counts["PUNCH"], counts["BANANA_HIT"], bomb_hits, punch_hits, counts["EJECTED"]])
	if OS.get_cmdline_user_args().has("--verbose"):
		for line in item_log:
			print("          ", line)
	_report["player_race_item_log"] = item_log
	rows[0]["player_resets"] = player_resets
	_summarize("player", rows, main.track.get_checkpoints().size(), (Time.get_ticks_msec() - started) / 1000.0)
	main.queue_free()
	await get_tree().process_frame


var _stuck_time := 0.0
var player_resets := 0


func _item_seed() -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--item-seed="):
			return arg.trim_prefix("--item-seed=").to_int()
	return 7


## Like a person: pick a line around obstacles seen up to 40 m ahead
## (boulders, trees, logs on the road, crates, rocks).
func _dodge(main: RaceSession, current: float) -> float:
	var track := main.track
	var trike := main.trike
	var index := main.get_progress().current_index
	var half := track.half_width_at(index) - 1.6
	var forward := track.path.forwards[index]
	var wanted := 0.0
	for obstacle: Dictionary in main.racers.get_obstacles():
		var node: Node3D = obstacle["node"]
		if not is_instance_valid(node) or (node.has_method(&"is_active") and not node.call(&"is_active")):
			continue
		var along := (node.global_position - trike.global_position).dot(forward)
		if along < -2.0 or along > 40.0:
			continue
		var at := track.path.find_nearest(node.global_position, index)
		var lateral := (node.global_position - track.path.points[at]).dot(track.path.rights[at])
		var clearance: float = obstacle["radius"] + 2.0
		if absf(current - lateral) < clearance:
			# Pass on the side with more room.
			wanted = lateral + clearance if lateral < 0.0 else lateral - clearance
			return clampf(wanted, -half, half)
		if absf(current - lateral) < clearance + 1.0:
			return current
	return move_toward(current, wanted, 0.05)


## Like a person: press reset after being stuck for 3 s.
func _reset_when_stuck(main: RaceSession) -> void:
	if absf(main.trike.forward_speed) < 1.0:
		_stuck_time += 1.0 / Engine.physics_ticks_per_second
	else:
		_stuck_time = 0.0
	if _stuck_time > 3.0:
		_stuck_time = 0.0
		player_resets += 1
		main.trike.input.reset_pressed = true


## After a wipeout the simple player walks back to the trike and remounts,
## like a person would: run toward the trike, press interact when close.
func _walk_back(main: RaceSession) -> void:
	var rider := main.rider
	var input := rider.input
	input.move_direction = Vector3.ZERO
	if rider.state == RiderController.State.ON_FOOT:
		var to_trike := main.trike.global_position - rider.on_foot.global_position
		to_trike.y = 0.0
		input.move_direction = to_trike.normalized()
		input.interact_pressed = to_trike.length() < 2.5
