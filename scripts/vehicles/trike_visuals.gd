class_name TrikeVisuals
extends Node3D
## Purely cosmetic: places/spins wheels from the physics state, turns the
## fork and handlebars, poses the rider (IK keeps hands on the grips), sways
## the safety flag and drives drift/boost effects.
## Wheel nodes are placed exactly where the physics raycast wheels are.
## Holds no gameplay state, so remote (networked) trikes can reuse it as is.

const DRIFT_TIER_COLORS: Array[Color] = [
	Color(0.85, 0.78, 0.65), Color(0.35, 0.75, 1.0), Color(1.0, 0.55, 0.15),
]

## Recolors every mesh in the "body_paint" group (per-player colors later).
@export var body_color := Color(1.0, 0.4, 0.2):
	set(value):
		body_color = value
		if is_node_ready():
			_apply_body_color()
## Handlebar turns this fraction of the front wheel angle (keeps arms comfortable).
@export_range(0.0, 1.0) var handlebar_steer_ratio := 0.6
@export var flag_sway_deg := 22.0

var _trike: Trike
var _wheel_spin := PackedFloat32Array([0.0, 0.0, 0.0])
var _flag_time := 0.0
var _flag_lean := 0.0

@onready var _wheels: Array[Node3D] = [$FrontPivot/FrontWheel, $RearWheelLeft, $RearWheelRight]
@onready var _wheel_spinners: Array[Node3D] = [
	$FrontPivot/FrontWheel/Spin, $RearWheelLeft/Spin, $RearWheelRight/Spin,
]
@onready var _front_pivot: Node3D = $FrontPivot
@onready var _handlebar: Node3D = $Handlebar
@onready var _rider: Rider = $Rider
@onready var _drift_particles: Array[CPUParticles3D] = [$DriftDustLeft, $DriftDustRight]
@onready var _drift_sparks: Array[CPUParticles3D] = [$DriftSparksLeft, $DriftSparksRight]
@onready var _boost_flame: Node3D = $BoostFlame
@onready var _flag_pivot: Node3D = $FlagPivot


func _ready() -> void:
	_trike = get_parent() as Trike
	_apply_body_color()
	_front_pivot.position = _trike.get_wheel_mount(Trike.Wheel.FRONT)


func _process(delta: float) -> void:
	if _trike == null:
		return
	for i in Trike.WHEEL_COUNT:
		var drop := _trike.wheel_suspension_length[i]
		var mount := _trike.get_wheel_mount(i)
		if i == Trike.Wheel.FRONT:
			_wheels[i].position = Vector3(0.0, -drop, 0.0)
		else:
			_wheels[i].position = mount + Vector3(0.0, -drop, 0.0)
		var spin_speed := _trike.forward_speed / _trike.get_wheel_radius(i)
		_wheel_spin[i] = wrapf(_wheel_spin[i] - spin_speed * delta, -TAU, TAU)
		_wheel_spinners[i].rotation.x = _wheel_spin[i]
	_front_pivot.rotation.y = _trike.steer_angle
	_handlebar.rotation.y = _trike.steer_angle * handlebar_steer_ratio
	_update_flag(delta)

	var speed_ratio := clampf(absf(_trike.forward_speed) / _trike.config.max_speed, 0.0, 1.0)
	var lean := _trike.steer_amount
	if _trike.is_drifting:
		lean = float(_trike.drift_direction) * 1.2
	_rider.update_pose(lean, speed_ratio, delta)

	var tier := _trike.get_drift_tier()
	for i in _drift_particles.size():
		var particles := _drift_particles[i]
		var wheel := Trike.Wheel.REAR_LEFT if i == 0 else Trike.Wheel.REAR_RIGHT
		var sliding := _trike.is_drifting and _trike.wheel_contact[wheel]
		particles.emitting = sliding
		particles.color = DRIFT_TIER_COLORS[tier]
		_drift_sparks[i].emitting = sliding and tier > 0
		_drift_sparks[i].color = DRIFT_TIER_COLORS[tier]
	_boost_flame.visible = _trike.boost_time > 0.0
	if _boost_flame.visible:
		_boost_flame.scale = Vector3(1.0, 1.0, randf_range(0.75, 1.3))


## Whip flag trails back with speed, swings out in turns and flutters.
func _update_flag(delta: float) -> void:
	var speed := _trike.linear_velocity.length()
	var yaw_rate := _trike.angular_velocity.dot(_trike.global_basis.y)
	_flag_time += delta * (4.0 + speed * 0.6)
	_flag_lean = lerpf(_flag_lean, clampf(yaw_rate * speed * 0.04, -1.0, 1.0), 1.0 - exp(-4.0 * delta))
	var flutter := sin(_flag_time) * (0.15 + minf(speed / 25.0, 1.0) * 0.35)
	_flag_pivot.rotation = Vector3(
		deg_to_rad(-minf(speed, 25.0) * 0.5),
		flutter * 0.6,
		deg_to_rad(_flag_lean * flag_sway_deg) + flutter * 0.1)


func _apply_body_color() -> void:
	var painted: StandardMaterial3D = null
	for node in find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if not part.is_in_group(&"body_paint"):
			continue
		if painted == null:
			var source := part.material_override as StandardMaterial3D
			if source == null:
				continue
			painted = source.duplicate() as StandardMaterial3D
			painted.albedo_color = body_color
		part.material_override = painted
