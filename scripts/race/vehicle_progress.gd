class_name VehicleProgress
extends RefCounted
## Tracks one vehicle's position along a Track: the nearest sample, and the
## last sample where it was safely on the road (used as the respawn point).
## One instance per racer, so it scales to 5 players unchanged.

var track: Track
var current_index := 0
var last_safe_index := 0


func _init(for_track: Track, start_index := 0) -> void:
	track = for_track
	reset(start_index)


## Placed at `index` (start, respawn, teleport). The respawn point is the
## nearest safe sample at or before it.
func reset(index: int) -> void:
	current_index = index
	last_safe_index = track.get_recovery_index(index)


func update(trike: Trike) -> void:
	current_index = track.path.find_nearest(trike.global_position, current_index)
	var upright := trike.global_basis.y.dot(Vector3.UP) > 0.7
	if trike.is_grounded() and upright and track.is_on_road(trike.global_position, current_index) \
			and track.is_safe_index(current_index):
		last_safe_index = current_index


## Distance travelled along the track in meters.
func get_distance() -> float:
	return current_index * track.path.spacing
