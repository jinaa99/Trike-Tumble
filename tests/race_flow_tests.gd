extends RefCounted
## Race management tests (final-demo milestone 03): state machine, countdown,
## checkpoints, positions, finish in the race flow, results, race again.
## Run as part of tests/test_runner.gd; uses its helpers.

const MAIN_SCENE := preload("res://scenes/main/main.tscn")
const TRACKS_DIR := "res://scenes/tracks"
const State := RaceStateMachine.State

var runner: Node


func _init(test_runner: Node) -> void:
	runner = test_runner


func run() -> void:
	_test_state_machine_rules()
	await _test_every_map_has_checkpoints()
	await _test_countdown_and_start()
	await _test_checkpoint_order_and_reverse()
	await _test_skipped_checkpoints()
	await _test_checkpoints_survive_ejection()
	_test_position_ranking_rules()
	await _test_full_race_positions_finish_results()
	await _test_pending_finish_in_race()
	await _test_finish_timeout_and_dnf()
	await _test_race_again_and_lobby()


# --- Helpers ----------------------------------------------------------------

func _check(condition: bool, test_name: String, detail := "") -> void:
	runner._check(condition, test_name, detail)


func _tree() -> SceneTree:
	return runner.get_tree()


func _wait(seconds: float) -> void:
	await runner._wait(seconds)


func _dt() -> float:
	return 1.0 / Engine.physics_ticks_per_second


func _clear_arena() -> void:
	if runner._arena:
		runner._arena.queue_free()
		runner._arena = null
	await _tree().process_frame


## Race scene; the local player is driven by tests (no keyboard).
func _load_flow(ai_count: int, auto_start := true) -> RaceSession:
	await _clear_arena()
	var main: RaceSession = MAIN_SCENE.instantiate()
	main.ai_racer_count = ai_count
	main.ai_difficulty = 3
	main.auto_start = auto_start
	runner.add_child(main)
	main.trike.input_source = null
	main.rider.input_source = null
	return main


func _free(node: Node) -> void:
	node.queue_free()
	await _tree().process_frame


## Waits until the race reaches `wanted` (or `seconds` pass), driving the
## local trike with `pilot` if given.
func _run_until_state(main: RaceSession, wanted: State, seconds: float, pilot: TrackAutopilot = null) -> float:
	var t := 0.0
	while main.race.get_state() != wanted and t < seconds:
		if pilot and main.rider.is_riding():
			pilot.drive()
		await _tree().physics_frame
		t += _dt()
	return t


func _teleport(main: RaceSession, racer: Racer, index: int) -> void:
	racer.trike.teleport(main.track.path.get_frame(index).translated_local(Vector3(racer.lane_offset, 0.8, 0.0)))
	racer.progress.reset(index)


# --- State machine ----------------------------------------------------------

func _test_state_machine_rules() -> void:
	print("\n[Race flow: state machine]")
	var machine := RaceStateMachine.new()
	var changes: Array[String] = []
	machine.state_changed.connect(func(old: State, new_state: State) -> void:
		changes.append("%s>%s" % [RaceStateMachine.STATE_NAMES[old], RaceStateMachine.STATE_NAMES[new_state]]))
	_check(machine.state == State.LOBBY, "starts in LOBBY")
	var refused := not machine.transition(State.RACING) and not machine.transition(State.RESULTS) \
			and not machine.transition(State.FINISHED)
	_check(refused and machine.state == State.LOBBY, "LOBBY can't jump to RACING, FINISHED or RESULTS")
	var path := machine.transition(State.COUNTDOWN) and machine.transition(State.RACING) \
			and machine.transition(State.FINISHED) and machine.transition(State.RESULTS) \
			and machine.transition(State.LOBBY)
	_check(path and changes == ["LOBBY>COUNTDOWN", "COUNTDOWN>RACING", "RACING>FINISHED", "FINISHED>RESULTS", "RESULTS>LOBBY"],
			"LOBBY → COUNTDOWN → RACING → FINISHED → RESULTS → LOBBY, each announced", "(%s)" % ", ".join(changes))
	machine.transition(State.COUNTDOWN)
	_check(not machine.transition(State.RESULTS) and not machine.transition(State.FINISHED) and machine.transition(State.LOBBY),
			"COUNTDOWN can only go to RACING or back to LOBBY")


func _test_every_map_has_checkpoints() -> void:
	print("\n[Checkpoints: every map]")
	await _clear_arena()
	var files := DirAccess.get_files_at(TRACKS_DIR)
	var maps := 0
	for file in files:
		if not file.ends_with(".tscn"):
			continue
		var track := (load(TRACKS_DIR.path_join(file)) as PackedScene).instantiate() as Track
		if track == null:
			continue
		maps += 1
		runner.add_child(track)
		var cps := track.get_checkpoints()
		var ordered := cps.size() >= 3
		for i in range(1, cps.size()):
			ordered = ordered and cps[i] > cps[i - 1] \
					and (cps[i] - cps[i - 1]) * track.path.spacing <= track.checkpoint_spacing + track.checkpoint_finish_gap + 2.0
		_check(ordered and cps[0] > track.get_start_index() and cps[cps.size() - 1] == track.get_finish_index(),
				"%s: %d ordered checkpoints from the start to the finish line" % [file, cps.size()])
		await _free(track)
	_check(maps >= 1, "found the maps to check", "(%d)" % maps)


# --- Countdown, starting controls, timer ------------------------------------

func _test_countdown_and_start() -> void:
	print("\n[Race flow: countdown, starting controls, timer]")
	var main := await _load_flow(4)
	var steps: Array[String] = []
	var step_times: Array[float] = []
	var hud_texts: Array[String] = []
	var clock := [0.0]
	main.race.countdown_step.connect(func(text: String) -> void:
		steps.append(text)
		step_times.append(clock[0]))
	_check(main.race.get_state() == State.LOBBY and main.racers.get_racer_count() == 5,
			"all 5 racers spawned, race waiting in LOBBY")
	var max_speed := 0.0
	var moved := false
	var ai_active := false
	var clock_ran := false
	while main.race.get_state() != State.RACING and clock[0] < 6.0:
		main.trike.input.throttle = 1.0  # flooring it before GO does nothing
		await _tree().physics_frame
		await _tree().process_frame
		clock[0] += _dt()
		var shown := main.hud.get_message_text()
		if shown != "" and (hud_texts.is_empty() or hud_texts[-1] != shown):
			hud_texts.append(shown)
		if main.race.get_state() != State.COUNTDOWN:
			continue  # spawn settling in the lobby; GO happened this tick
		for racer in main.racers.get_racers():
			max_speed = maxf(max_speed, racer.trike.linear_velocity.length())
			moved = moved or racer.trike.global_position.distance_to(racer.spawn_transform.origin) > 0.5
			if racer.is_ai():
				ai_active = ai_active or racer.get_ai_driver().active
		clock_ran = clock_ran or main.racers.race_time > 0.0
	_check(steps == ["3", "2", "1", "GO!"], "countdown shows 3, 2, 1, GO!", "(%s)" % ", ".join(steps))
	_check(hud_texts.slice(0, 3) == ["3", "2", "1"], "the HUD displays each number", "(%s)" % ", ".join(hud_texts))
	var spacing_ok := step_times.size() == 4
	for i in range(1, step_times.size()):
		spacing_ok = spacing_ok and absf(step_times[i] - step_times[i - 1] - main.race.countdown_step_time) < 0.05
	_check(spacing_ok, "one second per step", "(%s)" % str(step_times))
	_check(main.race.machine.history == [State.LOBBY, State.COUNTDOWN, State.RACING],
			"states: LOBBY → COUNTDOWN → RACING")
	_check(max_speed < 0.5 and not moved, "no racer moves during the countdown, even with throttle held",
			"(max %.2f m/s)" % max_speed)
	_check(not ai_active and not clock_ran, "AI and race timer wait for GO")
	await _tree().process_frame
	_check(main.hud.get_message_text() == "GO!", "HUD shows GO!")
	var t := 0.0
	while t < 1.5:
		main.trike.input.throttle = 1.0
		await _tree().physics_frame
		t += _dt()
	main.trike.input.clear()
	_check(main.trike.forward_speed > 10.0, "after GO the player drives", "(%.1f m/s after 1.5 s)" % main.trike.forward_speed)
	var ai_moving := true
	for racer in main.racers.get_racers():
		if racer.is_ai():
			ai_moving = ai_moving and racer.trike.forward_speed > 5.0
	_check(ai_moving, "after GO the AI drive")
	_check(absf(main.racers.race_time - 1.5) < 0.05 and absf(main.get_race_time() - main.racers.race_time) < 0.05,
			"race timer starts at GO", "(%.2f s after 1.5 s)" % main.racers.race_time)
	await _free(main)


# --- Checkpoints ------------------------------------------------------------

func _test_checkpoint_order_and_reverse() -> void:
	print("\n[Checkpoints: order, no repeats, reversing]")
	var main := await _load_flow(0)
	main.race.start_immediately()
	var racer := main.get_local_racer()
	var cps := racer.checkpoints
	var passed: Array[int] = []
	cps.checkpoint_passed.connect(func(checkpoint: int) -> void: passed.append(checkpoint))
	var pilot := TrackAutopilot.new(main.track, main.trike)
	var target := cps.checkpoints[1] + 10
	var t := 0.0
	while racer.progress.current_index < target and t < 30.0:
		pilot.drive()
		await _tree().physics_frame
		t += _dt()
	main.trike.input.clear()
	_check(passed == [0, 1] and cps.get_passed_count() == 2, "checkpoints register in order while driving",
			"(passed %s)" % str(passed))
	await runner._hold(main.trike, 2.0, 0.0, 1.0)  # brake to a stop
	var before := cps.distance
	var max_seen := before
	# Reverse back over checkpoint 1.
	t = 0.0
	while racer.progress.current_index > cps.checkpoints[1] - 6 and t < 12.0:
		main.trike.input.brake = 1.0
		main.trike.input.steer = 0.0
		await _tree().physics_frame
		t += _dt()
		max_seen = maxf(max_seen, cps.distance)
	main.trike.input.clear()
	_check(racer.progress.current_index < cps.checkpoints[1], "setup: reversed back over checkpoint 2",
			"(%.1f s)" % t)
	_check(max_seen <= before + 0.5 and cps.distance < before - 5.0, "reversing never gains progress",
			"(%.1f m → %.1f m)" % [before, cps.distance])
	_check(cps.get_passed_count() == 2, "reversing keeps the checkpoints already passed")
	# Drive forward through checkpoint 1 again.
	t = 0.0
	while racer.progress.current_index < cps.checkpoints[1] + 8 and t < 10.0:
		pilot.drive()
		await _tree().physics_frame
		t += _dt()
	main.trike.input.clear()
	_check(passed == [0, 1], "driving through a checkpoint again doesn't register it twice", "(%s)" % str(passed))
	await _free(main)


func _test_skipped_checkpoints() -> void:
	print("\n[Checkpoints: skipping]")
	var main := await _load_flow(1)
	main.race.start_immediately()
	var racer := main.get_local_racer()
	var ai := main.racers.get_racer(2)
	ai.get_ai_driver().active = false
	var cps := racer.checkpoints
	await _wait(0.3)
	# Jump well past checkpoint 1 without driving through it.
	_teleport(main, racer, cps.checkpoints[0] + 40)
	await _hold_throttle(main.trike, 1.5)
	_check(cps.get_passed_count() == 0 and cps.missed_checkpoint, "jumping past a checkpoint doesn't pass it")
	_check(cps.distance <= cps.checkpoints[0] * main.track.path.spacing + 0.01,
			"progress stays capped at the skipped checkpoint", "(%.0f m)" % cps.distance)
	# Straight to the finish line from there: doesn't count.
	var pending := [0]
	main.get_finish_tracker().finish_pending.connect(func(_id: int, _t: float) -> void: pending[0] += 1)
	_teleport(main, racer, main.track.get_finish_index() - 12)
	await _hold_throttle(main.trike, 3.0)
	_check(racer.progress.current_index > main.track.get_finish_index() and not racer.finished
			and pending[0] == 0 and not main.get_finish_tracker().has_finished(racer.id),
			"crossing the finish line with skipped checkpoints doesn't finish",
			"(index %d / finish %d, finished %s, pending %d)" % [racer.progress.current_index,
			main.track.get_finish_index(), racer.finished, pending[0]])
	_check(not cps.can_finish(), "finish stays locked until every checkpoint is passed")
	await _free(main)


func _hold_throttle(trike: Trike, seconds: float) -> void:
	await runner._hold(trike, seconds, 1.0)


func _test_checkpoints_survive_ejection() -> void:
	print("\n[Checkpoints: rider ejection]")
	var main := await _load_flow(0)
	main.race.start_immediately()
	var racer := main.get_local_racer()
	var cps := racer.checkpoints
	var pilot := TrackAutopilot.new(main.track, main.trike)
	var t := 0.0
	while cps.get_passed_count() < 1 and t < 20.0:
		pilot.drive()
		await _tree().physics_frame
		t += _dt()
	var passed_before := cps.get_passed_count()
	var distance_before := cps.distance
	main.rider.eject()
	var min_passed := passed_before
	t = 0.0
	while not main.rider.is_riding() and t < 8.0:
		if main.rider.state == RiderController.State.ON_FOOT and main.rider.can_mount:
			main.rider.input.interact_pressed = true
		elif main.rider.state == RiderController.State.ON_FOOT:
			var to_trike := main.trike.global_position - main.rider.on_foot.global_position
			main.rider.input.move_direction = Vector3(to_trike.x, 0.0, to_trike.z).normalized()
		await _tree().physics_frame
		t += _dt()
		min_passed = mini(min_passed, cps.get_passed_count())
	main.rider.input.clear()
	_check(passed_before >= 1 and min_passed == passed_before, "checkpoints stay passed through the whole wipeout")
	_check(main.rider.is_riding() and cps.get_passed_count() == passed_before and cps.distance >= distance_before - 10.0,
			"back on the trike with the same checkpoint state", "(%.1f s off the trike)" % t)
	await _free(main)


# --- Positions --------------------------------------------------------------

func _test_position_ranking_rules() -> void:
	print("\n[Positions: ranking rules]")
	var track := Track.new()
	track.control_points = PackedVector3Array([Vector3.ZERO, Vector3(0, -10, -400), Vector3(0, -20, -800)])
	track.path.build(track.control_points, track.sample_spacing)
	track.call(&"_build_checkpoints", track.get_finish_index())
	var a := _fake_racer(track, 1, 0)
	var b := _fake_racer(track, 2, 1)
	var c := _fake_racer(track, 3, 2)
	a.checkpoints.next_checkpoint = 2
	a.checkpoints.distance = 230.0
	b.checkpoints.next_checkpoint = 1
	b.checkpoints.distance = 240.0  # further along but missed a checkpoint
	c.checkpoints.next_checkpoint = 2
	c.checkpoints.distance = 220.0
	var racers: Array[Racer] = [a, b, c]
	var order := RacePositions.rank(racers, [])
	_check(order == [a, c, b], "more checkpoints beats more raw distance")
	c.checkpoints.distance = 230.6
	order = RacePositions.rank(racers, [a, c, b])
	_check(order[0] == a, "a 0.6 m lead doesn't flip positions (hysteresis)")
	c.checkpoints.distance = 233.0
	order = RacePositions.rank(racers, [a, c, b])
	_check(order[0] == c, "a clear lead takes the position")
	b.finished = true
	b.finish_position = 1
	order = RacePositions.rank(racers, order)
	_check(order[0] == b, "finished racers rank first, in finishing order")
	track.free()


func _fake_racer(track: Track, id: int, slot: int) -> Racer:
	var racer := Racer.new()
	racer.id = id
	racer.spawn_slot = slot
	racer.checkpoints = CheckpointProgress.new(track, track.get_start_index())
	return racer


## A whole 5-racer race: positions, finish order, official times, results.
func _test_full_race_positions_finish_results() -> void:
	print("\n[Race flow: five-racer race, positions, finish, results]")
	var main := await _load_flow(4)
	main.race.finish_timeout = 0.0  # wait for everyone
	var finishes := {}
	var order: Array[int] = []
	main.get_finish_tracker().racer_finished.connect(func(id: int, _pos: int, _time: float) -> void:
		finishes[id] = int(finishes.get(id, 0)) + 1
		order.append(id))
	var pilot := TrackAutopilot.new(main.track, main.trike)
	await _run_until_state(main, State.RACING, 6.0)
	var valid := true
	var consistent := true
	var changes := 0
	var last_positions := {}
	var t := 0.0
	while main.race.get_state() == State.RACING and t < 150.0:
		if main.rider.is_riding() and not main.get_local_racer().finished:
			pilot.drive()
		elif main.get_local_racer().finished:
			main.trike.input.clear()
		await _tree().physics_frame
		t += _dt()
		var seen := {}
		for racer in main.racers.get_racers():
			seen[racer.position] = true
			if last_positions.has(racer.id) and last_positions[racer.id] != racer.position:
				changes += 1
			last_positions[racer.id] = racer.position
		valid = valid and seen.size() == 5 and seen.has(1) and seen.has(5)
		var ranking := main.racers.get_ranking()
		for i in ranking.size() - 1:
			var ahead := ranking[i]
			var behind := ranking[i + 1]
			if not ahead.finished and not behind.finished \
					and ahead.checkpoints.get_passed_count() == behind.checkpoints.get_passed_count() \
					and behind.checkpoints.distance > ahead.checkpoints.distance + main.racers.position_swap_margin + 0.5:
				consistent = false
	_check(valid, "positions are always exactly 1st–5th")
	_check(consistent, "positions follow valid track progress (within the swap margin)")
	_check(changes < 60, "positions change calmly", "(%d changes in a %.0f s race)" % [changes, t])
	_check(main.race.get_state() == State.FINISHED, "race ends (FINISHED) when everyone has finished")
	var once := finishes.size() == 5
	for id: int in finishes:
		once = once and finishes[id] == 1
	_check(once, "every racer finishes exactly once")
	var times_ok := true
	var previous_time := -1.0
	for id in order:
		var racer := main.racers.get_racer(id)
		var result := main.get_finish_tracker().get_result(id)
		times_ok = times_ok and racer.finish_position == order.find(id) + 1 \
				and absf(racer.finish_time - float(result["time"])) < 1e-4 and racer.finish_time >= previous_time
		previous_time = racer.finish_time
	_check(times_ok, "finishing order = confirmation order, with ascending official times")
	_check(absf(main.race.race_duration - previous_time) < 1e-4, "race duration = last finisher's time",
			"(%s)" % Hud.format_time(main.race.race_duration))
	var clock := main.racers.race_time
	await _run_until_state(main, State.RESULTS, 4.0)
	_check(main.race.get_state() == State.RESULTS and main.results_screen.is_open(), "results screen follows")
	_check(absf(main.racers.race_time - clock) < 0.001, "race clock stops at the end")
	var rows := main.results_screen.row_texts
	var rows_ok := rows.size() == 5
	for i in rows.size():
		var racer := main.racers.get_racer(order[i])
		rows_ok = rows_ok and rows[i] == "%s|%s|%s" % [RaceSession.ordinal(i + 1), racer.display_name, Hud.format_time(racer.finish_time)]
	_check(rows_ok, "results list 1st–5th with names and finishing times", "(%s)" % " / ".join(rows))
	await _free(main)


## Thrown off right before the line during a race with AI: pending, then the
## remount confirms it with the correct position.
func _test_pending_finish_in_race() -> void:
	print("\n[Race flow: pending finish after ejection]")
	var main := await _load_flow(1)
	main.race.start_immediately()
	var ai := main.racers.get_racer(2)
	var me := main.get_local_racer()
	var start := main.track.get_finish_index() - 14
	_teleport(main, me, start)
	me.checkpoints.force_passed_through(start)
	await runner._hold(main.trike, 1.6, 1.0)
	main.rider.eject()
	var tracker := main.get_finish_tracker()
	var t := 0.0
	while not tracker.is_pending(me.id) and t < 6.0:
		await _tree().physics_frame
		t += _dt()
	_check(tracker.is_pending(me.id) and not me.finished, "empty trike over the line: pending, not finished",
			"(index %d / finish %d, riding %s, can finish %s, state %s)" % [me.progress.current_index,
			main.track.get_finish_index(), main.rider.is_riding(), me.checkpoints.can_finish(), main.race.get_state_name()])
	# The AI gets there first while we are on foot.
	_teleport(main, ai, start)
	ai.checkpoints.force_passed_through(start)
	ai.get_ai_driver().path_index = start
	t = 0.0
	while not ai.finished and t < 6.0:
		await _tree().physics_frame
		t += _dt()
	_check(ai.finished and ai.finish_position == 1, "AI riding across meanwhile finishes 1st")
	await runner._wait_for_state(main.rider, RiderController.State.ON_FOOT, 4.0)
	var side := main.trike.global_basis.x
	side.y = 0.0
	main.rider.on_foot.activate(main.trike.global_position + side.normalized() * 1.4, -side)
	await _wait(0.2)
	main.rider.input.interact_pressed = true
	await runner._wait_for_state(main.rider, RiderController.State.RIDING, 2.0)
	await _wait(0.1)
	_check(me.finished and me.finish_position == 2 and me.finish_time >= ai.finish_time,
			"remounting confirms the finish: 2nd, official time at confirmation",
			"(%.2f s vs AI %.2f s)" % [me.finish_time, ai.finish_time])
	await _free(main)


func _test_finish_timeout_and_dnf() -> void:
	print("\n[Race flow: finish timeout]")
	var main := await _load_flow(2)
	main.race.finish_timeout = 4.0
	main.race.start_immediately()
	var first := main.racers.get_racer(2)
	var second := main.racers.get_racer(3)
	# First AI starts near the end, the other well behind; the player stays put.
	var near := main.track.get_finish_index() - 25
	_teleport(main, first, near)
	first.checkpoints.force_passed_through(near)
	first.get_ai_driver().path_index = near
	var t := 0.0
	while not first.finished and t < 10.0:
		await _tree().physics_frame
		t += _dt()
	_check(first.finished and main.race.get_state() == State.RACING, "after the first finisher the race goes on")
	var others_before := second.checkpoints.distance
	await _wait(2.0)
	_check(second.checkpoints.distance > others_before + 20.0 and main.race.get_timeout_left() > 0.0,
			"remaining racers keep racing while the timeout runs",
			"(%.1f s left)" % main.race.get_timeout_left())
	await _run_until_state(main, State.FINISHED, 4.0)
	_check(main.race.get_state() == State.FINISHED and absf(main.racers.race_time - first.finish_time - 4.0) < 0.1,
			"the race ends finish_timeout seconds after the first finisher",
			"(%.2f s after)" % (main.racers.race_time - first.finish_time))
	_check(main.get_local_racer().did_not_finish and second.did_not_finish and not first.did_not_finish,
			"unfinished racers are DNF")
	await _run_until_state(main, State.RESULTS, 4.0)
	var rows := main.results_screen.row_texts
	_check(rows.size() == 3 and rows[0].begins_with("1st|%s|" % first.display_name) and rows[1].ends_with("|DNF")
			and rows[2].ends_with("|DNF"), "results: the finisher with a time, the rest DNF", "(%s)" % " / ".join(rows))
	await _free(main)


# --- Race again, lobby, consecutive races ------------------------------------

func _test_race_again_and_lobby() -> void:
	print("\n[Race flow: race again, lobby, consecutive races]")
	var main := await _load_flow(4)
	main.race.finish_timeout = 3.0
	main.race.results_delay = 0.5
	var crate := _first_crate(main)
	var crate_start := crate.global_position
	for race_number in 3:
		# Countdown → race. Push one AI near the line so races end quickly.
		await _run_until_state(main, State.RACING, 6.0)
		var finisher := main.racers.get_racer(2)
		var near := main.track.get_finish_index() - 25
		_teleport(main, finisher, near)
		finisher.checkpoints.force_passed_through(near)
		finisher.get_ai_driver().path_index = near
		crate.global_position += Vector3(3.0, 0.0, 0.0)  # knock a prop out of place
		main.rider.eject()
		await _run_until_state(main, State.RESULTS, 20.0)
		_check(main.race.get_state() == State.RESULTS and finisher.finished
				and main.results_screen.row_texts.size() == 5 and main.results_screen.row_texts[0].contains(finisher.display_name),
				"race %d runs to the results" % (race_number + 1))
		if race_number < 2:
			main.results_screen.press_race_again()
			await _tree().physics_frame
			var problems: Array[String] = []
			for racer in main.racers.get_racers():
				if racer.trike.global_position.distance_to(racer.spawn_transform.origin) > 0.3:
					problems.append("%s off grid %.2f m" % [racer.display_name, racer.trike.global_position.distance_to(racer.spawn_transform.origin)])
				if not racer.rider.is_riding() or racer.finished or racer.did_not_finish:
					problems.append("%s riding/finish state" % racer.display_name)
				# Back-row slots sit a few samples behind the start sample.
				if racer.checkpoints.get_passed_count() != 0 or racer.progress.current_index > main.track.get_start_index() \
						or racer.progress.current_index < main.track.get_start_index() - 6:
					problems.append("%s progress %d cp %d" % [racer.display_name, racer.progress.current_index, racer.checkpoints.get_passed_count()])
				if not racer.trike.input_locked or main.get_finish_tracker().has_finished(racer.id) \
						or (racer.is_ai() and racer.get_ai_driver().active):
					problems.append("%s lock/tracker/AI" % racer.display_name)
			_check(problems.is_empty(), "Race Again: everyone back on the grid, riding, progress and finish cleared, locked",
					"(%s)" % ", ".join(problems))
			_check(main.racers.race_time == 0.0 and main.get_race_time() == 0.0 and not main.results_screen.is_open(),
					"timer reset, results hidden")
			_check(crate.global_position.distance_to(crate_start) < 0.05, "knocked props are put back")
			_check(main.race.get_state() == State.COUNTDOWN and main.race.countdown_value == 3,
					"countdown restarts")
	_check(main.race.race_count == 3, "three consecutive races", "(%d)" % main.race.race_count)

	main.results_screen.press_return_to_lobby()
	await _wait(2.0)
	_check(main.race.get_state() == State.LOBBY and main.lobby_screen.is_open() and main.trike.input_locked,
			"Return to Lobby: waits in the lobby, locked, lobby screen shown")
	main.lobby_screen.press_start()
	await _tree().physics_frame
	_check(main.race.get_state() == State.COUNTDOWN and not main.lobby_screen.is_open(),
			"Start Race in the lobby begins the countdown")
	await _free(main)


func _first_crate(main: RaceSession) -> RigidBody3D:
	for child in main.track.get_node("Props").get_children():
		if child is RigidBody3D and (child as Node).scene_file_path.ends_with("crate.tscn"):
			return child
	return null
