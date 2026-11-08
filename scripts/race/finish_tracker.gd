class_name FinishTracker
extends RefCounted
## Player-specific finish detection.
##
## Each racer is registered under a player id with its own trike, rider and
## progress tracker. A finish-line crossing is resolved to the owning player
## through the trike, so another player's vehicle can never finish for you.
##
## - Trike crosses with its rider aboard  -> finish confirmed immediately.
## - Trike crosses empty (rider thrown off) -> finish is PENDING. It is
##   confirmed on the first tick the owner is back on that trike while the
##   trike is still past the line (normal [E] mount or emergency recovery).
##   If the trike ends up back before the line, the pending finish is dropped
##   and the line must be crossed again.
## - Every player finishes at most once.
##
## The official finish time is the race time when the finish is confirmed
## (the rider must be aboard to finish). Positions count up from 1 in
## confirmation order. Pure data + logic (no nodes), so a future host can run
## it authoritatively and broadcast `racer_finished`.

signal racer_finished(player_id: int, position: int, finish_time: float)
signal finish_pending(player_id: int, crossed_time: float)

## player_id -> {"trike": Trike, "rider": RiderController, "progress": VehicleProgress}
var _racers := {}
## player_id -> race time when the empty trike crossed
var _pending := {}
## player_id -> {"position", "time", "crossed_time"}
var _results := {}
var _finish_index := 0


func _init(finish_index: int) -> void:
	_finish_index = finish_index


func register_racer(player_id: int, trike: Trike, rider: RiderController, progress: VehicleProgress) -> void:
	_racers[player_id] = {"trike": trike, "rider": rider, "progress": progress}


func unregister_racer(player_id: int) -> void:
	_racers.erase(player_id)
	_pending.erase(player_id)


## Which registered player owns this body (a trike). -1 if nobody.
func get_owner_id(body: Node) -> int:
	for player_id: int in _racers:
		if _racers[player_id]["trike"] == body:
			return player_id
	return -1


## Called when anything enters the finish line.
func on_body_crossed(body: Node, race_time: float) -> void:
	var player_id := get_owner_id(body)
	if player_id < 0 or has_finished(player_id):
		return
	var rider: RiderController = _racers[player_id]["rider"]
	if rider == null or rider.is_riding():
		_confirm(player_id, race_time, race_time)
	elif not _pending.has(player_id):
		_pending[player_id] = race_time
		finish_pending.emit(player_id, race_time)


## Call every physics tick: confirms or drops pending finishes.
func update(race_time: float) -> void:
	for player_id: int in _pending.keys():
		var racer: Dictionary = _racers.get(player_id, {})
		if racer.is_empty():
			_pending.erase(player_id)
			continue
		var progress: VehicleProgress = racer["progress"]
		if progress.current_index < _finish_index - 1:
			_pending.erase(player_id)  # trike went back before the line
			continue
		var rider: RiderController = racer["rider"]
		if rider.is_riding():
			_confirm(player_id, race_time, _pending[player_id])


func has_finished(player_id: int) -> bool:
	return _results.has(player_id)


func is_pending(player_id: int) -> bool:
	return _pending.has(player_id)


## {"position": int, "time": float, "crossed_time": float}, or {} if not finished.
func get_result(player_id: int) -> Dictionary:
	return _results.get(player_id, {})


func get_finished_count() -> int:
	return _results.size()


func _confirm(player_id: int, race_time: float, crossed_time: float) -> void:
	if has_finished(player_id):
		return
	_pending.erase(player_id)
	var position := _results.size() + 1
	_results[player_id] = {"position": position, "time": race_time, "crossed_time": crossed_time}
	racer_finished.emit(player_id, position, race_time)
