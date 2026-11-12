class_name TrackAutopilot
extends RefCounted
## Test helper: steers a trike along a track centerline by writing to its
## TrikeInput. Used by automated tests and screenshot capture, not gameplay.

var track: Track
var trike: Trike
var lookahead_samples := 7
var steer_gain := 2.8
var target_speed := 22.0
## Meters right (+) or left (-) of the centerline to drive on.
var lateral_offset := 0.0
var _index := 0


func _init(for_track: Track, for_trike: Trike) -> void:
	track = for_track
	trike = for_trike
	_index = track.path.find_nearest(trike.global_position)


func drive() -> void:
	_index = track.path.find_nearest(trike.global_position, _index)
	var speed_bonus := int(trike.forward_speed / 6.0)
	var ahead := mini(_index + lookahead_samples + speed_bonus, track.path.size() - 1)
	var target := track.path.points[ahead] + track.path.rights[ahead] * lateral_offset
	var forward := -trike.global_basis.z
	forward.y = 0.0
	var to_target := target - trike.global_position
	to_target.y = 0.0
	var angle := forward.signed_angle_to(to_target, Vector3.UP)  # + = target to the left
	trike.input.steer = clampf(-angle * steer_gain, -1.0, 1.0)
	var too_fast := trike.forward_speed > target_speed and absf(angle) > 0.25
	trike.input.throttle = 0.0 if too_fast else 1.0
	trike.input.brake = 0.6 if too_fast else 0.0
	trike.input.drift = false


## Like a person: picks a line around obstacles seen up to 40 m ahead
## (`obstacles`: RacerManager.get_obstacles()) and sets `lateral_offset`;
## drifts back to `home_offset` when the road is clear. Call before drive().
func dodge(obstacles: Array[Dictionary], home_offset := 0.0) -> void:
	var index := track.path.find_nearest(trike.global_position, _index)
	var half := track.half_width_at(index) - 1.6
	var forward := track.path.forwards[index]
	for obstacle: Dictionary in obstacles:
		var node: Node3D = obstacle["node"]
		if not is_instance_valid(node) or (node.has_method(&"is_active") and not node.call(&"is_active")):
			continue
		var along := (node.global_position - trike.global_position).dot(forward)
		if along < -2.0 or along > 40.0:
			continue
		var at := track.path.find_nearest(node.global_position, index)
		var lateral := (node.global_position - track.path.points[at]).dot(track.path.rights[at])
		var clearance: float = obstacle["radius"] + 2.0
		if absf(lateral_offset - lateral) < clearance:
			# Pass on the side with more room.
			lateral_offset = clampf(lateral + clearance if lateral < 0.0 else lateral - clearance, -half, half)
			return
		if absf(lateral_offset - lateral) < clearance + 1.0:
			return
	lateral_offset = move_toward(lateral_offset, clampf(home_offset, -half, half), 0.05)
