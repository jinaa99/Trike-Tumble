class_name NetRaceSync
extends Node
## Online race glue (one per race scene, created by RaceSession).
##
## - Sends a snapshot of every racer this computer simulates (its player;
##   on the host also the AI) every `send_interval_ticks` physics ticks.
## - Feeds received snapshots into one SnapshotBuffer per proxy racer and
##   moves the proxies every tick from the interpolated state (trike as a
##   kinematic body, so local trikes collide with it; rider state + body).
## - Host: sends positions/checkpoints/finish state `status_rate` times a second.

@export var send_interval_ticks := 2
@export var status_rate := 10.0
## Seconds the proxies trail the newest data (jitter buffer).
@export var interpolation_delay := 0.1

var racers: RacerManager
## Snapshots sent / received (diagnostics, tests).
var sent := 0
var received := 0
## Largest normal proxy move in one tick (m), and how many times a proxy
## jumped (owner respawns/resets, or a move over `jump_threshold`).
var max_proxy_step := 0.0
var proxy_jumps := 0
var jump_log: Array[String] = []
## Jumps not caused by an owner teleport (should stay 0).
var unexplained_jumps := 0
## Ticks where a proxy moved more than `hitch_step` (usually this computer
## stalled and the playback clock caught up).
var hitches := 0
@export var hitch_step := 1.0
## A proxy moving more than this in one tick counts as a jump, not motion.
@export var jump_threshold := 3.0

## Proxy playback clock: advances with physics ticks (steady steps even when
## a slow frame makes several ticks run back to back) and is pulled gently
## toward the wall clock; resyncs after a long stall.
var _play_time := -1.0
var _buffers := {}
var _tick := 0
var _status_elapsed := 0.0
var _last_proxy_positions := {}
var _last_teleports := {}


func setup(manager: RacerManager) -> void:
	racers = manager
	for racer in racers.get_racers():
		if racer.is_proxy:
			var buffer := SnapshotBuffer.new()
			buffer.delay = interpolation_delay
			_buffers[racer.id] = buffer


static func now() -> float:
	return Time.get_ticks_usec() / 1000000.0


func receive_snapshot(racer_id: int, data: Array) -> void:
	var buffer: SnapshotBuffer = _buffers.get(racer_id)
	if buffer:
		buffer.push(data, now())
		received += 1


func get_buffer(racer_id: int) -> SnapshotBuffer:
	return _buffers.get(racer_id)


func _physics_process(delta: float) -> void:
	if racers == null:
		return
	_tick += 1
	var t := now()
	if _play_time < 0.0 or absf(t - _play_time) > 0.25:
		_play_time = t
	else:
		_play_time += delta
		_play_time += (t - _play_time) * 0.05
	if _tick % send_interval_ticks == 0:
		for racer in racers.get_racers():
			if racer.is_proxy or racer.disconnected or not is_instance_valid(racer.trike):
				continue
			Net.send_snapshot(racer.id, NetSnapshot.encode(t, racer.trike.get_network_state(), racer.rider.get_network_state()))
			sent += 1
	for racer in racers.get_racers():
		if not racer.is_proxy or racer.disconnected:
			continue
		var state: Dictionary = (_buffers[racer.id] as SnapshotBuffer).sample(_play_time)
		if state.is_empty():
			continue
		racer.trike.apply_network_state(state["trike"])
		racer.rider.apply_network_state(state["rider"])
		var position := racer.trike.global_position
		var teleported := racer.trike.teleport_count != int(_last_teleports.get(racer.id, racer.trike.teleport_count))
		_last_teleports[racer.id] = racer.trike.teleport_count
		if _last_proxy_positions.has(racer.id):
			var step := position.distance_to(_last_proxy_positions[racer.id])
			if teleported or step > jump_threshold:
				proxy_jumps += 1
				if not teleported:
					unexplained_jumps += 1
				jump_log.append("racer %d %s %.1f m at %.1f s" % [racer.id, "respawn" if teleported else "JUMP", step,
						racers.race_time])
			else:
				max_proxy_step = maxf(max_proxy_step, step)
				if step > hitch_step:
					hitches += 1
		_last_proxy_positions[racer.id] = position
	if Net.is_host():
		_status_elapsed += delta
		if _status_elapsed >= 1.0 / status_rate:
			_status_elapsed = 0.0
			Net.send_status(racers.build_status())


## After a reset (Race Again) proxies restart from fresh data.
func clear_buffers() -> void:
	for buffer: SnapshotBuffer in _buffers.values():
		buffer.clear()
	_last_proxy_positions.clear()
	_last_teleports.clear()
