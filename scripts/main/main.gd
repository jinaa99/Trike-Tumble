class_name RaceSession
extends Node3D
## Single-player race session for the prototype.
##
## Wires track, trike, rider, camera, HUD and pause menu together and owns
## race rules: spawning, respawning (manual, emergency, out of bounds) and the
## timer. The rider's fall/recovery loop lives in RiderController; this node
## only connects it to the camera, HUD and track. Systems talk through signals and small APIs so this can later
## become a multiplayer race manager that handles several trikes.

@export var respawn_message := "Back on track!"
@export var wipeout_messages: Array[String] = ["WIPEOUT!", "BONK!", "OOF!", "WHOOPS!"]

var _progress: VehicleProgress
var _race_time := 0.0
var _race_started := false
var _race_finished := false

@onready var track: Track = $TestTrack
@onready var trike: Trike = $Trike
@onready var rider: RiderController = $RiderCharacter
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

	rider.track = track
	rider.focus_changed.connect(follow_camera.set_target)
	rider.mount_prompt_changed.connect(hud.set_mount_prompt)
	rider.ejected.connect(_on_rider_ejected)
	rider.emergency_recovery_requested.connect(_on_emergency_recovery)

	follow_camera.target = trike
	follow_camera.snap_to_target()
	hud.set_vehicle(trike)
	hud.show_message("Hold W to ride!", 3.0)


func _physics_process(delta: float) -> void:
	_progress.update(trike)
	# Off the road and unreachable: put the trike back (the rider keeps
	# whatever they are doing; a riding rider comes along with the trike).
	if track.is_out_of_bounds(trike.global_position, _progress.current_index):
		trike.request_respawn()

	if not _race_started and (trike.input.throttle > 0.0 or not rider.is_riding()):
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


func _on_rider_ejected(_strength: float) -> void:
	hud.show_message(wipeout_messages[randi() % wipeout_messages.size()], 1.2)


## R while off the trike: trike back on the road, rider back on the seat.
func _on_emergency_recovery() -> void:
	var index := _progress.last_safe_index
	trike.teleport(track.get_respawn_transform(index))
	_progress.reset(index)
	rider.force_mount()
	hud.show_message(respawn_message, 1.2)


func _on_finish_crossed(body: Node3D) -> void:
	if body != trike or not rider.is_riding() or _race_finished or not _race_started:
		return
	_race_finished = true
	hud.set_race_time(_race_time)
	hud.show_message("FINISH!  %s" % Hud.format_time(_race_time), 6.0)
