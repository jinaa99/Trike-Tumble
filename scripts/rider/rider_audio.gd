class_name RiderAudio
extends Node
## Rider sounds (positional, SFX bus) from the rider's state changes, so a
## network proxy rider sounds the same: a "whoa!" when thrown off, a thud
## on landing, a boing and dizzy chime on getting up, footsteps while on
## foot (a softer crunch on snow), a hop when mounting.
## Created by RiderController.

## Meters walked or run per footstep.
@export var stride := 0.95

## Voice bark per reaction kind: [sound, shortest time between two (s), volume dB].
const BARKS := {
	&"laugh": [&"bark_laugh", 3.5, -3.0], &"yelp": [&"eject", 1.2, -4.0], &"cheer": [&"cheer", 3.0, -5.0],
	&"taunt": [&"bark_taunt", 2.0, -3.0], &"smug": [&"bark_heh", 4.0, -6.0], &"confused": [&"bark_huh", 2.0, -3.0],
	&"grumble": [&"bark_grr", 5.0, -6.0], &"skill": [&"bark_hup", 2.0, -6.0],
}
## Voice pitch per character (Zip, Pip, Bramble, Nutmeg, Rusty).
const VOICE_PITCH: Array[float] = [1.1, 1.26, 0.94, 1.42, 0.78]
## No rider speaks within this long of its own last bark; at most
## MAX_VOICES barks start within VOICE_WINDOW seconds in the whole scene.
const OWN_GAP := 0.7
const MAX_VOICES := 2
const VOICE_WINDOW := 0.6

static var _recent_barks: Array[float] = []

var rider: RiderController
## Barks played so far, by kind (tests).
var barks: Array[StringName] = []
var _bark_ready := {}
var _last_bark := -100.0
## Footsteps played so far (tests).
var steps := 0
var _last_foot := Vector3.INF


func setup(controller: RiderController) -> void:
	rider = controller
	rider.state_changed.connect(_on_state_changed)


## A short voice reaction (see BARKS), pitched to the rider's character.
## Rate-limited per kind, per rider and across the scene. Returns true if
## it played.
func bark(kind: StringName) -> bool:
	if rider == null or not BARKS.has(kind) or not rider.is_inside_tree():
		return false
	var now := Time.get_ticks_msec() / 1000.0
	var spec: Array = BARKS[kind]
	if now < float(_bark_ready.get(kind, -100.0)) or now - _last_bark < OWN_GAP:
		return false
	while not _recent_barks.is_empty() and now - _recent_barks[0] > VOICE_WINDOW:
		_recent_barks.pop_front()
	if _recent_barks.size() >= MAX_VOICES:
		return false
	_recent_barks.append(now)
	_bark_ready[kind] = now + float(spec[1])
	_last_bark = now
	barks.append(kind)
	var pitch := VOICE_PITCH[posmod(rider.character, VOICE_PITCH.size())] * randf_range(0.95, 1.06)
	SoundPlayer.play_at(rider, spec[0], rider.get_rider_position(), float(spec[2]), pitch)
	return true


func _on_state_changed(_old: RiderController.State, new_state: RiderController.State) -> void:
	var at := rider.get_rider_position()
	match new_state:
		RiderController.State.EJECTED:
			SoundPlayer.play_at(rider, &"eject", at, -2.0, randf_range(1.1, 1.35))
		RiderController.State.RAGDOLL:
			SoundPlayer.play_at(rider, &"fall_thud", at, -2.0)
			SoundPlayer.play_at(rider, &"oof", at, -6.0, randf_range(1.05, 1.3))
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
