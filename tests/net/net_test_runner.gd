extends Node
## Multi-process network tests: launches real game instances (headless,
## real time, ENet over 127.0.0.1) as host and clients, lets them play
## scripted scenarios through the real game code and checks the JSON each
## peer writes. Run (takes a few minutes):
##   $GODOT --headless --path . --scene res://tests/net/net_test_runner.tscn
## Optional: -- duo rules drop five forest   (scenarios to run; default all)

const PEER_SCENE := "res://tests/net/net_peer.tscn"
const ALL_SCENARIOS: Array[String] = ["duo", "rules", "drop", "five", "forest"]

var _passed := 0
var _failed := 0
var _out_dir := ""
var _port := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_out_dir = ProjectSettings.globalize_path("user://net_tests")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_port = 47100 + randi() % 800
	var wanted: Array[String] = []
	for arg in OS.get_cmdline_user_args():
		if ALL_SCENARIOS.has(arg):
			wanted.append(arg)
	if wanted.is_empty():
		wanted = ALL_SCENARIOS.duplicate()
	print("\n=== TRIKE TUMBLE NETWORK TESTS (separate processes, ENet on 127.0.0.1) ===")
	for scenario in wanted:
		_port += 7
		match scenario:
			"duo":
				await _scenario_duo()
			"rules":
				await _scenario_rules()
			"drop":
				await _scenario_drop()
			"five":
				await _scenario_five()
			"forest":
				await _scenario_forest()
	print("\n=== NETWORK RESULT: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


# --- Helpers ----------------------------------------------------------------

func _check(condition: bool, test_name: String, detail := "") -> void:
	if condition:
		_passed += 1
		print("  PASS  %s  %s" % [test_name, detail])
	else:
		_failed += 1
		print("  FAIL  %s  %s" % [test_name, detail])


## Starts one peer process; returns the path of the JSON it will write.
func _launch(peer_name: String, role: String, extra: Array[String]) -> String:
	var out := _out_dir.path_join("%s_%d.json" % [peer_name, _port])
	if FileAccess.file_exists(out):
		DirAccess.remove_absolute(out)
	var peer_args: Array[String] = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--scene", PEER_SCENE, "--",
			"--role=" + role, "--name=" + peer_name, "--port=%d" % _port, "--out=" + out]
	peer_args.append_array(extra)
	var pid := OS.create_process(OS.get_executable_path(), peer_args)
	if pid <= 0:
		push_error("couldn't start peer " + peer_name)
	return out


func _wait_seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Waits for every report (or `limit` seconds) and loads them.
func _collect(paths: Dictionary, limit: float) -> Dictionary:
	var reports := {}
	var waited := 0.0
	while waited < limit:
		var all_there := true
		for key: String in paths:
			if not reports.has(key) and FileAccess.file_exists(paths[key]):
				await _wait_seconds(0.3)  # let the writer finish
				reports[key] = JSON.parse_string(FileAccess.get_file_as_string(paths[key]))
			all_there = all_there and reports.has(key)
		if all_there:
			break
		await _wait_seconds(0.5)
		waited += 0.5
	for key: String in paths:
		if not reports.has(key) or reports[key] == null:
			reports[key] = {"missing": true, "events": [], "race_states": [], "countdown": [], "proxies": {}, "results": [],
					"reason": ""}
	return reports


static func _names(lobby_entry: Variant) -> Array:
	var names := []
	if lobby_entry is Dictionary:
		for player: Dictionary in lobby_entry["players"]:
			names.append(player["name"])
	return names


func _proxy_named(report: Dictionary, wanted: String) -> Dictionary:
	for entry: Dictionary in report["proxies"].values():
		if entry["name"] == wanted:
			return entry
	return {}


# --- Scenarios --------------------------------------------------------------

## Two local instances: join, identity, lobby + map sync, countdown, race,
## rider state sync, smooth proxies, spoofing and checkpoint skipping refused,
## results agree.
func _scenario_duo() -> void:
	print("\n[Network: two local instances]")
	var paths := {
		"host": _launch("Hosty", "host", ["--expect=2", "--timeout=8", "--max-time=110"]),
	}
	await _wait_seconds(1.5)
	paths["client"] = _launch("Cleo", "client", ["--eject-at=6", "--spoof-at=3", "--cheat-at=22", "--max-time=110"])
	var r := await _collect(paths, 130.0)
	var host: Dictionary = r["host"]
	var client: Dictionary = r["client"]
	_check(not host.has("missing") and not client.has("missing"), "both instances ran and reported")
	_check(int(host.get("host_error", -1)) == OK and _names(host.get("lobby_at_start")) == ["Hosty", "Cleo"],
			"host created the lobby and the client joined", "(%s)" % str(_names(host.get("lobby_at_start"))))
	var client_id := int(client.get("my_id", 0))
	var host_lobby: Dictionary = host.get("lobby_at_start", {"players": []})
	var ids_ok: bool = client_id > 1 and host_lobby["players"].size() == 2 and int(host_lobby["players"][1]["id"]) == client_id \
			and int(host_lobby["players"][0]["id"]) == 1
	_check(ids_ok, "player identity: host is 1, the client keeps its own network id", "(client %d)" % client_id)
	var mirror: Dictionary = client.get("lobby_on_join", {"players": [], "map": ""})
	_check(_names(mirror) == ["Hosty", "Cleo"] and mirror["map"] == "forest_rush" and bool(mirror["players"][1]["local"]),
			"client received the lobby and the selected map", "(map %s)" % mirror["map"])
	_check(client["countdown"] == ["3", "2", "1", "GO!"] and host["countdown"] == ["3", "2", "1", "GO!"],
			"both saw the countdown", "(%s)" % str(client["countdown"]))
	_check((client["race_states"] as Array).slice(0, 3) == ["COUNTDOWN", "RACING", "FINISHED"]
			and (client["race_states"] as Array).has("RESULTS"), "client followed the host's race states",
			"(%s)" % " → ".join(client["race_states"]))
	var host_view := _proxy_named(host, "Cleo")
	var client_view := _proxy_named(client, "Hosty")
	_check(float(host_view.get("distance", 0.0)) > 300.0 and float(client_view.get("distance", 0.0)) > 300.0,
			"each saw the other's trike race down the track",
			"(host saw %.0f m, client saw %.0f m)" % [host_view.get("distance", 0.0), client_view.get("distance", 0.0)])
	_check(int(host.get("hitches", 99)) <= 3 and int(client.get("hitches", 99)) <= 3
			and int(host.get("unexplained_jumps", 99)) == 0 and int(client.get("unexplained_jumps", 99)) == 0,
			"remote trikes move smoothly (jumps only when their owner teleports/respawns)",
			"(max step %.2f / %.2f m per tick, owner teleports seen %d / %d)" % [host.get("max_proxy_step", 99.0),
			client.get("max_proxy_step", 99.0), host.get("proxy_jumps", 99), client.get("proxy_jumps", 99)])
	var states: Array = host_view.get("states", [])
	_check(states.has("EJECTED") and states.has("RAGDOLL") and states.has("ON_FOOT") and states.has("MOUNTING")
			and states.count("RIDING") >= 2, "the host saw the client's wipeout, run back and remount",
			"(%s)" % " → ".join(states))
	_check(int(host.get("rejected_snapshots", 0)) >= 10, "spoofed snapshots for someone else's trike were rejected",
			"(%d rejected)" % int(host.get("rejected_snapshots", 0)))
	var host_finish: Dictionary = host.get("my_finish", {})
	var client_finish: Dictionary = client.get("my_finish", {})
	_check(bool(host_finish.get("finished", false)) and int(host_finish.get("position", 0)) == 1,
			"host finished 1st (decided by the host)")
	_check(not bool(client_finish.get("finished", true)) and bool(client_finish.get("dnf", false)),
			"teleporting past checkpoints never counts: the client is DNF")
	_check(client["results"] == host["results"] and (host["results"] as Array).size() == 2,
			"both show the same results", "(%s)" % " / ".join(host["results"]))


## Two instances racing on the real map (Forest Rush) for a minute.
func _scenario_forest() -> void:
	print("\n[Network: two instances on Forest Rush]")
	var paths := {
		"host": _launch("Hosty", "host", ["--expect=2", "--real-map", "--stop-at=60", "--max-time=110"]),
	}
	await _wait_seconds(1.5)
	paths["client"] = _launch("Cleo", "client", ["--real-map", "--stop-at=60", "--max-time=110"])
	var r := await _collect(paths, 130.0)
	var host: Dictionary = r["host"]
	var client: Dictionary = r["client"]
	_check(host.get("track", "") == "ForestRush" and client.get("track", "") == "ForestRush",
			"host and client both loaded Forest Rush", "(%s / %s)" % [host.get("track", "?"), client.get("track", "?")])
	var host_view := _proxy_named(host, "Cleo")
	var client_view := _proxy_named(client, "Hosty")
	_check(float(host_view.get("distance", 0.0)) > 800.0 and float(client_view.get("distance", 0.0)) > 800.0,
			"each saw the other race a minute down the mountain",
			"(host saw %.0f m, client saw %.0f m; drove %.0f / %.0f m)" % [host_view.get("distance", 0.0),
			client_view.get("distance", 0.0), host.get("my_distance", 0.0), client.get("my_distance", 0.0)])
	_check(int(host.get("hitches", 99)) <= 3 and int(client.get("hitches", 99)) <= 3
			and int(host.get("unexplained_jumps", 99)) == 0 and int(client.get("unexplained_jumps", 99)) == 0,
			"remote trikes move smoothly on the big map",
			"(max step %.2f / %.2f m per tick)" % [host.get("max_proxy_step", 99.0), client.get("max_proxy_step", 99.0)])
	_check(int(host.get("rejected_snapshots", 99)) == 0, "no honest snapshot was rejected on the big map",
			"(%d)" % int(host.get("rejected_snapshots", 99)))


## Capacity, timeouts, validation, duplicate ids, joining mid-race, host
## shutdown and rejoining after the host comes back.
func _scenario_rules() -> void:
	print("\n[Network: connection rules]")
	var paths := {
		"host": _launch("Hostess", "host", ["--cap=2", "--expect=2", "--start-delay=4", "--shutdown-after=5",
				"--rehost-after=2", "--max-time=60"]),
	}
	await _wait_seconds(1.5)
	paths["first"] = _launch("First", "client", ["--dup-hello", "--rejoin", "--max-time=60"])
	paths["wrong_port"] = _launch("Lost", "client", ["--port=%d" % (_port + 3), "--max-time=20"])
	paths["bad_ip"] = _launch("Typo", "client", ["--bad-address=300.1.2.3", "--max-time=10"])
	await _wait_seconds(2.0)
	paths["full"] = _launch("Late", "client", ["--max-time=20"])
	await _wait_seconds(5.0)
	paths["midrace"] = _launch("Tardy", "client", ["--max-time=20"])
	# The wrong-port client: point it one port off.
	var r := await _collect(paths, 90.0)
	var host: Dictionary = r["host"]
	var first: Dictionary = r["first"]
	_check(_names(host.get("lobby_at_start")) == ["Hostess", "First"], "a lobby with capacity 2 fills up",
			"(%s)" % str(_names(host.get("lobby_at_start"))))
	_check(String(r["full"]["reason"]).contains("full"), "a third player is told the lobby is full",
			"(%s)" % r["full"]["reason"])
	_check(String(r["midrace"]["reason"]).contains("race is in progress"), "joining during a race is refused",
			"(%s)" % r["midrace"]["reason"])
	_check(String(r["bad_ip"].get("validation", "")).contains("0 to 255"), "an invalid IP is rejected before connecting")
	_check(int(host.get("duplicate_hellos", 0)) == 1 and _names(host.get("lobby_at_start")).size() == 2,
			"a duplicate join from the same player id is ignored")
	_check(bool(first.get("lost_connection", false)) and String(first["reason"]).contains("Lost connection")
			and bool(first.get("returned_to_menu", false)), "host shutdown: the client is told and returns to the menu",
			"(%s)" % first["reason"])
	_check(int(host.get("rehost_error", -1)) == OK and _names(host.get("lobby_after_rehost")).size() == 2
			and _names(first.get("lobby_after_rejoin")).size() == 2, "after the host restarts, the client can join again")
	var wrong: Dictionary = r["wrong_port"]
	_check(String(wrong["reason"]).contains("timed out") or String(wrong["reason"]).contains("Couldn't reach"),
			"nobody listening on the port: the join times out with a message", "(%s)" % wrong["reason"])


## Three players: one quits mid-race; the others finish, the leaver is DNF.
func _scenario_drop() -> void:
	print("\n[Network: three players, one disconnects]")
	var paths := {"host": _launch("Hank", "host", ["--expect=3", "--timeout=8", "--max-time=110"])}
	await _wait_seconds(1.5)
	paths["stay"] = _launch("Stella", "client", ["--max-time=110"])
	paths["quit"] = _launch("Quinn", "client", ["--quit-at=5", "--max-time=60"])
	var r := await _collect(paths, 130.0)
	var host: Dictionary = r["host"]
	var stay: Dictionary = r["stay"]
	_check(_names(host.get("lobby_at_start")).size() == 3, "three players in the lobby")
	_check(bool(r["quit"].get("quit_mid_race", false)), "one player quit mid-race")
	var quinn_on_host := _proxy_named(host, "Quinn")
	var quinn_on_stay := _proxy_named(stay, "Quinn")
	_check(bool(quinn_on_host.get("disconnected", false)) and not bool(quinn_on_host.get("visible", true))
			and bool(quinn_on_stay.get("disconnected", false)), "everyone removed the leaver's trike")
	_check((stay["race_states"] as Array).has("RESULTS") and (host["race_states"] as Array).has("RESULTS"),
			"the race still ends normally")
	var rows: Array = host["results"]
	_check(rows.size() == 3 and String(rows[2]).begins_with("3rd|Quinn|DNF") and stay["results"] == rows,
			"results: the leaver is DNF, everyone agrees", "(%s)" % " / ".join(rows))
	_check(bool(stay.get("my_finish", {}).get("finished", false)), "the remaining client finished")


## Five players: everyone sees four others race; one shared finish order.
func _scenario_five() -> void:
	print("\n[Network: five players]")
	# All five test drivers use the same centre line, so the back of the grid
	# loses time in start pile-ups; allow 30 s after the winner.
	var paths := {"host": _launch("P1", "host", ["--expect=5", "--timeout=30", "--max-time=140"])}
	await _wait_seconds(1.5)
	for i in range(2, 6):
		paths["p%d" % i] = _launch("P%d" % i, "client", ["--max-time=140"])
		await _wait_seconds(0.3)
	var r := await _collect(paths, 170.0)
	var host: Dictionary = r["host"]
	_check(_names(host.get("lobby_at_start")).size() == 5, "five players in the lobby",
			"(%s)" % str(_names(host.get("lobby_at_start"))))
	var sees_all := true
	var smooth := true
	var same_results := true
	var all_finished := true
	var min_distance := INF
	var worst_step := 0.0
	var hitches := 0
	for key: String in r:
		var report: Dictionary = r[key]
		sees_all = sees_all and (report["proxies"] as Dictionary).size() == 4
		for entry: Dictionary in report["proxies"].values():
			min_distance = minf(min_distance, float(entry["distance"]))
		smooth = smooth and int(report.get("hitches", 99)) <= 3 and int(report.get("unexplained_jumps", 99)) == 0
		worst_step = maxf(worst_step, float(report.get("max_proxy_step", 99.0)))
		hitches += int(report.get("hitches", 99))
		same_results = same_results and report["results"] == host["results"]
		all_finished = all_finished and bool(report.get("my_finish", {}).get("finished", false))
	_check(sees_all and min_distance > 300.0, "every player saw the four others race",
			"(shortest remote run %.0f m)" % min_distance)
	_check(smooth, "remote trikes move smoothly for everyone (≤ 3 stall hitches per player, no unexplained jumps)",
			"(%d ticks over 1 m in total, worst %.2f m)" % [hitches, worst_step])
	_check(all_finished and (host["results"] as Array).size() == 5, "all five finished")
	_check(same_results, "all five show the same finish order and times", "(%s)" % " / ".join(host["results"]))
