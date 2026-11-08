extends RefCounted
## Networking pieces that can be tested inside one process (final-demo
## milestone 05): lobby sync data, snapshot validation, the jitter buffer,
## proxy trikes/riders and real ENet hosting. Multi-process host/client
## tests: tests/net/net_test_runner.tscn (see docs/TESTING.md).

const TRIKE_SCENE := preload("res://scenes/vehicles/trike.tscn")
const RIDER_SCENE := preload("res://scenes/characters/rider_character.tscn")

var runner: Node


func _init(test_runner: Node) -> void:
	runner = test_runner


func run() -> void:
	_test_lobby_sync_data()
	_test_snapshot_validation()
	_test_snapshot_buffer()
	await _test_proxy_trike_and_rider()
	await _test_proxy_collision()
	await _test_enet_hosting()
	await _test_online_menus()


func _check(condition: bool, test_name: String, detail := "") -> void:
	runner._check(condition, test_name, detail)


func _tree() -> SceneTree:
	return runner.get_tree()


func _test_lobby_sync_data() -> void:
	print("\n[Net: lobby data]")
	var host := Lobby.new()
	host.max_players = 4
	host.map_id = "forest_rush"
	var me := host.add_human("Sam", true, true, 1)
	var friend := host.add_human("Sam", false, false, 123456)
	host.add_ai(AIDriverConfig.Difficulty.HARD)
	_check(me.id == 1 and friend.id == 123456 and friend.display_name == "Sam 2", "peer ids as player ids; duplicate names get a number")
	_check(host.add_human("Copy", false, false, 123456) == null, "a duplicate player id is refused")
	var mirror := Lobby.new()
	mirror.apply_dict(host.to_dict(), 123456)
	var same := mirror.count() == 3 and mirror.max_players == 4 and mirror.map_id == "forest_rush"
	for i in 3:
		same = same and mirror.players[i].id == host.players[i].id and mirror.players[i].display_name == host.players[i].display_name \
				and mirror.players[i].is_host == host.players[i].is_host and mirror.players[i].is_ai == host.players[i].is_ai
	_check(same, "a client's mirror matches the host's lobby")
	_check(mirror.get_local_player().id == 123456 and not mirror.get_local_player().is_host,
			"the mirror marks the client's own seat")
	var ai := mirror.players[2]
	_check(ai.is_ai and ai.ai_difficulty == AIDriverConfig.Difficulty.HARD and ai.is_ready, "AI seats sync with difficulty")


func _snapshot(t: float, position := Vector3.ZERO, state := 0) -> Array:
	var trike := {"xf": Transform3D(Basis(), position), "vel": Vector3(0, 0, -10), "steer_amount": 0.1, "steer_angle": 0.05,
			"forward_speed": 10.0, "drift_dir": 0, "drift_charge": 0.0, "boost": 0.0,
			"susp": PackedFloat32Array([0.2, 0.2, 0.2]), "contact": 7, "has_rider": state == 0}
	var rider := {"state": state, "state_time": 0.5, "ragdoll_xf": Transform3D(Basis(), position + Vector3.UP),
			"foot": position + Vector3.RIGHT, "facing": 0.3}
	return NetSnapshot.encode(t, trike, rider)


func _test_snapshot_validation() -> void:
	print("\n[Net: snapshot validation]")
	var good := _snapshot(1.0, Vector3(5, 100, -40))
	_check(NetSnapshot.validate(good) == "" and good.size() == NetSnapshot.FIELD_COUNT, "a real snapshot passes")
	var short := good.slice(0, 10)
	var wrong_type := good.duplicate()
	wrong_type[1] = "here"
	var fast := good.duplicate()
	fast[3] = Vector3(0, 0, -500)
	var nan := good.duplicate()
	nan[1] = Vector3(NAN, 0, 0)
	var far := good.duplicate()
	far[1] = Vector3(1e6, 0, 0)
	var bad_state := good.duplicate()
	bad_state[13] = 42
	var rejected := NetSnapshot.validate(short) != "" and NetSnapshot.validate(wrong_type) != "" \
			and NetSnapshot.validate(fast) != "" and NetSnapshot.validate(nan) != "" \
			and NetSnapshot.validate(far) != "" and NetSnapshot.validate(bad_state) != "" \
			and NetSnapshot.validate("hello") != ""
	_check(rejected, "malformed, impossible or corrupt snapshots are rejected (host validation)")
	var before := _snapshot(1.0, Vector3(0, 0, 0))
	var after := _snapshot(1.1, Vector3(0, 0, -300))
	after[19] = 1  # the owner respawned in between
	var mid: Dictionary = NetSnapshot.blend(before, after, 0.5)
	var z: float = (mid["trike"]["xf"] as Transform3D).origin.z
	_check(is_equal_approx(z, -300.0), "across a respawn the proxy snaps instead of sliding over the map")


func _test_snapshot_buffer() -> void:
	print("\n[Net: interpolation buffer]")
	var buffer := SnapshotBuffer.new()
	buffer.delay = 0.1
	# Owner sends at 30 Hz moving 1 m per snapshot; arrival jitters 0–40 ms.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var arrivals := []
	for i in 60:
		var t := 100.0 + i / 30.0
		arrivals.append([t + 0.05 + rng.randf() * 0.04, _snapshot(t, Vector3(0, 0, -i))])
	arrivals.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var steps: Array[float] = []
	var last := INF
	var next := 0
	var local := 100.0
	while local < 102.0:
		while next < arrivals.size() and arrivals[next][0] <= local:
			buffer.push(arrivals[next][1], arrivals[next][0])
			next += 1
		var state := buffer.sample(local)
		if not state.is_empty():
			var z: float = (state["trike"]["xf"] as Transform3D).origin.z
			if last != INF:
				steps.append(last - z)
			last = z
		local += 1.0 / 60.0
	var smooth := not steps.is_empty()
	for step in steps:
		smooth = smooth and step >= -0.001 and step < 1.0
	_check(smooth, "jittery 30 Hz data plays back smoothly at 60 fps (no backward steps, no jumps)",
			"(max step %.2f m)" % steps.max())
	buffer.push(_snapshot(100.5), local)
	_check(buffer.count() < 60, "late, out-of-order snapshots are dropped")
	var frozen := buffer.sample(local + 5.0)
	var held_z: float = (frozen["trike"]["xf"] as Transform3D).origin.z
	_check(held_z > -59.0 - 10.0 * buffer.max_extrapolation - 0.01, "when data stops, extrapolation is capped (no flying off)",
			"(%.2f m past the last snapshot)" % (-59.0 - held_z))


func _test_proxy_trike_and_rider() -> void:
	print("\n[Net: proxy trike and rider]")
	await runner._new_arena()
	var trike: Trike = TRIKE_SCENE.instantiate()
	runner._arena.add_child(trike)
	var rider: RiderController = RIDER_SCENE.instantiate()
	runner._arena.add_child(rider)
	rider.attach_to(trike)
	await _tree().physics_frame
	trike.set_network_proxy(true)
	rider.set_network_proxy(true)
	trike.teleport(Transform3D(Basis(), Vector3(0, 3, 0)), false)
	trike.input.throttle = 1.0
	await runner._wait(0.5)
	_check(trike.freeze and trike.global_position.distance_to(Vector3(0, 3, 0)) < 0.01,
			"a proxy trike is frozen: no gravity, no input-driven motion")
	var states: Array[String] = []
	rider.state_changed.connect(func(_o: int, n: int) -> void: states.append(RiderController.STATE_NAMES[n]))
	var model := trike.get_node("Visuals/Rider") as Node3D
	var sequence := [RiderController.State.EJECTED, RiderController.State.RAGDOLL, RiderController.State.GETTING_UP,
			RiderController.State.ON_FOOT, RiderController.State.MOUNTING, RiderController.State.RIDING]
	var off_seat := true
	for state: int in sequence:
		var data := NetSnapshot.blend(_snapshot(1.0, Vector3(0, 3, 0), state), _snapshot(1.0, Vector3(0, 3, 0), state), 0.0)
		trike.apply_network_state(data["trike"])
		rider.apply_network_state(data["rider"])
		await _tree().physics_frame
		if state != RiderController.State.RIDING:
			off_seat = off_seat and model.top_level and not trike.has_rider
	_check(states == ["EJECTED", "RAGDOLL", "GETTING_UP", "ON_FOOT", "MOUNTING", "RIDING"],
			"rider proxy follows the owner's state machine", "(%s)" % " → ".join(states))
	_check(off_seat and not model.top_level and trike.has_rider and rider.eject_count == 1,
			"rider model leaves and returns to the seat like the real rider")
	var moved := NetSnapshot.blend(_snapshot(2.0, Vector3(4, 3, -6)), _snapshot(2.0, Vector3(4, 3, -6)), 0.0)
	trike.apply_network_state(moved["trike"])
	await _tree().physics_frame
	_check(trike.global_position.is_equal_approx(Vector3(4, 3, -6)) and is_equal_approx(trike.forward_speed, 10.0)
			and trike.get_motion_velocity() == Vector3(0, 0, -10), "snapshot moves the proxy and drives its visuals")


## A local trike driving into a kinematic proxy bounces off it: knockback
## and the normal impact rule work against remote players.
func _test_proxy_collision() -> void:
	print("\n[Net: collisions with remote trikes]")
	await runner._new_arena()
	var proxy: Trike = TRIKE_SCENE.instantiate()
	runner._arena.add_child(proxy)
	proxy.input_source = null
	proxy.teleport(Transform3D(Basis(), Vector3(0, 0.9, 0)), false)
	await runner._wait(0.8)
	proxy.set_network_proxy(true)
	var proxy_rest := proxy.global_position
	var local := runner._spawn_trike(Vector3(0, 0.9, 30)) as Trike
	await runner._wait(0.5)
	var max_impact := [0.0]
	local.impact.connect(func(strength: float, _v: Vector3) -> void: max_impact[0] = maxf(max_impact[0], strength))
	var t := 0.0
	while local.global_position.z > 2.5 and t < 5.0:
		local.input.throttle = 1.0 if local.forward_speed < 12.0 else 0.0
		await _tree().physics_frame
		t += 1.0 / 60.0
	await runner._wait(0.5)
	_check(max_impact[0] > 5.0 and local.global_position.z > 0.5, "driving into a remote trike stops you with an impact",
			"(impact %.1f)" % max_impact[0])
	_check(proxy.global_position.distance_to(proxy_rest) < 0.05, "the remote trike only moves when its owner says so",
			"(moved %.2f m)" % proxy.global_position.distance_to(proxy_rest))
	# A moving proxy pushes a local trike out of the way.
	var parked := runner._spawn_trike(Vector3(0, 0.9, -8)) as Trike
	await runner._wait(0.6)
	var start := parked.global_position
	var z := proxy.global_position.z
	for i in 60:
		z -= 0.25
		proxy.apply_network_state({"xf": Transform3D(Basis(), Vector3(0, 0.75, z)), "vel": Vector3(0, 0, -15), "steer_amount": 0.0,
				"steer_angle": 0.0, "forward_speed": 15.0, "drift_dir": 0, "drift_charge": 0.0, "boost": 0.0,
				"susp": PackedFloat32Array([0.2, 0.2, 0.2]), "contact": 7, "has_rider": true})
		await _tree().physics_frame
	_check(parked.global_position.distance_to(start) > 1.0, "a remote trike moving through you knocks you away",
			"(%.1f m)" % parked.global_position.distance_to(start))
	await runner._new_arena()


## Online the pause menu must not stop the game (other players keep
## racing); clients get Leave Game instead of Restart / Race Again.
func _test_online_menus() -> void:
	print("\n[Net: online pause and results menus]")
	await runner._new_arena()
	var main: RaceSession = load("res://scenes/main/main.tscn").instantiate()
	main.skip_countdown = true
	runner._arena.add_child(main)
	await _tree().process_frame
	main.pause_menu.set_online(false)
	main.results_screen.set_online(false)
	main.pause_menu.set_paused(true)
	var lobby_button := main.pause_menu.find_child("LobbyButton", true, false) as Button
	var restart_button := main.pause_menu.find_child("RestartButton", true, false) as Button
	_check(main.pause_menu.is_open() and not _tree().paused, "online pause menu opens without freezing the race")
	_check(lobby_button.text == "Leave Game" and not restart_button.visible, "clients: Leave Game, no Restart")
	await runner._press_action(&"pause")
	_check(not main.pause_menu.is_open() and not _tree().paused, "ESC closes it again")
	var again := main.results_screen.find_children("*", "Button", true, false).filter(
			func(b: Button) -> bool: return b.text == "Host decides…")
	_check(again.size() == 1 and (again[0] as Button).disabled, "clients can't trigger Race Again (the host decides)")
	await runner._new_arena()


func _test_enet_hosting() -> void:
	print("\n[Net: ENet hosting]")
	var error := GameSession.host_lobby("Hosty", 47811, 3)
	_check(error == OK and Net.is_host() and Net.port == 47811 and GameSession.lobby.max_players == 3,
			"Host Game opens a real ENet server")
	_check(GameSession.transport.status == NetworkTransport.Status.HOSTING
			and GameSession.transport.status_message.contains("47811"), "status shows the port")
	var second := ENetMultiplayerPeer.new()
	var busy := second.create_server(47811, 4)
	_check(busy != OK, "the port is really in use")
	second.close()
	var start := GameSession.build_racer_list()
	_check(start.size() == 1 and int(start[0]["owner"]) == 1, "the host owns its own racer")
	GameSession.leave_lobby()
	_check(not Net.is_online() and Net.lobby == null, "leaving shuts the server down")
	var again := GameSession.host_lobby("Hosty", 47811, 3)
	_check(again == OK, "the same port can be hosted again right away")
	GameSession.leave_lobby()
