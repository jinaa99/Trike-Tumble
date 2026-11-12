extends RefCounted
## Item system tests (final-demo milestone 07): boxes, roll, inventory,
## activation, the four items, host validation, duplicates and event sync.
## Run as part of tests/test_runner.gd (`-- --only=items` for this group).

const MAIN_SCENE := preload("res://scenes/main/main.tscn")
const MUD := ItemKind.Kind.MUD_BOMB
const PUNCH := ItemKind.Kind.SPRING_PUNCH
const TURBO := ItemKind.Kind.TURBO_BOTTLE
const BANANA := ItemKind.Kind.BANANA_PEEL

var runner: Node
var main: RaceSession
var items: ItemManager
var me: Racer
var bot: Racer
var events: Array = []


func _init(test_runner: Node) -> void:
	runner = test_runner


func run() -> void:
	_test_roll()
	await _test_pickup_while_driving()
	await _test_inventory_and_respawn()
	await _test_turbo()
	await _test_mud_bomb()
	await _test_banana_peel()
	await _test_spring_punch()
	await _test_host_validation()
	await _test_event_sync()
	await _free_race()


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


## Test track race: the local player (id 1) and one AI racer (id 2), both
## driven by the test, racing from the first tick. `tweak` edits a copy of
## the item config before anything happens.
func _load(tweak := Callable(), authoritative := true) -> void:
	await _free_race()
	await runner._new_arena()
	main = MAIN_SCENE.instantiate()
	main.ai_racer_count = 1
	main.skip_countdown = true
	runner.add_child(main)
	main.trike.input_source = null
	main.rider.input_source = null
	items = main.items
	items.config = items.config.duplicate()
	if tweak.is_valid():
		tweak.call(items.config)
	items.authoritative = authoritative
	me = main.racers.get_racer(1)
	bot = main.racers.get_racer(2)
	bot.get_ai_driver().active = false
	bot.trike.input_source = null
	bot.rider.input_source = null
	events = []
	items.event_applied.connect(func(event: Array) -> void: events.append(event))
	await _wait(0.6)


## Frame `distance` m along the test track, `lateral` m right of center.
func _spot(distance: float, lateral := 0.0, up := 0.8) -> Transform3D:
	var index := main.track.path.index_at_distance(distance)
	return main.track.path.get_frame(index).translated_local(Vector3(lateral, up, 0.0))


func _place(racer: Racer, distance: float, lateral := 0.0) -> void:
	racer.trike.teleport(_spot(distance, lateral), false)
	racer.progress.reset(main.track.path.index_at_distance(distance))


func _events_of(type: ItemManager.Event) -> Array:
	return events.filter(func(e: Array) -> bool: return e[1] == type)


func _use(racer: Racer) -> void:
	racer.trike.input.use_item_pressed = true
	await _tree().physics_frame
	await _tree().physics_frame


func _yaw_rate(trike: Trike) -> float:
	return absf(trike.angular_velocity.dot(trike.global_basis.y))


# --- Tests --------------------------------------------------------------------

func _test_roll() -> void:
	print("\n[Items: random roll]")
	var config := ItemConfig.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var leader := {}
	var last := {}
	for i in 4000:
		var a := ItemRoll.roll(rng, config, 1, 5)
		var b := ItemRoll.roll(rng, config, 5, 5)
		leader[a] = leader.get(a, 0) + 1
		last[b] = last.get(b, 0) + 1
	_check(leader.size() == 4 and last.size() == 4, "every item can come out of a box", "(leader %s, last %s)" % [leader, last])
	_check(leader[BANANA] > last[BANANA] and last[TURBO] > 2 * leader[TURBO],
			"the roll favors the back of the field (more turbos), the leader gets more bananas",
			"(turbo %d vs %d, banana %d vs %d)" % [last[TURBO], leader[TURBO], leader[BANANA], last[BANANA]])
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 99
	var sequence: Array = []
	for i in 12:
		sequence.append(ItemRoll.roll(rng2, config, 3, 5))
	var distinct := {}
	for kind: int in sequence:
		distinct[kind] = true
	_check(distinct.size() >= 3, "consecutive boxes give random, varied items", "(%s)" % str(sequence))


func _test_pickup_while_driving() -> void:
	print("\n[Items: pickup while driving]")
	await _load()
	var box := items.add_box(_spot(70.0, 0.0, 1.0))
	var pilot := TrackAutopilot.new(main.track, me.trike)
	var speed_before := 0.0
	var speed_at_pickup := -1.0
	var min_after := INF
	var got_at := -1.0
	var t := 0.0
	while t < 7.0:
		pilot.drive()
		await _tree().physics_frame
		t += 1.0 / 60.0
		if speed_at_pickup < 0.0:
			speed_before = me.trike.linear_velocity.length()
			if ItemKind.is_valid(me.held_item):
				speed_at_pickup = speed_before
				got_at = t
		elif t < got_at + 0.5:
			min_after = minf(min_after, me.trike.linear_velocity.length())
		else:
			break
	_check(ItemKind.is_valid(me.held_item) and not box.active, "driving through a box collects it",
			"(%s)" % ItemKind.display_name(me.held_item))
	_check(speed_at_pickup > 12.0, "collected at full speed: no stopping needed", "(%.1f m/s)" % speed_at_pickup)
	_check(min_after > speed_at_pickup - 1.0, "the box doesn't slow the trike down",
			"(lowest %.1f m/s in the next 0.5 s)" % min_after)
	_check(_events_of(ItemManager.Event.BOX_TAKEN).size() == 1, "exactly one pickup event for one box")
	await _tree().process_frame
	_check(main.hud.get_item_text() == ItemKind.display_name(me.held_item), "the HUD shows the held item",
			"(%s)" % main.hud.get_item_text())
	_check(items.sounds.played.has(ItemSounds.Sound.PICKUP), "pickup plays the pickup sound")
	_check(main.hud.get_message_text().begins_with("+ "), "pickup feedback message", "(%s)" % main.hud.get_message_text())
	_check(main.hud.get_item_hint_text().contains("[Q]"), "use item is on Q", "(%s)" % main.hud.get_item_hint_text())


func _test_inventory_and_respawn() -> void:
	print("\n[Items: one item, no overwrite, respawn]")
	await _load(func(c: ItemConfig) -> void:
		c.box_respawn_delay = 1.0
		c.box_respawn_clearance = 3.5)
	var first := items.add_box(_spot(40.0, 0.0, 1.0))
	var second := items.add_box(_spot(40.0, 4.0, 1.0))
	_place(me, 40.0)
	await _wait(0.2)
	var held := me.held_item
	_check(ItemKind.is_valid(held) and not first.active, "a racer standing in a box gets it")
	_place(me, 40.0, 4.0)
	await _wait(0.3)
	_check(me.held_item == held and second.active, "a second box never overwrites the held item (it stays for others)")
	_check(main.hud.get_message_text().contains("HANDS FULL"), "the player is told to use the item first",
			"(%s)" % main.hud.get_message_text())
	# Parked on the first box: it must not respawn inside the trike.
	_place(me, 40.0)
	await _wait(1.6)
	_check(not first.active, "a box doesn't respawn while a trike sits on it")
	_place(me, 70.0)
	await _wait(0.3)
	_check(first.active, "the box respawns once the spot is clear", "(after %.1f s)" % items.config.box_respawn_delay)
	_check(_events_of(ItemManager.Event.BOX_RESPAWNED).size() == 1, "one respawn event")
	# Not while on foot.
	var third := items.add_box(_spot(100.0, 0.0, 1.0))
	main.rider.eject()
	me.held_item = ItemKind.Kind.NONE
	me.trike.teleport(_spot(100.0), false)
	await _wait(0.3)
	_check(third.active and me.held_item == ItemKind.Kind.NONE, "an empty trike (rider off) collects nothing")
	main.rider.force_mount()


func _test_turbo() -> void:
	print("\n[Items: turbo bottle]")
	await _load()
	items.grant_item(me, TURBO)
	await _use(me)
	_check(me.held_item == TURBO, "no use right after getting it (use delay)")
	await _wait(items.config.use_delay)
	await _use(me)
	_check(me.held_item == ItemKind.Kind.NONE and me.trike.boost_time > items.config.turbo_duration - 0.1,
			"Q uses the item: turbo boost starts", "(boost %.2f s)" % me.trike.boost_time)
	var pilot := TrackAutopilot.new(main.track, me.trike)
	pilot.target_speed = 60.0
	var top := 0.0
	var boost_end := -1.0
	var t := 0.0
	while t < 3.5:
		pilot.drive()
		await _tree().physics_frame
		t += 1.0 / 60.0
		top = maxf(top, me.trike.forward_speed)
		if boost_end < 0.0 and me.trike.boost_time <= 0.0:
			boost_end = t
	_check(absf(boost_end - items.config.turbo_duration) < 0.1, "turbo lasts its configured time",
			"(%.2f s, config %.2f s)" % [boost_end, items.config.turbo_duration])
	_check(top > me.trike.config.max_speed * 0.8, "turbo speeds the trike up", "(%.1f m/s)" % top)
	await _use(me)
	_check(_events_of(ItemManager.Event.TURBO_USED).size() == 1, "an item is used once (empty hands do nothing)")
	items.grant_item(me, TURBO)
	main.rider.eject()
	await _wait(0.5)
	me.trike.input.use_item_pressed = true
	await _wait(0.1)
	_check(me.held_item == TURBO, "no item use while off the trike")
	main.rider.force_mount()


func _test_mud_bomb() -> void:
	print("\n[Items: mud bomb]")
	await _load(func(c: ItemConfig) -> void:
		c.mud_patch_duration = 3.0
		c.mud_owner_grace = 0.0)
	_place(me, 30.0)
	_place(bot, 48.0)
	await _wait(0.5)
	items.grant_item(me, MUD)
	await _wait(0.4)
	await _use(me)
	_check(items.bombs.size() == 1, "a mud bomb is thrown as a projectile")
	var flew := 0
	while items.bombs.size() > 0 and flew < 200:
		await _tree().physics_frame
		flew += 1
	var landed := _events_of(ItemManager.Event.BOMB_LANDED)
	_check(landed.size() == 1 and int(landed[0][4]) == bot.id, "the bomb hits the racer ahead (projectile collision)",
			"(after %.2f s)" % (flew / 60.0))
	_check(bot.trike.slip_time > 0.0 and items.is_immune(bot.id), "a direct hit makes the victim slip (and briefly immune)")
	_check(items.patches.size() == 1, "the bomb leaves a mud patch")
	_check(bot.rider.is_riding(), "a mud bomb never throws the rider off")
	# Driving into the patch: slippery while inside.
	var patch: MudPatch = items.patches.values()[0]
	me.trike.teleport(Transform3D(me.trike.global_basis, patch.global_position + Vector3.UP * 0.8), false)
	me.progress.reset(main.track.path.find_nearest(patch.global_position))
	await _wait(0.2)
	_check(me.trike.slip_time > 0.0, "a trike in the mud patch slips")
	var age := items.config.mud_patch_duration - patch.time_left
	await _wait(patch.time_left - 0.3)
	_check(items.patches.size() == 1, "the mud patch is still there shortly before its time is up",
			"(%.1f s left)" % patch.time_left)
	await _wait(0.5)
	_check(items.patches.is_empty(), "the mud patch dries up after its duration", "(%.1f s)" % items.config.mud_patch_duration)
	await _wait(0.5)
	_check(me.trike.slip_time == 0.0, "the slipperiness ends with the patch")
	# A throw with nobody ahead lands on the road.
	items.config.mud_owner_grace = 3.0
	_place(bot, 200.0)
	_place(me, 30.0)
	await _wait(0.4)
	items.grant_item(me, MUD)
	await _wait(0.4)
	await _use(me)
	await _wait(1.5)
	landed = _events_of(ItemManager.Event.BOMB_LANDED)
	var spot: Vector3 = landed[-1][3]
	var along := (spot - me.trike.global_position).dot(-me.trike.global_basis.z)
	_check(landed.size() == 2 and int(landed[-1][4]) == 0 and items.patches.size() == 1 and along > 8.0,
			"a missed bomb splats on the road ahead (avoidable puddle)", "(%.0f m ahead)" % along)
	var own: MudPatch = items.patches.values()[0]
	me.trike.teleport(Transform3D(me.trike.global_basis, own.global_position + Vector3.UP * 0.8), false)
	me.progress.reset(main.track.path.find_nearest(own.global_position))
	await _wait(0.2)
	var spared := me.trike.slip_time == 0.0
	_place(bot, main.track.path.find_nearest(own.global_position) * main.track.path.spacing)
	bot.trike.teleport(Transform3D(bot.trike.global_basis, own.global_position + Vector3(1.0, 0.8, 0.0)), false)
	await _wait(0.2)
	_check(spared and bot.trike.slip_time > 0.0, "the thrower isn't caught by its own fresh puddle, others are",
			"(grace %.0f s)" % items.config.mud_owner_grace)


func _test_banana_peel() -> void:
	print("\n[Items: banana peel]")
	await _load()
	_place(me, 60.0)
	await _wait(0.5)
	items.grant_item(me, BANANA)
	await _wait(0.4)
	await _use(me)
	_check(items.peels.size() == 1, "a banana peel is dropped")
	var peel: BananaPeel = items.peels.values()[0]
	var behind := (peel.global_position - me.trike.global_position).dot(me.trike.global_basis.z)
	_check(behind > 1.5 and absf(peel.global_position.y - (me.trike.global_position.y - 0.5)) < 1.0,
			"it lies on the road behind the trike", "(%.1f m behind)" % behind)
	await _wait(0.5)
	_check(items.peels.size() == 1, "the dropper doesn't slip on a fresh peel")
	# The other racer drives over it.
	_place(bot, 35.0)
	me.trike.teleport(_spot(120.0), false)
	me.progress.reset(main.track.path.index_at_distance(120.0))
	await _wait(0.4)
	var pilot := TrackAutopilot.new(main.track, bot.trike)
	pilot.lateral_offset = main.track.path.rights[main.track.path.find_nearest(peel.global_position)].dot(
			peel.global_position - main.track.path.points[main.track.path.find_nearest(peel.global_position)])
	var speed_before := 0.0
	var max_yaw := 0.0
	var hit_at := -1
	for i in 360:
		if hit_at < 0:
			pilot.drive()
			speed_before = bot.trike.linear_velocity.length()
		else:
			bot.trike.input.clear()
			max_yaw = maxf(max_yaw, _yaw_rate(bot.trike))
			if i > hit_at + 30:
				break
		await _tree().physics_frame
		if hit_at < 0 and not _events_of(ItemManager.Event.BANANA_HIT).is_empty():
			hit_at = i
	var hits := _events_of(ItemManager.Event.BANANA_HIT)
	_check(hits.size() == 1 and int(hits[0][3]) == bot.id and items.peels.is_empty(), "another racer slips on it and it's gone")
	_check(max_yaw > 3.0 and bot.trike.linear_velocity.length() < speed_before * 0.8,
			"slipping spins the trike out and costs speed", "(spin %.1f rad/s, %.1f → %.1f m/s)" % [max_yaw, speed_before,
			bot.trike.linear_velocity.length()])
	_check(bot.rider.is_riding(), "a banana never throws the rider off")
	await _wait(1.5)
	_check(bot.trike.slip_time == 0.0 and bot.trike.global_basis.y.y > 0.8, "the spin-out ends quickly (no long stun)")
	# Most peels on the track at once.
	for i in items.config.banana_max_count + 3:
		items.grant_item(me, BANANA)
		me.item_hold_time = 1.0
		await _use(me)
	_check(items.peels.size() == items.config.banana_max_count, "peels are capped (oldest goes first)",
			"(%d)" % items.peels.size())


func _test_spring_punch() -> void:
	print("\n[Items: spring punch]")
	await _load(func(c: ItemConfig) -> void: c.hit_immunity = 0.5)
	# Beside, mid range: knocked sideways, stays on.
	_place(me, 60.0, -2.0)
	_place(bot, 61.0, 2.2)
	await _wait(0.8)
	var start := bot.trike.global_position
	items.grant_item(me, PUNCH)
	await _wait(0.4)
	await _use(me)
	await _wait(0.8)
	var punches := _events_of(ItemManager.Event.PUNCH)
	var knock: Vector3 = punches[0][4] if not punches.is_empty() else Vector3.ZERO
	var moved := bot.trike.global_position - start
	var sideways := moved.dot(bot.trike.global_basis.x)
	_check(punches.size() == 1 and int(punches[0][3]) == bot.id, "the punch hits the racer beside")
	_check(sideways > 1.5, "it knocks the opponent sideways (away from the attacker)", "(%.1f m, knock %.1f m/s)" % [sideways,
			Vector2(knock.x, knock.z).length()])
	_check(bot.rider.is_riding() and not bool(punches[0][5]), "a punch from a few meters doesn't throw the rider off",
			"(%.1f m/s < %.1f)" % [Vector2(knock.x, knock.z).length(), items.config.punch_eject_speed])
	_check(moved.length() < 6.0, "knockback is moderate", "(%.1f m)" % moved.length())
	# Point-blank: strong enough to eject.
	await _wait(0.5)
	_place(me, 90.0, -0.8)
	_place(bot, 90.0, 0.9)
	await _wait(0.6)
	items.grant_item(me, PUNCH)
	await _wait(0.4)
	await _use(me)
	await _wait(0.3)
	punches = _events_of(ItemManager.Event.PUNCH)
	_check(punches.size() == 2 and bool(punches[1][5]) and not bot.rider.is_riding() and bot.rider.eject_count == 1,
			"a point-blank punch is strong enough to throw the rider off")
	# Out of range: a miss, item gone, nobody moves.
	await _wait(2.5)
	bot.rider.force_mount()
	_place(me, 120.0)
	_place(bot, 140.0)
	await _wait(0.6)
	start = bot.trike.global_position
	items.grant_item(me, PUNCH)
	await _wait(0.4)
	await _use(me)
	await _wait(0.4)
	punches = _events_of(ItemManager.Event.PUNCH)
	_check(punches.size() == 3 and int(punches[2][3]) == 0 and me.held_item == ItemKind.Kind.NONE
			and bot.trike.global_position.distance_to(start) < 0.3, "out of range the punch misses (no unavoidable hits)")
	_check(main.hud.get_message_text() == "MISSED!", "the attacker sees the miss")
	# Immune right after a hit: no chain-stun.
	_place(bot, 121.0, 2.5)
	await _wait(0.6)
	items._immune[bot.id] = 2.0
	items.grant_item(me, PUNCH)
	await _wait(0.4)
	await _use(me)
	punches = _events_of(ItemManager.Event.PUNCH)
	_check(int(punches[-1][3]) == 0, "a racer just hit by an item can't be hit again at once")


## The host's checks: simultaneous pickups, duplicates, wrong data, far away.
func _test_host_validation() -> void:
	print("\n[Items: host validation and duplicates]")
	await _load()
	var box := items.add_box(_spot(200.0, 0.0, 1.0))
	_place(me, 197.0, -1.0)
	_place(bot, 197.0, 1.0)
	await _wait(0.4)
	# Both racers ask for the same box in the same tick (two players arriving
	# together): the first request wins, the second is denied.
	var first := items.handle_request(me.id, 100, ItemManager.Request.PICKUP, [box.box_id])
	var second := items.handle_request(bot.id, 100, ItemManager.Request.PICKUP, [box.box_id])
	_check(first and not second and ItemKind.is_valid(me.held_item) and bot.held_item == ItemKind.Kind.NONE,
			"simultaneous pickup: only one racer gets the box")
	_check(_events_of(ItemManager.Event.BOX_TAKEN).size() == 1, "one box, one pickup event")
	var held := me.held_item
	var again := items.handle_request(me.id, 100, ItemManager.Request.USE, [int(held), me.trike.global_position,
			-me.trike.global_basis.z, Vector3.ZERO])
	_check(not again and items.duplicate_requests == 1 and me.held_item == held, "a repeated request id is ignored")
	var wrong := items.handle_request(bot.id, 101, ItemManager.Request.USE, [int(TURBO), bot.trike.global_position,
			Vector3.FORWARD, Vector3.ZERO])
	_check(not wrong and bot.trike.boost_time == 0.0, "can't use an item you don't hold")
	var bogus := items.handle_request(bot.id, 102, ItemManager.Request.USE, ["x", 1, 2])
	var nan := items.handle_request(bot.id, 103, ItemManager.Request.USE, [int(TURBO), Vector3(NAN, 0, 0), Vector3.FORWARD,
			Vector3.ZERO])
	_check(not bogus and not nan, "malformed item requests are rejected")
	var far_box := items.add_box(_spot(400.0, 0.0, 1.0))
	var far := items.handle_request(bot.id, 104, ItemManager.Request.PICKUP, [far_box.box_id])
	_check(not far and far_box.active, "a pickup far from the box is refused")
	var no_box := items.handle_request(bot.id, 105, ItemManager.Request.PICKUP, [9999])
	_check(not no_box, "an unknown box id is refused")
	# Use twice in one go: the second has nothing left to use.
	me.item_hold_time = 1.0
	var pos := me.trike.global_position
	var used := items.handle_request(me.id, 106, ItemManager.Request.USE, [int(held), pos, -me.trike.global_basis.z, Vector3.ZERO])
	var twice := items.handle_request(me.id, 107, ItemManager.Request.USE, [int(held), pos, -me.trike.global_basis.z, Vector3.ZERO])
	_check(used and not twice, "an item can be used only once (no infinite use)")
	# Not before GO / after the race.
	main.racers.is_race_over = true
	var box2 := items.add_box(_spot(198.0, 0.0, 1.0))
	var late := items.handle_request(bot.id, 108, ItemManager.Request.PICKUP, [box2.box_id])
	_check(not late, "no pickups once the race is over")
	main.racers.is_race_over = false


## Events recorded on a host race applied to a separate client-mode race:
## both end up with the same items, boxes, peels and puddles, and repeated
## or malformed events are ignored.
func _test_event_sync() -> void:
	print("\n[Items: event sync host → client]")
	await _load()
	items.add_box(_spot(40.0, 0.0, 1.0))
	items.add_box(_spot(80.0, 0.0, 1.0))
	_place(me, 40.0)
	await _wait(0.3)
	var host_held := me.held_item
	items.grant_item(bot, BANANA)
	await _wait(0.4)
	await _use(bot)
	items.grant_item(bot, MUD)
	await _wait(0.4)
	await _use(bot)
	await _wait(1.5)
	var recorded: Array = events.duplicate(true)
	var host_state := _item_state()
	# The "client": the same race in client mode, fed only the host's events.
	await _load(Callable(), false)
	items.add_box(_spot(40.0, 0.0, 1.0))
	items.add_box(_spot(80.0, 0.0, 1.0))
	_place(me, 300.0)
	_place(bot, 330.0)
	await _wait(0.2)
	var box_requests := []
	items.send_request = func(racer_id: int, req_id: int, kind: int, data: Array) -> void:
		box_requests.append([racer_id, req_id, kind, data])
	for event: Array in recorded:
		items.apply_remote_event(event.duplicate(true))
		await _tree().physics_frame
	await _wait(0.2)
	var client_state := _item_state()
	_check(client_state == host_state, "the client shows the same items, boxes, peels and puddles as the host",
			"(%s)" % str(client_state))
	_check(me.held_item == host_held, "the client's HUD item matches the host's decision", "(%s)" % ItemKind.display_name(host_held))
	var before := items.events_applied
	for event: Array in recorded:
		items.apply_remote_event(event)
	items.apply_remote_event([999, 77])
	items.apply_remote_event("junk")
	_check(items.events_applied == before and items.duplicate_events == recorded.size() and items.invalid_events == 2,
			"repeated and malformed events are ignored")
	# A client never decides: driving into a box only sends a request.
	var box := items.add_box(_spot(330.0, 4.0, 1.0))
	me.held_item = ItemKind.Kind.NONE
	_place(me, 330.0, 4.0)
	await _wait(0.3)
	_check(box.active and me.held_item == ItemKind.Kind.NONE and box_requests.size() == 1
			and int(box_requests[0][2]) == ItemManager.Request.PICKUP, "a client only requests a pickup (once), the host decides",
			"(%d requests)" % box_requests.size())


func _item_state() -> Dictionary:
	var active: Array = []
	for box in items.boxes:
		active.append(box.active)
	var peel_spots: Array = []
	for peel: BananaPeel in items.peels.values():
		peel_spots.append(peel.global_position.snapped(Vector3.ONE * 0.01))
	var patch_spots: Array = []
	for patch: MudPatch in items.patches.values():
		patch_spots.append(patch.global_position.snapped(Vector3.ONE * 0.01))
	return {"held": [me.held_item, bot.held_item], "boxes": active, "peels": peel_spots, "patches": patch_spots,
			"bombs": items.bombs.size()}
