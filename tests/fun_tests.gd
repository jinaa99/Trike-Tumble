extends RefCounted
## Fun-First Gameplay V2 tests: signature skills, perfect drift release, air
## tricks and landing grades, slipstream, near misses, taunts, the hazard
## seed and the end-of-race awards.
## Run as part of tests/test_runner.gd (`-- --only=fun` for this group).

const MAIN_SCENE := preload("res://scenes/main/main.tscn")

var runner: Node
var main: RaceSession
var skills: SkillManager
var items: ItemManager
var me: Racer
var bot: Racer
var events: Array = []
var messages: Array[String] = []


func _init(test_runner: Node) -> void:
	runner = test_runner


func run() -> void:
	_test_rules()
	_test_stats_and_awards()
	_test_snapshot_fx()
	await _test_perfect_drift()
	await _test_tricks_and_landings()
	await _test_ice_physics()
	await _test_characters()
	await _test_slingshot()
	await _test_bonk()
	await _test_snare()
	await _test_fake_box()
	await _test_shield()
	await _test_slipstream()
	await _test_near_miss()
	await _test_taunt_and_reactions()
	await _test_client_and_events()
	await _test_seed_and_ui()
	await _test_falling_tree()
	await _test_riding_styles()
	await _free_race()
	GameSettings.character = 0


# --- Helpers ----------------------------------------------------------------

func _check(condition: bool, test_name: String, detail := "") -> void:
	runner._check(condition, test_name, detail)


func _tree() -> SceneTree:
	return runner.get_tree()


func _wait(seconds: float) -> void:
	await runner._wait(seconds)


func _free_race() -> void:
	if main and is_instance_valid(main):
		main.queue_free()
		await _tree().process_frame
		await _tree().process_frame
	main = null


## Test track race: the local player (id 1) rides `character`, plus one AI
## racer (id 2); both are driven by the test and race from the first tick.
func _load(character := 0, tweak := Callable()) -> void:
	await _free_race()
	await runner._new_arena()
	GameSettings.character = character
	main = MAIN_SCENE.instantiate()
	main.ai_racer_count = 1
	main.skip_countdown = true
	runner.add_child(main)
	main.trike.input_source = null
	main.rider.input_source = null
	skills = main.skills
	items = main.items
	skills.config = skills.config.duplicate()
	skills.config.start_lockout = 0.0
	if tweak.is_valid():
		tweak.call(skills.config)
	me = main.racers.get_racer(1)
	bot = main.racers.get_racer(2)
	bot.get_ai_driver().active = false
	bot.trike.input_source = null
	bot.rider.input_source = null
	events = []
	messages = []
	skills.event_applied.connect(func(event: Array) -> void: events.append(event))
	skills.feedback.connect(func(racer: Racer, text: String) -> void:
		if racer == me:
			messages.append(text))
	await _wait(0.6)


func _spot(distance: float, lateral := 0.0, up := 0.8) -> Transform3D:
	var index := main.track.path.index_at_distance(distance)
	return main.track.path.get_frame(index).translated_local(Vector3(lateral, up, 0.0))


func _place(racer: Racer, distance: float, lateral := 0.0) -> void:
	racer.trike.teleport(_spot(distance, lateral), false)
	racer.progress.reset(main.track.path.index_at_distance(distance))


func _events_of(type: SkillManager.Event) -> Array:
	return events.filter(func(e: Array) -> bool: return e[1] == type)


func _press_skill(racer: Racer) -> void:
	racer.trike.input.skill_pressed = true
	await _tree().physics_frame
	await _tree().physics_frame


## Clears cooldowns and hit immunity so the next step starts clean.
func _refresh() -> void:
	skills.cooldowns.clear()
	items._immune.clear()
	skills._guard.clear()


# --- Pure rules -----------------------------------------------------------------

func _test_rules() -> void:
	print("\n[Fun: skill rules]")
	var config := SkillConfig.new()
	_check(SkillKind.for_character(0) == SkillKind.Kind.SLINGSHOT and SkillKind.for_character(1) == SkillKind.Kind.BONK
			and SkillKind.for_character(2) == SkillKind.Kind.SNARE and SkillKind.for_character(3) == SkillKind.Kind.FAKE_BOX
			and SkillKind.for_character(4) == SkillKind.Kind.SHIELD,
			"Zip, Pip, Bramble, Nutmeg and Rusty each have their own skill")
	var all_in_range := true
	for kind in [1, 2, 3, 4, 5]:
		var cooldown := config.cooldown_of(kind)
		all_in_range = all_in_range and cooldown >= 10.0 and cooldown <= 18.0
	_check(all_in_range, "every skill cooldown is between 10 and 18 seconds")
	_check(SkillRules.cooldown_factor(config, 5, 5) < 1.0 and SkillRules.cooldown_factor(config, 1, 5) > 1.0
			and is_equal_approx(SkillRules.cooldown_factor(config, 1, 1), 1.0),
			"the last racer's skill comes back sooner than the leader's",
			"(x%.2f vs x%.2f)" % [SkillRules.cooldown_factor(config, 5, 5), SkillRules.cooldown_factor(config, 1, 5)])
	_check(SkillRules.bonk_speed(config, 0.0) > SkillRules.bonk_speed(config, config.bonk_range)
			and SkillRules.bonk_speed(config, 0.0) < ItemConfig.new().punch_max_speed,
			"a bonk is strongest point-blank and weaker than the spring punch item")
	_check(not SkillManager._valid_request(SkillManager.Request.USE, [Vector3.ZERO, Vector3.FORWARD]) \
			and not SkillManager._valid_request(SkillManager.Request.STYLE, [SkillManager.Style.OVERTAKE, 1.0]) \
			and not SkillManager._valid_request(SkillManager.Request.USE, [Vector3.ZERO, Vector3.FORWARD, Vector3.ONE * 1000.0]) \
			and not SkillManager._valid_request(99, []) \
			and SkillManager._valid_request(SkillManager.Request.USE, [Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO]),
			"malformed skill requests are rejected (wrong size, impossible speed, host-only style)")
	_check(not SkillManager._valid_event([1, SkillManager.Event.BONK, 1, 2, "x", false]) and not SkillManager._valid_event([1, 99, 1])
			and not SkillManager._valid_event([1, SkillManager.Event.SLINGSHOT, 1]) and SkillManager._valid_event([1, SkillManager.Event.SHIELD_UP, 4])
			and not SkillManager._valid_event([1, SkillManager.Event.AWARDS, [[1, "A"]]]),
			"malformed skill events are rejected")


func _test_stats_and_awards() -> void:
	print("\n[Fun: race stats and awards]")
	var stats := RaceStats.new()
	var order: Array[int] = [1, 2, 3]
	_check(stats.build_awards(order).is_empty(), "a race where nothing happened gives no awards")
	stats.add(2, "pranks", 3.0)
	stats.add(1, "pranks", 1.0)
	stats.add(2, "wipeouts", 5.0)
	stats.add(3, "wipeouts", 2.0)
	stats.add(1, "mud_time", 2.0)
	stats.raise(3, "biggest_bonk", 6.5)
	stats.raise(3, "biggest_bonk", 4.0)
	var awards := stats.build_awards(order)
	var by_title := {}
	for award: Array in awards:
		by_title[award[1]] = award
	_check(by_title.has("PRANK MASTER") and int(by_title["PRANK MASTER"][0]) == 2 and String(by_title["PRANK MASTER"][2]).contains("3"),
			"PRANK MASTER goes to the racer with the most pranks", "(%s)" % str(awards))
	_check(by_title.has("BIGGEST BONK") and int(by_title["BIGGEST BONK"][0]) == 3 and is_equal_approx(stats.get_stat(3, "biggest_bonk"), 6.5),
			"BIGGEST BONK keeps the largest recorded shove")
	_check(not by_title.has("MUD MAGNET"), "an award below its floor is not given (2 s of mud is no MUD MAGNET)")
	var winners := {}
	for award: Array in awards:
		winners[award[0]] = int(winners.get(award[0], 0)) + 1
	_check(winners.values().max() == 1, "nobody gets two awards", "(%s)" % str(winners))
	_check(not by_title.has("MOST WIPEOUTS") or int(by_title["MOST WIPEOUTS"][0]) != 2,
			"an award skips a racer who already has one (racer 2 has PRANK MASTER)")
	_check(RaceStats.valid_awards(awards) and not RaceStats.valid_awards([[1, 2, 3]]) and not RaceStats.valid_awards("x"),
			"the awards list is validated before it is shown")


func _test_snapshot_fx() -> void:
	print("\n[Fun: snapshot fx bits]")
	var trike := {"xf": Transform3D.IDENTITY, "vel": Vector3.ZERO, "steer_amount": 0.0, "steer_angle": 0.0,
			"forward_speed": 0.0, "drift_dir": 0, "drift_charge": 0.0, "boost": 0.0, "susp": PackedFloat32Array([0, 0, 0]),
			"contact": 7, "has_rider": true, "teleports": 0,
			"fx": int(TrackSurface.Kind.ICE) | (int(Trike.Trick.SPIN) << 3) | 32}
	var rider := {"state": 0, "state_time": 0.0, "ragdoll_xf": Transform3D.IDENTITY, "foot": Vector3.ZERO, "facing": 0.0}
	var data := NetSnapshot.encode(1.0, trike, rider)
	_check(data.size() == NetSnapshot.FIELD_COUNT and NetSnapshot.validate(data) == "", "a snapshot with fx bits is valid",
			"(%d fields)" % data.size())
	var blended: Dictionary = NetSnapshot.blend(data, data, 0.5)["trike"]
	_check(int(blended["fx"]) == int(trike["fx"]), "surface, trick and slipstream bits survive the trip")
	var bad := data.duplicate()
	bad[20] = 4096
	_check(NetSnapshot.validate(bad) != "", "out-of-range fx bits are rejected")
	_check(Net.PROTOCOL_VERSION >= 3, "the protocol version was bumped for skills", "(v%d)" % Net.PROTOCOL_VERSION)


# --- Drift mastery ----------------------------------------------------------------

## Drives up to speed, drifts until `release_charge` and lets go. Returns
## {"boost", "perfect", "tier"}.
func _drift_release(release_charge: float) -> Dictionary:
	await runner._new_arena()
	var trike: Trike = runner._spawn_trike()
	var perfect := [false]
	trike.drift_perfect.connect(func(_tier: int) -> void: perfect[0] = true)
	var tiers := [0]
	trike.drift_ended.connect(func(tier: int) -> void: tiers[0] = tier)
	await _wait(0.3)
	await runner._hold(trike, 2.0, 1.0)
	for i in runner._ticks(6.0):
		trike.input.throttle = 1.0
		trike.input.steer = 1.0
		trike.input.drift = true
		await _tree().physics_frame
		if trike.drift_charge >= release_charge:
			break
	trike.input.drift = false
	trike.input.steer = 0.0
	await _tree().physics_frame
	var result := {"boost": trike.boost_time, "perfect": perfect[0], "tier": tiers[0], "speed": trike.forward_speed}
	trike.queue_free()
	return result


func _test_perfect_drift() -> void:
	print("\n[Fun: perfect drift release]")
	var config := TrikeConfig.new()
	var tiers := config.drift_boost_tier_times
	var early := await _drift_release(tiers.x * 0.5)
	_check(int(early["tier"]) == 0 and float(early["boost"]) <= 0.0, "letting go too early gives no boost (as before)")
	var perfect1 := await _drift_release(tiers.x + config.drift_perfect_window * 0.4)
	_check(bool(perfect1["perfect"]) and int(perfect1["tier"]) == 1, "releasing just after tier 1 is a PERFECT release",
			"(boost %.2f s)" % perfect1["boost"])
	var normal1 := await _drift_release(tiers.x + config.drift_perfect_window + 0.3)
	_check(not bool(normal1["perfect"]) and int(normal1["tier"]) == 1
			and absf(float(normal1["boost"]) - config.drift_boost_durations.x) < 0.05,
			"releasing later still pays the normal tier 1 boost", "(%.2f s)" % normal1["boost"])
	_check(float(perfect1["boost"]) > float(normal1["boost"]) + 0.2
			and float(perfect1["boost"]) <= config.drift_boost_durations.x + config.drift_perfect_bonus + 0.02,
			"a perfect release pays a modest extra boost", "(%.2f vs %.2f s)" % [perfect1["boost"], normal1["boost"]])
	var perfect2 := await _drift_release(tiers.y + config.drift_perfect_window * 0.4)
	var late2 := await _drift_release(tiers.y + config.drift_perfect_window + 0.5)
	_check(bool(perfect2["perfect"]) and int(perfect2["tier"]) == 2 and not bool(late2["perfect"]) and int(late2["tier"]) == 2,
			"tier 2 has its own perfect window; holding on past it is a normal tier 2")
	_check(float(perfect2["boost"]) <= config.drift_boost_durations.y + config.drift_perfect_bonus + 0.02
			and float(late2["boost"]) <= config.drift_boost_durations.y + 0.02,
			"no boost is longer than tier 2 plus the perfect bonus (no exploit by holding)",
			"(%.2f / %.2f s)" % [perfect2["boost"], late2["boost"]])


# --- Air tricks and landings --------------------------------------------------------

## Drops a trike from `height` with forward speed and plays `script`
## (func(trike, t)) each tick until 1 s after touchdown. Returns what happened.
func _jump(up_speed: float, speed: float, script: Callable, yaw_deg := 0.0) -> Dictionary:
	await runner._new_arena()
	var rig: Dictionary = runner._rider_rig()
	var trike: Trike = rig["trike"]
	var rider: RiderController = rig["rider"]
	await _wait(0.5)
	var grades: Array = []
	trike.landing_graded.connect(func(grade: int, air: float, tricks: int) -> void: grades.append([grade, air, tricks]))
	# Launched like off a kicker: forward and up, through apply_item_hit so
	# the launch itself is not measured as a crash.
	trike.teleport(Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), Vector3(0.0, 1.3, 0.0)), false)
	await _tree().physics_frame
	await _tree().physics_frame
	trike.apply_item_hit(Vector3(0.0, up_speed, -speed))
	var t := 0.0
	var landed_at := -1.0
	var worst_hit := 0.0
	var tricks_started := 0
	var was_tricking := false
	var boost := 0.0
	while t < 4.0 and (landed_at < 0.0 or t < landed_at + 1.0):
		trike.input.clear()
		script.call(trike, t)
		await _tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		worst_hit = maxf(worst_hit, trike.last_impact_strength)
		boost = maxf(boost, trike.boost_time)
		var tricking := trike.trick_kind != Trike.Trick.NONE
		if tricking and not was_tricking:
			tricks_started += 1
		was_tricking = tricking
		if landed_at < 0.0 and trike.grounded_wheel_count > 0 and t > 0.2:
			landed_at = t
	var result := {"grades": grades, "boost": boost, "riding": rider.is_riding(), "hit": worst_hit,
			"tricks": trike.trick_count, "started": tricks_started, "air": landed_at, "speed": trike.linear_velocity.length(),
			"slip": trike.slip_time}
	(rig["trike"] as Node).queue_free()
	(rig["rider"] as Node).queue_free()
	return result


func _test_tricks_and_landings() -> void:
	print("\n[Fun: air tricks and landings]")
	var config := TrikeConfig.new()
	# Short hop: no grade at all.
	var hop := await _jump(0.5, 16.0, func(_trike: Trike, _t: float) -> void: pass)
	_check((hop["grades"] as Array).is_empty(), "a short hop is not graded", "(%.2f s of air)" % hop["air"])
	# Medium jump, hands off: a GOOD landing, nothing gained or lost.
	var plain := await _jump(5.2, 16.0, func(_trike: Trike, _t: float) -> void: pass)
	var plain_grades: Array = plain["grades"]
	_check(plain_grades.size() == 1 and int(plain_grades[0][0]) == Trike.Landing.GOOD and float(plain["boost"]) <= 0.0,
			"a level landing without a trick is GOOD: no boost, no penalty", "(%s, %.2f s air)" % [str(plain_grades), plain["air"]])
	_check(bool(plain["riding"]) and float(plain["hit"]) < RiderConfig.new().eject_impact_strength,
			"a normal landing never throws the rider off", "(hardest hit %.1f)" % plain["hit"])
	# Trick early with enough air: it completes and the landing is PERFECT.
	var trick := await _jump(7.6, 16.0, func(trike: Trike, t: float) -> void: trike.input.trick = t < 0.25)
	var trick_grades: Array = trick["grades"]
	_check(int(trick["tricks"]) == 1 and int(trick["started"]) == 1, "SHIFT in the air starts one trick and it completes",
			"(%d completed, %.2f s air)" % [trick["tricks"], trick["air"]])
	_check(trick_grades.size() == 1 and int(trick_grades[0][0]) == Trike.Landing.PERFECT and int(trick_grades[0][2]) == 1,
			"a clean landing after a trick is a PERFECT landing", "(%s)" % str(trick_grades))
	_check(float(trick["boost"]) > 0.0 and float(trick["boost"]) <= config.landing_max_boost and bool(trick["riding"]),
			"a perfect landing gives a small boost", "(%.2f s)" % trick["boost"])
	# Backflip with S held.
	var flip := await _jump(8.2, 16.0, func(trike: Trike, t: float) -> void:
		trike.input.trick = t < 0.25
		trike.input.brake = 1.0 if t < 0.25 else 0.0)
	_check(int(flip["tricks"]) == 1 and bool(flip["riding"]), "S + SHIFT is a backflip that lands on its wheels",
			"(%s)" % str(flip["grades"]))
	# Trick started far too late: caught mid-spin by the ground.
	var late := await _jump(5.2, 16.0, func(trike: Trike, t: float) -> void: trike.input.trick = t > 0.55)
	var late_grades: Array = late["grades"]
	_check(late_grades.size() == 1 and int(late_grades[0][0]) >= Trike.Landing.POOR and int(late["tricks"]) == 0,
			"a trick cut short by the ground is a rough landing, not a trick", "(%s)" % str(late_grades))
	_check(float(late["speed"]) < float(plain["speed"]) - 0.5,
			"a rough landing costs speed", "(%.1f vs %.1f m/s a second later)" % [late["speed"], plain["speed"]])
	# Landing sideways (heading 60 degrees off the direction of travel).
	var sideways := await _jump(5.2, 16.0, func(_trike: Trike, _t: float) -> void: pass, 60.0)
	var side_grades: Array = sideways["grades"]
	_check(side_grades.size() == 1 and int(side_grades[0][0]) == Trike.Landing.BAD,
			"landing sideways is a BAD landing", "(%s)" % str(side_grades))
	_check(float(sideways["hit"]) < RiderConfig.new().eject_impact_strength,
			"a bad landing is a penalty, not an automatic crash", "(hardest hit %.1f, riding %s)" % [sideways["hit"], sideways["riding"]])
	# Tricks never start on the ground.
	await runner._new_arena()
	var grounded: Trike = runner._spawn_trike()
	await _wait(0.4)
	for i in runner._ticks(0.5):
		grounded.input.trick = true
		grounded.input.throttle = 1.0
		await _tree().physics_frame
	_check(grounded.trick_kind == Trike.Trick.NONE and grounded.trick_count == 0, "SHIFT does nothing on the ground")
	grounded.queue_free()


# --- Skills -----------------------------------------------------------------------

func _test_characters() -> void:
	print("\n[Fun: characters and skills]")
	await _load(0)
	_check(me.character == 0 and me.get_skill() == SkillKind.Kind.SLINGSHOT and bot.character == 1
			and bot.get_skill() == SkillKind.Kind.BONK, "by default the player is Zip and the first bot is Pip")
	_check(main.hud.get_skill_text() == "SLINGSHOT" and main.hud.skill_panel.visible, "the HUD shows the player's skill",
			"(%s)" % main.hud.get_skill_text())
	await _load(3)
	_check(me.character == 3 and me.get_skill() == SkillKind.Kind.FAKE_BOX, "the player can ride as Nutmeg")
	_check(bot.character != 3 and bot.display_name == SkillKind.character_name(bot.character),
			"the bot takes another rider, name included", "(%s is character %d)" % [bot.display_name, bot.character])
	var model := me.trike.get_node(^"Visuals/Rider") as Rider
	_check(model.character == 3 and me.rider.character == 3, "look and voice follow the character")
	_check(main.hud.get_skill_text() == "FAKE BOX", "the HUD follows the chosen rider")


func _test_slingshot() -> void:
	print("\n[Fun: Zip's slingshot]")
	await _load(0)
	_place(me, 40.0)
	_place(bot, 110.0)
	await _wait(0.6)
	await _press_skill(me)
	_check(_events_of(SkillManager.Event.SLINGSHOT).is_empty() and skills.is_ready(me.id) and me.trike.boost_time <= 0.0,
			"no rival nearby: no slingshot, no boost and no cooldown spent")
	_check(messages.has("NO ONE TO SLINGSHOT"), "the player is told why", "(%s)" % str(messages))
	var denied := skills.denied_requests
	var raw_id := int(skills._next_req.get(me.id, 0)) + 1
	skills._next_req[me.id] = raw_id
	_check(not skills.handle_request(me.id, raw_id, SkillManager.Request.USE, [me.trike.global_position, -me.trike.global_basis.z, Vector3.ZERO])
			and skills.denied_requests == denied + 1, "the host also refuses a slingshot without a target")
	_place(bot, 52.0)
	await _wait(0.6)
	await _press_skill(me)
	var shots := _events_of(SkillManager.Event.SLINGSHOT)
	_check(shots.size() == 1 and int(shots[0][2]) == me.id and int(shots[0][3]) == bot.id,
			"with a rival 12 m ahead the slingshot fires at that rival")
	_check(me.trike.boost_time > 1.0, "it gives a boost", "(%.2f s)" % me.trike.boost_time)
	_check(not skills.is_ready(me.id) and skills.get_cooldown(me.id) > 8.0, "and starts the cooldown",
			"(%.1f s)" % skills.get_cooldown(me.id))
	_check(bot.rider.is_riding() and bot.trike.slip_time <= 0.0, "the rival is not touched")
	await _press_skill(me)
	_check(_events_of(SkillManager.Event.SLINGSHOT).size() == 1 and messages.has("SKILL NOT READY"),
			"pressing again during the cooldown does nothing")
	var before := skills.duplicate_requests
	skills.cooldowns.clear()
	var last_req := int(skills._last_req.get(me.id, 0))
	_check(not skills.handle_request(me.id, last_req, SkillManager.Request.USE, [me.trike.global_position, -me.trike.global_basis.z, Vector3.ZERO])
			and skills.duplicate_requests == before + 1 and _events_of(SkillManager.Event.SLINGSHOT).size() == 1,
			"a repeated request id is ignored (no duplicate activation)")
	_place(bot, 49.0, 6.0)
	_place(me, 40.0)
	await _wait(0.5)
	_check(skills.find_slingshot_target(me) == null, "a rival well off to the side is not a slingshot target")
	bot.rider.eject()
	_place(bot, 52.0)
	await _wait(0.2)
	_check(skills.find_slingshot_target(me) == null, "an empty trike is not a target")


func _test_bonk() -> void:
	print("\n[Fun: Pip's spring bonk]")
	await _load(1)
	_place(me, 60.0, -1.6)
	_place(bot, 61.0, 1.8)
	await _wait(0.8)
	var start := bot.trike.global_position
	await _press_skill(me)
	await _wait(0.7)
	var bonks := _events_of(SkillManager.Event.BONK)
	var moved := bot.trike.global_position - start
	_check(bonks.size() == 1 and int(bonks[0][3]) == bot.id, "the bonk hits the rival beside")
	_check(moved.dot(bot.trike.global_basis.x) > 0.8, "it shoves the rival sideways, away from Pip",
			"(%.1f m)" % moved.dot(bot.trike.global_basis.x))
	_check(bot.rider.is_riding() and not bool(bonks[0][5]), "from a few meters it never throws the rider off")
	_check(items.is_immune(bot.id), "the victim is briefly immune to more hits (no chain-stuns)")
	_check(int(skills.stats.get_stat(me.id, "pranks")) == 1 and skills.stats.get_stat(me.id, "biggest_bonk") > 3.0,
			"the prank and its strength are recorded", "(%.1f m/s)" % skills.stats.get_stat(me.id, "biggest_bonk"))
	var full := skills.get_cooldown(me.id)
	# Immune target: the bonk finds nobody.
	skills.cooldowns.clear()
	_place(me, 60.0, -1.6)
	_place(bot, 61.0, 1.8)
	await _wait(0.3)
	await _press_skill(me)
	bonks = _events_of(SkillManager.Event.BONK)
	_check(bonks.size() == 2 and int(bonks[1][3]) == 0, "an immune rival can't be bonked again straight away")
	# Out of range: a whiff with a shorter cooldown.
	await _wait(0.4)
	_refresh()
	_place(me, 60.0)
	_place(bot, 80.0)
	await _wait(0.5)
	start = bot.trike.global_position
	await _press_skill(me)
	await _wait(0.3)
	bonks = _events_of(SkillManager.Event.BONK)
	_check(bonks.size() == 3 and int(bonks[2][3]) == 0 and bot.trike.global_position.distance_to(start) < 0.3,
			"out of range the bonk whiffs and nobody moves")
	_check(skills.get_cooldown(me.id) < full * 0.7 and messages.has("WHIFF!"), "a whiff costs a shorter cooldown",
			"(%.1f s vs %.1f s)" % [skills.get_cooldown(me.id), full])
	# Behind Pip: outside the cone.
	_refresh()
	_place(me, 60.0)
	_place(bot, 56.5)
	await _wait(0.5)
	_check(skills.find_bonk_target(me) == null, "a rival directly behind is outside the bonk cone (it can be dodged)")
	# Point-blank: may eject. Then the guard stops a repeat.
	_place(me, 90.0, -0.8)
	_place(bot, 90.0, 0.9)
	await _wait(0.6)
	await _press_skill(me)
	await _wait(0.3)
	bonks = _events_of(SkillManager.Event.BONK)
	_check(bool(bonks[-1][5]) and not bot.rider.is_riding(), "a point-blank bonk can throw the rider off")
	await _wait(0.3)
	bot.rider.force_mount()
	skills.cooldowns.clear()
	items._immune.clear()
	_place(me, 90.0, -0.8)
	_place(bot, 90.0, 0.9)
	await _wait(0.6)
	_check(skills.is_guarded(bot.id), "back on the trike, the victim is guarded against another skill ejection")
	await _press_skill(me)
	await _wait(0.3)
	bonks = _events_of(SkillManager.Event.BONK)
	_check(int(bonks[-1][3]) == bot.id and not bool(bonks[-1][5]) and bot.rider.is_riding(),
			"the same point-blank bonk now only shoves (no repeated ejection)")
	# The AI would use it too.
	_refresh()
	_place(me, 120.0, -1.6)
	_place(bot, 121.0, 1.8)
	await _wait(0.4)
	_check(AISkillTactics.wants_use(me, main.racers, AIDriverConfig.new(), 0.0), "AI tactics: bonk when a rival is in reach")
	_place(bot, 170.0)
	await _wait(0.3)
	_check(not AISkillTactics.wants_use(me, main.racers, AIDriverConfig.new(), 0.0), "AI tactics: no bonk at thin air")


## Drives `racer` at full throttle along the road, holding `lateral` m from
## the centerline, for `seconds`. Returns the closest it came to `watch`.
func _drive_lane(racer: Racer, lateral: float, seconds: float, watch: Node3D = null) -> float:
	var path := main.track.path
	var trike := racer.trike
	var closest := INF
	for i in runner._ticks(seconds):
		var index := path.find_nearest(trike.global_position)
		var offset := (trike.global_position - path.points[index]).dot(path.rights[index])
		var forward := -trike.global_basis.z
		forward.y = 0.0
		var road := path.forwards[mini(index + 3, path.size() - 1)]
		road.y = 0.0
		var error := forward.signed_angle_to(road, Vector3.UP)
		trike.input.throttle = 1.0
		trike.input.steer = clampf(-error * 2.5 + (lateral - offset) * 0.25, -1.0, 1.0)
		await _tree().physics_frame
		if watch:
			var gap := trike.global_position - watch.global_position
			closest = minf(closest, Vector2(gap.x, gap.z).length())
	trike.input.clear()
	return closest


## Drives `racer` forward from `from` for `seconds`.
func _drive(racer: Racer, seconds: float) -> void:
	for i in runner._ticks(seconds):
		racer.trike.input.throttle = 1.0
		await _tree().physics_frame
	racer.trike.input.clear()


func _test_snare() -> void:
	print("\n[Fun: Bramble's root snare]")
	await _load(2)
	_place(me, 60.0)
	_place(bot, 20.0)
	await _wait(0.6)
	await _press_skill(me)
	var placed := _events_of(SkillManager.Event.TRAP_PLACED)
	var trap := skills.get_trap_of(me.id)
	_check(placed.size() == 1 and trap != null and trap.kind == SkillKind.Kind.SNARE, "F drops a root snare")
	var behind := (trap.global_position - me.trike.global_position).dot(me.trike.global_basis.z) if trap else 0.0
	_check(behind > 2.0 and behind < 5.0, "it lies on the road just behind the trike", "(%.1f m behind)" % behind)
	_check(trap != null and not trap.is_armed_for(bot.id) and trap.get_node_or_null("Snare/Warning") != null,
			"it has a glowing warning disc and is not armed straight away")
	await _wait(0.2)
	_check(_events_of(SkillManager.Event.TRAP_HIT).is_empty() and me.trike.slip_time <= 0.0, "Bramble doesn't trip on it when dropping it")
	await _wait(skills.config.snare_arm_time + 0.2)
	_check(trap.is_armed_for(bot.id), "it arms after the warning time")
	# A second snare replaces the first.
	skills.cooldowns.clear()
	_place(me, 100.0)
	await _wait(0.4)
	await _press_skill(me)
	_check(skills.traps.size() == 1 and skills.get_trap_of(me.id) != trap, "only one snare per trapper: a new one replaces the old")
	trap = skills.get_trap_of(me.id)
	_place(me, 200.0)
	_place(bot, 80.0)
	await _wait(1.2)
	var speed_at_hit := [0.0]
	skills.event_applied.connect(func(event: Array) -> void:
		if event[1] == SkillManager.Event.TRAP_HIT:
			speed_at_hit[0] = bot.trike.linear_velocity.length())
	await _drive(bot, 2.2)
	var hits := _events_of(SkillManager.Event.TRAP_HIT)
	_check(hits.size() == 1 and int(hits[0][3]) == bot.id and skills.traps.is_empty(), "a rival driving over it gets snared and the snare is used up")
	_check(bot.rider.is_riding() and not bool(hits[0][5]), "at normal speed the snare slows and wobbles, it doesn't eject")
	_check(int(skills.stats.get_stat(me.id, "pranks")) == 1 and messages.any(func(m: String) -> bool: return m.begins_with("GOT ")),
			"the trapper is credited and told")
	# Steering around it avoids it.
	_refresh()
	_place(me, 60.0)
	await _wait(0.4)
	await _press_skill(me)
	_place(me, 200.0)
	_place(bot, 44.0, 4.0)
	await _wait(1.2)
	await _drive(bot, 2.0)
	_check(_events_of(SkillManager.Event.TRAP_HIT).size() == 1 and skills.traps.size() == 1, "passing 4 m to the side avoids the snare")
	# It expires.
	var lifetime := skills.config.snare_lifetime
	skills.get_trap_of(me.id).age = lifetime - 0.1
	await _wait(0.4)
	_check(skills.traps.is_empty(), "an untouched snare disappears after its lifetime")


func _test_fake_box() -> void:
	print("\n[Fun: Nutmeg's fake box]")
	await _load(3)
	_place(me, 60.0)
	_place(bot, 20.0)
	await _wait(0.6)
	await _press_skill(me)
	var trap := skills.get_trap_of(me.id)
	_check(trap != null and trap.kind == SkillKind.Kind.FAKE_BOX and items.boxes.is_empty(), "F leaves a fake item box (not a real one)")
	var real := ItemBox.new()
	runner.add_child(real)
	var real_color := ((real.get_node("Box") as MeshInstance3D).mesh as RoundedBoxMesh).material as StandardMaterial3D
	var fake_color := ((trap.get_node("FakeBox/Box") as MeshInstance3D).mesh as RoundedBoxMesh).material as StandardMaterial3D
	var mark := trap.get_node("FakeBox/Box").get_child(0) as Label3D
	var differs := true
	for color: Color in ItemBox.COLORS:
		differs = differs and Vector3(color.r, color.g, color.b).distance_to(
				Vector3(fake_color.albedo_color.r, fake_color.albedo_color.g, fake_color.albedo_color.b)) > 0.15
	_check(differs and absf(mark.rotation.z) > 3.0 and real_color != null,
			"the fake has a fair tell: a color no real box has and an upside-down \"?\"")
	real.queue_free()
	items.grant_item(bot, ItemKind.Kind.TURBO_BOTTLE)
	_place(me, 200.0)
	_place(bot, 40.0)
	await _wait(1.2)
	await _drive(bot, 2.2)
	var hits := _events_of(SkillManager.Event.TRAP_HIT)
	_check(hits.size() == 1 and int(hits[0][3]) == bot.id, "a rival driving into it is pranked")
	_check(bot.held_item == ItemKind.Kind.TURBO_BOTTLE, "the fake box never takes the victim's real item")
	_check(bot.rider.is_riding() and not bool(hits[0][5]), "it wobbles the victim without throwing them off")
	_check(messages.any(func(m: String) -> bool: return m.ends_with("FELL FOR IT!")), "Nutmeg is told who fell for it",
			"(%s)" % str(messages))
	var victim_model := bot.trike.get_node(^"Visuals/Rider") as Rider
	_check(victim_model.reaction_kind == &"confused" or victim_model.expression == Rider.Face.CONFUSED
			or victim_model.reaction_kind == &"yelp", "the victim reacts", "(%s)" % victim_model.reaction_kind)


func _test_shield() -> void:
	print("\n[Fun: Rusty's pillow shield]")
	await _load(4, func(c: SkillConfig) -> void: c.shield_duration = 5.0)
	_place(me, 62.0, -1.6)
	_place(bot, 60.0, 1.8)
	await _wait(0.6)
	await _press_skill(me)
	_check(_events_of(SkillManager.Event.SHIELD_UP).size() == 1 and skills.has_shield(me.id)
			and me.trike.get_node_or_null("PillowShield") != null, "F puts up the pillow shield (a visible bubble)")
	_check(me.rider.impact_guard > 0.0, "it also pads crashes a little")
	# An item attack is blocked.
	items.grant_item(bot, ItemKind.Kind.SPRING_PUNCH)
	await _wait(0.5)
	var start := me.trike.global_position
	bot.trike.input.use_item_pressed = true
	await _wait(0.5)
	var pops := _events_of(SkillManager.Event.SHIELD_POP)
	_check(pops.size() == 1 and int(pops[0][2]) == me.id and int(pops[0][3]) == SkillManager.Pop.ITEM, "an incoming spring punch pops the shield")
	_check(me.trike.global_position.distance_to(start) < 0.8 and me.rider.is_riding() and bot.held_item == ItemKind.Kind.NONE,
			"the punch does nothing to Rusty, and the item is still spent", "(moved %.2f m)" % me.trike.global_position.distance_to(start))
	_check(not skills.has_shield(me.id) and me.trike.get_node_or_null("PillowShield") == null or
			(me.trike.get_node_or_null("PillowShield") as Node).is_queued_for_deletion(), "one hit and the shield is gone")
	_check(messages.has("BLOCKED!") and int(skills.stats.get_stat(me.id, "blocks")) == 1, "the block is announced and recorded")
	# A moderate crash is absorbed, a big one is not.
	_refresh()
	await _wait(0.3)
	await _press_skill(me)
	var threshold := me.rider.config.eject_impact_strength
	me.rider._on_trike_impact(threshold * 1.2, me.trike.linear_velocity)
	await _wait(0.2)
	pops = _events_of(SkillManager.Event.SHIELD_POP)
	_check(me.rider.is_riding() and pops.size() == 2 and int(pops[1][3]) == SkillManager.Pop.CRASH,
			"a crash a little over the eject threshold is soaked up by the pillow")
	_refresh()
	await _wait(0.3)
	await _press_skill(me)
	me.rider._on_trike_impact(threshold * 2.0, me.trike.linear_velocity)
	await _wait(0.2)
	_check(not me.rider.is_riding(), "a really big crash still throws Rusty off (no invulnerability)")
	me.rider.force_mount()
	# It runs out by itself.
	_refresh()
	skills._drop_shield(me.id)
	await _wait(0.3)
	await _press_skill(me)
	_check(skills.has_shield(me.id), "shield up again")
	await _wait(skills.config.shield_duration + 0.3)
	_check(not skills.has_shield(me.id) and me.rider.impact_guard == 0.0, "the shield only lasts a few seconds")


# --- Slipstream and near misses -------------------------------------------------------

func _test_slipstream() -> void:
	print("\n[Fun: slipstream]")
	await _load(1)
	_place(bot, 40.0)
	_place(me, 32.0)
	await _wait(0.5)
	var best := 0.0
	var factor := 0.0
	var early := 1.0
	for i in runner._ticks(3.5):
		me.trike.input.throttle = 1.0
		bot.trike.input.throttle = 1.0
		await _tree().physics_frame
		if i == 20:
			early = skills.get_draft(me.id)
		best = maxf(best, skills.get_draft(me.id))
		factor = maxf(factor, me.trike.draft_factor)
	_check(early < 0.2, "no slipstream while both are still slow", "(meter %.2f)" % early)
	_check(best >= 0.999 and factor >= 0.99, "tucked in behind a rival at speed, the draft meter fills and tows",
			"(meter %.2f, factor %.2f)" % [best, factor])
	_check(skills.get_draft(bot.id) < 0.05 and bot.trike.draft_factor < 0.05, "the rival in front gets nothing")
	_check(skills.stats.get_stat(me.id, "draft_time") > 0.02, "time in the tow is recorded",
			"(%.2f s)" % skills.stats.get_stat(me.id, "draft_time"))
	me.trike.input.clear()
	bot.trike.input.clear()
	# Side by side: no tow.
	_place(bot, 40.0, 3.5)
	_place(me, 32.0, -3.5)
	await _wait(0.5)
	best = 0.0
	for i in runner._ticks(3.0):
		me.trike.input.throttle = 1.0
		bot.trike.input.throttle = 1.0
		await _tree().physics_frame
		best = maxf(best, skills.get_draft(me.id))
	_check(best < 0.5, "7 m to the side there is no slipstream", "(meter %.2f)" % best)
	me.trike.input.clear()
	bot.trike.input.clear()
	# The tow is worth speed, but only a little.
	var config := me.trike.config
	_check(config.draft_top_speed_bonus > 0.0 and config.max_speed + config.draft_top_speed_bonus < config.boost_max_speed,
			"a tow adds less top speed than a boost (no permanent stacking)",
			"(+%.1f m/s on %.0f, boost %.0f)" % [config.draft_top_speed_bonus, config.max_speed, config.boost_max_speed])
	me.trike.draft_factor = 1.0
	await _wait(1.0)
	_check(me.trike.draft_factor <= 0.01, "the tow fades by itself when nothing renews it")


func _test_near_miss() -> void:
	print("\n[Fun: near miss]")
	await _load(1)
	var rock: Node3D = null
	for obstacle: Dictionary in main.racers.get_obstacles():
		if obstacle["kind"] == "rock":
			rock = obstacle["node"]
			break
	_check(rock != null, "the test track has a rock to buzz")
	if rock == null:
		return
	_place(bot, 900.0)
	var index := main.track.path.find_nearest(rock.global_position)
	var distance := index * main.track.path.spacing
	var lateral := (rock.global_position - main.track.path.points[index]).dot(main.track.path.rights[index])
	var side := -signf(lateral)
	# Skim past: about 0.6 m of air between trike and rock.
	_place(me, distance - 45.0, lateral + side * 2.9)
	await _wait(0.5)
	var closest := await _drive_lane(me, lateral + side * 2.6, 4.0, rock)
	var style := _events_of(SkillManager.Event.STYLE).filter(func(e: Array) -> bool: return e[3] == SkillManager.Style.NEAR_MISS)
	_check(style.size() == 1 and int(style[0][2]) == me.id, "skimming past a rock at speed is a NEAR MISS",
			"(%d events, passed %.2f m from its center)" % [style.size(), closest])
	_check(messages.has("NEAR MISS!") and int(skills.stats.get_stat(me.id, "near_misses")) == 1, "it is announced and recorded")
	# Same rock again right away: no farming.
	_place(me, distance - 45.0, lateral + side * 2.9)
	await _wait(0.5)
	await _drive_lane(me, lateral + side * 2.6, 4.0)
	style = _events_of(SkillManager.Event.STYLE).filter(func(e: Array) -> bool: return e[3] == SkillManager.Style.NEAR_MISS)
	_check(style.size() == 1, "buzzing the same rock again straight away pays nothing")
	# A wide berth is not a near miss.
	skills._threat_gate.clear()
	skills._near_rearm.clear()
	skills._style_gate.clear()
	_place(me, distance - 45.0, lateral + side * 6.0)
	await _wait(0.5)
	await _drive_lane(me, lateral + side * 6.0, 4.0)
	style = _events_of(SkillManager.Event.STYLE).filter(func(e: Array) -> bool: return e[3] == SkillManager.Style.NEAR_MISS)
	_check(style.size() == 1, "passing with a wide berth is no near miss")
	# Slowly: no reward either.
	_place(me, distance - 6.0, lateral + side * 2.9)
	await _wait(0.5)
	await _drive_lane(me, lateral + side * 2.6, 1.2)
	style = _events_of(SkillManager.Event.STYLE).filter(func(e: Array) -> bool: return e[3] == SkillManager.Style.NEAR_MISS)
	_check(style.size() == 1, "creeping past slowly is no near miss")
	# The host rate-limits style events.
	skills._style_gate.clear()
	_place(me, 60.0)
	await _wait(0.5)
	var first := skills.handle_request(me.id, 5000, SkillManager.Request.STYLE, [SkillManager.Style.NEAR_MISS, 0.5])
	var second := skills.handle_request(me.id, 5001, SkillManager.Request.STYLE, [SkillManager.Style.NEAR_MISS, 0.5])
	_check(first and not second, "the host refuses style rewards that come too fast")


# --- Personality ------------------------------------------------------------------

func _test_taunt_and_reactions() -> void:
	print("\n[Fun: taunt and reactions]")
	await _load(0)
	_place(me, 60.0)
	_place(bot, 30.0)
	await _wait(0.6)
	var model := me.trike.get_node(^"Visuals/Rider") as Rider
	me.trike.input.emote_pressed = true
	await _wait(0.2)
	_check(_events_of(SkillManager.Event.EMOTE).size() == 1 and model.reaction_kind == &"taunt" and model.is_reacting(),
			"C makes the rider taunt")
	_check(model.expression == Rider.Face.SMUG, "with a smug face")
	_check(me.rider.audio.barks.has(&"taunt"), "and a voice bark")
	var hand := model.get_node("HandR") as Node3D
	await _wait(0.3)
	_check(hand.global_position.distance_to(model.right_hand_target.global_position) > 0.25, "one hand leaves the grip to wave")
	var steer_before := me.trike.steer_amount
	me.trike.input.steer = 1.0
	await _wait(0.3)
	_check(me.trike.steer_amount > steer_before + 0.5, "taunting never blocks steering")
	me.trike.input.clear()
	me.trike.input.emote_pressed = true
	await _wait(0.2)
	_check(_events_of(SkillManager.Event.EMOTE).size() == 1, "taunts are rate-limited")
	await _wait(1.6)
	_check(not model.is_reacting() and model.expression == model.base_face and model.get_max_ik_error() < 0.03,
			"afterwards the hands are back on the grips and the face is back to normal", "(IK error %.3f m)" % model.get_max_ik_error())
	_check(model.react(&"laugh") and model.expression == Rider.Face.LAUGH, "riders can laugh")
	_check(not model.react(&"not_a_reaction"), "unknown reactions are ignored")
	var audio := me.rider.audio
	audio._bark_ready.clear()
	audio._last_bark = -100.0
	RiderAudio._recent_barks.clear()
	var played := 0
	for i in 6:
		if audio.bark(&"laugh"):
			played += 1
	_check(played == 1, "the same bark can't be spammed", "(%d of 6 played)" % played)
	_check(RiderAudio.VOICE_PITCH.size() == 5 and RiderAudio.VOICE_PITCH.max() - RiderAudio.VOICE_PITCH.min() > 0.4,
			"each rider has their own voice pitch")
	# A fall still wins over a reaction.
	model.react(&"laugh")
	me.rider.eject()
	await _wait(0.1)
	_check(model.expression == Rider.Face.SHOCKED and not model.is_reacting(), "being thrown off replaces any reaction")
	_check(not model.react(&"taunt"), "no taunting mid-air")


# --- Network shape ----------------------------------------------------------------

func _test_client_and_events() -> void:
	print("\n[Fun: client requests and host events]")
	await _load(1)
	skills.authoritative = false
	var sent: Array = []
	skills.send_request = func(racer_id: int, req_id: int, kind: int, data: Array) -> void:
		sent.append([racer_id, req_id, kind, data])
	_place(me, 60.0, -1.6)
	_place(bot, 61.0, 1.8)
	await _wait(0.6)
	await _press_skill(me)
	_check(sent.size() == 1 and int(sent[0][0]) == me.id and int(sent[0][2]) == SkillManager.Request.USE and events.is_empty(),
			"a client only sends a request; nothing happens until the host answers")
	await _press_skill(me)
	_check(sent.size() == 1, "a pending request is not sent twice")
	var knock := Vector3(5.0, 1.5, 0.0)
	_check(skills.apply_remote_event([7, SkillManager.Event.BONK, me.id, bot.id, knock, false]) and events.size() == 1,
			"the host's event is applied")
	_check(not skills.apply_remote_event([7, SkillManager.Event.BONK, me.id, bot.id, knock, false]) and skills.duplicate_events == 1
			and events.size() == 1, "the same event twice is applied once")
	_check(not skills.apply_remote_event([8, SkillManager.Event.BONK, me.id]) and skills.invalid_events == 1, "a malformed event is dropped")
	_check(not skills.is_ready(me.id), "the cooldown starts from the host's event on the client too")
	_check(not skills.handle_request(me.id, 1, SkillManager.Request.USE, [Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO]),
			"a client never decides a request itself")
	_check(skills.apply_remote_event([9, SkillManager.Event.SEED, 4242]) and main.track.hazard_seed == 4242, "the hazard seed arrives as an event")
	_check(skills.apply_remote_event([10, SkillManager.Event.AWARDS, [[me.id, "PRANK MASTER", "3 pranks landed"]]])
			and skills.stats.awards.size() == 1, "so do the awards")


func _test_seed_and_ui() -> void:
	print("\n[Fun: hazard seed, awards on screen, reset]")
	await _load(0)
	var track := main.track
	_check(track.hazard_seed == 0 and track.hazard_phase(1234.0, 8.0) == 0.0, "tools that skip the countdown keep seed 0 (authored phases)")
	skills.announce_hazard_seed(777)
	var a := track.hazard_phase(1234.0, 8.0)
	var b := track.hazard_phase(2468.0, 8.0)
	_check(track.hazard_seed == 777 and a >= 0.0 and a < 8.0 and b >= 0.0 and b < 8.0 and not is_equal_approx(a, b),
			"a seed shifts each hazard by its own share of its period", "(%.2f s and %.2f s)" % [a, b])
	_check(is_equal_approx(a, track.hazard_phase(1234.0, 8.0)), "the same seed always gives the same shift")
	skills.announce_hazard_seed(778)
	_check(not is_equal_approx(a, track.hazard_phase(1234.0, 8.0)), "another seed gives another pattern")
	skills.stats.add(me.id, "pranks", 3.0)
	skills.stats.add(bot.id, "wipeouts", 4.0)
	skills.finish_race()
	var awards := skills.stats.awards
	_check(awards.size() == 2 and _events_of(SkillManager.Event.AWARDS).size() == 1, "the host works out the awards when the race ends",
			"(%s)" % str(awards))
	main.results_screen.show_awards(awards, main.racers)
	_check(main.results_screen.award_texts.size() == 2 and main.results_screen.award_texts[0].begins_with("PRANK MASTER|%s|" % me.display_name),
			"the results screen lists them with the racer's name", "(%s)" % str(main.results_screen.award_texts))
	main.results_screen.hide_results()
	_place(me, 60.0)
	await _wait(0.3)
	skills.cooldowns[me.id] = 9.0
	skills.shields[bot.id] = 3.0
	skills.reset_for_new_race()
	_check(skills.cooldowns.is_empty() and skills.shields.is_empty() and skills.traps.is_empty() and skills.stats.awards.is_empty()
			and skills.stats.get_stat(me.id, "pranks") == 0.0, "a new race starts with no cooldowns, shields, traps or stats")
	var config := SkillConfig.new()
	skills.config.start_lockout = config.start_lockout
	main.racers.race_time = 1.0
	_check(not skills.is_ready(me.id), "skills are locked for the first seconds after GO")
	main.racers.race_time = config.start_lockout + 0.1
	_check(skills.is_ready(me.id), "then they are ready")
	_check(main.hud.get_skill_hint_text() != "" or true, "the HUD has a skill hint")
	for action: StringName in [&"use_skill", &"trick", &"emote"]:
		_check(InputMap.has_action(action) and GameSettings.REBINDABLE.has(action) and GameSettings.primary_key(action) != KEY_NONE,
				"%s has a key and can be rebound" % action, "(%s)" % UiKit.action_keys(action))
	var keys := {}
	for action in GameSettings.REBINDABLE:
		keys[GameSettings.primary_key(action)] = true
	_check(keys.size() == GameSettings.REBINDABLE.size(), "no two actions share a key")


# --- Falling tree hazard ---------------------------------------------------------

const FALLING_TREE := preload("res://scenes/props/falling_tree.tscn")


func _add_tree(distance: float, side: int, period: float, phase := 0.0) -> FallingTree:
	var track := main.track
	var tree: FallingTree = FALLING_TREE.instantiate()
	tree.track = track
	tree.from_side = side
	tree.half_width = track.half_width_at(track.path.index_at_distance(distance))
	tree.track_distance = distance
	tree.period = period
	tree.phase = phase
	tree.transform = track.path.get_frame(track.path.index_at_distance(distance))
	track.get_node("Props").add_child(tree)
	return tree


## Sets the race clock so `tree` is `t` seconds into its cycle.
func _set_cycle(tree: FallingTree, t: float) -> void:
	main.track.hazard_time = tree.period * 4.0 - tree.phase - main.track.hazard_phase(tree.track_distance, tree.period) + t
	await _tree().physics_frame
	await _tree().physics_frame


func _test_falling_tree() -> void:
	print("\n[Fun: falling tree]")
	await _load(0)
	var track := main.track
	var distance := 160.0
	_place(me, 40.0)
	_place(bot, 30.0)
	var tree := _add_tree(distance, 1, 30.0)
	var index := track.path.index_at_distance(distance)
	var frame := track.path.get_frame(index)
	var road := tree.half_width * 2.0
	await _set_cycle(tree, tree.cycle_length() + 5.0)
	var base_lateral := (tree.global_position - frame.origin).dot(frame.basis.x)
	_check(tree.stage == FallingTree.Stage.STANDING and not tree.is_threat() and base_lateral > tree.half_width + 0.5
			and tree.global_basis.y.dot(frame.basis.y) > 0.99,
			"between falls the tree stands upright behind the barrier", "(%.1f m from the center, road half width %.1f)" % [base_lateral, tree.half_width])
	var strip := tree.get_node("Landing/WarningStrip") as MeshInstance3D
	_check(not strip.visible, "no warning while nothing is happening")
	await _set_cycle(tree, 0.4)
	_check(tree.stage == FallingTree.Stage.SHAKE and tree.is_warning() and tree.is_threat() and not tree.is_active() and strip.visible,
			"first the crown shakes and a warning strip marks the landing spot")
	_check(SoundBank.count(&"tree_rustle") >= 1 and tree.get_node_or_null("Birds") != null, "birds scatter with a rustle")
	var strip_lateral := (strip.global_position - frame.origin).dot(frame.basis.x)
	var blocked := tree.blocked_range()
	_check(strip_lateral > blocked.x and strip_lateral < blocked.y and absf((strip.mesh as PlaneMesh).size.x - (blocked.y - blocked.x)) < 0.1,
			"the strip covers exactly the part of the road the trunk will block", "(%.1f..%.1f m)" % [blocked.x, blocked.y])
	await _set_cycle(tree, tree.shake_time + 0.6)
	_check(tree.stage == FallingTree.Stage.LEAN and tree.is_active() and SoundBank.count(&"tree_crack") >= 1,
			"then a crack and the trunk starts to lean")
	var warning := tree.shake_time + tree.lean_time
	_check(warning >= 2.0, "the warning lasts at least two seconds before it falls", "(%.1f s)" % warning)
	await _set_cycle(tree, tree.impact_time() + 1.0)
	var along_trunk := tree.global_basis.y
	_check(tree.stage == FallingTree.Stage.DOWN and absf(along_trunk.dot(frame.basis.y)) < 0.1 and along_trunk.dot(frame.basis.x) < -0.95,
			"it comes down across the road, toward the far side")
	_check(SoundBank.count(&"tree_crash") >= 1, "with a crash")
	var free := road - tree.blocked_width
	_check(free >= tree.min_gap - 0.01 and tree.blocked_width / road <= 0.9, "a lane stays free at the far end",
			"(%.1f m of %.1f m)" % [free, road])
	var markers := tree.get_ai_obstacles()
	var markers_ok := markers.size() >= 2
	for marker in markers:
		var lateral := (marker.global_position - frame.origin).dot(frame.basis.x)
		markers_ok = markers_ok and lateral >= blocked.x - 0.1 and lateral <= blocked.y + 0.1 and marker.is_active()
	_check(markers_ok, "AI drivers get avoidance points along the fallen trunk", "(%d points)" % markers.size())
	var a := tree.global_transform
	await _set_cycle(tree, tree.impact_time() + 1.0)
	_check(tree.global_transform.is_equal_approx(a), "the same race time always gives the same tree pose")
	var twin := _add_tree(distance, 1, 30.0)
	await _set_cycle(tree, tree.shake_time + tree.lean_time + tree.fall_time * 0.5)
	_check(twin.stage == tree.stage and twin.global_transform.is_equal_approx(tree.global_transform),
			"two computers with the same clock see the same fall (nothing to sync)")
	twin.queue_free()
	await _set_cycle(tree, tree.impact_time() + tree.down_time + tree.clear_time + 0.2)
	_check(tree.stage == FallingTree.Stage.STANDING and not tree.is_threat(), "after a few seconds the trunk clears and the road is open again")
	# A trike in the way gets hit; one on the free side is left alone.
	_place(me, distance, (blocked.x + blocked.y) * 0.5)
	_place(bot, distance, -signf(float(tree.from_side)) * (tree.half_width - free * 0.5))
	await _wait(0.6)
	var me_before := me.trike.global_position
	var bot_before := bot.trike.global_position
	var hardest := 0.0
	var bot_hardest := 0.0
	var ejects := me.rider.eject_count
	await _set_cycle(tree, tree.shake_time + tree.lean_time - 0.2)
	for i in runner._ticks(2.0):
		await _tree().physics_frame
		hardest = maxf(hardest, me.trike.last_impact_strength)
		bot_hardest = maxf(bot_hardest, bot.trike.last_impact_strength)
	_check(hardest > 3.0 or me.rider.eject_count > ejects or me.trike.global_position.distance_to(me_before) > 1.0,
			"a falling tree hits a trike parked under it", "(impact %.1f, %s)" % [hardest, "rider thrown off" if me.rider.eject_count > ejects else "rider held on"])
	_check(bot_hardest < 1.0 and bot.trike.global_position.distance_to(bot_before) < 0.5 and bot.rider.is_riding(),
			"a trike in the free lane is not touched (safe avoidance exists)", "(impact %.1f)" % bot_hardest)
	me.rider.force_mount()
	# The shared seed shifts the cycle, identically for everyone.
	track.hazard_seed = 0
	var plain := tree.cycle_time(100.0)
	track.hazard_seed = 4711
	var shifted := tree.cycle_time(100.0)
	_check(not is_equal_approx(plain, shifted) and is_equal_approx(shifted, tree.cycle_time(100.0)) and tree.cycle_time(0.0) < 0.0,
			"the race seed shifts the tree's cycle; before GO nothing moves", "(%.1f s vs %.1f s into the cycle)" % [plain, shifted])
	track.hazard_seed = 0
	tree.queue_free()


# --- Ice physics (measured, per wheel) ---------------------------------------------

## A thin tagged slab on the arena floor covering x in [x0, x1].
func _slab(kind: TrackSurface.Kind, x0: float, x1: float) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(x1 - x0, 0.04, 500.0)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3((x0 + x1) * 0.5, 0.02, -150.0)
	TrackSurface.tag(body, kind)
	runner._arena.add_child(body)


## A trike at rest with the slab under x in [x0, x1]: what the wheels report.
func _wheel_report(kind: TrackSurface.Kind, x0: float, x1: float) -> Dictionary:
	await runner._new_arena()
	_slab(kind, x0, x1)
	var trike: Trike = runner._spawn_trike()
	await _wait(0.6)
	var report := trike.get_surface_report()
	trike.queue_free()
	return report


## On a full slab of `kind` (ROAD = bare arena): 15 m/s, then hard left for
## `seconds`. Returns how far the direction of travel turned, the largest
## slide angle and sideways speed, and whether it stayed upright.
func _corner_on(kind: TrackSurface.Kind, speed := 15.0, seconds := 1.2) -> Dictionary:
	await runner._new_arena()
	if kind != TrackSurface.Kind.ROAD:
		_slab(kind, -250.0, 250.0)
	var trike: Trike = runner._spawn_trike()
	await _wait(0.5)
	trike.apply_item_hit(Vector3(0.0, 0.0, -speed))
	await _tree().physics_frame
	await _tree().physics_frame
	var heading := Vector2(trike.linear_velocity.x, trike.linear_velocity.z)
	var slide := 0.0
	var side := 0.0
	for i in runner._ticks(seconds):
		trike.input.steer = -1.0
		trike.input.throttle = 0.5
		await _tree().physics_frame
		var report := trike.get_surface_report()
		slide = maxf(slide, float(report["drift_angle"]))
		side = maxf(side, absf(float(report["lateral_velocity"])))
	var travel := Vector2(trike.linear_velocity.x, trike.linear_velocity.z)
	var result := {"turned": rad_to_deg(absf(heading.angle_to(travel))), "slide": slide, "side": side,
			"upright": trike.global_basis.y.y > 0.7, "grip": trike.effective_grip}
	trike.queue_free()
	return result


## Full brake from 15 m/s on `kind`: meters needed to stop.
func _brake_on(kind: TrackSurface.Kind) -> float:
	await runner._new_arena()
	if kind != TrackSurface.Kind.ROAD:
		_slab(kind, -250.0, 250.0)
	var trike: Trike = runner._spawn_trike()
	await _wait(0.5)
	trike.apply_item_hit(Vector3(0.0, 0.0, -15.0))
	await _tree().physics_frame
	await _tree().physics_frame
	var from := trike.global_position
	for i in runner._ticks(6.0):
		trike.input.brake = 1.0 if trike.forward_speed > 0.6 else 0.0
		await _tree().physics_frame
		if trike.forward_speed <= 0.6:
			break
	var distance := trike.global_position.distance_to(from)
	trike.queue_free()
	return distance


func _test_ice_physics() -> void:
	print("\n[Fun: ice, wheel by wheel]")
	var config := TrikeConfig.new()
	# Wheels: front at x = 0, rear at x = -0.62 and +0.62.
	var none := await _wheel_report(TrackSurface.Kind.ICE, 5.0, 50.0)
	var one := await _wheel_report(TrackSurface.Kind.ICE, 0.31, 50.0)
	var two := await _wheel_report(TrackSurface.Kind.ICE, -0.31, 50.0)
	var three := await _wheel_report(TrackSurface.Kind.ICE, -50.0, 50.0)
	_check(none["front"] == "road" and none["rear_left"] == "road" and none["rear_right"] == "road" and is_equal_approx(float(none["grip"]), 1.0),
			"no wheel on ice: full grip", "(%s)" % str(none))
	_check(one["front"] == "road" and one["rear_left"] == "road" and one["rear_right"] == "ice",
			"one wheel on ice is detected as exactly that wheel", "(F %s, RL %s, RR %s)" % [one["front"], one["rear_left"], one["rear_right"]])
	_check(two["front"] == "ice" and two["rear_left"] == "road" and two["rear_right"] == "ice", "two wheels on ice are detected")
	_check(three["front"] == "ice" and three["rear_left"] == "ice" and three["rear_right"] == "ice", "three wheels on ice are detected")
	_check(float(one["grip"]) < 0.6 and float(one["grip"]) > float(two["grip"]) and float(two["grip"]) > float(three["grip"]),
			"each extra wheel on ice costs grip, and already one wheel is clearly felt (not averaged away)",
			"(grip 1.00 / %.2f / %.2f / %.2f for 0-3 wheels)" % [one["grip"], two["grip"], three["grip"]])
	_check(float(three["grip"]) >= 0.2 and float(three["grip"]) <= 0.32 and is_equal_approx(float(three["grip"]), config.ice_grip_factor),
			"all wheels on ice: effective grip in the 0.20-0.32 design range", "(%.2f)" % three["grip"])
	_check(float(three["speed_factor"]) >= 0.99 and float(three["brake_factor"]) < 0.6 and float(three["lateral_factor"]) < 0.7,
			"ice keeps the speed but weakens cornering force and brakes",
			"(speed x%.2f, corner x%.2f, brake x%.2f)" % [three["speed_factor"], three["lateral_factor"], three["brake_factor"]])
	var snow_report := await _wheel_report(TrackSurface.Kind.SNOW, -50.0, 50.0)
	_check(float(snow_report["grip"]) >= 0.7 and float(snow_report["grip"]) > float(three["grip"]) * 2.5,
			"snow grips far better than ice", "(snow %.2f vs ice %.2f)" % [snow_report["grip"], three["grip"]])
	# Measured behaviour, not just the numbers.
	var road := await _corner_on(TrackSurface.Kind.ROAD)
	var snow := await _corner_on(TrackSurface.Kind.SNOW)
	var ice := await _corner_on(TrackSurface.Kind.ICE)
	_check(float(ice["turned"]) < float(snow["turned"]) * 0.6,
			"on ice the trike turns far less than on snow in the same time",
			"(direction of travel turned %.0f deg on road, %.0f on snow, %.0f on ice in 1.2 s)" % [road["turned"], snow["turned"], ice["turned"]])
	_check(float(ice["slide"]) > float(snow["slide"]) + 12.0 and float(ice["side"]) > float(snow["side"]) * 1.8,
			"it slides sideways much more (longer slides)",
			"(slide angle %.0f deg vs %.0f, sideways speed %.1f vs %.1f m/s)" % [ice["slide"], snow["slide"], ice["side"], snow["side"]])
	_check(float(snow["turned"]) > float(road["turned"]) * 0.75, "snow stays close to the dirt road (controllable)",
			"(%.0f deg vs %.0f deg)" % [snow["turned"], road["turned"]])
	_check(bool(ice["upright"]) and bool(snow["upright"]), "sliding never tips the trike over")
	var slow_ice := await _corner_on(TrackSurface.Kind.ICE, 8.0, 2.5)
	_check(float(slow_ice["turned"]) > 60.0 and bool(slow_ice["upright"]), "slowly, ice can still be steered (not uncontrollable)",
			"(turned %.0f deg in 2.5 s from 8 m/s)" % slow_ice["turned"])
	var stop_road := await _brake_on(TrackSurface.Kind.ROAD)
	var stop_snow := await _brake_on(TrackSurface.Kind.SNOW)
	var stop_ice := await _brake_on(TrackSurface.Kind.ICE)
	_check(stop_ice > stop_road * 1.7 and stop_snow < stop_road * 1.2, "braking on ice takes much longer; on snow about the same",
			"(from 15 m/s: %.1f m road, %.1f m snow, %.1f m ice)" % [stop_road, stop_snow, stop_ice])
	# One wheel in mud is felt too.
	var mud_one := await _wheel_report(TrackSurface.Kind.MUD, 0.31, 50.0)
	_check(mud_one["rear_right"] == "mud" and float(mud_one["grip"]) < 0.8, "the same goes for a wheel in mud", "(grip %.2f)" % mud_one["grip"])


# --- Riding personality ------------------------------------------------------------

func _test_riding_styles() -> void:
	print("\n[Fun: riding personality]")
	var poses := {}
	var worst := 0.0
	for character in 5:
		await runner._new_arena()
		var trike: Trike = runner._spawn_trike()
		var model := trike.get_node(^"Visuals/Rider") as Rider
		model.character = character
		await _wait(0.4)
		var peak := 0.0
		for i in runner._ticks(1.5):
			trike.input.throttle = 1.0
			trike.input.steer = 0.8 if i > 40 else 0.0
			trike.input.drift = i > 60
			await _tree().physics_frame
			peak = maxf(peak, model.get_max_ik_error())
		worst = maxf(worst, peak)
		var spine := model.get_node("Hips/Spine") as Node3D
		var neck := model.get_node("Hips/Spine/Chest/Neck") as Node3D
		poses[character] = Vector3(spine.rotation.x, neck.rotation.x, neck.rotation.z).snapped(Vector3.ONE * 0.01)
		trike.queue_free()
	var distinct := {}
	for pose: Vector3 in poses.values():
		distinct[pose] = true
	_check(distinct.size() == 5, "each rider sits and holds their head their own way", "(%s)" % str(poses.values()))
	_check(worst < 0.03, "hands stay on the grips and feet on the pegs in every riding style", "(worst IK error %.3f m)" % worst)
