extends Node
## Renders the real game and saves inspection screenshots.
## Needs a visible window (not --headless). Usage:
##   Godot --path . --fixed-fps 60 --always-on-top --resolution 1280x720 \
##     --scene res://tests/visual_capture.tscn -- <output_dir> [modes...]
## Modes (default: all): closeup overview drive pause perf
## "perf" must run WITHOUT --fixed-fps to measure real frame rate.

const MAIN_SCENE := preload("res://scenes/main/main.tscn")
const DRIVE_SHOTS: Array[float] = [0.5, 4.0, 9.0, 12.6, 14.4, 20.0, 27.0, 34.0]
const ALL_MODES: Array[String] = ["closeup", "overview", "drive", "pause"]

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
