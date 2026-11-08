class_name TrackAutopilot
extends RefCounted
## Test helper: steers a trike along a track centerline by writing to its
## TrikeInput. Used by automated tests and screenshot capture, not gameplay.

var track: Track
var trike: Trike
var lookahead_samples := 7
var steer_gain := 2.8
var target_speed := 22.0
var _index := 0


func _init(for_track: Track, for_trike: Trike) -> void:
	track = for_track
	trike = for_trike
	_index = track.path.find_nearest(trike.global_position)


func drive() -> void:
	_index = track.path.find_nearest(trike.global_position, _index)
	var speed_bonus := int(trike.forward_speed / 6.0)
	var target := track.path.points[mini(_index + lookahead_samples + speed_bonus, track.path.size() - 1)]
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
