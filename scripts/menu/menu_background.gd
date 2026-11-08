extends Node3D
## Main menu backdrop: AI racers on the real track, filmed by a slow,
## orbiting cinematic camera that follows the leader. Restarts the race when
## everyone is done (or after `loop_time`).

@export var racer_count := 4
## Seconds before the background race starts over regardless.
@export var loop_time := 70.0
## TV-style shot from ahead of the leader (so racers never pass through the
## camera): distance, height, and a slow swing between the two sides.
@export var camera_distance := 12.0
@export var camera_height := 3.2
@export var orbit_speed := 0.12
## Swing (degrees from straight ahead) of the camera around the leader.
@export var orbit_min_deg := 25.0
@export var orbit_max_deg := 70.0
@export var camera_smoothing := 2.5

var racers: RacerManager
var _orbit := 0.0
var _focus := Vector3.ZERO

@onready var track: Track = $TestTrack
@onready var camera: Camera3D = $Camera


func _ready() -> void:
	racers = RacerManager.new()
	racers.name = "Racers"
	racers.ai_configs = [load("res://resources/ai/ai_easy.tres"), load("res://resources/ai/ai_medium.tres"),
			load("res://resources/ai/ai_hard.tres")]
	add_child(racers)
	racers.setup(track)
	var difficulties := [AIDriverConfig.Difficulty.HARD, AIDriverConfig.Difficulty.MEDIUM,
			AIDriverConfig.Difficulty.MEDIUM, AIDriverConfig.Difficulty.EASY, AIDriverConfig.Difficulty.HARD]
	for i in clampi(racer_count, 1, 5):
		racers.add_ai_racer(difficulties[i])
	_start()
	GameSettings.apply_graphics(self)
	_focus = racers.get_racers()[0].trike.global_position
	_place_camera(1.0)


func _start() -> void:
	racers.start_race()
	racers.set_controls_locked(false)


func _physics_process(_delta: float) -> void:
	if racers.is_everyone_finished() or racers.race_time > loop_time:
		racers.reset_for_new_race()
		_start()


func _process(delta: float) -> void:
	_orbit += delta * orbit_speed
	_place_camera(delta)


func _place_camera(delta: float) -> void:
	var ranking := racers.get_ranking()
	if ranking.is_empty():
		return
	var leader := ranking[0].trike
	var target := leader.get_global_transform_interpolated().origin
	_focus = _focus.lerp(target, 1.0 - exp(-camera_smoothing * delta))
	var index := track.path.find_nearest(_focus, ranking[0].progress.current_index)
	var ahead := track.path.forwards[index]
	ahead.y = 0.0
	ahead = ahead.normalized()
	var swing := deg_to_rad(lerpf(orbit_min_deg, orbit_max_deg, 0.5 + 0.5 * sin(_orbit)))
	var offset := ahead.rotated(Vector3.UP, swing) * camera_distance + Vector3.UP * camera_height
	camera.global_position = _focus + offset
	camera.look_at(_focus + Vector3.UP * 0.6 - ahead * 4.0, Vector3.UP)
