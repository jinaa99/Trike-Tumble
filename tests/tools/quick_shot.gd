extends Node
## Quick look-dev screenshots of one map (Visual Overhaul V2). Needs a window.
##   Godot --path . --fixed-fps 60 --always-on-top --resolution 1280x720 \
##     --scene res://tests/tools/quick_shot.tscn -- <out_dir> <test|forest|canyon|snow> [ai=N] <shot>...
## Shots:
##   chase:<name>:<distance>:<seconds>           player view after driving
##   cam:<name>:<distance>:<ex,ey,ez>:<lx,ly,lz>[:fov]   fixed camera in the road frame
##   over:<name>                                  aerial overview (fog off)

const SCENES := {
	"test": "res://scenes/main/main.tscn",
	"forest": "res://scenes/main/forest_rush.tscn",
	"canyon": "res://scenes/main/rocky_canyon.tscn",
	"snow": "res://scenes/main/snow_slide.tscn",
}

var _out := "user://shots"


func _ready() -> void:
	GameSettings.use_test_profile("user://capture_settings.cfg")
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	var ai := 0
	var shots: Array[String] = []
	for i in range(2, args.size()):
		if args[i].begins_with("ai="):
			ai = int(args[i].substr(3))
		else:
			shots.append(args[i])
	var main: RaceSession = (load(SCENES[args[1]]) as PackedScene).instantiate()
	main.ai_racer_count = ai
	main.ai_difficulty = 3
	main.skip_countdown = true
	main.auto_start = true
	add_child(main)
	main.trike.input_source = null
	await _frames(20)
	for shot in shots:
		var p := shot.split(":")
		match p[0]:
			"chase":
				await _chase(main, p[1], float(p[2]), float(p[3]))
			"cam":
				await _cam(main, p[1], float(p[2]), _v(p[3]), _v(p[4]), float(p[5]) if p.size() > 5 else 60.0)
			"over":
				await _over(main, p[1])
	get_tree().quit()


func _v(text: String) -> Vector3:
	var c := text.split(",")
	return Vector3(float(c[0]), float(c[1]), float(c[2]))


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, file_name])
	print("saved ", file_name)


func _chase(main: RaceSession, file_name: String, distance: float, seconds: float) -> void:
	var track := main.track
	var index := track.path.index_at_distance(distance)
	main.hud.visible = true
	main.trike.teleport(track.path.get_frame(index).translated_local(Vector3(0.0, 0.8, 0.0)))
	main.get_progress().reset(index)
	main.follow_camera.target = main.trike
	main.follow_camera.snap_to_target()
	var pilot := TrackAutopilot.new(track, main.trike)
	for i in roundi(seconds * Engine.physics_ticks_per_second):
		pilot.drive()
		await get_tree().physics_frame
	await _frames(2)
	await _save(file_name)


func _cam(main: RaceSession, file_name: String, distance: float, eye: Vector3, look: Vector3, fov: float) -> void:
	var camera := main.follow_camera
	camera.target = null
	main.hud.visible = false
	var frame := main.track.path.get_frame(main.track.path.index_at_distance(distance))
	camera.global_position = frame * eye
	camera.look_at(frame * look, Vector3.UP)
	camera.fov = fov
	await _frames(6)
	await _save(file_name)


func _over(main: RaceSession, file_name: String) -> void:
	var camera := main.follow_camera
	camera.target = null
	camera.far = 6000.0
	main.hud.visible = false
	var environment: Environment = (main.get_node("WorldEnvironment") as WorldEnvironment).environment
	var fog := environment.fog_enabled
	environment.fog_enabled = false
	var track := main.track
	var bounds := AABB(track.path.points[0], Vector3.ZERO)
	for point in track.path.points:
		bounds = bounds.expand(point)
	var center := bounds.get_center()
	camera.global_position = center + Vector3(-1500.0, 1700.0, 900.0)
	camera.look_at(center + Vector3(150, -150, 0), Vector3.UP)
	camera.fov = 60.0
	await _frames(6)
	await _save(file_name)
	environment.fog_enabled = fog
