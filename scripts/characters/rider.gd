class_name Rider
extends Node3D
## Procedural cartoon rider, posed each frame by TrikeVisuals.
##
## The body is a bone-style node hierarchy (Hips > Spine > Chest > Neck > Head)
## with limbs placed by two-bone IK so the gloves stay on the handlebar grips
## and the boots stay on the footrests while the body leans. Node names follow
## BONE_MAP, so a future Skeleton3D rig can take over the same pose roles.
## Cosmetic only: no physics, no gameplay state.

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

var _time := 0.0

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
		var pole: Vector3 = limb["pole"]
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
	return {
		"root": root, "upper": upper, "lower": lower, "end": tip, "is_arm": is_arm, "side": side,
		"pole": Vector3(pole.x * side, pole.y, pole.z),
		"l1": upper_arm_length if is_arm else thigh_length,
		"l2": forearm_length if is_arm else shin_length,
	}


func _target_for(limb: Dictionary) -> Node3D:
	var left: bool = limb["side"] < 0.0
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
