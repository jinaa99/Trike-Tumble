extends Node
## Renders the real game and saves inspection screenshots.
## Needs a visible window (not --headless). Usage:
##   Godot --path . --fixed-fps 60 --always-on-top --resolution 1280x720 \
##     --scene res://tests/visual_capture.tscn -- <output_dir> [modes...]
## Modes (default: all): closeup overview drive pause eject perf
## "perf" must run WITHOUT --fixed-fps to measure real frame rate.

const MAIN_SCENE := preload("res://scenes/main/main.tscn")
const DRIVE_SHOTS: Array[float] = [0.5, 4.0, 9.0, 12.6, 14.4, 20.0, 27.0, 34.0]
const ALL_MODES: Array[String] = ["closeup", "overview", "drive", "pause", "eject"]

var _out_dir := "user://captures"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var modes: Array[String] = []
	for i in range(1, args.size()):
		modes.append(args[i])
	if modes.is_empty():
		modes = ALL_MODES.duplicate()
	_run.call_deferred(modes)


func _run(modes: Array[String]) -> void:
	for mode in modes:
		match mode:
			"closeup":
				await _capture_closeups()
			"overview":
				await _capture_overview()
			"drive":
				await _capture_drive()
			"pause":
				await _capture_pause()
			"eject":
				await _capture_eject()
			"perf":
				await _measure_performance()
	get_tree().quit()


# --- Helpers ----------------------------------------------------------------

func _load_main() -> RaceSession:
	var main: RaceSession = MAIN_SCENE.instantiate()
	add_child(main)
	(main.get_node("Trike") as Trike).input_source = null
	return main


func _unload(main: Node) -> void:
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [_out_dir, file_name]
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


## Free camera that ignores the trike (FollowCamera with no target).
func _free_camera(main: RaceSession) -> FollowCamera:
	var camera := main.follow_camera
	camera.target = null
	return camera


# --- Modes ------------------------------------------------------------------

func _capture_closeups() -> void:
	var main := _load_main()
	var trike := main.trike
	main.hud.visible = false
	var camera := _free_camera(main)
	# Settle, then hold a right turn (front wheel + bars turn, rider leans).
	for i in 90:
		trike.input.steer = 0.7
		await get_tree().physics_frame
	var xf := trike.global_transform
	var focus := xf * Vector3(0.0, 0.35, -0.1)
	var views := {
		"closeup_trike_front34": [Vector3(2.4, 1.1, -2.6), 42.0],
		"closeup_trike_side": [Vector3(-3.6, 0.7, -0.15), 40.0],
		"closeup_trike_rear34": [Vector3(-2.5, 1.5, 2.6), 42.0],
		"closeup_trike_top": [Vector3(0.6, 3.6, 0.9), 45.0],
	}
	for view_name: String in views:
		var view: Array = views[view_name]
		camera.global_position = xf * (view[0] as Vector3)
		camera.look_at(focus, Vector3.UP)
		camera.fov = view[1]
		await _frames(3)
		await _save(view_name)
	# Rider portrait and hands-on-grips detail.
	var head: Node3D = trike.get_node("Visuals/Rider/Hips/Spine/Chest/Neck/Head")
	camera.global_position = head.global_position + xf.basis * Vector3(0.35, 0.05, -1.25)
	camera.look_at(head.global_position + Vector3(0, -0.12, 0), Vector3.UP)
	camera.fov = 38.0
	await _frames(3)
	await _save("closeup_rider_face")
	var grip: Node3D = trike.get_node("Visuals/Handlebar")
	camera.global_position = grip.global_position + xf.basis * Vector3(0.9, 0.55, -0.9)
	camera.look_at(grip.global_position + xf.basis * Vector3(0, 0.05, 0.25), Vector3.UP)
	camera.fov = 45.0
	await _frames(3)
	await _save("closeup_rider_hands")
	await _unload(main)


func _capture_overview() -> void:
	var main := _load_main()
	main.hud.visible = false
	var camera := _free_camera(main)
	camera.far = 4000.0
	var points := main.track.path.points
	var bounds := AABB(points[0], Vector3.ZERO)
	for p in points:
		bounds = bounds.expand(p)
	var center := bounds.get_center()
	# Map-style aerial shot: thin the fog for this view only (it is tuned for
	# the chase camera, not for looking across a kilometre of track).
	var environment: Environment = (main.get_node("WorldEnvironment") as WorldEnvironment).environment
	var fog := environment.fog_density
	environment.fog_density = fog * 0.25
	camera.global_position = center + Vector3(-380.0, 330.0, 330.0)
	camera.look_at(center + Vector3(0, -30, 0), Vector3.UP)
	camera.fov = 55.0
	await _frames(5)
	await _save("overview_track")
	environment.fog_density = fog
	# Start area from above and behind.
	var start := main.track.get_start_transform(0)
	camera.global_position = start * Vector3(9.0, 14.0, 22.0)
	camera.look_at(start * Vector3(0.0, 0.0, -30.0), Vector3.UP)
	camera.fov = 60.0
	await _frames(3)
	await _save("overview_start")
	# A mid-track section with props.
	var frame := main.track.path.get_frame(main.track.path.index_at_distance(420.0))
	camera.global_position = frame * Vector3(-14.0, 11.0, 26.0)
	camera.look_at(frame * Vector3(0.0, 0.0, -25.0), Vector3.UP)
	await _frames(3)
	await _save("overview_section")
	# A corner with its chevron sign, seen from the rider's approach.
	var signs := main.track.get_node("Landmarks/TurnSignsRight") as MultiMeshInstance3D
	if signs.multimesh.instance_count > 0:
		var sign_xf := signs.multimesh.get_instance_transform(0)
		var near := main.track.path.find_nearest(sign_xf.origin)
		var approach := main.track.path.get_frame(maxi(near - 14, 0))
		camera.global_position = approach * Vector3(0.0, 2.0, 0.0)
		camera.look_at(sign_xf * Vector3(0.0, 2.0, 0.0), Vector3.UP)
		camera.fov = 55.0
		await _frames(3)
		await _save("overview_corner_sign")
	await _unload(main)


func _capture_drive() -> void:
	var main := _load_main()
	var trike := main.trike
	var pilot := TrackAutopilot.new(main.track, trike)
	var elapsed := 0.0
	var shot := 0
	while shot < DRIVE_SHOTS.size():
		await get_tree().physics_frame
		elapsed += 1.0 / Engine.physics_ticks_per_second
		if elapsed > 1.0:
			pilot.drive()
			# Force a short drift around 12-14 s to show the drift and boost effects.
			if elapsed > 12.0 and elapsed < 14.0:
				trike.input.drift = true
				trike.input.steer = -1.0 if trike.input.steer < 0.0 else 1.0
		if elapsed >= DRIVE_SHOTS[shot]:
			await _save("drive_%02d" % shot)
			print("  t=%.1f speed=%d km/h drifting=%s boost=%.2f" % [elapsed,
					roundi(trike.linear_velocity.length() * 3.6), trike.is_drifting, trike.boost_time])
			shot += 1
	await _unload(main)


func _capture_pause() -> void:
	var main := _load_main()
	await _frames(30)
	main.pause_menu.set_paused(true)
	await _frames(5)
	await _save("pause_menu")
	main.pause_menu.set_paused(false)
	await _unload(main)


## Wipeout sequence: thrown off at speed, tumble, get up, run back, get on.
## Ejection is triggered via RiderController.eject() so the shots are
## repeatable; real crash ejection is covered by the automated tests.
func _capture_eject() -> void:
	var main := _load_main()
	var trike := main.trike
	var rider := main.rider
	rider.input_source = null
	var pilot := TrackAutopilot.new(main.track, trike)
	for i in 60 * 5:
		pilot.drive()
		await get_tree().physics_frame
	trike.input.clear()
	rider.eject(14.0)
	var shots := {0.12: "eject_00_thrown", 0.45: "eject_01_flying", 0.9: "eject_02_tumble"}
	var t := 0.0
	while rider.state != RiderController.State.GETTING_UP and t < 3.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		for at: float in shots.keys():
			if absf(t - at) < 0.5 / 60.0:
				await _save(shots[at])
	var getup_shots := {0.15: "eject_03_push_up", 0.55: "eject_04_head_shake", 0.85: "eject_05_confused"}
	while rider.state == RiderController.State.GETTING_UP:
		await get_tree().physics_frame
		for at: float in getup_shots.keys():
			if absf(rider.state_time - at) < 0.5 / 60.0:
				await _save(getup_shots[at])
	# Close-up of the dizzy rider (free camera), then back to the follow camera.
	await _wait_physics(5)
	# Run back toward the trike with camera-relative input.
	var camera := main.follow_camera
	for i in 60 * 6:
		var to_trike := trike.global_position - rider.on_foot.global_position
		to_trike.y = 0.0
		if to_trike.length() < 1.8:
			break
		var fwd := -camera.global_basis.z
		fwd.y = 0.0
		var right := camera.global_basis.x
		right.y = 0.0
		var d := to_trike.normalized()
		rider.input.throttle = maxf(d.dot(fwd.normalized()), 0.0)
		rider.input.brake = maxf(-d.dot(fwd.normalized()), 0.0)
		rider.input.steer = d.dot(right.normalized())
		await get_tree().physics_frame
		if i == 25:
			await _save("eject_06_running")
	rider.input.clear()
	await _wait_physics(20)
	await _save("eject_07_prompt")
	rider.input.interact_pressed = true
	await _wait_physics(22)
	await _save("eject_08_mounting")
	while not rider.is_riding():
		await get_tree().physics_frame
	await _wait_physics(50)
	await _save("eject_09_riding_again")
	# Dizzy close-up from a fresh wipeout.
	trike.input.throttle = 1.0
	await _wait_physics(90)
	trike.input.clear()
	rider.eject(14.0)
	while rider.state != RiderController.State.GETTING_UP:
		await get_tree().physics_frame
	while rider.state_time < 0.6:
		await get_tree().physics_frame
	camera.target = null
	var head := rider.on_foot.global_position + Vector3.UP * 1.6
	var facing := rider.on_foot.facing
	camera.global_position = head + facing * Vector3(0.6, 0.2, -3.0)
	camera.look_at(head + Vector3.UP * 0.1, Vector3.UP)
	camera.fov = 45.0
	await _frames(2)
	await _save("eject_10_dizzy_closeup")
	await _unload(main)
	await _capture_real_crash()


## A real crash on the track: miss the corner at sample 128 and hit the
## outside barrier nearly head-on at full speed (measured impact ~12).
func _capture_real_crash() -> void:
	var main := _load_main()
	var trike := main.trike
	var rider := main.rider
	rider.input_source = null
	var start := 128 - 22
	trike.teleport(main.track.path.get_frame(start).translated_local(Vector3(0, 0.8, 0)))
	main.get_progress().reset(start)
	await _wait_physics(10)
	var t := 0
	while rider.is_riding() and t < 60 * 5:
		trike.input.throttle = 1.0
		await get_tree().physics_frame
		t += 1
	trike.input.clear()
	print("  real crash: state %s after %.1f s, ejections %d" % [rider.get_state_name(), t / 60.0, rider.eject_count])
	await _wait_physics(10)
	await _save("eject_11_real_crash")
	await _wait_physics(30)
	await _save("eject_12_real_crash_tumble")
	await _unload(main)


func _wait_physics(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


## Real-time frame rate while the autopilot drives (run without --fixed-fps).
func _measure_performance() -> void:
	var main := _load_main()
	var pilot := TrackAutopilot.new(main.track, main.trike)
	var frames := 0
	var draw_calls := 0.0
	var primitives := 0.0
	var viewport_rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
	var gpu_ms := 0.0
	var cpu_ms := 0.0
	var start_ms := Time.get_ticks_msec()
	var worst_ms := 0.0
	var last_ms := start_ms
	while Time.get_ticks_msec() - start_ms < 20000:
		pilot.drive()
		await get_tree().process_frame
		var now := Time.get_ticks_msec()
		if now - start_ms > 2000:  # skip warm-up (shader compilation)
			frames += 1
			worst_ms = maxf(worst_ms, now - last_ms)
			draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid)
			cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid)
		last_ms = now
	var seconds := (Time.get_ticks_msec() - start_ms - 2000) / 1000.0
	var n := maxf(frames, 1)
	print("PERF: avg %.1f fps, worst frame %.1f ms, render GPU %.2f ms / CPU %.2f ms, %.0f draw calls, %.0f primitives (%d frames, %.1f s, %s)" % [
		frames / seconds, worst_ms, gpu_ms / n, cpu_ms / n, draw_calls / n, primitives / n, frames, seconds,
		RenderingServer.get_video_adapter_name()])
	await _unload(main)
