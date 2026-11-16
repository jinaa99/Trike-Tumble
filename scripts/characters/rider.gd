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
## Faces. The first five are the looks' resting faces (RiderLook.Face);
## SHOCKED, DIZZY and CHEER are shown for falls, get-ups and celebrations.
## The rest are reaction faces (appended: RiderLook.Face mirrors the first five).
enum Face { CHEERFUL, DETERMINED, GRINNING, SLEEPY, CHEEKY, SHOCKED, DIZZY, CHEER, LAUGH, SMUG, OUCH, FOCUS, CONFUSED, GRUMPY }
## Per expression: [brow tilt (rad, + = inner ends down), brow lift (m),
## mouth scale (width, height), eye open L, eye open R, pupil scale].
const FACES := {
	Face.CHEERFUL: [0.0, 0.0, Vector2(1.0, 1.0), 1.0, 1.0, 1.0],
	Face.DETERMINED: [0.38, -0.012, Vector2(0.75, 0.55), 0.8, 0.8, 1.0],
	Face.GRINNING: [-0.1, 0.012, Vector2(1.45, 1.35), 0.85, 0.85, 1.0],
	Face.SLEEPY: [-0.05, -0.008, Vector2(0.85, 0.7), 0.42, 0.42, 1.0],
	Face.CHEEKY: [0.15, 0.006, Vector2(1.25, 1.15), 1.0, 0.35, 1.0],
	Face.SHOCKED: [-0.35, 0.035, Vector2(0.6, 1.9), 1.2, 1.2, 0.6],
	Face.DIZZY: [-0.2, 0.0, Vector2(1.0, 0.45), 0.3, 0.3, 1.0],
	Face.CHEER: [-0.2, 0.03, Vector2(1.6, 1.7), 0.55, 0.55, 1.0],
	Face.LAUGH: [-0.28, 0.03, Vector2(1.7, 2.0), 0.25, 0.25, 1.0],
	Face.SMUG: [0.22, 0.004, Vector2(1.5, 0.7), 0.6, 0.6, 1.0],
	Face.OUCH: [-0.4, 0.03, Vector2(1.3, 1.6), 0.2, 0.2, 0.8],
	Face.FOCUS: [0.45, -0.014, Vector2(0.8, 0.45), 0.7, 0.7, 0.85],
	Face.CONFUSED: [-0.3, 0.03, Vector2(0.55, 0.9), 1.25, 0.7, 0.7],
	Face.GRUMPY: [0.5, -0.016, Vector2(0.9, 0.4), 0.75, 0.75, 1.0],
}

## Riding personality per character (Zip, Pip, Bramble, Nutmeg, Rusty):
## [extra forward tuck (deg), how much the lean is exaggerated, head tilt
## (deg, + = toward the right shoulder), head nod (deg, + = chin down),
## bob amplitude (deg), bob speed (rad/s)]. Spine and neck only: the IK
## keeps hands on the grips and feet on the pegs.
const RIDING_STYLE: Array[Array] = [
	[2.0, 1.15, 0.0, -4.0, 2.2, 7.0],   # Zip: chin up, bouncy
	[7.0, 1.3, 0.0, 6.0, 0.6, 9.0],     # Pip: hunched forward, glaring, leans hard
	[-1.0, 0.85, 4.0, 2.0, 0.4, 2.0],   # Bramble: upright, calm, head cocked
	[1.0, 1.0, -3.0, 0.0, 3.0, 11.0],   # Nutmeg: fidgety wiggle
	[-4.0, 0.7, 7.0, 8.0, 0.8, 1.6],    # Rusty: laid back, head lolling
]

## Seated reactions: [face, seconds, arms leave the grips]. Feet always stay
## on the pegs; hands go back to the grips when the reaction ends.
const REACTIONS := {
	&"laugh": [Face.LAUGH, 1.3, true], &"yelp": [Face.OUCH, 0.8, false], &"cheer": [Face.CHEER, 1.4, true],
	&"taunt": [Face.SMUG, 1.4, true], &"smug": [Face.SMUG, 1.0, false], &"focus": [Face.FOCUS, 0.9, false],
	&"confused": [Face.CONFUSED, 1.3, false], &"grumble": [Face.GRUMPY, 1.2, false], &"skill": [Face.FOCUS, 0.7, true],
	&"trick": [Face.CHEER, 0.5, true], &"dizzy": [Face.DIZZY, 1.4, false],
}

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
var expression := Face.CHEERFUL
## The look's resting face (RiderStyle sets it).
var base_face := Face.CHEERFUL
## Seconds of finish celebration left (arms up while seated).
var celebrate_time := 0.0
## Which of the five riders this is (0 Zip .. 4 Rusty): picks the taunt.
var character := 0
## Reaction playing on top of the riding pose (REACTIONS key) and seconds left.
var reaction_kind := &""
var reaction_time := 0.0
var _reaction_arms := false
var _blink_in := 2.0
var _blink_time := 0.0
var _face_rest := {}
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
	RiderDetail.build(self)
	for target_name in ["FreeTargetHandL", "FreeTargetHandR", "FreeTargetFootL", "FreeTargetFootR"]:
		var marker := Marker3D.new()
		marker.name = target_name
		add_child(marker)
		_free_targets.append(marker)
	for part: String in ["BrowL", "BrowR", "Mouth", "EyeL", "EyeR", "PupilL", "PupilR", "EyeShineL", "EyeShineR"]:
		var node := _head.get_node_or_null(part) as Node3D
		if node:
			_face_rest[part] = node.transform
	solve_limbs()


func set_pose_mode(mode: PoseMode) -> void:
	pose_mode = mode
	reaction_time = 0.0
	reaction_kind = &""
	_reaction_arms = false
	_chest.rotation = Vector3.ZERO
	_neck.rotation = Vector3.ZERO
	_hips.position = HIPS_REST
	scale = Vector3.ONE
	if mode == PoseMode.RIDE:
		_spine.rotation = Vector3.ZERO
	match mode:
		PoseMode.FLAIL:
			set_expression(Face.SHOCKED)
		PoseMode.GET_UP:
			set_expression(Face.DIZZY)
		_:
			set_expression(base_face)


## The look's resting face; shown now unless a fall/get-up face is on.
func set_base_face(face: int) -> void:
	base_face = face as Face
	if pose_mode == PoseMode.RIDE or pose_mode == PoseMode.STAND:
		set_expression(base_face)


## Poses brows, eyes, pupils and mouth for `face` (relative to the rest pose).
func set_expression(face: Face) -> void:
	expression = face
	if _face_rest.is_empty():
		return
	var spec: Array = FACES[face]
	var tilt: float = spec[0]
	var lift: float = spec[1]
	var mouth: Vector2 = spec[2]
	for side in ["L", "R"]:
		var side_sign := -1.0 if side == "L" else 1.0
		var brow := _head.get_node("Brow" + side) as Node3D
		var rest: Transform3D = _face_rest["Brow" + side]
		brow.transform = Transform3D(Basis(Vector3.FORWARD, tilt * side_sign) * rest.basis, rest.origin + Vector3(0.0, lift, 0.0))
		var open: float = spec[3] if side == "L" else spec[4]
		for part: String in ["Eye", "EyeShine"]:
			var node := _head.get_node(part + side) as Node3D
			var eye_rest: Transform3D = _face_rest[part + side]
			node.transform = Transform3D(Basis.from_scale(Vector3(1.0, open, 1.0)) * eye_rest.basis, eye_rest.origin)
			if part == "EyeShine":
				node.visible = open > 0.5
		var pupil := _head.get_node("Pupil" + side) as Node3D
		var pupil_rest: Transform3D = _face_rest["Pupil" + side]
		var pupil_scale: float = spec[5]
		pupil.transform = Transform3D(Basis.from_scale(Vector3(pupil_scale, pupil_scale * minf(open, 1.0), pupil_scale))
				* pupil_rest.basis, pupil_rest.origin)
	var mouth_node := _head.get_node("Mouth") as Node3D
	var mouth_rest: Transform3D = _face_rest["Mouth"]
	mouth_node.transform = Transform3D(Basis.from_scale(Vector3(mouth.x, mouth.y, 1.0)) * mouth_rest.basis, mouth_rest.origin)


## Finish celebration: arms up (fist pump, wave) for `seconds` while seated,
## then the hands go back to the grips.
func celebrate(seconds := 3.5) -> void:
	celebrate_time = seconds
	set_expression(Face.CHEER)


func is_celebrating() -> bool:
	return celebrate_time > 0.0


## Plays a short reaction (see REACTIONS): a face, and for some a gesture
## with the arms off the grips. Seated or standing only; a fall, a get-up or
## the finish celebration always wins. Returns false if it was not shown.
func react(kind: StringName, seconds := -1.0) -> bool:
	if not REACTIONS.has(kind) or celebrate_time > 0.0:
		return false
	if pose_mode != PoseMode.RIDE and pose_mode != PoseMode.STAND:
		return false
	var spec: Array = REACTIONS[kind]
	reaction_kind = kind
	reaction_time = float(spec[1]) if seconds < 0.0 else seconds
	_reaction_arms = bool(spec[2]) and pose_mode == PoseMode.RIDE
	set_expression(spec[0])
	return true


func is_reacting() -> bool:
	return reaction_time > 0.0


func _end_reaction() -> void:
	reaction_time = 0.0
	reaction_kind = &""
	_reaction_arms = false
	if pose_mode == PoseMode.RIDE or pose_mode == PoseMode.STAND:
		set_expression(base_face)


## True while the arms are off the grips (celebration or an arm gesture).
func _arms_free() -> bool:
	return celebrate_time > 0.0 or (reaction_time > 0.0 and _reaction_arms)


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
	if celebrate_time > 0.0:
		celebrate_time = maxf(celebrate_time - delta, 0.0)
		# Left fist pumps, right hand waves above the head.
		var pump := absf(sin(_time * 7.0))
		_set_free_targets(Vector3(-0.32, 1.25 + pump * 0.18, 0.05 - pump * 0.05),
				Vector3(0.36 + sin(_time * 9.0) * 0.08, 1.38, 0.08), Vector3.ZERO, Vector3.ZERO)
		if celebrate_time <= 0.0:
			set_expression(base_face)
	elif reaction_time > 0.0:
		reaction_time -= delta
		if _reaction_arms:
			_pose_reaction_arms()
		if reaction_time <= 0.0:
			_end_reaction()
	else:
		_update_blink(delta)
	var weight := 1.0 - exp(-pose_smoothing * delta)
	var style: Array = RIDING_STYLE[posmod(character, RIDING_STYLE.size())]
	var bob := sin(_time * float(style[5])) * deg_to_rad(float(style[4]))
	var target_roll := -clampf(lean * float(style[1]), -1.5, 1.5) * deg_to_rad(max_side_lean_deg) + bob * 0.4
	var target_pitch := -speed_ratio * deg_to_rad(max_forward_tuck_deg) - deg_to_rad(float(style[0])) + bob * 0.3
	_spine.rotation.z = lerpf(_spine.rotation.z, target_roll, weight)
	_spine.rotation.x = lerpf(_spine.rotation.x, target_pitch, weight)
	if celebrate_time > 0.0:
		_chest.rotation.y = lerpf(_chest.rotation.y, 0.0, weight)
		_neck.rotation = Vector3(-0.25, sin(_time * 3.0) * 0.2, 0.0)
	else:
		_neck.rotation.x = lerpf(_neck.rotation.x, deg_to_rad(float(style[3])), weight)
		_neck.rotation.z = lerpf(_neck.rotation.z, -deg_to_rad(float(style[2])), weight)
		_twist_with_handlebar()
		if reaction_time > 0.0:
			_pose_reaction_head()
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
		var free: bool = pose_mode != PoseMode.RIDE or (_arms_free() and limb["is_arm"])
		var pole: Vector3 = limb["free_pole"] if free else limb["pole"]
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
	var celebrating_arm: bool = _arms_free() and limb["is_arm"] and pose_mode == PoseMode.RIDE
	if (pose_mode != PoseMode.RIDE or celebrating_arm) and _free_targets.size() == 4:
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


# --- Reactions (seated) ---------------------------------------------------------

## Arm gestures in rider space. Each rider taunts in their own way.
func _pose_reaction_arms() -> void:
	var t := _time
	var left := Vector3(-0.3, 0.98, -0.28)
	var right := Vector3(0.3, 0.98, -0.28)
	match reaction_kind:
		&"laugh":  # holding the belly, shaking
			var shake := absf(sin(t * 15.0)) * 0.07
			left = Vector3(-0.2, 0.86 + shake, -0.12)
			right = Vector3(0.2, 0.86 + shake, -0.12)
		&"cheer":  # both fists up
			var pump := absf(sin(t * 9.0)) * 0.16
			left = Vector3(-0.36, 1.3 + pump, 0.05)
			right = Vector3(0.36, 1.3 + pump, 0.05)
		&"trick":  # arms flung wide
			left = Vector3(-0.72, 1.12 + sin(t * 11.0) * 0.05, 0.08)
			right = Vector3(0.72, 1.12 + sin(t * 11.0 + 1.0) * 0.05, 0.08)
		&"skill":  # one arm thrown forward, the other steadies the bar
			right = Vector3(0.22, 1.12, -0.62)
		&"taunt":
			match character:
				1:  # Pip: shakes a fist
					right = Vector3(0.3, 1.28 + sin(t * 18.0) * 0.07, -0.25)
				2:  # Bramble: slow finger wag
					right = Vector3(0.18 + sin(t * 5.0) * 0.14, 1.26, -0.2)
				3:  # Nutmeg: hands by the ears, wiggling
					left = Vector3(-0.3, 1.36 + sin(t * 16.0) * 0.06, 0.12)
					right = Vector3(0.3, 1.36 + sin(t * 16.0 + PI) * 0.06, 0.12)
				4:  # Rusty: one lazy salute
					right = Vector3(0.24, 1.36, 0.02)
				_:  # Zip: big wave over the head
					right = Vector3(0.34 + sin(t * 10.0) * 0.16, 1.42, 0.05)
	_set_free_targets(left, right, Vector3.ZERO, Vector3.ZERO)


## Head acting for the current reaction, on top of the riding head pose.
func _pose_reaction_head() -> void:
	var t := _time
	match reaction_kind:
		&"laugh":
			_neck.rotation.x = -0.32 + sin(t * 15.0) * 0.08
		&"yelp":
			_neck.rotation.x = -0.4 * clampf(reaction_time / 0.4, 0.0, 1.0)
		&"cheer", &"trick":
			_neck.rotation.x = -0.22
		&"taunt":
			_neck.rotation.y += 0.55 if character != 4 else 0.3
			_neck.rotation.z = sin(t * 6.0) * 0.14
		&"smug":
			_neck.rotation.z = 0.2
			_neck.rotation.x = 0.06 + sin(t * 9.0) * 0.05
		&"confused":
			_neck.rotation.z = 0.36
			_neck.rotation.y += sin(t * 4.0) * 0.3
		&"grumble":
			_neck.rotation.y += sin(t * 16.0) * 0.22
			_neck.rotation.x = 0.14
		&"dizzy":
			_neck.rotation.z = sin(t * 5.0) * 0.3
			_neck.rotation.x = cos(t * 5.0) * 0.2
		&"focus", &"skill":
			_neck.rotation.x = 0.12


## An occasional blink while nothing else is going on.
func _update_blink(delta: float) -> void:
	if _face_rest.is_empty() or expression != base_face:
		return
	if _blink_time > 0.0:
		_blink_time -= delta
		if _blink_time <= 0.0:
			set_expression(base_face)
		return
	_blink_in -= delta
	if _blink_in > 0.0:
		return
	_blink_in = 2.2 + fmod(_time * 7.31 + character, 2.6)
	_blink_time = 0.11
	for side: String in ["L", "R"]:
		for part: String in ["Eye", "Pupil", "EyeShine"]:
			var node := _head.get_node_or_null(part + side) as Node3D
			if node:
				var rest: Transform3D = _face_rest[part + side]
				node.transform = Transform3D(Basis.from_scale(Vector3(1.0, 0.08, 1.0)) * rest.basis, rest.origin)


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
