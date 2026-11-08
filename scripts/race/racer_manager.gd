class_name RacerManager
extends Node3D
## Registry and spawner for the 1–5 racers of a race.
##
## Every racer (Racer) gets a unique id, a grid slot, its own trike + rider,
## an input source (keyboard for the local human, AIDriver for bots), its own
## VehicleProgress and a FinishTracker entry. The manager keeps each racer's
## progress, out-of-bounds respawns and emergency recoveries separate, owns the
## race clock and resolves finish-line crossings to their owner.
##
## The local human's trike and rider are placed in the scene and handed over
## with add_human_racer(); AI racers are spawned from the regular trike and
## rider scenes with add_ai_racer(). UI and camera stay in RaceSession.

signal racer_added(racer: Racer)
signal racer_respawned(racer: Racer)
signal racer_finished(racer: Racer)
## An empty trike crossed the line (finish waits for its rider).
signal racer_pending(racer: Racer)
signal race_started

const TRIKE_SCENE := preload("res://scenes/vehicles/trike.tscn")
const RIDER_SCENE := preload("res://scenes/characters/rider_character.tscn")

## Hard cap (project requirement: up to 5 players).
@export_range(1, 5) var max_racers := 5
## AI behavior per difficulty, indexed by AIDriverConfig.Difficulty.
@export var ai_configs: Array[AIDriverConfig] = []
@export var ai_names: Array[String] = ["Pip", "Bramble", "Nutmeg", "Rusty"]
## Trike paint per racer, in the order racers are added.
@export var racer_colors: Array[Color] = [
	Color(1.0, 0.4, 0.2), Color(0.2, 0.55, 1.0), Color(0.3, 0.78, 0.32),
	Color(0.68, 0.4, 0.95), Color(1.0, 0.42, 0.68),
]
## Number decal per racer, in the order racers are added.
@export var racer_numbers: Array[int] = [7, 2, 4, 5, 9]
## Driving lane (m from the centerline, + = right) per grid slot.
@export var lane_offsets: Array[float] = [0.0, -3.0, 3.0, -1.3, 1.3]
## Racers on the same checkpoint closer than this (m) keep their previous
## positions (no flickering side by side).
@export var position_swap_margin := 1.0
## Clearance (m) from props for AI avoidance, per prop kind.
@export var obstacle_radii := {"crate": 0.75, "cone": 0.35, "rock": 1.1, "boulder": 2.0, "road_tree": 0.6,
		"falling_log": 2.4}

var track: Track
var finish_tracker: FinishTracker
var race_time := 0.0
var is_race_started := false
## Set by stop_race(): the clock stops and the finish line no longer counts.
var is_race_over := false
## False on online clients: the host decides checkpoints, positions and
## finishes (apply_remote_status); this computer only simulates its own trike.
var authoritative := true

var _racers: Array[Racer] = []
## Racers by current position (index 0 = 1st).
var _ranking: Array[Racer] = []
var _obstacles: Array[Dictionary] = []
var _ramps: Array[Dictionary] = []


func setup(for_track: Track) -> void:
	track = for_track
	finish_tracker = FinishTracker.new(track.get_finish_index())
	finish_tracker.racer_finished.connect(_on_racer_finished)
	finish_tracker.can_finish = _can_finish
	finish_tracker.finish_pending.connect(func(player_id: int, _t: float) -> void:
		var racer := get_racer(player_id)
		if racer:
			racer.pending_finish = true
			racer_pending.emit(racer))
	track.finish_crossed.connect(_on_finish_crossed)
	_collect_obstacles()


func _physics_process(delta: float) -> void:
	if track == null:
		return
	if is_race_started and not is_race_over:
		race_time += delta
	# Timed track hazards run on race time from GO (and keep going after the
	# finish, so they don't freeze mid-road on the results screen).
	track.hazard_time = track.hazard_time + delta if is_race_started else 0.0
	for racer in _racers:
		if not is_instance_valid(racer.trike) or racer.disconnected:
			continue
		if racer.is_proxy and not authoritative:
			continue
		racer.progress.update(racer.trike)
		if authoritative:
			racer.checkpoints.update(racer.progress.current_index, racer.trike.global_position)
		# Off the road and unreachable: put the trike back (the rider keeps
		# whatever they are doing; a riding rider comes along with the trike).
		# Proxies are put back by their owner.
		if not racer.is_proxy and track.is_out_of_bounds(racer.trike.global_position, racer.progress.current_index):
			racer.trike.request_respawn()
	if not authoritative:
		return
	if not is_race_over:
		finish_tracker.update(race_time)
	_update_positions()


# --- Adding racers ----------------------------------------------------------

## Registers the scene-placed local player. Returns null if the race is full
## or the id is taken.
func add_human_racer(trike: Trike, rider: RiderController, id := -1, display_name := "Player", slot := -1) -> Racer:
	var racer := _new_racer(Racer.Type.HUMAN, id, display_name, slot)
	if racer == null:
		return null
	racer.trike = trike
	racer.rider = rider
	racer.input_source = trike.input_source
	_register(racer)
	return racer


## Spawns an AI racer from the normal trike and rider scenes. Returns null if
## the race is full or the id is taken.
func add_ai_racer(difficulty := AIDriverConfig.Difficulty.MEDIUM, display_name := "", id := -1, slot := -1) -> Racer:
	var name_index := _count_ai()
	if display_name.is_empty():
		display_name = ai_names[name_index % ai_names.size()] if not ai_names.is_empty() else "Bot"
	var racer := _new_racer(Racer.Type.AI, id, display_name, slot)
	if racer == null:
		return null
	var root := Node3D.new()
	root.name = "Racer%d" % racer.id
	add_child(root)

	var driver := AIDriver.new()
	driver.name = "AIDriver"
	root.add_child(driver)

	var trike: Trike = TRIKE_SCENE.instantiate()
	trike.name = "Trike"
	trike.input_source = driver
	_remove_keyboard(trike)
	root.add_child(trike)

	var rider: RiderController = RIDER_SCENE.instantiate()
	rider.name = "RiderCharacter"
	rider.input_source = driver
	_remove_keyboard(rider)
	root.add_child(rider)
	rider.attach_to(trike)

	racer.root = root
	racer.trike = trike
	racer.rider = rider
	racer.input_source = driver
	_register(racer)
	driver.racer_id = racer.id
	driver.lane_offset = racer.lane_offset
	driver.setup(trike, rider, track, get_ai_config(difficulty), racer.id * 7919, self)
	if is_race_started:
		driver.start()
	return racer


## Online: a racer simulated on another computer. Same trike and rider
## scenes, but no input source and both in network proxy mode.
func add_proxy_racer(display_name: String, id: int, slot: int, is_ai: bool, owner_peer: int) -> Racer:
	var racer := _new_racer(Racer.Type.AI if is_ai else Racer.Type.HUMAN, id, display_name, slot)
	if racer == null:
		return null
	var root := Node3D.new()
	root.name = "Racer%d" % racer.id
	add_child(root)
	var trike: Trike = TRIKE_SCENE.instantiate()
	trike.name = "Trike"
	_remove_keyboard(trike)
	root.add_child(trike)
	var rider: RiderController = RIDER_SCENE.instantiate()
	rider.name = "RiderCharacter"
	_remove_keyboard(rider)
	root.add_child(rider)
	rider.attach_to(trike)
	trike.set_network_proxy(true)
	rider.set_network_proxy(true)
	racer.root = root
	racer.trike = trike
	racer.rider = rider
	racer.is_proxy = true
	racer.owner_peer = owner_peer
	_register(racer)
	return racer


## Online clients: positions, checkpoints and finishes decided by the host.
## status: [[id, position, checkpoints passed, distance, finished,
## finish position, finish time, dnf, pending], ...]
func apply_remote_status(status: Array) -> void:
	for entry: Array in status:
		var racer := get_racer(int(entry[0]))
		if racer == null or entry.size() < 9:
			continue
		racer.position = int(entry[1])
		racer.checkpoints.next_checkpoint = int(entry[2])
		racer.checkpoints.distance = float(entry[3])
		racer.did_not_finish = bool(entry[7])
		if bool(entry[8]) and not racer.pending_finish and not racer.finished:
			racer.pending_finish = true
			racer_pending.emit(racer)
		if bool(entry[4]) and not racer.finished:
			racer.finished = true
			racer.pending_finish = false
			racer.finish_position = int(entry[5])
			racer.finish_time = float(entry[6])
			racer_finished.emit(racer)
	_ranking.clear()
	for racer in _racers:
		_ranking.append(racer)
	_ranking.sort_custom(func(a: Racer, b: Racer) -> bool: return a.position < b.position)


## Host: the status list for apply_remote_status().
func build_status() -> Array:
	var status: Array = []
	for racer in _racers:
		status.append([racer.id, racer.position, racer.checkpoints.get_passed_count(), racer.checkpoints.distance,
				racer.finished, racer.finish_position, racer.finish_time, racer.did_not_finish, racer.pending_finish])
	return status


## The owner of this racer left: it counts as DNF and leaves the track.
func mark_disconnected(id: int) -> void:
	var racer := get_racer(id)
	if racer == null or racer.disconnected:
		return
	racer.disconnected = true
	racer.did_not_finish = not racer.finished
	if is_instance_valid(racer.root):
		racer.root.visible = false
		racer.root.process_mode = Node.PROCESS_MODE_DISABLED


## Racer ids whose owner is `peer_id`.
func get_racers_owned_by(peer_id: int) -> Array[Racer]:
	var owned: Array[Racer] = []
	for racer in _racers:
		if racer.owner_peer == peer_id and not racer.is_ai():
			owned.append(racer)
	return owned


func get_ai_config(difficulty: AIDriverConfig.Difficulty) -> AIDriverConfig:
	for ai_config in ai_configs:
		if ai_config and ai_config.difficulty == difficulty:
			return ai_config
	return AIDriverConfig.new()


# --- Queries ----------------------------------------------------------------

func get_racers() -> Array[Racer]:
	return _racers


func get_racer_count() -> int:
	return _racers.size()


func get_racer(id: int) -> Racer:
	for racer in _racers:
		if racer.id == id:
			return racer
	return null


## The racer that owns this trike or rider body, or null.
func get_racer_for_body(body: Node) -> Racer:
	for racer in _racers:
		if body == racer.trike or (racer.rider and (body == racer.rider.ragdoll or body == racer.rider.on_foot)):
			return racer
	return null


func is_full() -> bool:
	return _racers.size() >= max_racers


## Props AI racers steer around: {"node": Node3D, "radius": float, "kind": String}.
func get_obstacles() -> Array[Dictionary]:
	return _obstacles


## Ramps AI racers line up with: {"node": Node3D, "half_width": float}.
func get_ramps() -> Array[Dictionary]:
	return _ramps


## Racers in current race order (index 0 = 1st).
func get_ranking() -> Array[Racer]:
	return _ranking


func is_everyone_finished() -> bool:
	for racer in _racers:
		if not racer.finished and not racer.disconnected:
			return false
	return not _racers.is_empty()


# --- Race flow --------------------------------------------------------------

func start_race() -> void:
	if is_race_started:
		return
	is_race_started = true
	for racer in _racers:
		var driver := racer.get_ai_driver()
		if driver:
			driver.start()
	race_started.emit()


## Race over (everyone finished or finish timeout): stops the clock, ignores
## the finish line and marks unfinished racers DNF.
func stop_race() -> void:
	if is_race_over:
		return
	is_race_over = true
	for racer in _racers:
		racer.did_not_finish = not racer.finished
		var driver := racer.get_ai_driver()
		if driver:
			driver.active = false


## Locks or unlocks every racer's trike controls (lobby, countdown, race over).
func set_controls_locked(locked: bool) -> void:
	for racer in _racers:
		if is_instance_valid(racer.trike):
			racer.trike.input_locked = locked


## Back to the starting grid for another race: riders back on their trikes,
## trikes on their grid slots, progress, checkpoints, finish states, clock
## and AI state cleared, knocked-over props put back. Racers keep their ids,
## slots and colors. Controls stay locked until the next start.
func reset_for_new_race() -> void:
	race_time = 0.0
	is_race_started = false
	is_race_over = false
	finish_tracker.reset()
	var start_index := track.get_start_index()
	for racer in _racers:
		if racer.disconnected:
			continue
		if racer.rider and not racer.rider.is_riding():
			racer.rider.force_mount()
		racer.trike.teleport(racer.spawn_transform, false)
		racer.trike.input.clear()
		racer.trike.input_locked = true
		if racer.rider:
			racer.rider.input.clear()
		racer.progress.reset(start_index)
		racer.checkpoints.reset(start_index)
		racer.finished = false
		racer.finish_position = 0
		racer.finish_time = 0.0
		racer.did_not_finish = false
		racer.pending_finish = false
		racer.respawn_count = 0
		var driver := racer.get_ai_driver()
		if driver:
			driver.reset_for_race()
	var props := track.get_node_or_null(^"Props")
	if props and props.has_method(&"reset_props"):
		props.reset_props()
	_ranking.clear()
	_update_positions()


# --- Internals --------------------------------------------------------------

func _new_racer(type: Racer.Type, id: int, display_name: String, slot: int) -> Racer:
	if is_full():
		return null
	if id < 0:
		id = _next_free_id()
	elif get_racer(id) != null:
		return null
	if slot < 0 or _slot_taken(slot):
		slot = _next_free_slot()
	var racer := Racer.new()
	racer.type = type
	racer.id = id
	racer.display_name = display_name
	racer.spawn_slot = slot
	racer.lane_offset = lane_offsets[slot % lane_offsets.size()] if not lane_offsets.is_empty() else 0.0
	return racer


func _register(racer: Racer) -> void:
	var order := _racers.size()
	racer.color = racer_colors[order % racer_colors.size()] if not racer_colors.is_empty() else Color.WHITE
	racer.spawn_transform = track.get_start_transform(racer.spawn_slot)
	racer.trike.teleport(racer.spawn_transform, false)
	racer.progress = VehicleProgress.new(track, track.get_start_index())
	racer.checkpoints = CheckpointProgress.new(track, track.get_start_index())
	racer.rider.track = track
	racer.trike.respawn_requested.connect(_on_respawn_requested.bind(racer))
	racer.rider.emergency_recovery_requested.connect(_on_emergency_recovery.bind(racer))
	finish_tracker.register_racer(racer.id, racer.trike, racer.rider, racer.progress)
	_apply_livery(racer, order)
	_racers.append(racer)
	_update_positions()
	racer_added.emit(racer)


func _apply_livery(racer: Racer, order: int) -> void:
	var visuals := racer.trike.get_node_or_null(^"Visuals") as TrikeVisuals
	if visuals:
		visuals.body_color = racer.color
	if racer_numbers.is_empty():
		return
	var number := str(racer_numbers[order % racer_numbers.size()])
	for path: NodePath in [^"Visuals/NumberSideL", ^"Visuals/NumberSideR", ^"Visuals/FrontPivot/PlateNumber"]:
		var label := racer.trike.get_node_or_null(path) as Label3D
		if label:
			label.text = number


## AI racers must never read the keyboard: drop the scene's PlayerInputSource.
static func _remove_keyboard(node: Node) -> void:
	var keyboard := node.get_node_or_null(^"PlayerInputSource")
	if keyboard:
		node.remove_child(keyboard)
		keyboard.free()


func _next_free_id() -> int:
	var id := 1
	while get_racer(id) != null:
		id += 1
	return id


func _slot_taken(slot: int) -> bool:
	for racer in _racers:
		if racer.spawn_slot == slot:
			return true
	return false


func _next_free_slot() -> int:
	var slot := 0
	while _slot_taken(slot):
		slot += 1
	return slot


func _count_ai() -> int:
	var count := 0
	for racer in _racers:
		if racer.is_ai():
			count += 1
	return count


func _collect_obstacles() -> void:
	_obstacles.clear()
	_ramps.clear()
	var props := track.get_node_or_null(^"Props")
	if props == null:
		return
	for child in props.get_children():
		if child is Ramp:
			_ramps.append({"node": child, "half_width": (child as Ramp).width * 0.5})
			continue
		var kind := (child as Node).scene_file_path.get_file().get_basename()
		if obstacle_radii.has(kind):
			_obstacles.append({"node": child, "radius": float(obstacle_radii[kind]), "kind": kind})


func _respawn_transform(racer: Racer, index: int) -> Transform3D:
	var half := track.half_width_at(index) - 2.0
	return track.get_respawn_transform(index, clampf(racer.lane_offset, -half, half))


func _on_respawn_requested(trike: Trike, racer: Racer) -> void:
	var index := racer.progress.last_safe_index
	trike.teleport(_respawn_transform(racer, index))
	racer.progress.reset(index)
	racer.respawn_count += 1
	racer_respawned.emit(racer)


## R while off the trike: trike back on the road, rider back on the seat.
func _on_emergency_recovery(racer: Racer) -> void:
	var index := racer.progress.last_safe_index
	racer.trike.teleport(_respawn_transform(racer, index))
	racer.progress.reset(index)
	racer.rider.force_mount()
	racer.respawn_count += 1
	racer_respawned.emit(racer)


func _update_positions() -> void:
	_ranking = RacePositions.rank(_racers, _ranking, position_swap_margin)
	for i in _ranking.size():
		_ranking[i].position = i + 1


## Finish gate for FinishTracker: every checkpoint passed in order. Players
## the manager doesn't know (registered with the tracker directly) aren't gated.
func _can_finish(player_id: int) -> bool:
	var racer := get_racer(player_id)
	return racer == null or racer.checkpoints == null or racer.checkpoints.can_finish()


## Any body entering the finish line; the tracker resolves which player's
## vehicle it is (if any) and whether the rider is aboard.
func _on_finish_crossed(body: Node3D) -> void:
	if is_race_started and not is_race_over:
		finish_tracker.on_body_crossed(body, race_time)


func _on_racer_finished(player_id: int, position: int, finish_time: float) -> void:
	var racer := get_racer(player_id)
	if racer == null:
		return
	racer.finished = true
	racer.finish_position = position
	racer.finish_time = finish_time
	racer.pending_finish = false
	racer.checkpoints.complete()
	var driver := racer.get_ai_driver()
	if driver:
		driver.finished = true
	racer_finished.emit(racer)
