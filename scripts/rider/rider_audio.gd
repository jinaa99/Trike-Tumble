class_name RiderAudio
extends Node
## Rider sounds (positional, SFX bus) from the rider's state changes, so a
## network proxy rider sounds the same: a "whoa!" when thrown off, a thud
## on landing, a boing and dizzy chime on getting up, footsteps while on
## foot (a softer crunch on snow), a hop when mounting.
## Created by RiderController.

## Meters walked or run per footstep.
@export var stride := 0.95

var rider: RiderController
## Footsteps played so far (tests).
var steps := 0
var _last_foot := Vector3.INF


func setup(controller: RiderController) -> void:
	rider = controller
	rider.state_changed.connect(_on_state_changed)


func _on_state_changed(_old: RiderController.State, new_state: RiderController.State) -> void:
	var at := rider.get_rider_position()
	match new_state:
		RiderController.State.EJECTED:
			SoundPlayer.play_at(rider, &"eject", at, 0.0, randf_range(0.92, 1.12))
		RiderController.State.RAGDOLL:
			SoundPlayer.play_at(rider, &"fall_thud", at, -2.0)
		RiderController.State.GETTING_UP:
			SoundPlayer.play_at(rider, &"get_up", at, -4.0)
		RiderController.State.MOUNTING:
			SoundPlayer.play_at(rider, &"mount", at, -4.0)
	_last_foot = Vector3.INF


func _physics_process(_delta: float) -> void:
	if rider == null or rider.state != RiderController.State.ON_FOOT or not rider.is_node_ready():
		return
	var foot := rider.on_foot.global_position
	if _last_foot == Vector3.INF:
		_last_foot = foot
		return
	var moved := Vector2(foot.x - _last_foot.x, foot.z - _last_foot.z).length()
	if moved >= stride:
		_last_foot = foot
		steps += 1
		var snowy := rider.track != null and rider.track.road_surface == TrackSurface.Kind.SNOW
		SoundPlayer.play_at(rider, &"step_snow" if snowy else &"step", foot, -8.0, randf_range(0.9, 1.15), 6.0)
