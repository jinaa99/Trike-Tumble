extends Node
## Automated gameplay tests. Drives real scenes with simulated input and
## checks physics outcomes. Run (see docs/TESTING.md):
##   Godot --headless --path . --fixed-fps 60 --scene res://tests/test_runner.tscn
## Exit code 0 = all passed.

const MAIN_SCENE := preload("res://scenes/main/main.tscn")
const TRIKE_SCENE := preload("res://scenes/vehicles/trike.tscn")
const CRATE_SCENE := preload("res://scenes/props/crate.tscn")
const RIDER_SCENE := preload("res://scenes/characters/rider_character.tscn")
const CAMERA_SCENE := preload("res://scenes/camera/follow_camera.tscn")
const RACER_TESTS := preload("res://tests/racer_tests.gd")
const RACE_FLOW_TESTS := preload("res://tests/race_flow_tests.gd")
const UI_TESTS := preload("res://tests/ui_tests.gd")
const NET_UNIT_TESTS := preload("res://tests/net_unit_tests.gd")
const MAP_TESTS := preload("res://tests/map_tests.gd")
const ITEM_TESTS := preload("res://tests/item_tests.gd")
const POLISH_TESTS := preload("res://tests/polish_tests.gd")
const REQUIRED_ACTIONS: Array[StringName] = [
	&"accelerate", &"brake", &"steer_left", &"steer_right", &"drift", &"reset", &"pause", &"interact", &"use_item",
]

var _passed := 0
var _failed := 0
var _arena: Node3D


func _ready() -> void:
	# Default controls and a separate settings file: the player's saved
	# settings never affect tests, and tests never overwrite them.
	GameSettings.use_test_profile("user://test_settings.cfg")
	_run_all.call_deferred()


func _run_all() -> void:
	print("\n=== TRIKE TUMBLE TESTS ===")
	# `-- --only=core|racers|flow|ui|net|items|polish|map` runs one group (while working on it).
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
	if only.is_empty() or only == "core":
		await _run_core()
	if only.is_empty() or only == "racers":
		await RACER_TESTS.new(self).run()
	if only.is_empty() or only == "flow":
		await RACE_FLOW_TESTS.new(self).run()
	if only.is_empty() or only == "ui":
		await UI_TESTS.new(self).run()
	if only.is_empty() or only == "net":
		await NET_UNIT_TESTS.new(self).run()
	if only.is_empty() or only == "items":
		await ITEM_TESTS.new(self).run()
	if only.is_empty() or only == "polish":
		await POLISH_TESTS.new(self).run()
	if only.is_empty() or only == "map":
		await MAP_TESTS.new(self).run()
	print("\n=== RESULT: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 or _passed == 0 else 0)


func _run_core() -> void:
	_test_input_map()
	await _test_keyboard_controls()
	await _test_settle()
	await _test_accelerate_and_top_speed()
	await _test_brake_and_reverse()
	await _test_steering()
	await _test_drift_and_boost()
	await _test_handbrake()
	await _test_wall_collision()
	await _test_crate_knock()
	await _test_flip_auto_recovery()
	await _test_manual_reset()
	await _test_stuck_recovery()
	await _test_main_scene_spawn_and_hud()
	await _test_out_of_bounds_respawn()
	await _test_pause()
	await _test_visuals_follow_physics()
	await _test_rider_riding_normally()
	await _test_rider_weak_impacts()
	await _test_rider_full_recovery_loop()
	await _test_rider_overturn_and_flipped_mount()
	await _test_rider_no_auto_respawn()
	await _test_rider_in_race_scene()
	await _test_rider_real_track_crash()
	await _test_rider_attach_lifecycle()
	await _test_rider_e_key_mount()
	await _test_finish_mounted()
	await _test_finish_after_ejection()
	await _test_finish_other_player()
	await _test_scenery_clear_of_road()
	await _test_full_track_run()


# --- Helpers ----------------------------------------------------------------

func _check(condition: bool, test_name: String, detail := "") -> void:
	if condition:
		_passed += 1
		print("  PASS  %s  %s" % [test_name, detail])
	else:
		_failed += 1
		print("  FAIL  %s  %s" % [test_name, detail])


func _ticks(seconds: float) -> int:
	return int(seconds * Engine.physics_ticks_per_second)


func _wait(seconds: float) -> void:
	for i in _ticks(seconds):
		await get_tree().physics_frame


## Holds the given input for `seconds`, re-applying it each tick.
func _hold(trike: Trike, seconds: float, throttle := 0.0, brake := 0.0, steer := 0.0, drift := false) -> void:
	for i in _ticks(seconds):
		trike.input.throttle = throttle
		trike.input.brake = brake
		trike.input.steer = steer
		trike.input.drift = drift
		await get_tree().physics_frame
	trike.input.clear()


func _new_arena() -> void:
	if _arena:
		_arena.queue_free()
		await get_tree().process_frame
	_arena = Node3D.new()
	_arena.name = "Arena"
	add_child(_arena)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(600.0, 1.0, 600.0)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	_arena.add_child(floor_body)


func _add_static_box(size: Vector3, position: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = position
	_arena.add_child(body)


func _spawn_trike(position := Vector3(0.0, 0.9, 0.0), basis := Basis.IDENTITY) -> Trike:
	var trike: Trike = TRIKE_SCENE.instantiate()
	_arena.add_child(trike)
	trike.input_source = null
	trike.teleport(Transform3D(basis, position))
	return trike


func _yaw(trike: Trike) -> float:
	var forward := -trike.global_basis.z
	return atan2(-forward.x, -forward.z)


func _slip_angle_deg(trike: Trike) -> float:
	var v := trike.linear_velocity
	v.y = 0.0
	var forward := -trike.global_basis.z
	forward.y = 0.0
	if v.length() < 1.0:
		return 0.0
	return rad_to_deg(forward.angle_to(v))


func _press_action(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame


# --- Vehicle tests (flat arena) ---------------------------------------------

func _test_input_map() -> void:
	print("\n[Input map]")
	for action in REQUIRED_ACTIONS:
		_check(InputMap.has_action(action) and not InputMap.action_get_events(action).is_empty(),
				"action '%s' mapped" % action)
	var e_mapped := false
	for event in InputMap.action_get_events(&"interact"):
		var key := event as InputEventKey
		if key and (key.physical_keycode == KEY_E or key.keycode == KEY_E):
			e_mapped = true
	_check(e_mapped, "E key is mapped to 'interact'")


## Sends real key events through Input and checks PlayerInputSource reads them.
func _test_keyboard_controls() -> void:
	print("\n[Keyboard controls]")
	await _new_arena()
	var trike: Trike = TRIKE_SCENE.instantiate()
	_arena.add_child(trike)
	trike.teleport(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.9, 0.0)))
	var cases := [
		[KEY_W, "throttle", 1.0], [KEY_UP, "throttle", 1.0],
		[KEY_S, "brake", 1.0], [KEY_DOWN, "brake", 1.0],
		[KEY_A, "steer", -1.0], [KEY_LEFT, "steer", -1.0],
		[KEY_D, "steer", 1.0], [KEY_RIGHT, "steer", 1.0],
		[KEY_SPACE, "drift", true],
		[KEY_E, "interact_pressed", true],
	]
	for entry: Array in cases:
		var key: Key = entry[0]
		var field: String = entry[1]
		await _send_key(key, true)
		# physics_frame fires before _physics_process, so wait one more tick
		# for the trike to poll its input source.
		await get_tree().physics_frame
		await get_tree().physics_frame
		var value: Variant = trike.input.get(field)
		await _send_key(key, false)
		await get_tree().physics_frame
		await get_tree().physics_frame
		_check(value == entry[2], "%s key -> %s" % [OS.get_keycode_string(key), field], "(%s)" % str(value))
	var respawns := [0]
	trike.respawned.connect(func() -> void: respawns[0] += 1)
	await _send_key(KEY_R, true)
	await get_tree().physics_frame
	await _send_key(KEY_R, false)
	await get_tree().physics_frame
	_check(respawns[0] == 1, "R key -> reset (fires once per press)", "(%d resets)" % respawns[0])


func _send_key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)
	await get_tree().process_frame


func _test_settle() -> void:
	print("\n[Spawn & suspension settle]")
	await _new_arena()
	var trike := _spawn_trike()
	await _wait(1.5)
	var heights: Array[float] = []
	for i in 30:
		heights.append(trike.global_position.y)
		await get_tree().physics_frame
	var bounce: float = heights.max() - heights.min()
	_check(trike.grounded_wheel_count == 3, "all three wheels touch the ground", "(%d)" % trike.grounded_wheel_count)
	_check(trike.global_basis.y.y > 0.97, "trike sits upright", "(up.y=%.3f)" % trike.global_basis.y.y)
	_check(bounce < 0.01, "suspension settles without bouncing", "(Δy=%.4f m)" % bounce)
	_check(trike.linear_velocity.length() < 0.2, "trike stays still with no input", "(%.3f m/s)" % trike.linear_velocity.length())


func _test_accelerate_and_top_speed() -> void:
	print("\n[Acceleration]")
	await _new_arena()
	var trike := _spawn_trike()
	await _wait(0.5)
	await _hold(trike, 1.0, 1.0)
	var speed_1s := trike.forward_speed
	await _hold(trike, 2.0, 1.0)
	var speed_3s := trike.forward_speed
	_check(speed_1s > 8.0, "accelerates quickly", "(%.1f m/s after 1 s)" % speed_1s)
	_check(speed_3s > 18.0, "keeps accelerating", "(%.1f m/s after 3 s)" % speed_3s)
	await _hold(trike, 6.0, 1.0)
	var top := trike.forward_speed
	_check(top > trike.config.max_speed * 0.85 and top < trike.config.max_speed * 1.05,
			"top speed near config max_speed", "(%.1f of %.1f m/s)" % [top, trike.config.max_speed])
	_check(trike.global_basis.y.y > 0.95, "stays upright at top speed")


func _test_brake_and_reverse() -> void:
	print("\n[Brake & reverse]")
	await _new_arena()
	var trike := _spawn_trike()
	await _wait(0.3)
	await _hold(trike, 3.0, 1.0)
	var start_speed := trike.forward_speed
	var ticks := 0
	while trike.forward_speed > 0.5 and ticks < _ticks(5.0):
		trike.input.brake = 1.0
		await get_tree().physics_frame
		ticks += 1
	var stop_time := ticks / float(Engine.physics_ticks_per_second)
	_check(stop_time < 1.5, "brakes to a stop", "(from %.1f m/s in %.2f s)" % [start_speed, stop_time])
	await _hold(trike, 2.5, 0.0, 1.0)
	_check(trike.forward_speed < -3.0, "reverses when holding brake at a stop", "(%.1f m/s)" % trike.forward_speed)
	_check(trike.forward_speed >= -trike.config.max_reverse_speed - 0.5, "reverse speed is capped")


func _test_steering() -> void:
	print("\n[Steering]")
	for steer: float in [1.0, -1.0]:
		await _new_arena()
		var trike := _spawn_trike()
		await _wait(0.3)
		await _hold(trike, 1.5, 1.0)
		var yaw_before := _yaw(trike)
		var min_up := 1.0
		for i in _ticks(1.0):
			trike.input.throttle = 1.0
			trike.input.steer = steer
			min_up = minf(min_up, trike.global_basis.y.y)
			await get_tree().physics_frame
		var turned := rad_to_deg(wrapf(_yaw(trike) - yaw_before, -PI, PI))
		var side := "right" if steer > 0.0 else "left"
		var correct := turned < -25.0 if steer > 0.0 else turned > 25.0
		_check(correct, "steers %s" % side, "(yaw change %.0f° in 1 s)" % turned)
		_check(min_up > 0.85, "does not tip over while turning %s" % side, "(min up.y %.2f)" % min_up)
		_check(_slip_angle_deg(trike) < 15.0, "normal turn grips (%s)" % side, "(slip %.1f°)" % _slip_angle_deg(trike))
		trike.input.clear()


func _test_drift_and_boost() -> void:
	print("\n[Drift & boost]")
	await _new_arena()
	var trike := _spawn_trike()
	await _wait(0.3)
	await _hold(trike, 2.0, 1.0)
	var max_slip := 0.0
	var drift_seen := false
	for i in _ticks(2.4):
		trike.input.throttle = 1.0
		trike.input.steer = 1.0
		trike.input.drift = true
		await get_tree().physics_frame
		drift_seen = drift_seen or trike.is_drifting
		max_slip = maxf(max_slip, _slip_angle_deg(trike))
	_check(drift_seen and trike.is_drifting, "holding SPACE + steer starts a drift")
	_check(max_slip > 12.0, "drift slides sideways", "(max slip %.1f°)" % max_slip)
	_check(trike.get_drift_tier() >= 1, "drift charges a boost tier", "(tier %d, charge %.2f s)" % [trike.get_drift_tier(), trike.drift_charge])
	_check(trike.global_basis.y.y > 0.85, "stays upright while drifting")
	var speed_before := trike.forward_speed
	trike.input.drift = false
	trike.input.steer = 0.0
	await get_tree().physics_frame
	_check(not trike.is_drifting and trike.boost_time > 0.0, "releasing drift awards a boost", "(%.2f s)" % trike.boost_time)
	await _hold(trike, 0.6, 1.0)
	_check(trike.forward_speed > speed_before + 2.0, "boost increases speed", "(%.1f → %.1f m/s)" % [speed_before, trike.forward_speed])


func _test_handbrake() -> void:
	print("\n[Handbrake]")
	await _new_arena()
	var trike := _spawn_trike()
	await _wait(0.3)
	await _hold(trike, 2.0, 1.0)
	var before := trike.forward_speed
	await _hold(trike, 1.0, 0.0, 0.0, 0.0, true)
	_check(not trike.is_drifting, "SPACE without steering does not drift")
	_check(trike.forward_speed < before - 5.0, "SPACE without steering slows like a handbrake", "(%.1f → %.1f m/s)" % [before, trike.forward_speed])


func _test_wall_collision() -> void:
	print("\n[Wall collision]")
	await _new_arena()
	_add_static_box(Vector3(12.0, 3.0, 1.0), Vector3(0.0, 1.5, -40.0))
	var trike := _spawn_trike()
	await _wait(0.3)
	var max_speed := 0.0
	var min_z := INF
	for i in _ticks(4.0):
		trike.input.throttle = 1.0
		await get_tree().physics_frame
		max_speed = maxf(max_speed, trike.forward_speed)
		min_z = minf(min_z, trike.global_position.z)
	trike.input.clear()
	_check(min_z > -40.0, "does not pass through a wall", "(closest z %.2f, wall face at -39.5)" % min_z)
	_check(trike.linear_velocity.length() < max_speed * 0.5, "impact stops the trike", "(%.1f → %.1f m/s)" % [max_speed, trike.linear_velocity.length()])


func _test_crate_knock() -> void:
	print("\n[Dynamic obstacle]")
	await _new_arena()
	var crate: RigidBody3D = CRATE_SCENE.instantiate()
	_arena.add_child(crate)
	crate.global_position = Vector3(0.0, 0.5, -30.0)
	var trike := _spawn_trike()
	await _wait(0.3)
	await _hold(trike, 3.5, 1.0)
	var moved := crate.global_position.distance_to(Vector3(0.0, 0.5, -30.0))
	_check(moved > 3.0, "crate gets knocked away", "(moved %.1f m)" % moved)
	_check(trike.global_basis.y.y > 0.5, "trike survives hitting a crate")


func _test_flip_auto_recovery() -> void:
	print("\n[Auto recovery when overturned]")
	await _new_arena()
	var trike := _spawn_trike(Vector3(0.0, 1.5, 0.0), Basis(Vector3.FORWARD, PI))
	var respawns := [0]
	trike.respawned.connect(func() -> void: respawns[0] += 1)
	await _wait(0.5)
	_check(trike.global_basis.y.y < 0.0, "trike lands upside down (setup)", "(up.y %.2f)" % trike.global_basis.y.y)
	await _wait(2.5)
	_check(respawns[0] >= 1, "automatic recovery triggers")
	await _wait(1.0)
	_check(trike.global_basis.y.y > 0.95 and trike.grounded_wheel_count == 3, "back on its wheels after recovery",
			"(up.y %.2f, wheels %d)" % [trike.global_basis.y.y, trike.grounded_wheel_count])


func _test_manual_reset() -> void:
	print("\n[Manual reset]")
	await _new_arena()
	var trike := _spawn_trike(Vector3(0.0, 1.5, 0.0), Basis(Vector3.FORWARD, PI))
	await _wait(0.7)
	var flipped := trike.global_basis.y.y
	# Press reset before the 1.5 s automatic recovery could kick in.
	trike.input.reset_pressed = true
	await _wait(0.6)
	_check(flipped < 0.0, "trike is upside down (setup)", "(up.y %.2f)" % flipped)
	_check(trike.global_basis.y.y > 0.95 and trike.grounded_wheel_count == 3, "R puts the trike back on its wheels",
			"(up.y %.2f)" % trike.global_basis.y.y)


func _test_stuck_recovery() -> void:
	print("\n[Stuck recovery]")
	await _new_arena()
	# A post under the chassis lifts the wheels off the ground (high-centered).
	_add_static_box(Vector3(0.5, 1.0, 0.5), Vector3(0.0, 0.5, 0.0))
	var trike := _spawn_trike(Vector3(0.0, 1.3, 0.0))
	var respawns := [0]
	trike.respawned.connect(func() -> void: respawns[0] += 1)
	await _wait(0.5)
	var wheels := trike.grounded_wheel_count
	await _hold(trike, 4.0, 1.0)
	_check(wheels < 2, "trike is high-centered (setup)", "(%d wheels down)" % wheels)
	_check(respawns[0] >= 1, "stuck detection triggers recovery")


# --- Full game scene tests --------------------------------------------------

func _load_main() -> RaceSession:
	if _arena:
		_arena.queue_free()
		_arena = null
	var main: RaceSession = MAIN_SCENE.instantiate()
	main.skip_countdown = true  # these tests drive from the first tick
	add_child(main)
	var trike: Trike = main.get_node("Trike")
	trike.input_source = null
	return main


func _test_main_scene_spawn_and_hud() -> void:
	print("\n[Main scene: spawn, camera, HUD]")
	var main := _load_main()
	var trike: Trike = main.get_node("Trike")
	var track: Track = main.get_node("TestTrack")
	var camera: FollowCamera = main.get_node("FollowCamera")
	var hud: Hud = main.get_node("HUD")
	await _wait(1.5)
	_check(track.path.length > 900.0, "test track is built", "(%.0f m long, %.0f m drop)" % [track.path.length, track.path.points[0].y - track.path.points[-1].y])
	_check(trike.grounded_wheel_count == 3 and trike.global_basis.y.y > 0.95, "trike spawns on the road")
	_check(trike.linear_velocity.length() < 0.5, "trike holds still on the downhill start", "(%.2f m/s)" % trike.linear_velocity.length())
	await _hold(trike, 2.5, 1.0)
	await get_tree().process_frame
	var shown := hud.get_displayed_speed()
	var actual := roundi(trike.linear_velocity.length() * 3.6)
	_check(shown > 30 and absi(shown - actual) <= 8, "HUD shows speed in km/h", "(HUD %d, actual %d)" % [shown, actual])
	var cam_distance := camera.global_position.distance_to(trike.global_position)
	var behind := (camera.global_position - trike.global_position).dot(trike.global_basis.z) > 0.0
	_check(cam_distance > 3.0 and cam_distance < 12.0 and behind, "camera follows behind the trike", "(%.1f m)" % cam_distance)
	_check(main.get_race_time() > 2.0, "race timer runs after throttle", "(%.2f s)" % main.get_race_time())
	main.queue_free()
	await get_tree().process_frame


func _test_out_of_bounds_respawn() -> void:
	print("\n[Out of bounds respawn]")
	var main := _load_main()
	var trike: Trike = main.get_node("Trike")
	var track: Track = main.get_node("TestTrack")
	await _wait(1.0)
	await _hold(trike, 3.0, 1.0)
	var safe_index: int = main.get_progress().last_safe_index
	trike.teleport(Transform3D(Basis.IDENTITY, trike.global_position + Vector3(30.0, -30.0, 0.0)))
	await _wait(1.5)
	var index := track.path.find_nearest(trike.global_position)
	_check(track.is_on_road(trike.global_position, index) and trike.grounded_wheel_count >= 2,
			"falling off the course respawns on the road", "(near sample %d, last safe %d)" % [index, safe_index])
	main.queue_free()
	await get_tree().process_frame


func _test_pause() -> void:
	print("\n[Pause]")
	var main := _load_main()
	var pause_menu: PauseMenu = main.get_node("PauseMenu")
	await _wait(0.3)
	await _press_action(&"pause")
	_check(get_tree().paused and pause_menu.is_open(), "ESC action pauses the game")
	await _press_action(&"pause")
	_check(not get_tree().paused and not pause_menu.is_open(), "ESC action resumes the game")
	main.queue_free()
	await get_tree().process_frame


## Visual wheels must sit exactly on the physics raycast wheels, and the
## rider's IK must keep gloves on the grips and boots on the footrests.
func _test_visuals_follow_physics() -> void:
	print("\n[Visuals follow physics]")
	var main := _load_main()
	var trike: Trike = main.get_node("Trike")
	# This test is about the riding pose; keep the rider aboard even if the
	# forced full-lock drift hits a barrier (own copy of the config).
	main.rider.config = main.rider.config.duplicate()
	main.rider.config.eject_impact_strength = INF
	main.rider.config.eject_tilt_up = -2.0
	var visuals: TrikeVisuals = trike.get_node("Visuals")
	var rider: Rider = trike.get_node("Visuals/Rider")
	var wheels: Array[Node3D] = [trike.get_node("Visuals/FrontPivot/FrontWheel"),
			trike.get_node("Visuals/RearWheelLeft"), trike.get_node("Visuals/RearWheelRight")]
	await _wait(1.0)
	var pilot := TrackAutopilot.new(main.track, trike)
	var worst_wheel := 0.0
	var worst_ik := 0.0
	for i in range(0, _ticks(6.0), 2):
		pilot.drive()
		# Throw in hard steering and a drift to stress the rider pose.
		if i > _ticks(3.0) and i < _ticks(4.5):
			trike.input.steer = 1.0
			trike.input.drift = true
		await get_tree().physics_frame
		await get_tree().physics_frame
		# Sync visuals to the current physics state before measuring.
		visuals._process(0.0)
		for w in Trike.WHEEL_COUNT:
			var expected := trike.global_transform * (trike.get_wheel_mount(w) + Vector3.DOWN * trike.wheel_suspension_length[w])
			worst_wheel = maxf(worst_wheel, wheels[w].global_position.distance_to(expected))
		worst_ik = maxf(worst_ik, rider.get_max_ik_error())
	_check(worst_wheel < 0.01, "visual wheels match physics wheel positions", "(max error %.4f m)" % worst_wheel)
	_check(worst_ik < 0.02, "gloves stay on grips and boots on footrests", "(max IK error %.4f m)" % worst_ik)
	main.queue_free()
	await get_tree().process_frame


## No scenery or landmark collider may stick into the drivable road.
func _test_scenery_clear_of_road() -> void:
	print("\n[Scenery collision stays off the road]")
	var main := _load_main()
	await get_tree().process_frame
	var track := main.track
	var shapes := scenery_colliders(track)
	var intrusions := count_road_intrusions(track, shapes)
	_check(shapes.size() > 100, "scenery has collision", "(%d colliders)" % shapes.size())
	_check(intrusions == 0, "no scenery collider inside the road corridor", "(%d intrusions)" % intrusions)
	main.queue_free()
	await get_tree().process_frame


## Every scenery, landmark and structure collider of a track.
static func scenery_colliders(track: Track) -> Array[CollisionShape3D]:
	var shapes: Array[CollisionShape3D] = []
	var stack: Array[Node] = []
	for path: String in ["Decor/SceneryCollision", "Landmarks/LandmarkCollision", "Structures/StructureCollision"]:
		var node := track.get_node_or_null(path)
		if node:
			stack.append(node)
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is CollisionShape3D:
			shapes.append(node)
		stack.append_array(node.get_children())
	return shapes


## Colliders whose center lies inside the drivable road corridor.
static func count_road_intrusions(track: Track, shapes: Array[CollisionShape3D]) -> int:
	var intrusions := 0
	for collider in shapes:
		var p := collider.global_position
		var i := track.path.find_nearest(p)
		var offset := p - track.path.points[i]
		var lateral := absf(offset.dot(track.path.rights[i]))
		var vertical := offset.dot(track.path.ups[i])
		if lateral < track.half_width_at(i) + 0.3 and vertical > -3.0 and vertical < 6.0 \
				and track.get_sample_kind(i) != TrackMeshBuilder.SampleKind.GAP:
			intrusions += 1
	return intrusions


# --- Rider ejection & recovery ------------------------------------------------

## Trike + rider + follow camera in the flat arena, wired like the race scene.
func _rider_rig(position := Vector3(0.0, 0.9, 0.0)) -> Dictionary:
	var trike := _spawn_trike(position)
	var rider: RiderController = RIDER_SCENE.instantiate()
	_arena.add_child(rider)
	rider.input_source = null
	rider.attach_to(trike)
	var camera: FollowCamera = CAMERA_SCENE.instantiate()
	_arena.add_child(camera)
	camera.current = true
	camera.target = trike
	camera.snap_to_target()
	rider.focus_changed.connect(camera.set_target)
	var states: Array[String] = []
	rider.state_changed.connect(func(_old: int, new_state: int) -> void:
		states.append(RiderController.STATE_NAMES[new_state]))
	var respawns := [0]
	trike.respawned.connect(func() -> void: respawns[0] += 1)
	return {"trike": trike, "rider": rider, "camera": camera, "states": states, "respawns": respawns}


## Drives straight at `target_speed` (m/s) for up to `seconds`, stopping early
## when the rider leaves the trike.
func _drive_until(rig: Dictionary, target_speed: float, seconds: float) -> void:
	var trike: Trike = rig["trike"]
	var rider: RiderController = rig["rider"]
	for i in _ticks(seconds):
		trike.input.throttle = 1.0 if trike.forward_speed < target_speed else 0.0
		await get_tree().physics_frame
		if not rider.is_riding():
			break
	trike.input.clear()


func _wait_for_state(rider: RiderController, wanted: RiderController.State, seconds: float) -> float:
	var t := 0.0
	while rider.state != wanted and t < seconds:
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	return t


func _test_rider_riding_normally() -> void:
	print("\n[Rider: normal riding]")
	await _new_arena()
	var rig := _rider_rig()
	var trike: Trike = rig["trike"]
	var rider: RiderController = rig["rider"]
	await _wait(0.5)
	await _hold(trike, 2.0, 1.0)
	await _hold(trike, 1.5, 1.0, 0.0, 1.0, true)
	await _hold(trike, 1.0, 0.0, 1.0)
	_check(rider.is_riding() and rider.eject_count == 0, "accelerating, drifting and braking never eject",
			"(state %s)" % rider.get_state_name())
	_check(trike.has_rider and (rig["camera"] as FollowCamera).target == trike, "trike has its rider and the camera")


func _test_rider_weak_impacts() -> void:
	print("\n[Rider: weak impacts]")
	await _new_arena()
	_add_static_box(Vector3(12.0, 3.0, 1.0), Vector3(0.0, 1.5, -30.0))
	var rig := _rider_rig()
	var rider: RiderController = rig["rider"]
	var trike: Trike = rig["trike"]
	await _wait(0.3)
	var peak := 0.0
	for i in _ticks(8.0):
		trike.input.throttle = 1.0 if trike.forward_speed < 5.0 else 0.0
		await get_tree().physics_frame
		peak = maxf(peak, trike.last_impact_strength)
	trike.input.clear()
	_check(peak > 3.0, "slow head-on wall hit registers an impact (setup)", "(peak %.1f)" % peak)
	_check(rider.is_riding(), "an 18 km/h wall bump does not eject", "(threshold %.1f)" % rider.config.eject_impact_strength)
	# Crate at full speed.
	var crate: RigidBody3D = CRATE_SCENE.instantiate()
	_arena.add_child(crate)
	crate.global_position = trike.global_position + Vector3(-6.0, 0.6, 26.0)
	trike.teleport(Transform3D(Basis(Vector3.UP, PI), trike.global_position + Vector3(-6.0, 0.4, 0.0)))
	await _hold(trike, 3.5, 1.0)
	_check(rider.is_riding() and rider.eject_count == 0, "smashing a crate at speed does not eject",
			"(crate moved %.1f m)" % crate.global_position.distance_to(trike.global_position))


## Crash -> fly -> tumble -> get up -> walk -> mount, checking timing,
## camera, trike behaviour and controls along the way.
func _test_rider_full_recovery_loop() -> void:
	print("\n[Rider: crash and full recovery loop]")
	await _new_arena()
	_add_static_box(Vector3(14.0, 3.0, 1.0), Vector3(0.0, 1.5, -60.0))
	var rig := _rider_rig()
	var trike: Trike = rig["trike"]
	var rider: RiderController = rig["rider"]
	var camera: FollowCamera = rig["camera"]
	var states: Array[String] = rig["states"]
	await _wait(0.3)
	await _drive_until(rig, 18.0, 8.0)
	_check(rider.state == RiderController.State.EJECTED and rider.eject_count == 1,
			"head-on wall hit at ~65 km/h ejects the rider", "(impact peak %.1f)" % trike.last_impact_strength)
	_check(not trike.has_rider, "trike controls are cut while the rider is off")

	var model: Rider = trike.get_node("Visuals/Rider")
	var trike_start := trike.global_position
	var max_trike_step := 0.0
	var max_cam_step := 0.0
	var last_trike := trike.global_position
	var last_cam := camera.global_position
	var max_separation := 0.0
	var camera_targets := {}
	var fall_time := 0.0
	var get_up_time := 0.0
	# Fall and get up with no input at all.
	for i in _ticks(6.0):
		await get_tree().physics_frame
		max_trike_step = maxf(max_trike_step, trike.global_position.distance_to(last_trike))
		max_cam_step = maxf(max_cam_step, camera.global_position.distance_to(last_cam))
		last_trike = trike.global_position
		last_cam = camera.global_position
		max_separation = maxf(max_separation, model.global_position.distance_to(trike.global_position))
		camera_targets[rider.get_state_name()] = camera.target
		if rider.state == RiderController.State.EJECTED or rider.state == RiderController.State.RAGDOLL:
			fall_time += 1.0 / Engine.physics_ticks_per_second
		elif rider.state == RiderController.State.GETTING_UP:
			get_up_time += 1.0 / Engine.physics_ticks_per_second
		# Extra impacts on the riderless trike must not re-trigger anything.
		if i == 30:
			trike.apply_central_impulse(trike.linear_velocity.normalized() * 600.0 if trike.linear_velocity.length() > 0.1 else Vector3(0, 0, 600))
		if rider.state == RiderController.State.ON_FOOT and rider.state_time > 0.5:
			break
	_check(states.slice(0, 4) == ["EJECTED", "RAGDOLL", "GETTING_UP", "ON_FOOT"],
			"states go EJECTED -> RAGDOLL -> GETTING_UP -> ON_FOOT", "(%s)" % ", ".join(states))
	_check(rider.eject_count == 1, "no repeated ejection while already off the trike")
	_check(max_separation > 2.0, "rider visibly flies away from the trike", "(max %.1f m apart)" % max_separation)
	_check(fall_time >= 0.9 and fall_time <= 2.2, "fall lasts about 1-2 s", "(%.2f s)" % fall_time)
	_check(get_up_time >= 0.8 and get_up_time <= 1.25, "get-up animation lasts about 1 s", "(%.2f s)" % get_up_time)
	_check(rider.on_foot.is_on_floor(), "rider ends up standing on the ground")
	_check(camera_targets.get("RAGDOLL") == rider.ragdoll and camera_targets.get("ON_FOOT") == rider.on_foot,
			"camera follows the falling rider, then the rider on foot")
	_check(max_trike_step < 0.6 and (rig["respawns"] as Array)[0] == 0, "trike never teleports while riderless",
			"(max step %.2f m/tick, %d respawns)" % [max_trike_step, (rig["respawns"] as Array)[0]])
	_check(trike.linear_velocity.length() < 0.5, "abandoned trike comes to rest", "(%.2f m/s, %.1f m from crash)" % [
			trike.linear_velocity.length(), trike.global_position.distance_to(trike_start)])

	# On-foot movement is camera relative and doesn't drive the trike.
	# Start in open ground beside the trike (the rider may have landed by the wall).
	var open_spot := trike.global_position + Vector3(8.0, 0.0, 12.0)
	rider.on_foot.activate(Vector3(open_spot.x, 0.0, open_spot.z), Vector3.FORWARD)
	for i in _ticks(1.5):
		await get_tree().physics_frame
		last_cam = camera.global_position
	var cam_forward := -camera.global_basis.z
	cam_forward.y = 0.0
	cam_forward = cam_forward.normalized()
	var cam_right := camera.global_basis.x
	cam_right.y = 0.0
	cam_right = cam_right.normalized()
	var trike_before := trike.global_position
	var start := rider.on_foot.global_position
	for i in _ticks(1.0):
		rider.input.throttle = 1.0
		await get_tree().physics_frame
		max_cam_step = maxf(max_cam_step, camera.global_position.distance_to(last_cam))
		last_cam = camera.global_position
	rider.input.clear()
	var moved := rider.on_foot.global_position - start
	_check(moved.dot(cam_forward) > 3.5, "W walks away from the camera (camera-relative forward)", "(%.1f m)" % moved.dot(cam_forward))
	start = rider.on_foot.global_position
	var right_now := camera.global_basis.x
	right_now.y = 0.0
	for i in _ticks(0.8):
		rider.input.steer = 1.0
		await get_tree().physics_frame
	rider.input.clear()
	moved = rider.on_foot.global_position - start
	_check(moved.dot(right_now.normalized()) > 2.0, "D strafes to the camera's right", "(%.1f m)" % moved.dot(right_now.normalized()))
	_check(trike.global_position.distance_to(trike_before) < 0.2, "walking input does not drive the trike")

	# Too far: no prompt, E does nothing.
	var far_spot := trike.global_position + trike.global_basis.x * 6.0
	rider.on_foot.activate(Vector3(far_spot.x, 0.0, far_spot.z), -trike.global_basis.x)
	await _wait(0.2)
	rider.input.interact_pressed = true
	await _wait(0.3)
	_check(not rider.can_mount and rider.state == RiderController.State.ON_FOOT,
			"E does nothing 6 m from the trike", "(mount distance %.1f m)" % rider.config.mount_distance)
	# Close enough: prompt appears, E mounts.
	var near_spot := trike.global_position + trike.global_basis.x * 1.4
	rider.on_foot.activate(Vector3(near_spot.x, 0.0, near_spot.z), -trike.global_basis.x)
	await _wait(0.2)
	_check(rider.can_mount, "[E] GET ON is offered within reach",
			"(%.1f m)" % rider.on_foot.global_position.distance_to(trike.global_position))
	# Measure the camera through the mount transition (test teleports above excluded).
	await get_tree().process_frame
	last_cam = camera.global_position
	rider.input.interact_pressed = true
	var mount_time := 0.0
	while not rider.is_riding() and mount_time < 2.0:
		await get_tree().process_frame
		mount_time += 1.0 / Engine.physics_ticks_per_second
		max_cam_step = maxf(max_cam_step, camera.global_position.distance_to(last_cam))
		last_cam = camera.global_position
	_check(rider.is_riding() and states.has("MOUNTING"), "E plays the mount and returns to RIDING", "(%.2f s)" % mount_time)
	await _wait(0.1)
	_check(not model.top_level and model.get_parent().name == "Visuals", "rider model is back on the seat")
	_check(model.get_max_ik_error() < 0.02, "hands are back on the handlebar", "(IK error %.3f m)" % model.get_max_ik_error())
	var cam_settle := 0.0
	for i in _ticks(1.0):
		await get_tree().process_frame
		max_cam_step = maxf(max_cam_step, camera.global_position.distance_to(last_cam))
		last_cam = camera.global_position
		cam_settle += 1.0
	_check(camera.target == trike, "camera is back on the trike after mounting")
	_check(max_cam_step < 1.0, "camera never cuts during the whole loop", "(max %.2f m per frame)" % max_cam_step)
	# The trike may face the crash wall, so test with reverse.
	await _hold(trike, 1.5, 0.0, 1.0)
	_check(trike.forward_speed < -3.0, "vehicle controls work again after mounting", "(reversing at %.1f m/s)" % trike.forward_speed)


func _test_rider_overturn_and_flipped_mount() -> void:
	print("\n[Rider: overturn]")
	await _new_arena()
	var rig := _rider_rig()
	var trike: Trike = rig["trike"]
	var rider: RiderController = rig["rider"]
	await _wait(0.5)
	trike.teleport(Transform3D(Basis(Vector3.FORWARD, PI * 0.9), Vector3(0.0, 1.6, 0.0)), false)
	var t := await _wait_for_state(rider, RiderController.State.EJECTED, 1.0)
	_check(rider.state == RiderController.State.EJECTED, "overturning throws the rider off", "(after %.2f s)" % t)
	await _wait_for_state(rider, RiderController.State.ON_FOOT, 4.0)
	await _wait(2.0)
	_check(trike.global_basis.y.y < 0.0 and (rig["respawns"] as Array)[0] == 0,
			"overturned riderless trike is not auto-recovered", "(up.y %.2f)" % trike.global_basis.y.y)
	var spot := trike.global_position + Vector3(1.5, 0.0, 0.0)
	rider.on_foot.activate(Vector3(spot.x, 0.0, spot.z), Vector3.LEFT)
	await _wait(0.2)
	rider.input.interact_pressed = true
	await _wait_for_state(rider, RiderController.State.RIDING, 2.0)
	await _wait(0.8)
	_check(rider.is_riding() and trike.global_basis.y.y > 0.95 and trike.grounded_wheel_count == 3,
			"getting on puts an overturned trike back on its wheels", "(up.y %.2f)" % trike.global_basis.y.y)
	_check((rig["respawns"] as Array)[0] == 0, "...without a respawn/teleport to the rider")


func _test_rider_no_auto_respawn() -> void:
	print("\n[Rider: no automatic respawn]")
	await _new_arena()
	var rig := _rider_rig()
	var trike: Trike = rig["trike"]
	var rider: RiderController = rig["rider"]
	await _wait(0.3)
	await _hold(trike, 1.5, 1.0)
	var trike_spot := trike.global_position
	rider.eject()
	await _wait(10.0)
	_check(rider.state == RiderController.State.ON_FOOT, "rider waits on foot (never auto-mounted)", "(state %s)" % rider.get_state_name())
	_check((rig["respawns"] as Array)[0] == 0 and not trike.has_rider, "no automatic respawn in 10 s")
	_check(trike.global_position.distance_to(trike_spot) < 25.0, "trike stays near where it was abandoned",
			"(%.1f m)" % trike.global_position.distance_to(trike_spot))


## Race-scene wiring: HUD prompt, emergency R, race continues.
func _test_rider_in_race_scene() -> void:
	print("\n[Rider: race scene wiring]")
	var main := _load_main()
	var trike := main.trike
	var rider := main.rider
	rider.input_source = null
	await _wait(1.0)
	await _hold(trike, 2.0, 1.0)
	var time_before := main.get_race_time()
	rider.eject()
	await _wait_for_state(rider, RiderController.State.ON_FOOT, 4.0)
	_check(main.follow_camera.target == rider.on_foot, "race camera follows the rider on foot")
	_check(main.get_race_time() > time_before + 1.0, "race timer keeps running during recovery")
	var spot := trike.global_position + trike.global_basis.x * 1.2
	rider.on_foot.activate(spot, -trike.global_basis.x)
	await _wait(0.3)
	await get_tree().process_frame
	_check(main.hud.is_mount_prompt_visible(), "HUD shows the [E] GET ON prompt near the trike")
	# Walk away and use the emergency reset instead.
	rider.on_foot.activate(spot + trike.global_basis.x * 6.0, trike.global_basis.x)
	await _wait(0.3)
	_check(not main.hud.is_mount_prompt_visible(), "prompt hides when out of reach")
	rider.input.reset_pressed = true
	await _wait(0.5)
	var index := main.track.path.find_nearest(trike.global_position)
	_check(rider.is_riding() and main.track.is_on_road(trike.global_position, index),
			"R on foot = emergency recovery: back on the trike, on the road")
	_check(main.follow_camera.target == trike, "camera returns to the trike after emergency recovery")
	main.queue_free()
	await get_tree().process_frame


## Real crash on the real track: miss a corner, hit the barrier, get thrown
## over it, and get up back on the road (not stranded outside the barrier).
func _test_rider_real_track_crash() -> void:
	print("\n[Rider: real crash on the track]")
	var main := _load_main()
	var trike := main.trike
	var rider := main.rider
	rider.input_source = null
	var start := 128 - 22
	trike.teleport(main.track.path.get_frame(start).translated_local(Vector3(0, 0.8, 0)))
	main.get_progress().reset(start)
	await _wait(0.2)
	var t := 0.0
	while rider.is_riding() and t < 5.0:
		trike.input.throttle = 1.0
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	trike.input.clear()
	_check(rider.eject_count == 1, "missing a corner into the barrier at full speed ejects the rider", "(after %.1f s)" % t)
	await _wait_for_state(rider, RiderController.State.ON_FOOT, 4.0)
	var spot := rider.on_foot.global_position
	var index := main.track.path.find_nearest(spot)
	_check(rider.state == RiderController.State.ON_FOOT and main.track.is_on_road(spot, index),
			"rider gets up on the road, even if thrown over the barrier")
	_check(spot.distance_to(trike.global_position) < 15.0, "and close to the trike",
			"(%.1f m)" % spot.distance_to(trike.global_position))
	main.queue_free()
	await get_tree().process_frame


# --- Rider lifecycle, real E key, finish rules (final-demo milestone 01) ------

## Connections from `trike.impact` to this rider controller.
func _impact_links(trike: Trike, rider: RiderController) -> int:
	var count := 0
	for connection: Dictionary in trike.impact.get_connections():
		if (connection["callable"] as Callable).get_object() == rider:
			count += 1
	return count


func _test_rider_attach_lifecycle() -> void:
	print("\n[Rider: attach_to lifecycle]")
	await _new_arena()
	var trike_a := _spawn_trike(Vector3(0.0, 0.9, 0.0))
	var trike_b := _spawn_trike(Vector3(6.0, 0.9, 0.0))
	await _wait(0.2)
	var rider: RiderController = RIDER_SCENE.instantiate()
	# Before the node is in the tree (not ready): must not crash, binds in _ready.
	var early := rider.attach_to(trike_a)
	_check(early and not rider.is_node_ready(), "attach_to() before _ready is accepted (deferred)")
	_arena.add_child(rider)
	rider.input_source = null
	await get_tree().physics_frame
	_check(rider.is_attached() and rider.trike == trike_a and not trike_a.auto_recover_when_flipped,
			"deferred attach completes in _ready")
	_check(_impact_links(trike_a, rider) == 1, "impact signal connected once after deferred attach",
			"(%d)" % _impact_links(trike_a, rider))
	for i in 3:
		rider.attach_to(trike_a)
	_check(_impact_links(trike_a, rider) == 1, "repeated attach_to() never duplicates the connection",
			"(%d after 3 more calls)" % _impact_links(trike_a, rider))
	rider.attach_to(trike_b)
	_check(_impact_links(trike_a, rider) == 0 and _impact_links(trike_b, rider) == 1 and rider.trike == trike_b,
			"attaching to another trike moves the binding cleanly")
	_check(trike_a.auto_recover_when_flipped and not trike_b.auto_recover_when_flipped,
			"the released trike gets its own flip recovery back")
	_check(not rider.attach_to(null), "attach_to(null) is rejected without side effects")
	_check(rider.trike == trike_b and rider.is_attached(), "...and the current binding is kept")
	# Trike freed while the rider is off it: controller must let go safely.
	await _hold(trike_b, 1.0, 1.0)
	rider.eject()
	await _wait(0.3)
	trike_b.queue_free()
	await _wait(0.3)
	_check(not rider.is_attached() and rider.is_riding() and not rider.ragdoll.is_active(),
			"freed trike: rider controller releases it without errors", "(state %s)" % rider.get_state_name())
	_check(rider.attach_to(trike_a) and rider.is_attached() and _impact_links(trike_a, rider) == 1,
			"...and can attach to a new trike afterwards")


## Mounting through a real E key event, at the edge of the allowed distance.
func _test_rider_e_key_mount() -> void:
	print("\n[Rider: real E key mounting]")
	await _new_arena()
	var rig := _rider_rig()
	var trike: Trike = rig["trike"]
	var rider: RiderController = rig["rider"]
	rider.input_source = rider.get_node("PlayerInputSource") as PlayerInputSource
	await _wait(0.3)
	rider.eject()
	await _wait_for_state(rider, RiderController.State.ON_FOOT, 4.0)
	await _wait(1.0)  # let the trike come to rest
	var limit := rider.config.mount_distance
	var side := trike.global_basis.x
	side.y = 0.0
	side = side.normalized()
	# Just outside the limit: no prompt, real E does nothing.
	var outside := trike.global_position + side * (limit + 0.4)
	rider.on_foot.activate(Vector3(outside.x, trike.global_position.y - 0.5, outside.z), -side)
	await _wait(0.3)
	var far_distance := rider.on_foot.global_position.distance_to(trike.global_position)
	await _send_key(KEY_E, true)
	await _wait(0.1)
	await _send_key(KEY_E, false)
	await _wait(0.3)
	_check(not rider.can_mount and rider.state == RiderController.State.ON_FOOT,
			"real E key does nothing just outside the mount distance", "(%.2f m, limit %.1f m)" % [far_distance, limit])
	# Just inside the limit: prompt, real E mounts.
	var inside := trike.global_position + side * (limit - 0.6)
	rider.on_foot.activate(Vector3(inside.x, trike.global_position.y - 0.5, inside.z), -side)
	await _wait(0.3)
	var near_distance := rider.on_foot.global_position.distance_to(trike.global_position)
	_check(rider.can_mount, "[E] GET ON offered just inside the mount distance", "(%.2f m)" % near_distance)
	await _send_key(KEY_E, true)
	await _wait(0.1)
	await _send_key(KEY_E, false)
	var t := await _wait_for_state(rider, RiderController.State.RIDING, 2.0)
	_check(rider.is_riding(), "real E key press mounts the trike", "(%.2f s)" % t)
	rider.input_source = null


## Drives `trike` from `samples_before` path samples before the finish line
## (resetting race progress so the out-of-bounds check accepts the jump).
func _place_before_finish(main: RaceSession, trike: Trike, samples_before: int) -> int:
	var start := main.track.get_finish_index() - samples_before
	trike.teleport(main.track.path.get_frame(start).translated_local(Vector3(0, 0.8, 0)))
	if trike == main.trike:
		main.get_progress().reset(start)
		# Teleporting skips checkpoints, which the finish line now rejects.
		main.get_local_racer().checkpoints.force_passed_through(start)
	return start


func _start_race(main: RaceSession) -> void:
	for i in 5:
		main.trike.input.throttle = 1.0
		await get_tree().physics_frame
	main.trike.input.clear()


func _test_finish_mounted() -> void:
	print("\n[Finish: normal mounted finish]")
	var main := _load_main()
	main.rider.input_source = null
	await _wait(0.5)
	await _start_race(main)
	var finishes := [0]
	main.get_finish_tracker().racer_finished.connect(func(_id: int, _pos: int, _t: float) -> void: finishes[0] += 1)
	_place_before_finish(main, main.trike, 20)
	await _wait(0.2)
	var t := 0.0
	while not main.is_race_finished() and t < 8.0:
		main.trike.input.throttle = 1.0
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	var result := main.get_finish_tracker().get_result(RaceSession.LOCAL_PLAYER_ID)
	_check(main.is_race_finished() and result.get("position") == 1, "riding across the line finishes 1st",
			"(time %.2f s)" % result.get("time", -1.0))
	_check(absf(float(result.get("time", -1.0)) - main.get_race_time()) < 0.001, "finish time is recorded and the clock stops")
	# Keep driving, and fake extra crossings: still exactly one finish.
	await _hold(main.trike, 1.0, 1.0)
	main.get_finish_tracker().on_body_crossed(main.trike, main.get_race_time() + 5.0)
	await _wait(0.2)
	_check(finishes[0] == 1 and main.get_finish_tracker().get_finished_count() == 1,
			"finish registers exactly once", "(%d events)" % finishes[0])
	main.queue_free()
	await get_tree().process_frame


func _test_finish_after_ejection() -> void:
	print("\n[Finish: thrown off just before the line]")
	var main := _load_main()
	var trike := main.trike
	var rider := main.rider
	rider.input_source = null
	await _wait(0.5)
	await _start_race(main)
	var tracker := main.get_finish_tracker()
	var finishes := [0]
	tracker.racer_finished.connect(func(_id: int, _pos: int, _t: float) -> void: finishes[0] += 1)
	_place_before_finish(main, trike, 12)
	await _hold(trike, 1.3, 1.0)
	_check(not main.is_race_finished(), "not finished yet before the line (setup)")
	rider.eject()
	_check(not rider.is_riding(), "rider ejected before the finish line")
	var t := 0.0
	while not tracker.is_pending(RaceSession.LOCAL_PLAYER_ID) and t < 6.0:
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	_check(tracker.is_pending(RaceSession.LOCAL_PLAYER_ID) and not main.is_race_finished(),
			"empty trike crossing the line records a PENDING finish (not a finish)")
	await _wait_for_state(rider, RiderController.State.ON_FOOT, 4.0)
	await _wait(1.0)
	_check(not main.is_race_finished(), "still not finished while on foot past the line")
	var side := trike.global_basis.x
	side.y = 0.0
	var spot := trike.global_position + side.normalized() * 1.4
	rider.on_foot.activate(Vector3(spot.x, trike.global_position.y - 0.5, spot.z), -side)
	await _wait(0.2)
	rider.input.interact_pressed = true
	await _wait_for_state(rider, RiderController.State.RIDING, 2.0)
	await _wait(0.2)
	var result := tracker.get_result(RaceSession.LOCAL_PLAYER_ID)
	_check(main.is_race_finished() and result.get("position") == 1, "remounting beyond the line confirms the finish",
			"(crossed %.2f s, confirmed %.2f s)" % [result.get("crossed_time", -1.0), result.get("time", -1.0)])
	_check(float(result.get("time", 0.0)) >= float(result.get("crossed_time", 1e9)), "official time is the confirmation time")
	await _hold(trike, 1.0, 1.0)
	_check(finishes[0] == 1 and not tracker.is_pending(RaceSession.LOCAL_PLAYER_ID), "pending finish confirmed exactly once",
			"(%d events)" % finishes[0])
	main.queue_free()
	await get_tree().process_frame


## A second registered player: their vehicle finishes only for them.
func _test_finish_other_player() -> void:
	print("\n[Finish: player-specific]")
	var main := _load_main()
	main.rider.input_source = null
	await _wait(0.5)
	await _start_race(main)
	var tracker := main.get_finish_tracker()
	var trike2: Trike = TRIKE_SCENE.instantiate()
	main.add_child(trike2)
	trike2.input_source = null
	var rider2: RiderController = RIDER_SCENE.instantiate()
	main.add_child(rider2)
	rider2.input_source = null
	rider2.attach_to(trike2)
	var start2 := _place_before_finish(main, trike2, 15)
	var progress2 := VehicleProgress.new(main.track, start2)
	tracker.register_racer(2, trike2, rider2, progress2)
	_check(tracker.get_owner_id(trike2) == 2 and tracker.get_owner_id(main.trike) == RaceSession.LOCAL_PLAYER_ID,
			"each vehicle resolves to its own player")
	await _wait(0.2)
	await _hold(trike2, 3.0, 1.0)
	_check(tracker.has_finished(2) and tracker.get_result(2).get("position") == 1, "player 2 finishes 1st with their own trike")
	_check(not tracker.has_finished(RaceSession.LOCAL_PLAYER_ID) and not main.is_race_finished(),
			"player 2's vehicle does not finish player 1")
	tracker.on_body_crossed(main.rider.ragdoll, main.get_race_time())
	_check(tracker.get_finished_count() == 1, "an unregistered body crossing the line is ignored")
	_place_before_finish(main, main.trike, 15)
	await _wait(0.2)
	await _hold(main.trike, 3.0, 1.0)
	_check(tracker.get_result(RaceSession.LOCAL_PLAYER_ID).get("position") == 2 and main.is_race_finished(),
			"player 1 then finishes 2nd")
	main.queue_free()
	await get_tree().process_frame


func _test_full_track_run() -> void:
	print("\n[Full downhill run with autopilot]")
	var main := _load_main()
	var trike: Trike = main.get_node("Trike")
	var track: Track = main.get_node("TestTrack")
	var respawns := [0]
	trike.respawned.connect(func() -> void: respawns[0] += 1)
	await _wait(1.0)
	respawns[0] = 0
	var pilot := TrackAutopilot.new(track, trike)
	var max_speed := 0.0
	var airtime := 0.0
	var ticks := 0
	while not main.is_race_finished() and ticks < _ticks(240.0):
		pilot.drive()
		await get_tree().physics_frame
		ticks += 1
		max_speed = maxf(max_speed, trike.linear_velocity.length())
		if trike.grounded_wheel_count == 0:
			airtime += 1.0 / Engine.physics_ticks_per_second
	var progress: VehicleProgress = main.get_progress()
	_check(main.is_race_finished(), "autopilot reaches the finish line",
			"(%.1f s race time, %.0f m)" % [main.get_race_time(), progress.get_distance()])
	_check(respawns[0] <= 3, "run needs few respawns", "(%d respawns)" % respawns[0])
	_check(main.rider.eject_count == 0, "a clean race run (ramps, crates, cones, corners) never ejects the rider",
			"(%d ejections)" % main.rider.eject_count)
	print("        info: top speed %.0f km/h, airtime %.1f s" % [max_speed * 3.6, airtime])
	main.queue_free()
	await get_tree().process_frame
