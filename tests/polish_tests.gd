extends RefCounted
## Milestone 09 tests: rider looks and faces, celebration, audio triggers,
## effects, camera feedback, effects/audio on network proxies, UI volume.
## Run as part of tests/test_runner.gd (`-- --only=polish`).

const MAIN_SCENE := preload("res://scenes/main/main.tscn")
const TRIKE_SCENE := preload("res://scenes/vehicles/trike.tscn")
const RIDER_SCENE := preload("res://scenes/characters/rider_character.tscn")

var runner: Node


func _init(test_runner: Node) -> void:
	runner = test_runner


func run() -> void:
	await _test_rider_looks()
	await _test_faces_and_celebration()
	await _test_vehicle_audio_and_effects()
	await _test_rider_audio()
	await _test_race_audio()
	await _test_camera_feedback()
	await _test_proxy_effects()
	_test_ui_audio()


# --- Helpers ----------------------------------------------------------------

func _check(condition: bool, test_name: String, detail := "") -> void:
	runner._check(condition, test_name, detail)


func _tree() -> SceneTree:
	return runner.get_tree()


func _wait(seconds: float) -> void:
	await runner._wait(seconds)


func _load(ai := 0, skip := true) -> RaceSession:
	await runner._new_arena()
	var main: RaceSession = MAIN_SCENE.instantiate()
	main.ai_racer_count = ai
	main.skip_countdown = skip
	main.auto_start = false
	runner._arena.add_child(main)
	main.trike.input_source = null
	main.rider.input_source = null
	return main


static func _model(racer: Racer) -> Rider:
	return racer.trike.get_node("Visuals/Rider") as Rider


static func _head_part(model: Rider, part: String) -> Node3D:
	return model.get_node_or_null("Hips/Spine/Chest/Neck/Head/" + part) as Node3D


## A floor tagged with a ground surface (arena tests).
func _surface_floor(kind: TrackSurface.Kind) -> void:
	for child in runner._arena.get_children():
		if child is StaticBody3D:
			TrackSurface.tag(child, kind)


# --- Riders -----------------------------------------------------------------

func _test_rider_looks() -> void:
	print("\n[Polish: five distinct riders]")
	var main := await _load(4)
	await _wait(1.0)
	var racers := main.racers.get_racers()
	var helmets := {}
	var styles := {}
	var jackets := {}
	var materials := {}
	var ik_ok := true
	var worst := 0.0
	for racer in racers:
		var model := _model(racer)
		var helmet := (_head_part(model, "Helmet") as MeshInstance3D).material_override as StandardMaterial3D
		var jacket := (model.get_node("Hips/Spine/Torso") as MeshInstance3D).material_override as StandardMaterial3D
		helmets[helmet.albedo_color.to_html()] = true
		jackets[jacket.albedo_color.to_html()] = true
		materials[helmet.get_instance_id()] = true
		var look := main.racers.rider_looks[racers.find(racer) % main.racers.rider_looks.size()]
		styles[look.helmet_style] = true
		worst = maxf(worst, model.get_max_ik_error())
		ik_ok = ik_ok and model.get_max_ik_error() < 0.03
	_check(racers.size() == 5 and helmets.size() == 5 and jackets.size() == 5 and styles.size() == 5,
			"five racers, five helmet colors, jackets and helmet styles", "(%d / %d / %d)" % [helmets.size(), jackets.size(), styles.size()])
	_check(materials.size() == 5, "every rider has its own materials (recoloring one never repaints another)")
	_check(ik_ok, "every look keeps gloves on the grips and boots on the footrests", "(worst %.3f m)" % worst)
	var looks: Array = []
	for racer in racers:
		var model := _model(racer)
		var parts: Array[String] = []
		for child in _head_part(model, "").get_children() + model.get_node("Hips/Spine/Chest").get_children():
			if child.name.begins_with(RiderStyle.ADDED_PREFIX) or (child.name in ["EarL", "Crest", "Scarf"] and (child as Node3D).visible):
				parts.append(String(child.name).trim_prefix(RiderStyle.ADDED_PREFIX).rstrip("0123456789-"))
		parts.sort()
		looks.append(",".join(parts))
	var unique := {}
	for parts: String in looks:
		unique[parts] = true
	_check(unique.size() == 5, "each rider has its own silhouette (helmet shape + accessory)", "(%s)" % " | ".join(looks))
	var accents := {}
	for racer in racers:
		var hub := racer.trike.get_node("Visuals/RearWheelLeft/Spin/HubCap") as MeshInstance3D
		accents[(hub.material_override as StandardMaterial3D).albedo_color.to_html()] = true
	_check(accents.size() == 5, "each trike has its own accent color (trim, stripes, flag, hubs)")
	# Re-applying a look is safe (no duplicate accessories).
	var model0 := _model(racers[1])
	var before := model0.find_children(RiderStyle.ADDED_PREFIX + "*", "", true, false).size()
	RiderStyle.apply(model0, main.racers.rider_looks[1])
	await _tree().process_frame
	var after := model0.find_children(RiderStyle.ADDED_PREFIX + "*", "", true, false).size()
	_check(before > 0 and before == after, "re-applying a look replaces it (no duplicated parts)", "(%d parts)" % after)


func _test_faces_and_celebration() -> void:
	print("\n[Polish: faces, animations and celebration]")
	var main := await _load(0)
	await _wait(0.5)
	var model := _model(main.get_local_racer())
	var mouth := _head_part(model, "Mouth")
	var rest_mouth := mouth.transform
	var faces := []
	main.rider.eject(14.0, -main.trike.global_basis.z * 14.0)
	await _wait(0.1)
	faces.append(model.expression)
	var shocked_mouth := mouth.transform.basis.get_scale()
	while main.rider.state != RiderController.State.GETTING_UP:
		await _tree().physics_frame
	faces.append(model.expression)
	while main.rider.state != RiderController.State.ON_FOOT:
		await _tree().physics_frame
	faces.append(model.expression)
	_check(faces == [Rider.Face.SHOCKED, Rider.Face.DIZZY, model.base_face], "faces follow the fall: shocked → dizzy → own face",
			"(%s)" % str(faces.map(func(f: int) -> String: return Rider.Face.keys()[f])))
	_check(not shocked_mouth.is_equal_approx(rest_mouth.basis.get_scale()), "the mouth really changes shape")
	main.rider.force_mount()
	await _wait(0.3)
	var gripping := model.get_max_ik_error()
	model.celebrate(1.0)
	await _wait(0.4)
	var hand := (model.get_node("HandR") as Node3D).global_position
	var grip := (main.trike.get_node("Visuals/Handlebar/GripTargetR") as Node3D).global_position
	var raised := hand.y - grip.y
	_check(model.is_celebrating() and model.expression == Rider.Face.CHEER and raised > 0.4,
			"celebration: a hand goes up above the bars and the rider cheers", "(hand %.2f m above the grip)" % raised)
	await _wait(1.0)
	_check(not model.is_celebrating() and model.get_max_ik_error() < 0.03 and gripping < 0.03,
			"after celebrating the hands go back to the grips", "(IK error %.3f m)" % model.get_max_ik_error())
	# The finish line makes a finisher celebrate.
	var racer := main.get_local_racer()
	var finish := main.track.get_finish_index()
	main.trike.teleport(main.track.path.get_frame(finish - 12).translated_local(Vector3(0, 0.8, 0)))
	main.get_progress().reset(finish - 12)
	racer.checkpoints.force_passed_through(finish - 12)
	var t := 0.0
	while not racer.finished and t < 6.0:
		main.trike.input.throttle = 0.6
		await _tree().physics_frame
		t += 1.0 / 60.0
	main.trike.input.clear()
	_check(racer.finished and model.is_celebrating(), "crossing the finish line starts the celebration")
	_check(main.race_audio.confetti_bursts == 1 and SoundBank.count(&"finish") >= 1, "finish fanfare and confetti for the local player")


# --- Audio and effects ---------------------------------------------------------

func _test_vehicle_audio_and_effects() -> void:
	print("\n[Polish: trike sounds and effects]")
	await runner._new_arena()
	var trike: Trike = runner._spawn_trike(Vector3(0, 0.9, 0))
	var visuals := trike.get_node("Visuals") as TrikeVisuals
	await _wait(0.6)
	var idle_pitch := visuals.audio.engine.pitch_scale
	await runner._hold(trike, 2.5, 1.0)
	trike.input.throttle = 1.0
	await _wait(0.2)
	var fast_pitch := visuals.audio.engine.pitch_scale
	_check(visuals.audio.engine.playing and fast_pitch > idle_pitch + 0.4, "engine loop plays and its pitch rises with speed",
			"(%.2f → %.2f)" % [idle_pitch, fast_pitch])
	_check(visuals.effects.sprays[0].emitting and visuals.effects.sprays[1].emitting, "dust sprays from the rear wheels at speed")
	# Drift: skid sound and skid marks.
	var skid_peak := 0.0
	var marks := false
	for k in 70:
		trike.input.throttle = 1.0
		trike.input.drift = true
		trike.input.steer = 1.0
		await _tree().physics_frame
		skid_peak = maxf(skid_peak, visuals.audio.skid_amount)
		marks = marks or visuals.effects.skid_marks[0].emitting
	trike.input.clear()
	_check(skid_peak > 0.6 and marks, "drifting: tyre skid sound and skid marks", "(skid %.2f)" % skid_peak)
	# Ground styles: snow powder and mud splash look different.
	_surface_floor(TrackSurface.Kind.SNOW)
	await _wait(0.2)
	var snow := visuals.effects.sprays[0].color
	_surface_floor(TrackSurface.Kind.MUD)
	await _wait(0.2)
	var mud := visuals.effects.sprays[0].color
	_check(trike.surface == TrackSurface.Kind.MUD and snow.v > 0.9 and mud.v < 0.4 and visuals.effects.sprays[0].gravity.y < -10.0,
			"the spray follows the ground: white snow powder, heavy dark mud", "(snow %s, mud %s)" % [snow.to_html(), mud.to_html()])
	_surface_floor(TrackSurface.Kind.ROAD)
	trike.boost_time = 1.0
	await _wait(0.1)
	_check(visuals.effects.boost_trail.emitting, "boosting leaves a boost trail")
	trike.boost_time = 0.0
	# Landing from a drop: thump, puff.
	var lands := SoundBank.count(&"landing")
	trike.teleport(Transform3D(Basis(), trike.global_position + Vector3(0, 5, 0)), false)
	await _wait(2.0)
	_check(SoundBank.count(&"landing") > lands and visuals.effects.bursts.has("landing"), "landing after a drop: thump and dust puff")
	# A crash: hit sound and impact burst.
	var hits := SoundBank.count(&"hit_hard")
	runner._add_static_box(Vector3(8, 3, 1), trike.global_position + Vector3(0, 1, -14))
	await runner._hold(trike, 3.0, 1.0)
	_check(SoundBank.count(&"hit_hard") > hits and visuals.effects.bursts.has("impact"), "a hard crash: crash sound and impact burst")
	trike.input.clear()


func _test_rider_audio() -> void:
	print("\n[Polish: rider sounds]")
	await runner._new_arena()
	var trike: Trike = runner._spawn_trike(Vector3(0, 0.9, 0))
	var rider: RiderController = RIDER_SCENE.instantiate()
	runner._arena.add_child(rider)
	rider.attach_to(trike)
	rider.input_source = null
	await _wait(0.5)
	var counts := {}
	for sound: StringName in [&"eject", &"fall_thud", &"get_up", &"mount"]:
		counts[sound] = SoundBank.count(sound)
	rider.eject(14.0, Vector3(0, 0, -14))
	while rider.state != RiderController.State.ON_FOOT:
		await _tree().physics_frame
	var steps := rider.audio.steps
	for k in 60:
		rider.input.move_direction = Vector3.RIGHT
		await _tree().physics_frame
	rider.input.move_direction = Vector3.ZERO
	var to_trike := trike.global_position - rider.on_foot.global_position
	var t := 0.0
	while rider.state != RiderController.State.RIDING and t < 10.0:
		to_trike = trike.global_position - rider.on_foot.global_position
		to_trike.y = 0.0
		rider.input.move_direction = to_trike.normalized() if to_trike.length() > 0.5 else Vector3.ZERO
		rider.input.interact_pressed = rider.can_mount
		await _tree().physics_frame
		t += 1.0 / 60.0
	var heard: Array[String] = []
	for sound: StringName in counts:
		if SoundBank.count(sound) > int(counts[sound]):
			heard.append(String(sound))
	_check(heard.size() == 4, "ejection yelp, landing thud, get-up boing and mount hop", "(%s)" % ", ".join(heard))
	_check(rider.audio.steps > steps + 2, "footsteps while running", "(%d steps)" % (rider.audio.steps - steps))


func _test_race_audio() -> void:
	print("\n[Polish: race sounds]")
	var main := await _load(0, false)
	var beeps := SoundBank.count(&"countdown")
	var go := SoundBank.count(&"go")
	main.race.begin_countdown()
	var t := 0.0
	while not main.race.is_racing() and t < 6.0:
		await _tree().physics_frame
		t += 1.0 / 60.0
	await _tree().physics_frame
	_check(SoundBank.count(&"countdown") - beeps == 3 and SoundBank.count(&"go") - go == 1, "countdown: three beeps and a GO",
			"(%d beeps)" % (SoundBank.count(&"countdown") - beeps))
	var victory := SoundBank.count(&"victory")
	main.race_audio._on_state_changed(RaceStateMachine.State.FINISHED, RaceStateMachine.State.RESULTS)
	_check(SoundBank.count(&"victory") == victory and SoundBank.count(&"results") > 0, "results without a podium: a soft chord, no victory jingle")
	main.get_local_racer().finished = true
	main.get_local_racer().finish_position = 1
	main.race_audio._on_state_changed(RaceStateMachine.State.FINISHED, RaceStateMachine.State.RESULTS)
	_check(SoundBank.count(&"victory") == victory + 1, "a podium finish plays the victory jingle")
	var items := SoundBank.count(&"item_pickup")
	main.items.grant_item(main.get_local_racer(), ItemKind.Kind.TURBO_BOTTLE)
	_check(SoundBank.count(&"item_pickup") == items + 1, "items use the same sound bank (pickup chime)")


func _test_camera_feedback() -> void:
	print("\n[Polish: camera feedback]")
	var main := await _load(0)
	await _wait(0.5)
	var camera := main.follow_camera
	camera.add_impact_shake(2.0)
	_check(camera.trauma == 0.0, "small bumps don't shake the camera")
	for k in 5:
		camera.add_impact_shake(40.0)
	_check(camera.trauma <= 1.0 and camera.get_shake_offset() <= camera.shake_offset + 0.0001,
			"a big crash shakes it, but never more than the cap", "(%.2f m)" % camera.get_shake_offset())
	await _wait(0.6)
	_check(camera.trauma == 0.0, "the shake dies down within half a second")
	var y0 := camera.global_position.y
	camera.add_landing(1.2)
	var lowest := y0
	for k in 30:
		await _tree().process_frame
		lowest = minf(lowest, camera.global_position.y)
	await _wait(1.0)
	_check(y0 - lowest > 0.05 and absf(camera.global_position.y - y0) < 0.1, "a landing dips the camera and it springs back",
			"(dip %.2f m)" % (y0 - lowest))
	# The real crash wiring: the local trike's impact shakes the camera.
	main.trike.impact.emit(12.0, Vector3.ZERO)
	_check(camera.trauma > 0.3, "the player's crashes shake the camera")


## Network proxies show effects and play sounds from synced state only.
func _test_proxy_effects() -> void:
	print("\n[Polish: effects and sounds on remote players]")
	await runner._new_arena()
	var trike: Trike = TRIKE_SCENE.instantiate()
	runner._arena.add_child(trike)
	trike.input_source = null
	await _tree().physics_frame
	trike.set_network_proxy(true)
	var visuals := trike.get_node("Visuals") as TrikeVisuals
	var state := {"xf": Transform3D(Basis(), Vector3(0, 0.8, 0)), "vel": Vector3(4, 0, -18), "steer_amount": 0.6,
			"steer_angle": -0.3, "forward_speed": 18.0, "drift_dir": 1, "drift_charge": 1.0, "boost": 1.0,
			"susp": PackedFloat32Array([0.2, 0.2, 0.2]), "contact": 7, "has_rider": true}
	trike.apply_network_state(state)
	await _wait(0.3)
	_check(visuals.effects.sprays[0].emitting and visuals.effects.skid_marks[0].emitting and visuals.effects.boost_trail.emitting,
			"a remote drifting, boosting trike shows spray, skid marks and boost trail")
	_check(visuals.audio.skid_amount > 0.5 and visuals.audio.engine.pitch_scale > 1.0, "and sounds like it (engine, skid)")
	state["contact"] = 0
	trike.apply_network_state(state)
	await _wait(0.8)
	state["contact"] = 7
	var lands := SoundBank.count(&"landing")
	trike.apply_network_state(state)
	await _wait(0.1)
	_check(SoundBank.count(&"landing") > lands and visuals.effects.bursts.has("landing"), "a remote trike's landing thumps and puffs too")


func _test_ui_audio() -> void:
	print("\n[Polish: UI sounds and volume]")
	var bus := AudioServer.get_bus_index(&"UI")
	GameSettings.set_volume("UI", 0.5)
	_check(bus >= 0 and absf(db_to_linear(AudioServer.get_bus_volume_db(bus)) - 0.5) < 0.05 and GameSettings.ui_volume == 0.5,
			"menu sounds have their own UI bus and volume setting")
	GameSettings.set_volume("UI", 0.8)
	var button := UiKit.button("Test")
	runner._arena.add_child(button)
	var clicks := SoundBank.count(&"ui_click")
	button.pressed.emit()
	_check(SoundBank.count(&"ui_click") == clicks + 1, "buttons click")
	button.queue_free()
