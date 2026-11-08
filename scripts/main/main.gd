class_name RaceSession
extends Node3D
## Single-player race session for the prototype.
##
## Wires track, trike, camera, HUD and pause menu together and owns race
## rules: spawning, respawning (manual, automatic, out of bounds) and the
## timer. Systems talk through signals and small APIs so this can later
## become a multiplayer race manager that handles several trikes.

@export var respawn_message := "Back on track!"

var _progress: VehicleProgress
var _race_time := 0.0
var _race_started := false
var _race_finished := false

@onready var track: Track = $TestTrack
@onready var trike: Trike = $Trike
@onready var follow_camera: FollowCamera = $FollowCamera
@onready var hud: Hud = $HUD
@onready var pause_menu: PauseMenu = $PauseMenu


func _ready() -> void:
	_progress = VehicleProgress.new(track, track.get_start_index())
	trike.teleport(track.get_start_transform(0))
	trike.respawn_requested.connect(_on_respawn_requested)
	trike.respawned.connect(follow_camera.snap_to_target)
	track.finish_crossed.connect(_on_finish_crossed)
	pause_menu.restart_requested.connect(restart)

	follow_camera.target = trike
	follow_camera.snap_to_target()
	hud.set_vehicle(trike)
	hud.show_message("Hold W to ride!", 3.0)


func _physics_process(delta: float) -> void:
	_progress.update(trike)
	if track.is_out_of_bounds(trike.global_position, _progress.current_index):
		trike.request_respawn()

	if not _race_started and trike.input.throttle > 0.0:
		_race_started = true
	if _race_started and not _race_finished:
		_race_time += delta
		hud.set_race_time(_race_time)


func restart() -> void:
	get_tree().reload_current_scene()


func get_progress() -> VehicleProgress:
	return _progress


func get_race_time() -> float:
	return _race_time


func is_race_finished() -> bool:
	return _race_finished


func _on_respawn_requested(target: Trike) -> void:
	var index := _progress.last_safe_index
	target.teleport(track.get_respawn_transform(index))
	_progress.reset(index)
	hud.show_message(respawn_message, 1.2)


func _on_finish_crossed(body: Node3D) -> void:
	if body != trike or _race_finished or not _race_started:
		return
	_race_finished = true
	hud.set_race_time(_race_time)
	hud.show_message("FINISH!  %s" % Hud.format_time(_race_time), 6.0)
