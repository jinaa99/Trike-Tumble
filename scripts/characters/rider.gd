class_name Rider
extends Node3D
## Procedural cartoon rider, posed each frame by TrikeVisuals.
##
## The body is a bone-style node hierarchy (Hips > Spine > Chest > Neck > Head)
## with limbs placed by two-bone IK so the gloves stay on the handlebar grips
## and the boots stay on the footrests while the body leans. Node names follow
## BONE_MAP, so a future Skeleton3D rig can take over the same pose roles.
## Cosmetic only: no physics, no gameplay state.
##
## Pose modes: RIDE (IK to the trike's grips/footrests, posed by TrikeVisuals)
## and, off the trike, FLAIL / GET_UP / STAND, posed by RiderController via
## update_free_pose(), which uses internal IK targets.

enum PoseMode { RIDE, FLAIL, GET_UP, STAND }

## Rider-root position relative to the feet when standing (rider space is
## the seated trike space, so the hips are lifted and moved over the feet).
const STAND_ROOT_OFFSET := Vector3(0.0, 0.55, -0.3)
## Rider-space point used as the centre of the falling body.
const FALL_CENTER := Vector3(0.0, 0.85, 0.15)
const HIPS_REST := Vector3(0.0, 0.36, 0.3)

## Pose role -> node path. Kept for the later switch to a skinned skeleton.
const BONE_MAP := {
	"hips": "Hips", "spine": "Hips/Spine", "chest": "Hips/Spine/Chest",
	"neck": "Hips/Spine/Chest/Neck", "head": "Hips/Spine/Chest/Neck/Head",
	"upper_arm_l": "UpperArmL", "forearm_l": "ForearmL", "hand_l": "HandL",
	"upper_arm_r": "UpperArmR", "forearm_r": "ForearmR", "hand_r": "HandR",
	"thigh_l": "ThighL", "shin_l": "ShinL", "foot_l": "FootL",
	"thigh_r": "ThighR", "shin_r": "ShinR", "foot_r": "FootR",
}

@export_group("Pose")
@export var max_side_lean_deg := 12.0
@export var max_forward_tuck_deg := 10.0
@export var pose_smoothing := 8.0
@export var scarf_sway_deg := 18.0
## How much the chest twists to follow the handlebars (0..1). Keeps both
## hands within reach at full steering lock.
@export_range(0.0, 1.0) var chest_twist := 0.85

@export_group("IK targets")
@export var left_hand_target: Node3D
@export var right_hand_target: Node3D
@export var left_foot_target: Node3D
@export var right_foot_target: Node3D

@export_group("Limbs")
@export var upper_arm_length := 0.42
@export var forearm_length := 0.42
@export var thigh_length := 0.42
@export var shin_length := 0.42
## Elbow/knee bend direction in rider space (X is mirrored for the left side).
@export var arm_pole := Vector3(1.0, -0.8, 0.5)
@export var leg_pole := Vector3(0.45, 1.0, -0.5)
## Elbow/knee directions for standing, running and flailing.
@export var free_arm_pole := Vector3(0.6, -0.2, 1.0)
@export var free_leg_pole := Vector3(0.2, 0.2, -1.0)

var pose_mode := PoseMode.RIDE
var _time := 0.0
var _run_phase := 0.0
var _free_targets: Array[Marker3D] = []

@onready var _hips: Node3D = $Hips
@onready var _head: Node3D = $Hips/Spine/Chest/Neck/Head
@onready var _spine: Node3D = $Hips/Spine
@onready var _chest: Node3D = $Hips/Spine/Chest
@onready var _neck: Node3D = $Hips/Spine/Chest/Neck
@onready var _scarf_tail: Node3D = $Hips/Spine/Chest/ScarfTail
@onready var _limbs: Array[Dictionary] = [
	_limb($Hips/Spine/Chest/ShoulderL, $UpperArmL, $ForearmL, $HandL, -1.0, true),
	_limb($Hips/Spine/Chest/ShoulderR, $UpperArmR, $ForearmR, $HandR, 1.0, true),
	_limb($Hips/HipJointL, $ThighL, $ShinL, $FootL, -1.0, false),
	_limb($Hips/HipJointR, $ThighR, $ShinR, $FootR, 1.0, false),
]


func _ready() -> void:
	for target_name in ["FreeTargetHandL", "FreeTargetHandR", "FreeTargetFootL", "FreeTargetFootR"]:
		var marker := Marker3D.new()
		marker.name = target_name
		add_child(marker)
		_free_targets.append(marker)
	solve_limbs()


func set_pose_mode(mode: PoseMode) -> void:
	pose_mode = mode
	_chest.rotation = Vector3.ZERO
	_neck.rotation = Vector3.ZERO
	_hips.position = HIPS_REST
	scale = Vector3.ONE
	if mode == PoseMode.RIDE:
		_spine.rotation = Vector3.ZERO


func get_head_global_position() -> Vector3:
	return _head.global_position


## Off-trike animation. speed_ratio: 0..1 run speed (STAND).
## progress: 0..1 through the get-up (GET_UP).
func update_free_pose(delta: float, speed_ratio := 0.0, progress := 0.0) -> void:
	_time += delta
	match pose_mode:
		PoseMode.FLAIL:
			_pose_flail()
		PoseMode.GET_UP:
			_pose_get_up(progress)
		PoseMode.STAND:
			_run_phase = wrapf(_run_phase + delta * lerpf(0.0, 10.0, speed_ratio), 0.0, TAU)
			_pose_stand(speed_ratio)
		_:
			return
	solve_limbs()


## lean: -1 (left) .. 1 (right). speed_ratio: 0..1.
func update_pose(lean: float, speed_ratio: float, delta: float) -> void:
	_time += delta
	var weight := 1.0 - exp(-pose_smoothing * delta)
	var target_roll := -clampf(lean, -1.5, 1.5) * deg_to_rad(max_side_lean_deg)
	var target_pitch := -speed_ratio * deg_to_rad(max_forward_tuck_deg)
	_spine.rotation.z = lerpf(_spine.rotation.z, target_roll, weight)
	_spine.rotation.x = lerpf(_spine.rotation.x, target_pitch, weight)
	_twist_with_handlebar()
	var flutter := sin(_time * (6.0 + speed_ratio * 14.0)) * (0.2 + speed_ratio)
	_scarf_tail.rotation.x = deg_to_rad(10.0 + speed_ratio * scarf_sway_deg + flutter * 6.0)
	_scarf_tail.rotation.y = -lean * 0.25 + flutter * 0.08
	solve_limbs()


## Turns the chest to match the handlebar angle (measured from the grip
## targets) and counter-turns the head so the rider keeps looking ahead.
func _twist_with_handlebar() -> void:
	if left_hand_target == null or right_hand_target == null:
		return
	var bar := to_local(right_hand_target.global_position) - to_local(left_hand_target.global_position)
	var bar_yaw := atan2(-bar.z, bar.x)
	_chest.rotation.y = bar_yaw * chest_twist
	_neck.rotation.y = -_chest.rotation.y


## Places every limb with two-bone IK in rider space.
func solve_limbs() -> void:
	for limb in _limbs:
		var target: Node3D = _target_for(limb)
		if target == null:
			continue
		var root: Node3D = limb["root"]
		var start := to_local(root.global_position)
		var goal := to_local(target.global_position)
		var pole: Vector3 = limb["pole"] if pose_mode == PoseMode.RIDE else limb["free_pole"]
		var l1: float = limb["l1"]
		var l2: float = limb["l2"]
		var points := solve_two_bone(start, goal, l1, l2, pole)
		var upper: Node3D = limb["upper"]
		var lower: Node3D = limb["lower"]
		var tip: Node3D = limb["end"]
		upper.transform = _segment(points[0], points[1], pole)
		lower.transform = _segment(points[1], points[2], pole)
		if limb["is_arm"]:
			tip.transform = Transform3D(lower.transform.basis, points[2])
		else:
			tip.transform = Transform3D(Basis.IDENTITY, points[2])


## Largest distance between a glove/boot and its target (for tests).
func get_max_ik_error() -> float:
	var worst := 0.0
	for limb in _limbs:
		var target: Node3D = _target_for(limb)
		if target:
			var tip: Node3D = limb["end"]
			worst = maxf(worst, tip.global_position.distance_to(target.global_position))
	return worst


## Distance from each limb root to its target, divided by the limb's reach (debug aid).
func get_reach_ratios() -> PackedFloat32Array:
	var ratios := PackedFloat32Array()
	for limb in _limbs:
		var target: Node3D = _target_for(limb)
		var root: Node3D = limb["root"]
		var reach: float = limb["l1"] + limb["l2"]
		ratios.append(root.global_position.distance_to(target.global_position) / reach if target else 0.0)
	return ratios


## Returns [start, joint, end]. If the goal is out of reach the limb points
## at it fully extended.
static func solve_two_bone(start: Vector3, goal: Vector3, l1: float, l2: float, pole: Vector3) -> PackedVector3Array:
	var to_goal := goal - start
	var distance := clampf(to_goal.length(), absf(l1 - l2) + 0.001, (l1 + l2) * 0.9999)
	var direction := to_goal.normalized() if to_goal.length_squared() > 1e-8 else Vector3.DOWN
	var cos_a := clampf((l1 * l1 + distance * distance - l2 * l2) / (2.0 * l1 * distance), -1.0, 1.0)
	var bend := pole - direction * pole.dot(direction)
	bend = bend.normalized() if bend.length_squared() > 1e-8 else direction.cross(Vector3.RIGHT).normalized()
	var joint := start + direction * (l1 * cos_a) + bend * (l1 * sqrt(1.0 - cos_a * cos_a))
	var tip := joint + (start + direction * distance - joint).normalized() * l2
	return PackedVector3Array([start, joint, tip])


func _limb(root: Node3D, upper: Node3D, lower: Node3D, tip: Node3D, side: float, is_arm: bool) -> Dictionary:
	var pole := arm_pole if is_arm else leg_pole
	var free_pole := free_arm_pole if is_arm else free_leg_pole
	return {
		"root": root, "upper": upper, "lower": lower, "end": tip, "is_arm": is_arm, "side": side,
		"pole": Vector3(pole.x * side, pole.y, pole.z),
		"free_pole": Vector3(free_pole.x * side, free_pole.y, free_pole.z),
		"l1": upper_arm_length if is_arm else thigh_length,
		"l2": forearm_length if is_arm else shin_length,
	}


func _target_for(limb: Dictionary) -> Node3D:
	var left: bool = limb["side"] < 0.0
	if pose_mode != PoseMode.RIDE and _free_targets.size() == 4:
		var index := (0 if left else 1) + (0 if limb["is_arm"] else 2)
		return _free_targets[index]
	if limb["is_arm"]:
		return left_hand_target if left else right_hand_target
	return left_foot_target if left else right_foot_target


## Transform whose +Y runs from `from` to `to`, rolled toward `pole`.
func _segment(from: Vector3, to: Vector3, pole: Vector3) -> Transform3D:
	var y := (to - from).normalized()
	var x := y.cross(pole)
	if x.length_squared() < 1e-8:
		x = y.cross(Vector3.FORWARD)
	x = x.normalized()
	return Transform3D(Basis(x, y, x.cross(y)), from)


# --- Off-trike poses (rider space; seated hips at HIPS_REST) ----------------

func _set_free_targets(hand_l: Vector3, hand_r: Vector3, foot_l: Vector3, foot_r: Vector3) -> void:
	_free_targets[0].position = hand_l
	_free_targets[1].position = hand_r
	_free_targets[2].position = foot_l
	_free_targets[3].position = foot_r


## Thrown off: arms and legs windmill, body wobbles.
func _pose_flail() -> void:
	var t := _time
	_spine.rotation = Vector3(-0.2 + sin(t * 7.0) * 0.3, 0.0, sin(t * 5.0) * 0.25)
	_neck.rotation = Vector3(sin(t * 9.0) * 0.2, sin(t * 6.0) * 0.4, 0.0)
	_set_free_targets(
		Vector3(-0.5 - sin(t * 13.0) * 0.1, 1.0 + sin(t * 15.0) * 0.25, 0.2 + cos(t * 11.0) * 0.2),
		Vector3(0.5 + sin(t * 12.0) * 0.1, 1.0 + sin(t * 15.0 + 1.7) * 0.25, 0.2 + cos(t * 10.0 + 1.0) * 0.2),
		Vector3(-0.28, 0.05 + sin(t * 12.0) * 0.2, -0.25 + cos(t * 9.0) * 0.25),
		Vector3(0.28, 0.05 + sin(t * 12.0 + 2.0) * 0.2, -0.25 + cos(t * 9.0 + 2.0) * 0.25))


## Standing feet in rider space (feet at the on-foot body origin).
func _foot_spot(side: float, forward := 0.0, lift := 0.0) -> Vector3:
	return Vector3(0.13 * side, 0.1 - STAND_ROOT_OFFSET.y + lift, -STAND_ROOT_OFFSET.z - forward)


## Get-up: push up off the ground, shake the head, look confused.
func _pose_get_up(p: float) -> void:
	var hands_down := Vector3(0.0, -0.4, 0.0)
	if p < 0.4:
		var q := p / 0.4
		_spine.rotation = Vector3(lerpf(-0.7, 0.48, q * q), 0.0, 0.0)
		_hips.position = HIPS_REST - Vector3(0.0, 0.3 * (1.0 - q), 0.0)
		_neck.rotation = Vector3.ZERO
		_set_free_targets(Vector3(-0.28, 0.0, 0.0) + hands_down, Vector3(0.28, 0.0, 0.0) + hands_down,
				_foot_spot(-1.0), _foot_spot(1.0))
		scale = Vector3.ONE
	elif p < 0.7:
		var q := (p - 0.4) / 0.3
		_spine.rotation = Vector3(0.48, 0.0, 0.0)
		_hips.position = HIPS_REST
		_neck.rotation = Vector3(0.0, sin(_time * 38.0) * 0.55 * (1.0 - q * 0.5), 0.0)
		_set_free_targets(Vector3(-0.32, 0.42, 0.3), Vector3(0.32, 0.42, 0.3), _foot_spot(-1.0), _foot_spot(1.0))
		var squash := 1.0 + sin(q * PI) * 0.07
		scale = Vector3(1.0 / sqrt(squash), squash, 1.0 / sqrt(squash))
	else:
		var q := (p - 0.7) / 0.3
		_spine.rotation = Vector3(0.48, 0.0, sin(q * PI) * 0.12)
		_neck.rotation = Vector3(0.0, 0.0, sin(q * PI) * 0.35)
		var scratch := Vector3(0.24, 1.18 + sin(_time * 30.0) * 0.03, 0.22)
		_set_free_targets(Vector3(-0.26, 0.4, 0.26), scratch, _foot_spot(-1.0), _foot_spot(1.0))
		scale = Vector3.ONE


## Idle breathing or a run cycle, blended by speed.
func _pose_stand(speed_ratio: float) -> void:
	var phase := _run_phase
	var stride := 0.3 * speed_ratio
	var lift := 0.16 * speed_ratio
	var breathe := sin(_time * 2.2) * 0.02 * (1.0 - speed_ratio)
	_spine.rotation = Vector3(0.48 - 0.28 * speed_ratio + breathe, sin(phase) * 0.08 * speed_ratio, 0.0)
	_hips.position = HIPS_REST + Vector3(0.0, absf(sin(phase)) * 0.05 * speed_ratio + breathe, 0.0)
	_neck.rotation = Vector3(0.18 * speed_ratio, 0.0, 0.0)
	var swing_l := sin(phase)
	var swing_r := sin(phase + PI)
	_set_free_targets(
		Vector3(-0.3, 0.42 + absf(swing_r) * 0.08 * speed_ratio, 0.3 + swing_r * 0.28 * speed_ratio),
		Vector3(0.3, 0.42 + absf(swing_l) * 0.08 * speed_ratio, 0.3 + swing_l * 0.28 * speed_ratio),
		_foot_spot(-1.0, swing_l * stride, maxf(cos(phase), 0.0) * lift),
		_foot_spot(1.0, swing_r * stride, maxf(cos(phase + PI), 0.0) * lift))
