extends RefCounted
## Visual Overhaul V2 tests: texture sets and shared materials, sculpted
## scenery, trike and rider detail (added without touching the rig, the
## wheel mounts or the collision), the layered engine audio, recorded sound
## files, music, fonts and quality tiers.
## Run as part of tests/test_runner.gd (`-- --only=overhaul`).

const MAIN_SCENE := preload("res://scenes/main/main.tscn")
const TRIKE_SCENE := preload("res://scenes/vehicles/trike.tscn")

var runner: Node


func _init(test_runner: Node) -> void:
	runner = test_runner


func run() -> void:
	print("\n[Visual Overhaul V2]")
	_test_materials()
	_test_scenery_models()
	_test_sound_files()
	await _test_trike_and_rider_detail()
	await _test_engine_layers()
	await _test_music()
	_test_fonts()


func _check(condition: bool, test_name: String, detail := "") -> void:
	runner._check(condition, test_name, detail)


func _load() -> RaceSession:
	await runner._new_arena()
	var main: RaceSession = MAIN_SCENE.instantiate()
	main.skip_countdown = true
	main.auto_start = true
	runner._arena.add_child(main)
	main.trike.input_source = null
	main.rider.input_source = null
	return main


func _test_materials() -> void:
	var missing: Array[String] = []
	for set_name: String in ["terrain/dirt", "terrain/grass", "terrain/mud", "stone/rock_face",
			"stone/sandstone", "stone/boulder", "snow/snow_packed", "wood/planks", "wood/bark"]:
		for map: String in ["albedo", "normal", "rough"]:
			if MaterialLibrary.texture(set_name, map) == null:
				missing.append("%s_%s" % [set_name, map])
	_check(missing.is_empty(), "every PBR texture set loads (albedo, normal, roughness)", str(missing))
	var styles := [TrackTheme.SceneryStyle.FOREST, TrackTheme.SceneryStyle.CANYON, TrackTheme.SceneryStyle.SNOW]
	var distinct := {}
	for style: int in styles:
		var road := TrackMaterials.road(style) as ShaderMaterial
		var slope := TrackMaterials.grass(style) as ShaderMaterial
		_check(road != null and slope != null and road.get_shader_parameter(&"ground_normal") != null
				and slope.get_shader_parameter(&"steep_albedo") != null, "map style %d has textured road and slope materials" % style)
		distinct[road] = true
		_check(TrackMaterials.road(style) == road, "road material of style %d is shared (built once)" % style)
	_check(distinct.size() == 3, "each map has its own road material")
	var snow := TrackMaterials.road(TrackTheme.SceneryStyle.SNOW) as ShaderMaterial
	_check(float(snow.get_shader_parameter(&"sparkle")) > 0.0 and float(snow.get_shader_parameter(&"puddle_amount")) == 0.0,
			"snow road sparkles and has no puddles")
	# Snow must never be painted pure white (art bible: albedo at most 0.86).
	var theme := load("res://resources/maps/themes/snow_slide_theme.tres") as TrackTheme
	var brightest := 0.0
	for color: Color in [theme.dirt_color, theme.snow_color, theme.terrain_low_color, theme.grass_colors[0], theme.verge_color]:
		brightest = maxf(brightest, maxf(color.r, color.g))
	_check(brightest <= 0.9 and theme.exposure < 1.0, "Snow Slide: snow paint stays below white and exposure is reduced",
			"(brightest %.2f, exposure %.2f)" % [brightest, theme.exposure])


func _test_scenery_models() -> void:
	var counts := {}
	for v in 3:
		var pine := SceneryKit.pine(v)
		counts["pine%d" % v] = (pine["foliage"] as ArrayMesh).surface_get_array_len(0)
		_check(pine["foliage"] != null and pine["trunk"] != null and pine["snow"] != null, "pine variant %d: foliage, trunk and snow load" % v)
	_check(counts["pine0"] != counts["pine2"], "pine variants are different models", str(counts))
	var leaf := SceneryKit.broadleaf(0)
	var aabb := (leaf["foliage"] as ArrayMesh).get_aabb()
	_check(aabb.size.y > 2.0 and aabb.size.x > 2.0, "broadleaf tree has a full canopy", "(%.1f x %.1f m)" % [aabb.size.x, aabb.size.y])
	var farthest := 0.0
	for vertex: Vector3 in SceneryKit.rock(0).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		farthest = maxf(farthest, vertex.length())
	_check(farthest < 1.15, "boulder model stays inside its unit-sphere collider frame", "(farthest vertex %.2f)" % farthest)
	for mesh: ArrayMesh in [SceneryKit.hoodoo(0), SceneryKit.cactus(0), SceneryKit.stump(), SceneryKit.fern(), SceneryKit.rock_arch(0),
			SceneryKit.mountain(0, Color.GRAY, Color.WHITE, 0.6), SceneryKit.mountain(1, Color.GRAY, Color.WHITE, 1.0, true)]:
		_check(mesh != null and mesh.surface_get_array_len(0) > 30, "sculpted scenery model builds", "(%d vertices)" % mesh.surface_get_array_len(0))
	# Sculpt winding: a blob's normals must point outward.
	var sculpt := Sculpt.new(5)
	sculpt.blob(Vector3.ZERO, Vector3.ONE, 1, 0.1, 1.0, Color.WHITE, Color.GRAY)
	var arrays := sculpt.commit(true).surface_get_arrays(0)
	var outward := 0
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in vertices.size():
		if vertices[i].dot(normals[i]) > 0.0:
			outward += 1
	_check(outward == vertices.size(), "sculpted meshes have outward normals", "(%d of %d)" % [outward, vertices.size()])


func _test_sound_files() -> void:
	var missing: Array[String] = []
	var takes := 0
	for sound: StringName in SoundBank.FILES:
		for file: String in SoundBank.FILES[sound]:
			takes += 1
			if not ResourceLoader.exists("%s%s.wav" % [SoundBank.AUDIO, file]):
				missing.append(file)
	_check(missing.is_empty(), "every recorded sound file exists", "(%d takes) %s" % [takes, str(missing)])
	var loop := SoundBank.get_loop(&"engine_idle")
	_check(loop.loop_mode == AudioStreamWAV.LOOP_FORWARD and loop.loop_end > 44100, "engine layers are seamless loops",
			"(%.1f s)" % loop.get_length())
	_check(SoundBank.get_stream(&"engine_idle").loop_mode == AudioStreamWAV.LOOP_DISABLED, "one-shot use of a recording never loops")
	var seen := {}
	for i in 40:
		seen[SoundBank.use(&"step")] = true
	_check(seen.size() >= 3, "footsteps rotate through several recorded takes", "(%d takes heard)" % seen.size())
	_check(SoundBank.get_stream(&"ui_click") != null and not SoundBank.FILES.has(&"ui_click"), "UI clicks stay synthesized")


func _test_trike_and_rider_detail() -> void:
	var main := await _load()
	var trike := main.trike
	var visuals := trike.get_node("Visuals") as TrikeVisuals
	await runner._wait(0.3)
	var added: Array[String] = []
	for path: String in ["DetailChrome", "DetailEngine", "DetailBody", "FrontPivot/FrontWheel/Spin/Tread",
			"FrontPivot/FrontWheel/Spin/BrakeDisc", "FrontPivot/FrontWheel/Caliper", "Handlebar/BarPad",
			"RearWheelLeft/Spin/LugNuts", "RearWheelRight/Spin/Grooves"]:
		if visuals.get_node_or_null(path) is MeshInstance3D:
			added.append(path)
	_check(added.size() == 9, "trike detail parts are added (tread, brake, engine, exhausts, bolts...)", "(%d of 9)" % added.size())
	# Detail never moves the wheels or adds collision.
	var front := visuals.get_node("FrontPivot/FrontWheel") as Node3D
	var mount := trike.get_wheel_mount(Trike.Wheel.FRONT)
	var expected := trike.to_global(mount + Vector3(0, -trike.wheel_suspension_length[Trike.Wheel.FRONT], 0))
	_check(front.global_position.distance_to(expected) < 0.02, "front wheel visual still sits on the physics wheel",
			"(%.3f m off)" % front.global_position.distance_to(expected))
	var shapes := 0
	for node in trike.find_children("*", "CollisionShape3D", true, false):
		shapes += 1
	_check(shapes == 2, "the trike still has exactly its two collision shapes", "(%d)" % shapes)
	var body := visuals.get_node("DetailBody") as MeshInstance3D
	var tank := visuals.get_node("Tank") as MeshInstance3D
	visuals.body_color = Color(0.1, 0.9, 0.3)
	_check(body.material_override == tank.material_override
			and (body.material_override as StandardMaterial3D).albedo_color.is_equal_approx(Color(0.1, 0.9, 0.3)),
			"new body panels take the racer's body colour")
	var chrome := (visuals.get_node("Axle") as MeshInstance3D).material_override as StandardMaterial3D
	var tire := (visuals.get_node("FrontPivot/FrontWheel/Spin/Tire") as MeshInstance3D).material_override as StandardMaterial3D
	var frame := (visuals.get_node("DownTube") as MeshInstance3D).material_override as StandardMaterial3D
	_check(chrome.metallic > 0.9 and chrome.roughness < 0.2 and tire.roughness > 0.85 and tire.metallic < 0.1
			and frame.roughness > 0.4 and frame.metallic > 0.2, "chrome, rubber and powder-coat are distinct materials",
			"(chrome %.2f/%.2f, tyre %.2f, frame %.2f)" % [chrome.metallic, chrome.roughness, tire.roughness, frame.roughness])
	# Rider.
	var model := visuals.get_node("Rider") as Rider
	var head := model.get_node(RiderDetail.HEAD) as Node3D
	_check(head.get_node_or_null("EyeL/IrisL") is MeshInstance3D and head.get_node_or_null("EyeR/IrisR") is MeshInstance3D
			and head.get_node_or_null("EyeShineL/GlintL") != null, "eyes have irises and a second highlight")
	_check(model.get_node_or_null("ShinL/Kit_KneePad") != null and model.get_node_or_null("FootR/Kit_ToeCap") != null
			and head.get_node_or_null("Kit_HelmetStripe") != null, "outfit kit parts are added (pads, toe caps, helmet stripe)")
	var pip := load("res://resources/characters/looks/pip.tres") as RiderLook
	var zip := load("res://resources/characters/looks/zip.tres") as RiderLook
	RiderStyle.apply(model, pip)
	var pip_iris := (head.get_node("EyeL/IrisL") as MeshInstance3D).material_override as StandardMaterial3D
	var pip_stripe := (head.get_node("Kit_HelmetStripe") as Node3D).visible
	RiderStyle.apply(model, zip)
	var zip_iris := (head.get_node("EyeL/IrisL") as MeshInstance3D).material_override as StandardMaterial3D
	_check(not pip_iris.albedo_color.is_equal_approx(zip_iris.albedo_color) and pip_stripe != (head.get_node("Kit_HelmetStripe") as Node3D).visible,
			"looks differ in eye colour and kit, not only paint")
	await runner._wait(0.2)
	_check(model.get_max_ik_error() < 0.03, "hands and feet still reach the grips and pegs with the detail on",
			"(%.3f m)" % model.get_max_ik_error())


func _test_engine_layers() -> void:
	var main := await _load()
	var trike := main.trike
	var audio := (trike.get_node("Visuals") as TrikeVisuals).audio
	await runner._wait(0.8)
	_check(audio.layers.size() == 4 and audio.overrun != null and audio.wind != null and audio.rattle != null,
			"engine has four RPM layers plus overrun, rattle and wind")
	var all_playing := true
	for player in audio.layers:
		all_playing = all_playing and player.playing and player.stream is AudioStreamWAV
	_check(all_playing, "every engine layer runs (silent ones at -80 dB)")
	var idle_revs := audio.revs
	_check(audio.layers[0].volume_db > audio.layers[3].volume_db + 30.0, "at idle the idle layer is heard and the high layer is silent",
			"(idle %.0f dB, high %.0f dB)" % [audio.layers[0].volume_db, audio.layers[3].volume_db])
	# Flat out down the track.
	var pilot := TrackAutopilot.new(main.track, trike)
	var peak := 0.0
	var jump := 0.0
	var previous := -80.0
	for i in 60 * 7:
		pilot.drive()
		await runner.get_tree().physics_frame
		if i % 6 == 0:
			var loudest := -80.0
			for player in audio.layers:
				loudest = maxf(loudest, player.volume_db)
			if i > 30:
				jump = maxf(jump, absf(loudest - previous))
			previous = loudest
		peak = maxf(peak, audio.revs)
	_check(peak > idle_revs + 0.5, "revs climb with speed and throttle", "(%.2f → %.2f)" % [idle_revs, peak])
	_check(audio.layers[3].volume_db > audio.layers[0].volume_db + 30.0, "at speed the high layer has taken over from idle",
			"(idle %.0f dB, high %.0f dB)" % [audio.layers[0].volume_db, audio.layers[3].volume_db])
	_check(jump < 4.0, "layers crossfade without volume jumps", "(largest step %.1f dB per 0.1 s)" % jump)
	var pitches_ok := true
	for i in audio.layers.size():
		var layer: Array = TrikeAudio.LAYERS[i]
		pitches_ok = pitches_ok and audio.layers[i].pitch_scale >= float(layer[2]) - 0.001 and audio.layers[i].pitch_scale <= float(layer[3]) + 0.001
	_check(pitches_ok, "each layer stays inside its own pitch band (no single sample pitched across the range)")
	_check(audio.rolls.has(TrackSurface.Kind.ROAD) and (audio.rolls[TrackSurface.Kind.ROAD] as AudioStreamPlayer3D).volume_db > -30.0,
			"the gravel rolling loop plays while driving on dirt")
	# Lift off at speed: the overrun burble comes in.
	for i in 60:
		trike.input.throttle = 0.0
		trike.input.steer = 0.0
		await runner.get_tree().physics_frame
	_check(audio.overrun.volume_db > -30.0, "lifting off at speed brings in the overrun layer", "(%.0f dB)" % audio.overrun.volume_db)
	_check(TrikeAudio._band_gain(0.2, 0.1, 0.3, 0.4, 0.6) > 0.49 and TrikeAudio._band_gain(0.7, 0.1, 0.3, 0.4, 0.6) == 0.0,
			"layer bands fade in and out")


func _test_music() -> void:
	MusicPlayer.duck(false)
	MusicPlayer.play(&"menu")
	await runner._wait(0.3)
	_check(MusicPlayer.current == &"menu" and MusicPlayer._players[MusicPlayer._active].playing, "menu music plays")
	var menu_deck := MusicPlayer._active
	MusicPlayer.play(&"race")
	await runner._wait(0.2)
	_check(MusicPlayer.current == &"race" and MusicPlayer._active != menu_deck and MusicPlayer._players[menu_deck].playing
			and MusicPlayer._players[MusicPlayer._active].playing, "switching to race music crossfades (both decks sound during the fade)")
	await runner._wait(1.6)
	_check(not MusicPlayer._players[menu_deck].playing, "the old track stops when the fade ends")
	var stream := MusicPlayer._players[MusicPlayer._active].stream as AudioStreamOggVorbis
	_check(stream != null and stream.loop, "music tracks loop")
	_check(MusicPlayer._players[0].bus == &"Music" and MusicPlayer.target_db() < -8.0, "music is on the Music bus, mixed under the effects",
			"(%.0f dB)" % MusicPlayer.target_db())
	var loud := MusicPlayer.target_db()
	MusicPlayer.duck(true)
	_check(MusicPlayer.target_db() < loud - 3.0, "music ducks under the results screen")
	MusicPlayer.duck(false)
	MusicPlayer.stop()
	var master := AudioServer.get_bus_index("Master")
	_check(AudioServer.get_bus_effect_count(master) >= 1 and AudioServer.get_bus_effect(master, 0) is AudioEffectHardLimiter,
			"the Master bus has a limiter (no clipping)")


func _test_fonts() -> void:
	var display := UiKit.DISPLAY_FONT as FontVariation
	var body := UiKit.BODY_FONT as FontVariation
	_check(display != null and display.base_font is FontFile and body != null and body.base_font is FontFile,
			"UI uses the bundled OFL fonts (no system fonts)")
	_check(UiKit.THEME.default_font == body, "the theme's default font is the bundled body face")
	_check(FileAccess.file_exists("res://assets/fonts/lilita_one/OFL.txt") and FileAccess.file_exists("res://assets/fonts/nunito/OFL.txt"),
			"each font ships with its OFL license file")
