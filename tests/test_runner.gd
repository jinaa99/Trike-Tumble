extends Node
## Automated gameplay tests. Drives real scenes with simulated input and
## checks physics outcomes. Run (see docs/TESTING.md):
##   Godot --headless --path . --fixed-fps 60 --scene res://tests/test_runner.tscn
## Exit code 0 = all passed.

const MAIN_SCENE := preload("res://scenes/main/main.tscn")
const TRIKE_SCENE := preload("res://scenes/vehicles/trike.tscn")
const CRATE_SCENE := preload("res://scenes/props/crate.tscn")
const REQUIRED_ACTIONS: Array[StringName] = [
	&"accelerate", &"brake", &"steer_left", &"steer_right", &"drift", &"reset", &"pause",
]

var _passed := 0
var _failed := 0
var _arena: Node3D


func _ready() -> void:
	_run_all.call_deferred()


func _run_all() -> void:
	print("\n=== TRIKE TUMBLE TESTS ===")
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
	await _test_scenery_clear_of_road()
	await _test_full_track_run()
	print("\n=== RESULT: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


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
	var shapes: Array[Node] = []
	shapes.append_array(track.get_node("Decor/SceneryCollision").get_children())
	shapes.append_array(track.get_node("Landmarks/LandmarkCollision").get_children())
	var intrusions := 0
	for node in shapes:
		var collider := node as CollisionShape3D
		var p := collider.global_position
		var i := track.path.find_nearest(p)
		var offset := p - track.path.points[i]
		var lateral := absf(offset.dot(track.path.rights[i]))
		var vertical := offset.dot(track.path.ups[i])
		if lateral < track.road_width * 0.5 + 0.3 and vertical > -3.0 and vertical < 6.0:
			intrusions += 1
	_check(shapes.size() > 100, "scenery has collision", "(%d colliders)" % shapes.size())
	_check(intrusions == 0, "no scenery collider inside the road corridor", "(%d intrusions)" % intrusions)
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
	print("        info: top speed %.0f km/h, airtime %.1f s" % [max_speed * 3.6, airtime])
	main.queue_free()
	await get_tree().process_frame
