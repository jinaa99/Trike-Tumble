extends Node
## One game instance in a multi-process network test (launched headless by
## tests/net/net_test_runner.gd). Plays host or client through the real game
## code (GameSession, Net, RaceSession), drives its trike with the
## autopilot, performs scripted actions and writes what it saw as JSON.
##
## Args after `--`: --role=host|client --name=N --port=P --out=FILE
##   host:   --cap=N --expect=N --timeout=S --shutdown-after=S --rehost-after=S
##           --start-delay=S (wait this long in a full lobby before starting)
##           --map=ID (choose this map in the lobby before starting)
##   client: --address=A --join-delay=S --eject-at=S --cheat-at=S --spoof-at=S
##           --quit-at=S --dup-hello --rejoin --bad-address=A
##   both:   --max-time=S  (times "at" are seconds after GO)
##           --items  (item boxes along the test track; use held items after 1 s)
##           --use-items  (use held items after 1 s; the real maps have their own boxes)
##           --dodge  (steer around obstacles: needed to finish a whole real map)
##           --race-again  (host: press Race Again on the results screen; everyone
##                          records the second countdown and GO, then stops)
##           --lane=M  (preferred lateral offset on the road)
##           --second-race-seconds=S  (with --race-again: stop S s after the 2nd GO)
##   client: --item-spoof-at=S (item request for the host's racer)
##           --item-dup-at=S (replays an already used item request id)
##           --shots=DIR  (windowed runs: screenshots 3, 8, 15 and 30 s after GO)

const MAIN_SCENE := preload("res://scenes/main/main.tscn")

var args := {}
var report := {"events": [], "race_states": [], "countdown": [], "proxies": {}, "results": [], "reason": ""}
var race: RaceSession
var pilot: TrackAutopilot
var _clock := 0.0
var _go_time := -1.0
var _done := false
var _did := {}
var _stuck_time := 0.0
var _on_foot_time := 0.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var parts := arg.trim_prefix("--").split("=", true, 1)
			args[parts[0]] = parts[1] if parts.size() > 1 else "1"
	GameSettings.use_test_profile("user://net_peer_%s.cfg" % _arg("name", "peer"))
	GameSettings.player_name = _arg("name", "peer")
	report["role"] = _arg("role", "")
	report["name"] = GameSettings.player_name
	GameSession.race_scene_requested.connect(func(path: String) -> void: _load_race(path))
	GameSession.disconnected.connect(func(reason: String) -> void:
		_event("disconnected: " + reason)
		report["reason"] = reason
		report["lost_connection"] = true)
	GameSession.transport.connection_failed.connect(func(reason: String) -> void:
		_event("join failed: " + reason)
		report["reason"] = reason)
	GameSession.transport.connected.connect(func() -> void:
		_event("joined")
		report["my_id"] = Net.my_id()
		_record_lobby("lobby_on_join"))
	if _arg("role") == "host":
		_start_host()
	else:
		_start_client.call_deferred()


func _arg(key: String, fallback := "") -> String:
	return args.get(key, fallback)


func _num(key: String, fallback := -1.0) -> float:
	return float(args[key]) if args.has(key) else fallback


func _event(text: String) -> void:
	report["events"].append("%.2f %s" % [_clock, text])


func _record_lobby(key: String) -> void:
	var lobby := GameSession.lobby
	if lobby == null:
		return
	var players := []
	for player in lobby.players:
		players.append({"id": player.id, "name": player.display_name, "host": player.is_host, "ready": player.is_ready,
				"ai": player.is_ai,
				"local": player.is_local})
	report[key] = {"players": players, "map": lobby.map_id, "max": lobby.max_players}


# --- Host -------------------------------------------------------------------

func _start_host() -> void:
	var error := GameSession.host_lobby(GameSettings.player_name, int(_num("port")), int(_num("cap", 5)))
	report["host_error"] = error
	report["my_id"] = Net.my_id()
	_event("hosting %d" % error)


func _host_tick() -> void:
	var lobby := GameSession.lobby
	if race == null and lobby and not GameSession.race_active and not _did.has("started"):
		var expect := int(_num("expect", 2))
		if lobby.count() >= expect and not _did.has("full_since"):
			_did["full_since"] = _clock
		if lobby.count() >= expect and _clock - float(_did["full_since"]) >= _num("start-delay", 0.0):
			lobby.set_ready(1, true)
			if args.has("map") and lobby.map_id != _arg("map"):
				lobby.set_map(_arg("map"))
				_event("host chose map " + _arg("map"))
			if lobby.all_ready():
				_record_lobby("lobby_at_start")
				_did["started"] = true
				var scene := GameSession.begin_race()
				_event("begin_race " + scene)
				_load_race(scene)
	if _did.has("shut_down") and not _did.has("rehosted") and _clock - float(_did["shut_down"]) >= _num("rehost-after", 1e9):
		_did["rehosted"] = true
		var error := GameSession.host_lobby(GameSettings.player_name, int(_num("port")), int(_num("cap", 5)))
		_event("rehosted %d" % error)
		report["rehost_error"] = error
	if _did.has("rehosted") and GameSession.lobby and GameSession.lobby.count() >= int(_num("expect", 2)) \
			and not _did.has("rejoin_seen"):
		_did["rejoin_seen"] = true
		_record_lobby("lobby_after_rehost")
		_finish_soon(1.5)


# --- Client -----------------------------------------------------------------

func _start_client() -> void:
	if args.has("bad-address"):
		var problem := NetAddress.validate_address(_arg("bad-address"))
		report["validation"] = problem
		_event("validation: " + problem)
		_finish_soon(0.2)
		return
	await get_tree().create_timer(_num("join-delay", 0.0)).timeout
	_join()


func _join() -> void:
	var error := GameSession.join_game(_arg("address", "127.0.0.1"), int(_num("port")))
	_event("join %d" % error)


func _client_tick() -> void:
	var lobby := GameSession.lobby
	if lobby and race == null and not GameSession.race_active:
		var me := lobby.get_local_player()
		if me and not me.is_ready:
			GameSession.set_local_ready(true)
		if args.has("dup-hello") and not _did.has("dup"):
			_did["dup"] = true
			Net._c_hello.rpc_id(1, "Copycat", Net.PROTOCOL_VERSION)
			_event("sent duplicate hello")
		if _did.has("lost") and not _did.has("rejoined"):
			_did["rejoined"] = true
			_record_lobby("lobby_after_rejoin")
			_finish_soon(1.0)
	if report.get("lost_connection", false) and not _did.has("lost"):
		_did["lost"] = true
		if args.has("rejoin"):
			_retry_join()
		else:
			_finish_soon(0.5)
	if not report["reason"].is_empty() and not args.has("rejoin") and not GameSession.has_lobby() and race == null:
		_finish_soon(0.5)


func _retry_join() -> void:
	for attempt in 15:
		await get_tree().create_timer(1.0).timeout
		if GameSession.has_lobby():
			return
		if Net.role == Net.Role.NONE:
			_join()


# --- Race -------------------------------------------------------------------

## The fast test track by default; `--real-map` loads the scene the lobby's
## map asks for (Forest Rush).
func _load_race(path := "") -> void:
	if race:
		return
	var scene: PackedScene = load(path) if args.has("real-map") and not path.is_empty() else MAIN_SCENE
	race = scene.instantiate()
	race.scene_changer = func(path: String) -> void:
		_event("scene change " + path)
		report["returned_to_menu"] = true
		_free_race()
	add_child(race)
	race.trike.input_source = null
	race.rider.input_source = null
	if Net.is_host():
		race.race.finish_timeout = _num("timeout", 10.0)
		race.race.results_delay = 1.0
	pilot = TrackAutopilot.new(race.track, race.trike)
	if args.has("items"):
		_add_item_boxes()
		pilot.lateral_offset = -3.0 if Net.is_host() else 3.0  # each through its own column of boxes
	race.race.state_changed.connect(func(_o: RaceStateMachine.State, n: RaceStateMachine.State) -> void:
		report["race_states"].append(RaceStateMachine.STATE_NAMES[n])
		if n == RaceStateMachine.State.RACING:
			_go_time = _clock
			_did.erase("stop")
			if report["race_states"].count("RACING") >= 2:
				_event("second race started")
		if n == RaceStateMachine.State.RESULTS:
			_record_results()
			if args.has("race-again") and report["race_states"].count("RESULTS") == 1:
				report["first_results"] = report["results"].duplicate()
				report["first_results_data"] = report["results_data"].duplicate(true)
				if Net.is_host():
					get_tree().create_timer(3.0).timeout.connect(func() -> void:
						_event("host pressed Race Again")
						race.race_again())
				return
			_finish_soon(2.5 if Net.is_host() else 0.5))
	race.race.countdown_step.connect(func(text: String) -> void: report["countdown"].append(text))
	report["track"] = String(race.track.name)
	report["lobby_map"] = GameSession.lobby.map_id if GameSession.lobby else ""
	report["boxes"] = race.items.boxes.size()
	var sky := (race.get_node("WorldEnvironment") as WorldEnvironment).environment.sky.sky_material as ProceduralSkyMaterial
	report["sky"] = sky.sky_top_color.to_html()
	report["racers"] = []
	for racer in race.racers.get_racers():
		report["racers"].append({"id": racer.id, "name": racer.display_name, "proxy": racer.is_proxy, "slot": racer.spawn_slot})
	_event("race loaded")
	report["my_states"] = []
	race.rider.state_changed.connect(func(_o: int, n: int) -> void:
		report["my_states"].append("%.1f %s" % [race.racers.race_time, RiderController.STATE_NAMES[n]]))
	report["impacts"] = 0
	report["max_impact"] = 0.0
	report["item_log"] = []
	race.trike.impact.connect(func(strength: float, _v: Vector3) -> void:
		if strength > 4.0:
			report["impacts"] = int(report["impacts"]) + 1
		report["max_impact"] = maxf(float(report["max_impact"]), strength))
	race.items.event_applied.connect(func(event: Array) -> void:
		report["item_log"].append("%s %s" % [ItemManager.EVENT_NAMES[int(event[1])], str(event.slice(2, 4))]))


## The same boxes in the same order on every peer (box ids must match).
func _add_item_boxes() -> void:
	report["item_events"] = []
	for distance in range(60, 1000, 100):
		var frame := race.track.path.get_frame(race.track.path.index_at_distance(distance))
		for lateral: float in [-3.0, 0.0, 3.0]:
			race.items.add_box(frame.translated_local(Vector3(lateral, 1.0, 0.0)))
	race.items.event_applied.connect(func(event: Array) -> void:
		report["item_events"].append(str(event)))


func _free_race() -> void:
	if race:
		race.queue_free()
		race = null


func _record_results() -> void:
	report["results"] = race.results_screen.row_texts.duplicate()
	report["results_data"] = race.race.results.duplicate(true)
	report["race_duration"] = race.race.race_duration
	var me := race.get_local_racer()
	report["my_finish"] = {"finished": me.finished, "position": me.finish_position, "time": me.finish_time,
			"dnf": me.did_not_finish}
	report["my_respawns"] = me.respawn_count
	report["my_wipeouts"] = race.rider.eject_count
	report["my_id_in_race"] = me.id
	if race.net_sync:
		report["sent"] = race.net_sync.sent
		report["received"] = race.net_sync.received
		report["max_proxy_step"] = race.net_sync.max_proxy_step
		report["proxy_jumps"] = race.net_sync.proxy_jumps
		report["unexplained_jumps"] = race.net_sync.unexplained_jumps
		report["hitches"] = race.net_sync.hitches
		report["jump_log"] = race.net_sync.jump_log
	report["rejected_snapshots"] = Net.rejected_snapshots
	report["rejected_item_requests"] = Net.rejected_item_requests
	report["item_duplicate_requests"] = race.items.duplicate_requests
	report["item_denied_requests"] = race.items.denied_requests
	report["item_duplicate_events"] = race.items.duplicate_events
	report["item_invalid_events"] = race.items.invalid_events
	report["duplicate_hellos"] = Net.duplicate_hellos


func _race_tick() -> void:
	if race == null or not is_instance_valid(race):
		return
	var after_go := _clock - _go_time if _go_time >= 0.0 else -1.0
	var me := race.get_local_racer()
	if race.race.is_racing() and not me.finished:
		if race.rider.is_riding():
			if args.has("dodge"):
				pilot.dodge(race.racers.get_obstacles(), _num("lane", 0.0))
			pilot.drive()
			if (args.has("items") or args.has("use-items")) and ItemKind.is_valid(me.held_item) and me.item_hold_time > 1.0:
				race.trike.input.use_item_pressed = true
			# Like a player: stuck for 2 s (pinned in a pile-up) → press R.
			_stuck_time = _stuck_time + get_physics_process_delta_time() if race.trike.linear_velocity.length() < 1.0 else 0.0
			if _stuck_time > 2.0:
				_stuck_time = 0.0
				race.trike.input.reset_pressed = true
				_event("stuck: pressed reset")
		else:
			_walk_back()
			# Like a player (and the AI): on foot for 15 s without getting back
			# on (trike out of reach) → R puts trike and rider back on the road.
			_on_foot_time = _on_foot_time + get_physics_process_delta_time() if race.rider.state == RiderController.State.ON_FOOT else 0.0
			if _on_foot_time > 15.0:
				_on_foot_time = 0.0
				race.rider.input.reset_pressed = true
				_event("on foot too long: pressed reset")
	elif me.finished:
		race.trike.input.clear()
	if after_go >= 0.0:
		_scripted_actions(after_go)
	if race != null:
		_observe_proxies()


func _scripted_actions(after_go: float) -> void:
	if args.has("race-again") and report["race_states"].count("RACING") >= 2 and after_go >= _num("second-race-seconds", 8.0) \
			and not _did.has("second_done"):
		_did["second_done"] = true
		report["second_race_distance"] = me_distance()
		_event("second race running: stopping the test")
		_finish_soon(1.0)
		return
	if after_go >= _num("eject-at", 1e9) and not _did.has("eject"):
		_did["eject"] = true
		race.rider.eject()
		_event("ejected myself")
	if after_go >= _num("cheat-at", 1e9) and not _did.has("cheat"):
		_did["cheat"] = true
		var index := race.track.get_finish_index() - 15
		race.trike.teleport(race.track.path.get_frame(index).translated_local(Vector3(0, 0.8, 0)))
		race.get_progress().reset(index)
		pilot = TrackAutopilot.new(race.track, race.trike)
		_event("teleported to the finish (skipping checkpoints)")
	if after_go >= _num("spoof-at", 1e9) and not _did.has("spoof"):
		_did["spoof"] = true
		var host_racer := race.racers.get_racer(1)
		var fake := NetSnapshot.encode(NetRaceSync.now(), race.trike.get_network_state(), race.rider.get_network_state())
		fake[1] = host_racer.trike.global_position + Vector3(0, 30, 0)
		for i in 10:
			Net._c_snapshot.rpc_id(1, 1, fake)
		_event("sent 10 spoofed snapshots for the host's racer")
	if after_go >= _num("item-spoof-at", 1e9) and not _did.has("item_spoof"):
		_did["item_spoof"] = true
		Net._c_item_request.rpc_id(1, 1, 999, ItemManager.Request.USE,
				[int(ItemKind.Kind.TURBO_BOTTLE), Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO])
		_event("sent an item request for the host's racer")
	if after_go >= _num("item-dup-at", 1e9) and not _did.has("item_dup"):
		_did["item_dup"] = true
		var mine := race.get_local_racer().id
		Net._c_item_request.rpc_id(1, mine, 1, ItemManager.Request.PICKUP, [0])
		_event("replayed item request id 1")
	if args.has("shots") and DisplayServer.get_name() != "headless":
		for t: float in [3.0, 8.0, 15.0, 30.0]:
			if after_go >= t and not _did.has("shot%d" % t):
				_did["shot%d" % t] = true
				_save_shot("%s/%s_%02d.png" % [_arg("shots"), _arg("name"), int(t)])
	if after_go >= _num("quit-at", 1e9) and not _did.has("quit"):
		_did["quit"] = true
		_event("quitting mid-race")
		report["quit_mid_race"] = true
		_finish_soon(0.0)
	if after_go >= _num("stop-at", 1e9) and not _did.has("stop"):
		_did["stop"] = true
		_event("stopping the test race")
		report["my_distance"] = me_distance()
		_record_results()
		_finish_soon(0.5)
	if after_go >= _num("shutdown-after", 1e9) and not _did.has("shut_down"):
		_did["shut_down"] = _clock
		_record_results()
		_event("host shutting down")
		_free_race()
		GameSession.leave_lobby()


func me_distance() -> float:
	return race.get_progress().current_index * race.track.path.spacing


func _save_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	_event("screenshot " + path)


## On foot: run to the trike and press E (like the AI does).
func _walk_back() -> void:
	var rider := race.rider
	rider.input.move_direction = Vector3.ZERO
	if rider.state != RiderController.State.ON_FOOT:
		return
	if rider.can_mount:
		rider.input.interact_pressed = true
		return
	var to_trike := race.trike.global_position - rider.on_foot.global_position
	to_trike.y = 0.0
	if to_trike.length() > 0.1:
		rider.input.move_direction = to_trike.normalized()


func _observe_proxies() -> void:
	for racer in race.racers.get_racers():
		if not racer.is_proxy:
			continue
		var key := str(racer.id)
		var entry: Dictionary = report["proxies"].get(key, {"name": racer.display_name, "distance": 0.0, "states": [],
				"last": [], "disconnected": false, "positions": []})
		var position := racer.trike.global_position
		if not (entry["last"] as Array).is_empty():
			var last := Vector3(entry["last"][0], entry["last"][1], entry["last"][2])
			entry["distance"] = float(entry["distance"]) + position.distance_to(last)
		entry["last"] = [position.x, position.y, position.z]
		var state_name := racer.rider.get_state_name()
		if (entry["states"] as Array).is_empty() or entry["states"][-1] != state_name:
			entry["states"].append(state_name)
		entry["disconnected"] = racer.disconnected
		entry["visible"] = racer.root.visible if racer.root else true
		report["proxies"][key] = entry


# --- Main loop ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_clock += delta
	if _done:
		return
	if _clock > _num("max-time", 120.0):
		report["timed_out"] = true
		_event("max time reached")
		if race:
			_record_results()
		_finish_soon(0.0)
		return
	if _arg("role") == "host":
		_host_tick()
	else:
		_client_tick()
	_race_tick()


func _finish_soon(delay: float) -> void:
	if _done:
		return
	_done = true
	report["finished_at"] = _clock
	await get_tree().create_timer(delay).timeout
	if race and not report.has("results_data"):
		_record_results()
	_record_lobby("lobby_at_end")
	var file := FileAccess.open(_arg("out"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	GameSession.leave_lobby()
	await get_tree().create_timer(0.2).timeout
	get_tree().quit()
