class_name ItemManager
extends Node3D
## Item boxes, held items and item effects for one race (node "Items" in
## the race scene).
##
## Authority (same rules offline and online, see docs/NETWORKING.md):
## - Each computer watches only the racers it simulates (its player; the
##   host also its AI). When one drives through a box, over a banana peel or
##   presses [use item], it sends a *request* (racer id, request id, kind,
##   data). Offline the request goes straight to handle_request().
## - The host (`authoritative`) validates every request: the racer is riding
##   and racing, the box is active, hands are empty, the item is really
##   held, the racer is plausibly where it claims, and the request id is new
##   (no duplicates). It rolls items, places peels, flies mud bombs, picks
##   punch targets and decides ejection, and respawns boxes.
## - Every decision becomes a numbered *event* applied once on every
##   computer (apply_remote_event ignores repeats). Physical effects are
##   applied by the victim's owner only (proxies are never simulated).
##
## Mud patches are areas: each owner makes its own trikes slippery inside one.

signal item_changed(racer: Racer, kind: ItemKind.Kind)
signal event_applied(event: Array)
## Something worth a HUD message happened to (or was done by) a racer.
signal feedback(racer: Racer, text: String)

enum Event { BOX_TAKEN, BOX_RESPAWNED, TURBO_USED, BANANA_DROPPED, BANANA_HIT, BOMB_THROWN, BOMB_LANDED, PUNCH }
enum Request { PICKUP, USE, TRAP_HIT }
## Event array sizes (seq and type included).
const EVENT_SIZES: Array[int] = [5, 3, 3, 5, 5, 6, 6, 6]
const EVENT_NAMES: Array[String] = ["BOX_TAKEN", "BOX_RESPAWNED", "TURBO_USED", "BANANA_DROPPED", "BANANA_HIT",
		"BOMB_THROWN", "BOMB_LANDED", "PUNCH"]
## Largest believable reported speed (m/s) and coordinate (m).
const MAX_SPEED := 80.0
const MAX_COORD := 20000.0

@export var config: ItemConfig
## 0 = random rolls; anything else makes rolls repeatable (tests).
@export var rng_seed := 0
## An unanswered request may be sent again after this long (s).
@export var pending_timeout := 1.0
## A trike moving more than this in one tick teleported (no swept pickups).
@export var teleport_step := 6.0
@export_flags_3d_physics var ground_mask := 1

var racers: RacerManager
var track: Track
## Host / offline: decides. Online clients: send requests, apply events.
var authoritative := true
## Online client: func(racer_id, req_id, kind, data) sends a request to the host.
var send_request := Callable()
## Online host: func(event) sends an event to every client.
var broadcast := Callable()
## Racer whose events get flat sounds and HUD feedback (the local player).
var local_racer_id := -1

var boxes: Array[ItemBox] = []
var bombs := {}
var patches := {}
var peels := {}
var last_event_seq := 0
var events_applied := 0
## Diagnostics (tests, network checks).
var denied_requests := 0
var duplicate_requests := 0
var duplicate_events := 0
var invalid_events := 0
var sounds: ItemSounds

var _rng := RandomNumberGenerator.new()
var _seq := 0
var _next_object_id := 1
var _clock := 0.0
var _respawn_at := {}
var _immune := {}
var _cooldown := {}
var _pending := {}
var _next_req := {}
var _last_req := {}
var _last_positions := {}


func _ready() -> void:
	if config == null:
		config = ItemConfig.new()
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	sounds = ItemSounds.new()
	sounds.name = "Sounds"
	add_child(sounds)


## Places the track's item boxes (Track.get_item_box_transforms()).
func setup(manager: RacerManager, for_track: Track) -> void:
	racers = manager
	track = for_track
	for xf in track.get_item_box_transforms():
		add_box(xf)


## Adds one box (maps do it through setup; tests directly). Ids are the
## order of creation, so every computer numbers the same boxes alike.
func add_box(xf: Transform3D) -> ItemBox:
	var box := ItemBox.new()
	box.box_id = boxes.size()
	box.name = "ItemBox%d" % box.box_id
	add_child(box)
	box.global_transform = Transform3D(Basis(), xf.origin)
	boxes.append(box)
	return box


func get_held(racer_id: int) -> ItemKind.Kind:
	var racer := racers.get_racer(racer_id) if racers else null
	return racer.held_item if racer else ItemKind.Kind.NONE


func is_immune(racer_id: int) -> bool:
	return float(_immune.get(racer_id, 0.0)) > 0.0


func get_active_box_count() -> int:
	return boxes.filter(func(box: ItemBox) -> bool: return box.active).size()


## Host only: hands an item to a racer without a box (tests, debugging).
func grant_item(racer: Racer, kind: ItemKind.Kind) -> bool:
	if not authoritative or racer == null or ItemKind.is_valid(racer.held_item) or not ItemKind.is_valid(kind):
		return false
	_emit([Event.BOX_TAKEN, -1, racer.id, kind])
	return true


## Race Again / Return to Lobby: empty hands, every box back, no bombs,
## puddles or peels. Event and request numbering keeps counting.
func reset_for_new_race() -> void:
	_respawn_at.clear()
	_immune.clear()
	_cooldown.clear()
	_pending.clear()
	_last_positions.clear()
	for box in boxes:
		box.set_active(true, false)
	for group: Dictionary in [bombs, patches, peels]:
		for node: Node in group.values():
			node.queue_free()
		group.clear()
	if racers:
		for racer in racers.get_racers():
			if racer.held_item != ItemKind.Kind.NONE:
				racer.held_item = ItemKind.Kind.NONE
				item_changed.emit(racer, racer.held_item)
			racer.item_hold_time = 0.0


# --- Tick -------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if racers == null:
		return
	_clock += delta
	for timers: Dictionary in [_immune, _cooldown]:
		for id: int in timers.keys():
			timers[id] = float(timers[id]) - delta
			if timers[id] <= 0.0:
				timers.erase(id)
	for racer in racers.get_racers():
		if ItemKind.is_valid(racer.held_item):
			racer.item_hold_time += delta
		if not racer.is_proxy and not racer.disconnected and is_instance_valid(racer.trike):
			_owner_tick(racer)
	_tick_objects(delta)
	if authoritative:
		_respawn_boxes()


func _items_live() -> bool:
	return racers.is_race_started and not racers.is_race_over


## May this racer pick up, use or be hit by items right now?
func _can_act(racer: Racer) -> bool:
	if racer == null or racer.disconnected or racer.finished or not is_instance_valid(racer.trike):
		return false
	if racer.trike.input_locked or not _items_live():
		return false
	return racer.rider.is_riding() if racer.rider else racer.trike.has_rider


## Owner side: what this computer's own racer touched or pressed.
func _owner_tick(racer: Racer) -> void:
	var trike := racer.trike
	var position := trike.global_position
	var last: Vector3 = _last_positions.get(racer.id, position)
	if last.distance_to(position) > teleport_step:
		last = position
	_last_positions[racer.id] = position
	var use := trike.input.use_item_pressed
	trike.input.use_item_pressed = false
	if not _can_act(racer):
		return
	for patch: MudPatch in patches.values():
		if patch.thrower_id == racer.id and patch.get_age() < config.mud_owner_grace:
			continue
		if patch.contains(position):
			trike.set_slippery(config.mud_linger, config.mud_grip_factor, config.mud_speed_factor)
	for box in boxes:
		if not box.active or _segment_distance(box.global_position, last, position) > config.box_pickup_radius:
			continue
		if ItemKind.is_valid(racer.held_item):
			# Never overwrite: the box stays for someone else.
			if racer.id == local_racer_id and not _is_pending(racer.id, Request.PICKUP, -2):
				_set_pending(racer.id, Request.PICKUP, -2, 2.0)
				feedback.emit(racer, "HANDS FULL · USE YOUR ITEM")
			continue
		if _cooldown.has(racer.id) or _is_pending(racer.id, Request.PICKUP, box.box_id):
			continue
		_set_pending(racer.id, Request.PICKUP, box.box_id)
		_request(racer, Request.PICKUP, [box.box_id])
		break
	if not is_immune(racer.id):
		for peel: BananaPeel in peels.values():
			if not _peel_armed_for(peel, racer.id) or _is_pending(racer.id, Request.TRAP_HIT, peel.peel_id):
				continue
			if _segment_distance(peel.global_position, last, position) <= config.banana_trigger_radius:
				_set_pending(racer.id, Request.TRAP_HIT, peel.peel_id)
				_request(racer, Request.TRAP_HIT, [peel.peel_id])
				break
	if use and ItemKind.is_valid(racer.held_item) and racer.item_hold_time >= config.use_delay \
			and not _is_pending(racer.id, Request.USE, 0):
		_set_pending(racer.id, Request.USE, 0)
		_request(racer, Request.USE, [int(racer.held_item), position, -trike.global_basis.z, trike.linear_velocity])
	elif use and not ItemKind.is_valid(racer.held_item) and racer.id == local_racer_id:
		sounds.play(ItemSounds.Sound.DENIED)


## Bombs fly (the host decides where they land), puddles dry, peels age.
func _tick_objects(delta: float) -> void:
	for bomb: MudBomb in bombs.values():
		bomb.step(delta)
		if authoritative:
			_resolve_bomb(bomb)
		elif bomb.age > config.mud_max_flight + 1.0:
			bomb.visible = false  # waits for the host's landing event
	for id: int in patches.keys():
		if not (patches[id] as MudPatch).tick(delta):
			(patches[id] as Node).queue_free()
			patches.erase(id)
	for id: int in peels.keys():
		var peel: BananaPeel = peels[id]
		peel.age += delta
		if peel.age > config.banana_lifetime:
			peel.queue_free()
			peels.erase(id)


# --- Requests (owner → host) ---------------------------------------------------

func _request(racer: Racer, kind: Request, data: Array) -> void:
	var req_id := int(_next_req.get(racer.id, 0)) + 1
	_next_req[racer.id] = req_id
	if authoritative:
		handle_request(racer.id, req_id, kind, data)
	elif send_request.is_valid():
		send_request.call(racer.id, req_id, kind, data)


## Host: validates and resolves one request. The caller (Net) has already
## checked that the sender owns `racer_id`. Returns true if it was granted.
func handle_request(racer_id: int, req_id: int, kind: int, data: Array) -> bool:
	if not authoritative:
		return false
	var racer := racers.get_racer(racer_id) if racers else null
	if racer == null or not _valid_request(kind, data):
		denied_requests += 1
		return false
	if req_id <= int(_last_req.get(racer_id, 0)):
		duplicate_requests += 1
		return false
	_last_req[racer_id] = req_id
	var granted := false
	match kind:
		Request.PICKUP:
			granted = _host_pickup(racer, int(data[0]))
		Request.USE:
			granted = _host_use(racer, int(data[0]), data[1], data[2], data[3])
		Request.TRAP_HIT:
			granted = _host_trap(racer, int(data[0]))
	if not granted:
		denied_requests += 1
	return granted


static func _valid_request(kind: int, data: Variant) -> bool:
	if not data is Array:
		return false
	var values: Array = data
	match kind:
		Request.PICKUP, Request.TRAP_HIT:
			return values.size() == 1 and values[0] is int
		Request.USE:
			if values.size() != 4 or not values[0] is int:
				return false
			for i in [1, 2, 3]:
				if not values[i] is Vector3 or not (values[i] as Vector3).is_finite():
					return false
			return (values[1] as Vector3).length() < MAX_COORD and (values[3] as Vector3).length() <= MAX_SPEED
	return false


func _host_pickup(racer: Racer, box_id: int) -> bool:
	if box_id < 0 or box_id >= boxes.size():
		return false
	var box := boxes[box_id]
	if not box.active or not _can_act(racer) or ItemKind.is_valid(racer.held_item) or _cooldown.has(racer.id):
		return false
	if racer.trike.global_position.distance_to(box.global_position) > config.plausible_distance:
		return false
	var kind := ItemRoll.roll(_rng, config, maxi(racer.position, 1), racers.get_racer_count())
	_respawn_at[box_id] = _clock + config.box_respawn_delay
	_emit([Event.BOX_TAKEN, box_id, racer.id, kind])
	return true


func _host_use(racer: Racer, kind: int, reported: Vector3, forward: Vector3, velocity: Vector3) -> bool:
	if kind != racer.held_item or not ItemKind.is_valid(kind) or not _can_act(racer):
		return false
	if racer.item_hold_time < config.use_delay * 0.5:
		return false
	# Trust the owner's (newer) position only if it matches what we see.
	var position := reported
	if position.distance_to(racer.trike.global_position) > config.plausible_distance:
		position = racer.trike.global_position
		velocity = racer.trike.get_motion_velocity()
	var flat := Vector3(forward.x, 0.0, forward.z)
	flat = flat.normalized() if flat.length() > 0.01 else -racer.trike.global_basis.z
	match kind:
		ItemKind.Kind.TURBO_BOTTLE:
			_emit([Event.TURBO_USED, racer.id])
		ItemKind.Kind.BANANA_PEEL:
			var drop := _ground_point(position - flat * config.banana_drop_distance)
			if drop == Vector3.INF:
				drop = _ground_point(position)
			if drop == Vector3.INF:
				drop = position
			_emit([Event.BANANA_DROPPED, racer.id, _new_object_id(), drop])
		ItemKind.Kind.MUD_BOMB:
			var origin := position + Vector3.UP * 1.3 + flat * 1.2
			var throw := velocity * config.mud_inherit_velocity + flat * config.mud_throw_speed + Vector3.UP * config.mud_throw_up_speed
			_emit([Event.BOMB_THROWN, racer.id, _new_object_id(), origin, throw])
		ItemKind.Kind.SPRING_PUNCH:
			var target := ItemRules.pick_punch_target(config, racer, position, flat, racers.get_racers(), is_immune)
			if target == null:
				_emit([Event.PUNCH, racer.id, 0, Vector3.ZERO, false])
			else:
				var speed := ItemRules.punch_speed(config, position.distance_to(target.trike.global_position))
				var knock := ItemRules.punch_velocity(config, position, target.trike, speed)
				_emit([Event.PUNCH, racer.id, target.id, knock, ItemRules.punch_ejects(config, speed)])
	return true


func _host_trap(racer: Racer, peel_id: int) -> bool:
	var peel: BananaPeel = peels.get(peel_id)
	if peel == null or not _can_act(racer) or is_immune(racer.id) or not _peel_armed_for(peel, racer.id):
		return false
	if racer.trike.global_position.distance_to(peel.global_position) > config.plausible_distance:
		return false
	_emit([Event.BANANA_HIT, peel_id, racer.id, 1 if _rng.randf() < 0.5 else -1])
	return true


## Host: a bomb hits the first riding trike it passes (not the thrower's),
## else the ground; it lands where it was after the longest flight.
func _resolve_bomb(bomb: MudBomb) -> void:
	if bomb.has_meta(&"landed"):
		return
	var from := bomb.previous_position
	var to := bomb.global_position
	for racer in racers.get_racers():
		if racer.id == bomb.thrower_id or not _can_act(racer) or is_immune(racer.id):
			continue
		# Chassis or rider: a bomb dropping onto the rider's head counts too.
		var body := racer.trike.global_position
		var head := body + racer.trike.global_basis.y * config.mud_rider_height
		if minf(_segment_distance(body, from, to), _segment_distance(head, from, to)) <= config.mud_hit_radius:
			bomb.set_meta(&"landed", true)
			var spot := _ground_point(racer.trike.global_position)
			_emit([Event.BOMB_LANDED, bomb.bomb_id, spot if spot != Vector3.INF else racer.trike.global_position, racer.id, true])
			return
	var hit := _ray(from, to)
	if not hit.is_empty():
		bomb.set_meta(&"landed", true)
		_emit([Event.BOMB_LANDED, bomb.bomb_id, hit["position"], 0, true])
	elif bomb.age > config.mud_max_flight:
		bomb.set_meta(&"landed", true)
		var spot := _ground_point(to)
		_emit([Event.BOMB_LANDED, bomb.bomb_id, spot if spot != Vector3.INF else to, 0, spot != Vector3.INF])


## Host: collected boxes come back after the delay, but never on top of a racer.
func _respawn_boxes() -> void:
	for box_id: int in _respawn_at.keys():
		if _clock < float(_respawn_at[box_id]):
			continue
		var box := boxes[box_id]
		var clear := true
		for racer in racers.get_racers():
			if racer.disconnected or not is_instance_valid(racer.trike):
				continue
			var near := racer.trike.global_position.distance_to(box.global_position) < config.box_respawn_clearance
			if racer.rider and racer.rider.get_rider_position().distance_to(box.global_position) < config.box_respawn_clearance:
				near = true
			clear = clear and not near
		if clear:
			_respawn_at.erase(box_id)
			_emit([Event.BOX_RESPAWNED, box_id])


# --- Events (host → everyone) -------------------------------------------------

func _emit(body: Array) -> void:
	_seq += 1
	var event := [_seq]
	event.append_array(body)
	_apply_event(event)
	if broadcast.is_valid():
		broadcast.call(event)


## Clients: an event from the host. Repeats and malformed events are ignored.
func apply_remote_event(event: Variant) -> bool:
	if not _valid_event(event):
		invalid_events += 1
		return false
	if int(event[0]) <= last_event_seq:
		duplicate_events += 1
		return false
	_apply_event(event)
	return true


static func _valid_event(event: Variant) -> bool:
	if not event is Array or (event as Array).size() < 2 or not event[0] is int or not event[1] is int:
		return false
	var type: int = event[1]
	return type >= 0 and type < EVENT_SIZES.size() and (event as Array).size() == EVENT_SIZES[type]


func _apply_event(event: Array) -> void:
	last_event_seq = maxi(last_event_seq, int(event[0]))
	events_applied += 1
	match int(event[1]):
		Event.BOX_TAKEN:
			_on_box_taken(int(event[2]), racers.get_racer(int(event[3])), int(event[4]) as ItemKind.Kind)
		Event.BOX_RESPAWNED:
			var box_id := int(event[2])
			if box_id >= 0 and box_id < boxes.size():
				boxes[box_id].set_active(true)
		Event.TURBO_USED:
			_on_turbo(racers.get_racer(int(event[2])))
		Event.BANANA_DROPPED:
			_on_banana_dropped(racers.get_racer(int(event[2])), int(event[3]), event[4])
		Event.BANANA_HIT:
			_on_banana_hit(int(event[2]), racers.get_racer(int(event[3])), float(event[4]))
		Event.BOMB_THROWN:
			_on_bomb_thrown(racers.get_racer(int(event[2])), int(event[3]), event[4], event[5])
		Event.BOMB_LANDED:
			_on_bomb_landed(int(event[2]), event[3], racers.get_racer(int(event[4])), bool(event[5]))
		Event.PUNCH:
			_on_punch(racers.get_racer(int(event[2])), racers.get_racer(int(event[3])), event[4], bool(event[5]))
	event_applied.emit(event)


func _on_box_taken(box_id: int, racer: Racer, kind: ItemKind.Kind) -> void:
	var where := racer.trike.global_position if racer and is_instance_valid(racer.trike) else Vector3.ZERO
	if box_id >= 0 and box_id < boxes.size():
		var box := boxes[box_id]
		box.set_active(false)
		where = box.global_position
		ItemVisuals.burst(self, where, ItemKind.color_of(kind), 12, 1.8)
	if racer == null:
		return
	racer.held_item = kind
	racer.item_hold_time = 0.0
	_clear_pending(racer.id, Request.PICKUP)
	item_changed.emit(racer, kind)
	_play(racer, ItemSounds.Sound.PICKUP, where)
	if racer.id == local_racer_id:
		feedback.emit(racer, "+ " + ItemKind.display_name(kind))


func _consume(racer: Racer) -> void:
	racer.held_item = ItemKind.Kind.NONE
	racer.item_hold_time = 0.0
	_cooldown[racer.id] = config.pickup_cooldown
	_clear_pending(racer.id, Request.USE)
	item_changed.emit(racer, racer.held_item)


func _on_turbo(racer: Racer) -> void:
	if racer == null:
		return
	_consume(racer)
	if _owns(racer):
		racer.trike.boost_time = maxf(racer.trike.boost_time, config.turbo_duration)
	ItemVisuals.burst(self, racer.trike.global_position, ItemKind.color_of(ItemKind.Kind.TURBO_BOTTLE), 14, 2.4)
	_play(racer, ItemSounds.Sound.TURBO, racer.trike.global_position)
	if racer.id == local_racer_id:
		feedback.emit(racer, "TURBO!")


func _on_banana_dropped(racer: Racer, peel_id: int, position: Vector3) -> void:
	if racer:
		_consume(racer)
	var peel := BananaPeel.new()
	peel.peel_id = peel_id
	peel.dropper_id = racer.id if racer else 0
	peel.name = "BananaPeel%d" % peel_id
	add_child(peel)
	peel.global_position = position
	peels[peel_id] = peel
	_next_object_id = maxi(_next_object_id, peel_id + 1)
	while peels.size() > config.banana_max_count:
		var oldest: int = peels.keys().min()
		(peels[oldest] as Node).queue_free()
		peels.erase(oldest)
	_play(racer, ItemSounds.Sound.USE, position)


func _on_banana_hit(peel_id: int, victim: Racer, spin_sign: float) -> void:
	var peel: BananaPeel = peels.get(peel_id)
	var where := peel.global_position if peel else Vector3.ZERO
	if peel:
		peel.queue_free()
		peels.erase(peel_id)
	if victim == null:
		return
	_immune[victim.id] = config.hit_immunity
	_clear_pending(victim.id, Request.TRAP_HIT)
	if _owns(victim):
		victim.trike.apply_item_hit(Vector3.ZERO, Vector3.UP * config.banana_spin * spin_sign, config.banana_speed_keep)
		victim.trike.set_slippery(config.banana_slip, config.banana_grip_factor)
	ItemVisuals.burst(self, where, ItemKind.color_of(ItemKind.Kind.BANANA_PEEL), 8, 1.2)
	_play(victim, ItemSounds.Sound.SLIP, where)
	if victim.id == local_racer_id:
		feedback.emit(victim, "SLIPPED!")


func _on_bomb_thrown(racer: Racer, bomb_id: int, origin: Vector3, velocity: Vector3) -> void:
	if racer:
		_consume(racer)
	var bomb := MudBomb.new()
	bomb.bomb_id = bomb_id
	bomb.thrower_id = racer.id if racer else 0
	bomb.velocity = velocity
	bomb.gravity = config.mud_gravity
	bomb.name = "MudBomb%d" % bomb_id
	add_child(bomb)
	bomb.global_position = origin
	bomb.previous_position = origin
	bombs[bomb_id] = bomb
	_next_object_id = maxi(_next_object_id, bomb_id + 1)
	_play(racer, ItemSounds.Sound.USE, origin)


func _on_bomb_landed(bomb_id: int, position: Vector3, victim: Racer, make_patch: bool) -> void:
	var bomb: MudBomb = bombs.get(bomb_id)
	var thrower := bomb.thrower_id if bomb else 0
	if bomb:
		bomb.queue_free()
		bombs.erase(bomb_id)
	if make_patch:
		var patch := MudPatch.new()
		patch.patch_id = bomb_id
		patch.thrower_id = thrower
		patch.radius = config.mud_patch_radius
		patch.time_left = config.mud_patch_duration
		patch.name = "MudPatch%d" % bomb_id
		add_child(patch)
		patch.global_position = position
		patches[bomb_id] = patch
		ItemVisuals.burst(self, position + Vector3.UP * 0.3, ItemKind.color_of(ItemKind.Kind.MUD_BOMB), 12, 2.2)
	if victim:
		_immune[victim.id] = config.hit_immunity
		if _owns(victim):
			victim.trike.set_slippery(config.mud_direct_slip, config.mud_grip_factor, config.mud_speed_factor)
			victim.trike.apply_item_hit(Vector3.ZERO, Vector3.UP * config.mud_direct_spin)
		if victim.id == local_racer_id:
			feedback.emit(victim, "SPLAT!")
	_play(victim, ItemSounds.Sound.SPLAT, position)


func _on_punch(attacker: Racer, target: Racer, knock: Vector3, eject: bool) -> void:
	if attacker == null:
		return
	_consume(attacker)
	var from := attacker.trike.global_position + Vector3.UP * 0.9
	if target == null:
		ItemVisuals.punch(self, from, from - attacker.trike.global_basis.z * config.punch_range * 0.6, false)
		_play(attacker, ItemSounds.Sound.PUNCH, from)
		if attacker.id == local_racer_id:
			feedback.emit(attacker, "MISSED!")
		return
	ItemVisuals.punch(self, from, target.trike.global_position + Vector3.UP * 0.7, true)
	_immune[target.id] = config.hit_immunity
	if _owns(target):
		var spin := Vector3.UP * config.punch_spin * signf(knock.dot(target.trike.global_basis.x) + 0.001)
		target.trike.apply_item_hit(knock, spin)
		target.trike.set_slippery(config.punch_slip, config.punch_grip_factor)
		if eject and target.rider and target.rider.is_riding():
			target.rider.eject(knock.length(), target.trike.linear_velocity + knock)
	_play(target, ItemSounds.Sound.PUNCH, target.trike.global_position)
	if attacker.id == local_racer_id:
		feedback.emit(attacker, "POW!")
	if target.id == local_racer_id:
		feedback.emit(target, "PUNCHED!")


# --- Helpers ------------------------------------------------------------------

## True if this computer simulates the racer (applies physical effects).
func _owns(racer: Racer) -> bool:
	return racer != null and not racer.is_proxy and not racer.disconnected and is_instance_valid(racer.trike)


func _peel_armed_for(peel: BananaPeel, racer_id: int) -> bool:
	return peel.dropper_id != racer_id or peel.age >= config.banana_arm_time


func _new_object_id() -> int:
	_next_object_id += 1
	return _next_object_id - 1


func _pending_key(racer_id: int, kind: Request, target: int) -> String:
	return "%d:%d:%d" % [racer_id, kind, target]


func _is_pending(racer_id: int, kind: Request, target: int) -> bool:
	return float(_pending.get(_pending_key(racer_id, kind, target), -1.0)) > _clock


func _set_pending(racer_id: int, kind: Request, target: int, duration := -1.0) -> void:
	_pending[_pending_key(racer_id, kind, target)] = _clock + (pending_timeout if duration < 0.0 else duration)


func _clear_pending(racer_id: int, kind: Request) -> void:
	var prefix := "%d:%d:" % [racer_id, kind]
	for key: String in _pending.keys():
		if key.begins_with(prefix) and not key.ends_with(":-2"):
			_pending.erase(key)


func _play(racer: Racer, sound: ItemSounds.Sound, where: Vector3) -> void:
	if racer and racer.id == local_racer_id:
		sounds.play(sound)
	else:
		sounds.play_at(sound, where)


static func _segment_distance(point: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := 0.0 if ab.length_squared() < 1e-8 else clampf((point - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return point.distance_to(a + ab * t)


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	if not is_inside_tree() or from.is_equal_approx(to):
		return {}
	var query := PhysicsRayQueryParameters3D.create(from, to, ground_mask)
	return get_world_3d().direct_space_state.intersect_ray(query)


## Ground under a point (searching 3 m up and 6 m down), or Vector3.INF.
func _ground_point(near: Vector3) -> Vector3:
	var hit := _ray(near + Vector3.UP * 3.0, near + Vector3.DOWN * 6.0)
	return hit["position"] if not hit.is_empty() else Vector3.INF
