class_name RaceAudio
extends Node
## Race sounds and the finish celebration effects (one per race scene,
## created by RaceSession): countdown beeps and GO, the local player's finish
## fanfare with a confetti burst at the finish arch, and on the results
## screen a victory jingle for a podium place (a softer chord otherwise).

## Confetti: pieces and spread (m), fired at the finish line.
@export var confetti_pieces := 40
@export var confetti_spread := 5.5

var session: RaceSession
## Confetti bursts fired (tests).
var confetti_bursts := 0


func setup(race_session: RaceSession) -> void:
	session = race_session
	session.race.countdown_step.connect(_on_countdown_step)
	session.racers.racer_finished.connect(_on_racer_finished)
	session.race.state_changed.connect(_on_state_changed)
	_update_music(session.race.get_state())


func _on_countdown_step(text: String) -> void:
	if text == session.race.go_text:
		SoundPlayer.play_flat(self, &"go", -2.0)
	elif text.is_valid_int():
		SoundPlayer.play_flat(self, &"countdown", -4.0)


func _on_racer_finished(racer: Racer) -> void:
	if racer != session.get_local_racer():
		return
	SoundPlayer.play_flat(self, &"finish", -2.0)
	if racer.finish_position <= 3:
		SoundPlayer.play_flat(self, &"cheer", -5.0)
	fire_confetti(session.track.get_node_or_null(^"FinishGate") as Node3D)


## Menu theme in the lobby, race track from the countdown on, ducked under
## the results screen.
func _update_music(state: RaceStateMachine.State) -> void:
	MusicPlayer.play(&"menu" if state == RaceStateMachine.State.LOBBY else &"race")
	MusicPlayer.duck(state == RaceStateMachine.State.RESULTS)


func _on_state_changed(_old: RaceStateMachine.State, new_state: RaceStateMachine.State) -> void:
	_update_music(new_state)
	if new_state != RaceStateMachine.State.RESULTS:
		return
	var me := session.get_local_racer()
	var podium := me != null and me.finished and me.finish_position <= 3
	SoundPlayer.play_flat(self, &"victory" if podium else &"results", -3.0)


## Colorful confetti bursting over the finish arch (above head height, so
## it never hides the road).
func fire_confetti(at: Node3D) -> void:
	confetti_bursts += 1
	if at == null:
		return
	var colors: Array[Color] = [Color(1.0, 0.3, 0.35), Color(1.0, 0.82, 0.2), Color(0.3, 0.75, 1.0),
			Color(0.4, 0.88, 0.45), Color(0.9, 0.5, 1.0)]
	for k in colors.size():
		var offset := at.global_basis.x * lerpf(-confetti_spread, confetti_spread, k / 4.0)
		ItemVisuals.burst(at, at.global_position + offset + Vector3.UP * 5.5, colors[k],
				maxi(roundi(confetti_pieces / float(colors.size())), 1), 3.0, 1.4)
