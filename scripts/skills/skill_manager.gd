class_name SkillManager
extends Node3D
## Signature skills, traps, shields, slipstream, near misses, style events,
## taunts, the hazard seed and the end-of-race awards for one race (node
## "Skills" in the race scene). Separate from items: items stay on Q and in
## ItemManager; a racer's skill comes from its character (Racer.get_skill()).
##
## Authority is the same as for items (docs/NETWORKING.md):
## - Each computer watches only the racers it simulates. Pressing [skill],
##   driving over a trap, landing a trick or a near miss sends a *request*.
## - The host (`authoritative`) validates it (riding, racing, cooldown,
##   target in range, rate limits, no duplicates) and turns it into a
##   numbered *event* that every computer applies exactly once.
## - Physical effects are applied by the victim's owner only, through
##   Trike.apply_item_hit / set_slippery, so they never count as a crash.
##
## Slipstream is plain geometry every computer computes for every racer; only
## the owner feeds it to its trike (Trike.draft_factor).

signal event_applied(event: Array)
## Something worth a HUD message happened to (or was done by) a racer.
signal feedback(racer: Racer, text: String)
## A racer should show a reaction (laugh, yelp, cheer, taunt, ...).
signal reaction(racer: Racer, kind: StringName)
signal awards_ready(awards: Array)

enum Event { SLINGSHOT, BONK, TRAP_PLACED, TRAP_HIT, SHIELD_UP, SHIELD_POP, STYLE, EMOTE, SEED, AWARDS }
enum Request { USE, TRAP_TOUCH, STYLE, EMOTE, ABSORB }
enum Style { PERFECT_DRIFT, NEAR_MISS, TRICK, PERFECT_LANDING, ROUGH_LANDING, OVERTAKE }
## Why a shield popped.
enum Pop { ITEM = 1, SKILL = 2, CRASH = 3 }
## Event array sizes (seq and type included).
const EVENT_SIZES: Array[int] = [4, 6, 6, 6, 3, 4, 5, 4, 3, 3]
const EVENT_NAMES: Array[String] = ["SLINGSHOT", "BONK", "TRAP_PLACED", "TRAP_HIT", "SHIELD_UP", "SHIELD_POP", "STYLE",
		"EMOTE", "SEED", "AWARDS"]
const STYLE_TEXT: Array[String] = ["PERFECT DRIFT!", "NEAR MISS!", "TRICK!", "PERFECT LANDING!", "BAD LANDING!", ""]
## Shortest time (s) between two style events of one kind from one racer.
const STYLE_INTERVAL: Array[float] = [0.8, 1.5, 0.4, 1.2, 1.0, 4.0]
const MAX_SPEED := 80.0
const MAX_COORD := 20000.0

@export var config: SkillConfig
## An unanswered request may be sent again after this long (s).
@export var pending_timeout := 1.0
@export var teleport_step := 6.0
@export_flags_3d_physics var ground_mask := 1

var racers: RacerManager
var track: Track
var items: ItemManager
## Host / offline: decides. Online clients: send requests, apply events.
var authoritative := true
## Online client: func(racer_id, req_id, kind, data) sends a request to the host.
var send_request := Callable()
## Online host: func(event) sends an event to every client.
var broadcast := Callable()
var local_racer_id := -1
var stats := RaceStats.new()

## racer id -> seconds of cooldown left / the full cooldown it started with.
var cooldowns := {}
var cooldown_totals := {}
## racer id -> seconds of pillow shield left.
var shields := {}
## trap id -> SkillTrap.
var traps := {}
## racer id -> slipstream meter 0..1.
var draft := {}
var last_event_seq := 0
var events_applied := 0
## Diagnostics (tests, network checks).
var denied_requests := 0
var duplicate_requests := 0
var duplicate_events := 0
var invalid_events := 0

var _rng := RandomNumberGenerator.new()
var _seq := 0
var _next_trap_id := 1
var _clock := 0.0
var _pending := {}
var _next_req := {}
var _last_req := {}
var _last_positions := {}
var _bubbles := {}
var _bound := {}
var _style_gate := {}
var _emote_gate := {}
var _guard := {}
var _last_ejects := {}
var _last_rank := {}
var _worst_rank := {}
var _threats := {}
var _threat_gate := {}
var _near_rearm := {}
var _last_impact := {}
var _draft_full := {}


func _ready() -> void:
	if config == null:
		config = SkillConfig.new()
	_rng.randomize()


func setup(manager: RacerManager, for_track: Track, item_manager: ItemManager) -> void:
	racers = manager
	track = for_track
	items = item_manager
	racers.skills = self
	if items:
		# Shields eat item hits; item ejections respect the guard.
		items.block_hit = try_block
		items.eject_allowed = func(racer_id: int) -> bool: return not is_guarded(racer_id)
		items.prank_landed.connect(_on_item_prank)


# --- Queries ------------------------------------------------------------------

func get_cooldown(racer_id: int) -> float:
	return float(cooldowns.get(racer_id, 0.0))


## 0 = ready .. 1 = just used.
func get_cooldown_ratio(racer_id: int) -> float:
	var total := float(cooldown_totals.get(racer_id, 0.0))
	return clampf(get_cooldown(racer_id) / total, 0.0, 1.0) if total > 0.0 else 0.0


func is_ready(racer_id: int) -> bool:
	return not cooldowns.has(racer_id) and racers != null and racers.is_race_started \
			and racers.race_time >= config.start_lockout


func has_shield(racer_id: int) -> bool:
	return shields.has(racer_id)


func get_draft(racer_id: int) -> float:
	return float(draft.get(racer_id, 0.0))


## True while a racer may not be thrown off by an item or skill.
func is_guarded(racer_id: int) -> bool:
	return float(_guard.get(racer_id, 0.0)) > 0.0


func get_trap_of(racer_id: int) -> SkillTrap:
	for trap: SkillTrap in traps.values():
		if trap.owner_id == racer_id:
			return trap
	return null


## The rival a slingshot from `racer` would use right now (null = none).
func find_slingshot_target(racer: Racer) -> Racer:
	if racer == null or not is_instance_valid(racer.trike):
		return null
	return SkillRules.pick_slingshot_target(config, racer, racer.trike.global_position, -racer.trike.global_basis.z,
			racers.get_racers())


func find_bonk_target(racer: Racer) -> Racer:
	if racer == null or not is_instance_valid(racer.trike):
		return null
	return SkillRules.pick_bonk_target(config, racer, racer.trike.global_position, -racer.trike.global_basis.z,
			racers.get_racers(), _immune_check())


# --- Race flow ----------------------------------------------------------------

## Race Again / Return to Lobby: no cooldowns, shields, traps or stats.
func reset_for_new_race() -> void:
	cooldowns.clear()
	cooldown_totals.clear()
	for id: int in shields.keys():
		_drop_shield(id)
	for trap: Node in traps.values():
		trap.queue_free()
	traps.clear()
	draft.clear()
	stats.reset()
	for table: Dictionary in [_pending, _last_positions, _style_gate, _emote_gate, _guard, _last_ejects, _last_rank,
			_worst_rank, _threats, _threat_gate, _near_rearm, _last_impact, _draft_full]:
		table.clear()


## Host: picks this race's hazard seed and tells everyone (0 = authored phases).
func announce_hazard_seed(hazard_seed: int) -> void:
	if authoritative:
		_emit([Event.SEED, hazard_seed])


## Host: the race is over; works out the awards and tells everyone.
func finish_race() -> void:
	if not authoritative or racers == null:
		return
	var order: Array[int] = []
	for racer in racers.get_ranking():
		order.append(racer.id)
		var worst := int(_worst_rank.get(racer.id, racer.position))
		stats.raise(racer.id, "comeback", float(worst - racer.position))
	_emit([Event.AWARDS, stats.build_awards(order)])


# --- Tick ---------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if racers == null:
		return
	_clock += delta
	for id: int in cooldowns.keys():
		cooldowns[id] = float(cooldowns[id]) - delta
		if cooldowns[id] <= 0.0:
			cooldowns.erase(id)
	for id: int in shields.keys():
		shields[id] = float(shields[id]) - delta
		if shields[id] <= 0.0:
			_drop_shield(id)
	var live := racers.is_race_started and not racers.is_race_over
	for racer in racers.get_racers():
		if racer.disconnected or not is_instance_valid(racer.trike):
			continue
		_update_draft(racer, delta, live)
		if not racer.is_proxy:
			_owner_tick(racer)
	for id: int in traps.keys():
		var trap: SkillTrap = traps[id]
		trap.age += delta
		if trap.age > trap.lifetime:
			trap.queue_free()
			traps.erase(id)
	if authoritative and live:
		_host_tick(delta)


func _live() -> bool:
	return racers.is_race_started and not racers.is_race_over


## May this racer use skills, be hit by them or score style right now?
func _can_act(racer: Racer) -> bool:
	if racer == null or racer.disconnected or racer.finished or not is_instance_valid(racer.trike):
		return false
	if racer.trike.input_locked or not _live():
		return false
	return racer.rider.is_riding() if racer.rider else racer.trike.has_rider


## Owner side: what this computer's own racer pressed or touched.
func _owner_tick(racer: Racer) -> void:
	var trike := racer.trike
	_bind_owner(racer)
	var position := trike.global_position
	var last: Vector3 = _last_positions.get(racer.id, position)
	if last.distance_to(position) > teleport_step:
		last = position
	_last_positions[racer.id] = position
	var use := trike.input.skill_pressed
	var emote := trike.input.emote_pressed
	trike.input.skill_pressed = false
	trike.input.emote_pressed = false
	if racer.rider:
		racer.rider.input.skill_pressed = false
		racer.rider.input.emote_pressed = false
	if not _can_act(racer):
		(_threats.get(racer.id, {}) as Dictionary).clear()
		return
	if not (items and items.is_immune(racer.id)):
		for trap: SkillTrap in traps.values():
			if not trap.is_armed_for(racer.id) or _is_pending(racer.id, Request.TRAP_TOUCH, trap.trap_id):
				continue
			var radius := config.fake_box_radius if trap.kind == SkillKind.Kind.FAKE_BOX else config.snare_radius
			if ItemManager._segment_distance(trap.global_position, last, position) <= radius:
				_set_pending(racer.id, Request.TRAP_TOUCH, trap.trap_id)
				_request(racer, Request.TRAP_TOUCH, [trap.trap_id, trike.linear_velocity.length()])
				break
	if use:
		_try_use(racer)
	if emote and not _is_pending(racer.id, Request.EMOTE, 0):
		_set_pending(racer.id, Request.EMOTE, 0, 0.5)
		_request(racer, Request.EMOTE, [0])
	_near_miss_tick(racer)


## Owner-side checks before bothering the host (and instant feedback).
func _try_use(racer: Racer) -> void:
	var is_local := racer.id == local_racer_id
	if not is_ready(racer.id):
		if is_local:
			SoundPlayer.play_flat(self, &"item_denied", -6.0)
			feedback.emit(racer, "SKILL NOT READY")
		return
	if _is_pending(racer.id, Request.USE, 0):
		return
	if racer.get_skill() == SkillKind.Kind.SLINGSHOT and find_slingshot_target(racer) == null:
		if is_local:
			SoundPlayer.play_flat(self, &"item_denied", -6.0)
			feedback.emit(racer, "NO ONE TO SLINGSHOT")
		return
	_set_pending(racer.id, Request.USE, 0)
	var trike := racer.trike
	_request(racer, Request.USE, [trike.global_position, -trike.global_basis.z, trike.linear_velocity])


## Hooks the owner's trike and rider signals to style and shield requests (once).
func _bind_owner(racer: Racer) -> void:
	if _bound.has(racer.id):
		return
	_bound[racer.id] = true
	var trike := racer.trike
	trike.drift_perfect.connect(func(tier: int) -> void:
		_request_style(racer, Style.PERFECT_DRIFT, float(tier)))
	trike.trick_completed.connect(func(count: int) -> void:
		_request_style(racer, Style.TRICK, float(count)))
	trike.landing_graded.connect(_on_landing_graded.bind(racer))
	trike.impact.connect(func(strength: float, _v: Vector3) -> void:
		if strength >= 2.0:
			_last_impact[racer.id] = _clock)
	if racer.rider:
		racer.rider.impact_absorbed.connect(func(strength: float) -> void:
			_request(racer, Request.ABSORB, [strength]))


func _on_landing_graded(grade: int, _air: float, tricks: int, racer: Racer) -> void:
	if grade == Trike.Landing.PERFECT:
		_request_style(racer, Style.PERFECT_LANDING, float(tricks))
	elif grade == Trike.Landing.BAD:
		_request_style(racer, Style.ROUGH_LANDING, 0.0)
	elif grade == Trike.Landing.POOR and racer.id == local_racer_id:
		feedback.emit(racer, Trike.LANDING_NAMES[grade])


func _request_style(racer: Racer, style: Style, value: float) -> void:
	if _can_act(racer):
		_request(racer, Request.STYLE, [int(style), value])


# --- Slipstream ---------------------------------------------------------------

func _update_draft(racer: Racer, delta: float, live: bool) -> void:
	var towed := false
	if live and _can_act(racer):
		for other in racers.get_racers():
			if other == racer or other.disconnected or other.finished or not is_instance_valid(other.trike):
				continue
			if other.rider and not other.rider.is_riding():
				continue
			if SkillRules.in_slipstream(config, racer.trike, other.trike):
				towed = true
				break
	var meter := get_draft(racer.id)
	if towed:
		var rate := 1.0 / maxf(config.draft_charge_time, 0.05)
		if racer.get_skill() == SkillKind.Kind.SLINGSHOT:
			rate *= config.draft_zip_bonus
		meter = minf(meter + delta * rate, 1.0)
	else:
		meter = maxf(meter - delta / maxf(config.draft_decay_time, 0.05), 0.0)
	draft[racer.id] = meter
	var full := meter >= 0.999
	if full:
		if not racer.is_proxy:
			racer.trike.draft_factor = 1.0
		if authoritative:
			stats.add(racer.id, "draft_time", delta)
	if full and not _draft_full.get(racer.id, false) and racer.id == local_racer_id:
		SoundPlayer.play_flat(self, &"draft_on", -8.0)
		feedback.emit(racer, "SLIPSTREAM!")
	_draft_full[racer.id] = full


# --- Near misses (owner side) -------------------------------------------------

func _near_miss_tick(racer: Racer) -> void:
	var trike := racer.trike
	var velocity := Vector3(trike.linear_velocity.x, 0.0, trike.linear_velocity.z)
	var speed := velocity.length()
	var seen: Dictionary = _threats.get_or_add(racer.id, {})
	if speed < config.near_miss_min_speed * 0.6:
		seen.clear()
		return
	var direction := velocity / speed
	var position := trike.global_position
	var radii: Dictionary = config.near_miss_radii
	for obstacle: Dictionary in racers.get_obstacles():
		if not radii.has(obstacle["kind"]):
			continue
		var node: Node3D = obstacle["node"]
		if not is_instance_valid(node) or position.distance_squared_to(node.global_position) > 144.0:
			continue
		var active := not node.has_method(&"is_active") or bool(node.call(&"is_active"))
		_track_threat(racer, seen, node.get_instance_id(), node.global_position, float(radii[obstacle["kind"]]),
				active, direction, speed, true)
	for other in racers.get_racers():
		if other == racer or other.disconnected or not is_instance_valid(other.trike):
			continue
		if position.distance_squared_to(other.trike.global_position) > 144.0:
			continue
		var closing := speed - other.trike.get_motion_velocity().dot(direction)
		_track_threat(racer, seen, other.trike.get_instance_id(), other.trike.global_position, float(radii.get("racer", 0.9)),
				other.rider == null or other.rider.is_riding(), direction, speed, closing >= config.near_miss_pass_speed)


## Follows one obstacle as the trike approaches and passes it. While it is
## ahead the smallest gap is remembered; once it is behind, a small enough
## gap without a hit asks the host for a near miss.
func _track_threat(racer: Racer, seen: Dictionary, key: int, at: Vector3, radius: float, active: bool,
		direction: Vector3, speed: float, fast_enough: bool) -> void:
	var position := racer.trike.global_position
	var offset := Vector3(at.x - position.x, 0.0, at.z - position.z)
	var along := offset.dot(direction)
	var gap := offset.length() - radius - 0.8
	if absf(at.y - position.y) > 2.5:
		gap = INF
	if along > 0.5:
		var entry: Dictionary = seen.get_or_add(key, {"gap": INF, "ok": false})
		if gap < float(entry["gap"]):
			entry["gap"] = gap
			entry["ok"] = active and fast_enough and speed >= config.near_miss_min_speed
		return
	if along > -0.5 or not seen.has(key):
		return
	var passed: Dictionary = seen[key]
	seen.erase(key)
	if not bool(passed["ok"]) or float(passed["gap"]) > config.near_miss_gap:
		return
	if _clock - float(_last_impact.get(racer.id, -100.0)) < config.near_miss_impact_window:
		return  # that was a hit, not a miss
	var gate := "%d:%d" % [racer.id, key]
	if float(_threat_gate.get(gate, -100.0)) > _clock or float(_near_rearm.get(racer.id, -100.0)) > _clock:
		return
	_threat_gate[gate] = _clock + config.near_miss_repeat
	_near_rearm[racer.id] = _clock + config.near_miss_rearm
	_request_style(racer, Style.NEAR_MISS, maxf(float(passed["gap"]), 0.0))


# --- Host bookkeeping ---------------------------------------------------------

## Eject guards, stats that need the whole field, and overtake teasing.
func _host_tick(delta: float) -> void:
	for racer in racers.get_racers():
		if racer.disconnected or not is_instance_valid(racer.trike):
			continue
		var riding := racer.rider == null or racer.rider.is_riding()
		if not riding:
			_guard[racer.id] = config.eject_guard
		elif _guard.has(racer.id):
			_guard[racer.id] = float(_guard[racer.id]) - delta
			if _guard[racer.id] <= 0.0:
				_guard.erase(racer.id)
		if racer.rider:
			var ejects := racer.rider.eject_count
			var before := int(_last_ejects.get(racer.id, ejects))
			if ejects > before:
				stats.add(racer.id, "wipeouts", float(ejects - before))
			_last_ejects[racer.id] = ejects
		if racer.finished:
			continue
		if riding and racer.progress and racer.trike.get_motion_velocity().length() > 4.0:
			var index := racer.progress.current_index
			var lateral := (racer.trike.global_position - track.path.points[index]).dot(track.path.rights[index])
			match track.surface_at(index, lateral):
				TrackSurface.Kind.MUD:
					stats.add(racer.id, "mud_time", delta)
				TrackSurface.Kind.ICE:
					stats.add(racer.id, "ice_time", delta)
		if racers.race_time > 12.0:
			_worst_rank[racer.id] = maxi(int(_worst_rank.get(racer.id, racer.position)), racer.position)
			var rank_before := int(_last_rank.get(racer.id, racer.position))
			if racer.position < rank_before:
				_tease_overtaken(racer)
		_last_rank[racer.id] = racer.position


func _tease_overtaken(racer: Racer) -> void:
	var gate := "%d:%d" % [racer.id, Style.OVERTAKE]
	if float(_style_gate.get(gate, -100.0)) > _clock or not _can_act(racer):
		return
	for other in racers.get_racers():
		if other.position != racer.position + 1 or not is_instance_valid(other.trike):
			continue
		if other.trike.global_position.distance_to(racer.trike.global_position) <= config.overtake_tease_distance:
			_style_gate[gate] = _clock + config.overtake_tease_cooldown
			_emit([Event.STYLE, racer.id, Style.OVERTAKE, float(other.id)])
		return


## Host: an item or skill is about to hit `victim_id`. True if a pillow
## shield eats it (the shield pops for everyone).
func try_block(victim_id: int, cause: int) -> bool:
	if not authoritative or not shields.has(victim_id):
		return false
	_emit([Event.SHIELD_POP, victim_id, cause])
	return true


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
		Request.USE:
			granted = _host_use(racer, data[0], data[1], data[2])
		Request.TRAP_TOUCH:
			granted = _host_trap(racer, int(data[0]), float(data[1]))
		Request.STYLE:
			granted = _host_style(racer, int(data[0]), float(data[1]))
		Request.EMOTE:
			granted = _host_emote(racer, int(data[0]))
		Request.ABSORB:
			granted = _host_absorb(racer)
	if not granted:
		denied_requests += 1
	return granted


static func _valid_request(kind: int, data: Variant) -> bool:
	if not data is Array:
		return false
	var values: Array = data
	match kind:
		Request.USE:
			if values.size() != 3:
				return false
			for value: Variant in values:
				if not value is Vector3 or not (value as Vector3).is_finite():
					return false
			return (values[0] as Vector3).length() < MAX_COORD and (values[2] as Vector3).length() <= MAX_SPEED
		Request.TRAP_TOUCH:
			return values.size() == 2 and values[0] is int and values[1] is float and is_finite(values[1])
		Request.STYLE:
			return values.size() == 2 and values[0] is int and values[1] is float and is_finite(values[1]) \
					and int(values[0]) >= 0 and int(values[0]) < Style.OVERTAKE
		Request.EMOTE:
			return values.size() == 1 and values[0] is int and int(values[0]) >= 0 and int(values[0]) < 8
		Request.ABSORB:
			return values.size() == 1 and values[0] is float and is_finite(values[0])
	return false


func _host_use(racer: Racer, reported: Vector3, forward: Vector3, _velocity: Vector3) -> bool:
	if not _can_act(racer) or not is_ready(racer.id):
		return false
	# Trust the owner's (newer) position only if it matches what we see.
	var position := reported
	if position.distance_to(racer.trike.global_position) > config.plausible_distance:
		position = racer.trike.global_position
	var flat := Vector3(forward.x, 0.0, forward.z)
	flat = flat.normalized() if flat.length() > 0.01 else -racer.trike.global_basis.z
	match racer.get_skill():
		SkillKind.Kind.SLINGSHOT:
			var target := SkillRules.pick_slingshot_target(config, racer, position, flat, racers.get_racers())
			if target == null:
				return false
			_emit([Event.SLINGSHOT, racer.id, target.id])
		SkillKind.Kind.BONK:
			var target := SkillRules.pick_bonk_target(config, racer, position, flat, racers.get_racers(), _immune_check())
			if target == null:
				_emit([Event.BONK, racer.id, 0, Vector3.ZERO, false])
			elif try_block(target.id, Pop.SKILL):
				_emit([Event.BONK, racer.id, target.id, Vector3.ZERO, false])
			else:
				var distance := position.distance_to(target.trike.global_position)
				var knock := SkillRules.bonk_velocity(config, position, target.trike, SkillRules.bonk_speed(config, distance))
				_emit([Event.BONK, racer.id, target.id, knock, distance <= config.bonk_eject_distance and not is_guarded(target.id)])
		SkillKind.Kind.SNARE, SkillKind.Kind.FAKE_BOX:
			var kind := racer.get_skill()
			var back := config.snare_drop_distance if kind == SkillKind.Kind.SNARE else config.fake_box_drop_distance
			var drop := _ground_point(position - flat * back)
			if drop == Vector3.INF:
				drop = _ground_point(position)
			if drop == Vector3.INF:
				drop = position
			_next_trap_id += 1
			_emit([Event.TRAP_PLACED, racer.id, _next_trap_id - 1, int(kind), drop])
		SkillKind.Kind.SHIELD:
			_emit([Event.SHIELD_UP, racer.id])
		_:
			return false
	return true


func _host_trap(racer: Racer, trap_id: int, speed: float) -> bool:
	var trap: SkillTrap = traps.get(trap_id)
	if trap == null or not _can_act(racer) or not trap.is_armed_for(racer.id) or (items and items.is_immune(racer.id)):
		return false
	if racer.trike.global_position.distance_to(trap.global_position) > config.plausible_distance:
		return false
	if try_block(racer.id, Pop.SKILL):
		_emit([Event.TRAP_HIT, trap_id, racer.id, 0, false])
		return true
	var eject := trap.kind == SkillKind.Kind.SNARE and minf(speed, MAX_SPEED) >= config.snare_eject_speed \
			and not is_guarded(racer.id)
	_emit([Event.TRAP_HIT, trap_id, racer.id, 1 if _rng.randf() < 0.5 else -1, eject])
	return true


func _host_style(racer: Racer, style: int, value: float) -> bool:
	if not _can_act(racer) and style != Style.ROUGH_LANDING:
		return false
	var gate := "%d:%d" % [racer.id, style]
	if float(_style_gate.get(gate, -100.0)) > _clock:
		return false
	_style_gate[gate] = _clock + STYLE_INTERVAL[style]
	_emit([Event.STYLE, racer.id, style, clampf(value, 0.0, 99.0)])
	return true


func _host_emote(racer: Racer, emote: int) -> bool:
	if racer.disconnected or not _live() or float(_emote_gate.get(racer.id, -100.0)) > _clock:
		return false
	_emote_gate[racer.id] = _clock + config.emote_cooldown
	_emit([Event.EMOTE, racer.id, emote])
	return true


func _host_absorb(racer: Racer) -> bool:
	return try_block(racer.id, Pop.CRASH)


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
	if type < 0 or type >= EVENT_SIZES.size() or (event as Array).size() != EVENT_SIZES[type]:
		return false
	match type:
		Event.BONK:
			return event[2] is int and event[3] is int and event[4] is Vector3 and (event[4] as Vector3).is_finite() \
					and (event[4] as Vector3).length() <= MAX_SPEED and event[5] is bool
		Event.TRAP_PLACED:
			return event[2] is int and event[3] is int and event[4] is int and event[5] is Vector3 \
					and (event[5] as Vector3).is_finite() and SkillKind.is_valid(int(event[4]))
		Event.TRAP_HIT:
			return event[2] is int and event[3] is int and event[4] is int and event[5] is bool
		Event.STYLE:
			return event[2] is int and event[3] is int and event[4] is float and int(event[3]) >= 0 \
					and int(event[3]) < STYLE_TEXT.size()
		Event.AWARDS:
			return RaceStats.valid_awards(event[2])
	for i in range(2, (event as Array).size()):
		if not event[i] is int:
			return false
	return true


func _apply_event(event: Array) -> void:
	last_event_seq = maxi(last_event_seq, int(event[0]))
	events_applied += 1
	match int(event[1]):
		Event.SLINGSHOT:
			_on_slingshot(racers.get_racer(int(event[2])), racers.get_racer(int(event[3])))
		Event.BONK:
			_on_bonk(racers.get_racer(int(event[2])), racers.get_racer(int(event[3])), event[4], bool(event[5]))
		Event.TRAP_PLACED:
			_on_trap_placed(racers.get_racer(int(event[2])), int(event[3]), int(event[4]), event[5])
		Event.TRAP_HIT:
			_on_trap_hit(int(event[2]), racers.get_racer(int(event[3])), float(event[4]), bool(event[5]))
		Event.SHIELD_UP:
			_on_shield_up(racers.get_racer(int(event[2])))
		Event.SHIELD_POP:
			_on_shield_pop(racers.get_racer(int(event[2])), int(event[3]))
		Event.STYLE:
			_on_style(racers.get_racer(int(event[2])), int(event[3]), float(event[4]))
		Event.EMOTE:
			var racer := racers.get_racer(int(event[2]))
			if racer:
				_clear_pending(racer.id, Request.EMOTE)
				_react(racer, &"taunt")
		Event.SEED:
			if track:
				track.hazard_seed = int(event[2])
		Event.AWARDS:
			stats.awards = (event[2] as Array).duplicate(true)
			awards_ready.emit(stats.awards)
	event_applied.emit(event)


func _start_cooldown(racer: Racer, seconds: float) -> void:
	var total := seconds * SkillRules.cooldown_factor(config, maxi(racer.position, 1), racers.get_racer_count())
	cooldowns[racer.id] = total
	cooldown_totals[racer.id] = total
	_clear_pending(racer.id, Request.USE)


func _on_slingshot(racer: Racer, target: Racer) -> void:
	if racer == null:
		return
	_start_cooldown(racer, config.slingshot_cooldown)
	if _owns(racer):
		racer.trike.boost_time = maxf(racer.trike.boost_time, config.slingshot_boost)
		racer.trike.draft_factor = 1.0
	SkillVisuals.wind_burst(racer.trike)
	_play(racer, &"skill_slingshot", racer.trike.global_position)
	_react(racer, &"skill")
	stats.add(racer.id, "skills_used")
	if racer.id == local_racer_id:
		feedback.emit(racer, "SLINGSHOT!")
	elif target and target.id == local_racer_id:
		feedback.emit(target, "%s IS SLINGSHOTTING YOU!" % racer.display_name.to_upper())


func _on_bonk(attacker: Racer, target: Racer, knock: Vector3, eject: bool) -> void:
	if attacker == null:
		return
	var from := attacker.trike.global_position + Vector3.UP * 0.9
	_react(attacker, &"skill")
	stats.add(attacker.id, "skills_used")
	if target == null:
		_start_cooldown(attacker, config.bonk_whiff_cooldown)
		ItemVisuals.punch(self, from, from - attacker.trike.global_basis.z * config.bonk_range * 0.7, false)
		_play(attacker, &"skill_bonk", from)
		if attacker.id == local_racer_id:
			feedback.emit(attacker, "WHIFF!")
		return
	_start_cooldown(attacker, config.bonk_cooldown)
	ItemVisuals.punch(self, from, target.trike.global_position + Vector3.UP * 0.7, true)
	_play(target, &"skill_bonk", target.trike.global_position)
	if knock == Vector3.ZERO:
		return  # a pillow shield ate it (SHIELD_POP shows that)
	if items:
		items.set_immune(target.id, config.hit_immunity)
	if _owns(target):
		var spin := Vector3.UP * config.bonk_spin * signf(knock.dot(target.trike.global_basis.x) + 0.001)
		target.trike.apply_item_hit(knock, spin)
		target.trike.set_slippery(config.bonk_slip, config.bonk_grip_factor)
		if eject and target.rider and target.rider.is_riding():
			target.rider.eject(knock.length(), target.trike.linear_velocity + knock)
	_note_prank(attacker, target, knock.length())
	if attacker.id == local_racer_id:
		feedback.emit(attacker, "BONK!")
	if target.id == local_racer_id:
		feedback.emit(target, "BONKED!")


func _on_trap_placed(racer: Racer, trap_id: int, kind: int, position: Vector3) -> void:
	if racer:
		_start_cooldown(racer, config.cooldown_of(kind))
		_react(racer, &"skill")
		stats.add(racer.id, "skills_used")
		var old := get_trap_of(racer.id)
		if old:  # one trap per trapper
			traps.erase(old.trap_id)
			old.queue_free()
	var trap := SkillTrap.new()
	trap.trap_id = trap_id
	trap.kind = kind as SkillKind.Kind
	trap.owner_id = racer.id if racer else 0
	var fake := kind == SkillKind.Kind.FAKE_BOX
	trap.lifetime = config.fake_box_lifetime if fake else config.snare_lifetime
	trap.arm_time = config.fake_box_arm_time if fake else config.snare_arm_time
	trap.name = "Trap%d" % trap_id
	add_child(trap)
	trap.global_position = position
	traps[trap_id] = trap
	_next_trap_id = maxi(_next_trap_id, trap_id + 1)
	_play(racer, &"skill_fake_drop" if fake else &"skill_snare_drop", position)
	if racer and racer.id == local_racer_id:
		feedback.emit(racer, "FAKE BOX PLACED" if fake else "SNARE SET")


func _on_trap_hit(trap_id: int, victim: Racer, side: float, eject: bool) -> void:
	var trap: SkillTrap = traps.get(trap_id)
	var where := trap.global_position if trap else Vector3.ZERO
	var kind := trap.kind if trap else SkillKind.Kind.SNARE
	var trapper := racers.get_racer(trap.owner_id) if trap else null
	if trap:
		trap.queue_free()
		traps.erase(trap_id)
	if victim == null:
		return
	_clear_pending(victim.id, Request.TRAP_TOUCH)
	var fake := kind == SkillKind.Kind.FAKE_BOX
	if fake:
		SkillVisuals.confetti(self, where + Vector3.UP * 0.8)
	else:
		ItemVisuals.burst(self, where + Vector3.UP * 0.3, SkillKind.color_of(kind), 10, 1.8)
	_play(victim, &"skill_fake_hit" if fake else &"skill_snare_hit", where)
	if side == 0.0:
		return  # blocked by a pillow shield
	if items:
		items.set_immune(victim.id, config.hit_immunity)
	if _owns(victim):
		var trike := victim.trike
		if fake:
			trike.apply_item_hit(Vector3.UP * config.fake_box_hop, Vector3.UP * config.fake_box_spin * side,
					config.fake_box_speed_keep)
			trike.set_slippery(config.fake_box_slip, config.fake_box_grip_factor)
		else:
			var right := trike.global_basis.x
			right.y = 0.0
			trike.apply_item_hit(right.normalized() * config.snare_pull * side, Vector3.UP * config.snare_spin * side,
					config.snare_speed_keep)
			trike.set_slippery(config.snare_slip, config.snare_grip_factor)
			if eject and victim.rider and victim.rider.is_riding():
				victim.rider.eject(config.snare_pull, trike.linear_velocity)
	if trapper and trapper != victim:
		_note_prank(trapper, victim, 0.0)
	else:
		stats.add(victim.id, "hits_taken")
		_react(victim, &"yelp")
	if fake:
		_react(victim, &"confused")
	if victim.id == local_racer_id:
		feedback.emit(victim, "IT WAS A FAKE!" if fake else "SNARED!")
	if trapper and trapper.id == local_racer_id and trapper != victim:
		feedback.emit(trapper, "%s FELL FOR IT!" % victim.display_name.to_upper() if fake
				else "GOT %s!" % victim.display_name.to_upper())


func _on_shield_up(racer: Racer) -> void:
	if racer == null:
		return
	_start_cooldown(racer, config.shield_cooldown)
	shields[racer.id] = config.shield_duration
	stats.add(racer.id, "skills_used")
	if not _bubbles.has(racer.id) and is_instance_valid(racer.trike):
		var bubble := SkillVisuals.shield_bubble()
		racer.trike.add_child(bubble)
		bubble.scale = Vector3.ONE * 0.2
		var tween := bubble.create_tween()
		tween.tween_property(bubble, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(bubble, "scale", Vector3(1.06, 0.94, 1.06), 0.5).set_trans(Tween.TRANS_SINE)
		tween.tween_property(bubble, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_SINE)
		_bubbles[racer.id] = bubble
	if _owns(racer) and racer.rider:
		racer.rider.impact_guard = config.shield_impact_factor - 1.0
	_play(racer, &"skill_shield_up", racer.trike.global_position)
	_react(racer, &"skill")
	if racer.id == local_racer_id:
		feedback.emit(racer, "PILLOW SHIELD!")


func _on_shield_pop(racer: Racer, cause: int) -> void:
	if racer == null:
		return
	var at := racer.trike.global_position + Vector3.UP * 0.8 if is_instance_valid(racer.trike) else Vector3.ZERO
	_drop_shield(racer.id)
	SkillVisuals.confetti(self, at, 1.6)
	ItemVisuals.burst(self, at, Color(1.0, 0.97, 0.92), 12, 2.4)
	_play(racer, &"skill_shield_pop", at)
	if items and cause != Pop.CRASH:
		items.set_immune(racer.id, config.hit_immunity)
	if _owns(racer):
		# The pillow bounces: a small hop, nothing lost.
		racer.trike.apply_item_hit(Vector3.UP * 1.8)
	stats.add(racer.id, "blocks")
	_react(racer, &"smug")
	if racer.id == local_racer_id:
		feedback.emit(racer, "BLOCKED!")


func _drop_shield(racer_id: int) -> void:
	shields.erase(racer_id)
	var bubble: Node = _bubbles.get(racer_id)
	if bubble and is_instance_valid(bubble):
		bubble.queue_free()
	_bubbles.erase(racer_id)
	var racer := racers.get_racer(racer_id) if racers else null
	if racer and racer.rider and is_instance_valid(racer.rider):
		racer.rider.impact_guard = 0.0


func _on_style(racer: Racer, style: int, value: float) -> void:
	if racer == null:
		return
	var is_local := racer.id == local_racer_id
	match style:
		Style.PERFECT_DRIFT:
			stats.add(racer.id, "perfect_drifts")
			_react(racer, &"focus")
			if is_local:
				SoundPlayer.play_flat(self, &"style_perfect", -7.0)
		Style.NEAR_MISS:
			stats.add(racer.id, "near_misses")
			if _owns(racer):
				racer.trike.boost_time = maxf(racer.trike.boost_time, config.near_miss_boost)
			_react(racer, &"smug")
			if is_local:
				SoundPlayer.play_flat(self, &"style_near_miss", -7.0)
		Style.TRICK:
			stats.add(racer.id, "tricks")
			if is_local:
				SoundPlayer.play_flat(self, &"style_trick", -8.0)
		Style.PERFECT_LANDING:
			stats.add(racer.id, "perfect_landings")
			if is_instance_valid(racer.trike):
				SkillVisuals.confetti(self, racer.trike.global_position + Vector3.UP * 0.3, 1.5)
			_react(racer, &"cheer")
			if is_local:
				SoundPlayer.play_flat(self, &"style_perfect", -6.0)
		Style.ROUGH_LANDING:
			stats.add(racer.id, "bad_landings")
			_react(racer, &"yelp")
			if is_local:
				SoundPlayer.play_flat(self, &"style_rough", -7.0)
		Style.OVERTAKE:
			stats.add(racer.id, "overtakes")
			_react(racer, &"taunt")
			var passed := racers.get_racer(int(value))
			if passed:
				_react(passed, &"grumble")
	if is_local and not STYLE_TEXT[style].is_empty():
		var text := STYLE_TEXT[style]
		if style == Style.TRICK and value >= 2.0:
			text = "%d TRICKS!" % int(value)
		feedback.emit(racer, text)


## Banana, mud bomb and spring punch hits (ItemManager.prank_landed).
func _on_item_prank(attacker_id: int, victim_id: int, strength: float) -> void:
	var victim := racers.get_racer(victim_id)
	if victim == null:
		return
	var attacker := racers.get_racer(attacker_id)
	if attacker and attacker != victim:
		_note_prank(attacker, victim, strength)
	else:
		stats.add(victim.id, "hits_taken")
		_react(victim, &"yelp")


func _note_prank(attacker: Racer, victim: Racer, strength: float) -> void:
	stats.add(attacker.id, "pranks")
	stats.add(victim.id, "hits_taken")
	if strength > 0.0:
		stats.raise(attacker.id, "biggest_bonk", strength)
	_react(attacker, &"laugh")
	_react(victim, &"yelp")


## Shows a reaction on the racer's model and plays its bark (cosmetic, on
## every computer).
func _react(racer: Racer, kind: StringName) -> void:
	if racer == null or racer.disconnected or not is_instance_valid(racer.trike):
		return
	reaction.emit(racer, kind)
	var model := racer.trike.get_node_or_null(^"Visuals/Rider") as Rider
	if model:
		model.react(kind)
	if racer.rider and racer.rider.audio:
		racer.rider.audio.bark(kind)


# --- Helpers ------------------------------------------------------------------

func _immune_check() -> Callable:
	return items.is_immune if items else Callable()


## True if this computer simulates the racer (applies physical effects).
func _owns(racer: Racer) -> bool:
	return racer != null and not racer.is_proxy and not racer.disconnected and is_instance_valid(racer.trike)


func _pending_key(racer_id: int, kind: Request, target: int) -> String:
	return "%d:%d:%d" % [racer_id, kind, target]


func _is_pending(racer_id: int, kind: Request, target: int) -> bool:
	return float(_pending.get(_pending_key(racer_id, kind, target), -1.0)) > _clock


func _set_pending(racer_id: int, kind: Request, target: int, duration := -1.0) -> void:
	_pending[_pending_key(racer_id, kind, target)] = _clock + (pending_timeout if duration < 0.0 else duration)


func _clear_pending(racer_id: int, kind: Request) -> void:
	var prefix := "%d:%d:" % [racer_id, kind]
	for key: String in _pending.keys():
		if key.begins_with(prefix):
			_pending.erase(key)


func _play(racer: Racer, sound: StringName, where: Vector3) -> void:
	if racer and racer.id == local_racer_id:
		SoundPlayer.play_flat(self, sound, -6.0)
	else:
		SoundPlayer.play_at(self, sound, where, 0.0, 1.0, 12.0)


## Ground under a point (searching 3 m up and 6 m down), or Vector3.INF.
func _ground_point(near: Vector3) -> Vector3:
	if not is_inside_tree():
		return Vector3.INF
	var query := PhysicsRayQueryParameters3D.create(near + Vector3.UP * 3.0, near + Vector3.DOWN * 6.0, ground_mask)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"] if not hit.is_empty() else Vector3.INF
