class_name FollowCamera
extends Camera3D
## Third-person chase camera.
##
## Lives outside the trike so it never inherits roll/pitch. It follows the
## physics-interpolated target transform in _process. Yaw blends heading and
## velocity so drifts stay readable. With speed the camera pulls back and
## drops a little, looks further down the road and widens its FOV, which
## sells downhill speed without shaking. A sphere cast keeps it out of walls
## and terrain.
##
## Two modes, picked from the target type:
## - Vehicle (target is a Trike): the chase framing above.
## - Character (rider falling or on foot): a "dragged" follow camera that
##   keeps its distance and never auto-turns, so camera-relative walking
##   stays stable.
## set_target() blends between targets without cuts.

@export var target: Node3D

@export_group("Framing")
@export var distance := 4.6
## Extra distance at full speed.
@export var distance_at_speed := 0.9
@export var height := 1.85
## Height change at full speed (negative = lower, feels faster).
@export var height_at_speed := -0.3
@export var look_height := 0.55
@export var look_ahead := 3.5
## Extra look-ahead at full speed, so upcoming obstacles stay in view.
@export var look_ahead_at_speed := 5.0
## Speed (m/s) treated as "full speed" for the framing curves above.
@export var full_speed := 30.0

@export_group("Smoothing")
## How fast the camera turns to follow the heading (1/s).
@export var yaw_smoothing := 5.0
## Follow stiffness horizontally and vertically (1/s). Lower = more lag.
@export var follow_smoothing := 14.0
@export var vertical_smoothing := 7.0
## How fast speed-based framing changes (1/s).
@export var framing_smoothing := 2.5
## 0 = follow heading only, 1 = follow velocity direction only.
@export_range(0.0, 1.0) var velocity_yaw_weight := 0.55

@export_group("Field of view")
@export var base_fov := 66.0
@export var max_fov := 80.0
## Extra FOV while boosting.
@export var boost_fov_kick := 6.0

@export_group("Character mode")
@export var character_distance := 4.6
@export var character_height := 2.3
@export var character_look_height := 0.9
## How long a target change blends (seconds).
@export var transition_time := 0.9
## Follow stiffness at the start of a transition (1/s).
@export var transition_smoothing := 3.0

@export_group("Collision")
@export_flags_3d_physics var collision_mask := 1
@export var collision_radius := 0.3
## Minimum height above the ground directly below the camera.
@export var ground_clearance := 0.6

var _yaw := 0.0
var _focus := Vector3.ZERO
var _speed_ratio := 0.0
var _travel_dir := Vector3.FORWARD
var _probe := SphereShape3D.new()
var _transition_left := 0.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_probe.radius = collision_radius
	snap_to_target()


func _process(delta: float) -> void:
	if target == null:
		return
	var xf := target.get_global_transform_interpolated()
	# During a transition everything follows more softly, then tightens up.
	var blend := 1.0
	if _transition_left > 0.0:
		_transition_left = maxf(_transition_left - delta, 0.0)
		blend = 1.0 - _transition_left / transition_time
	var follow := lerpf(transition_smoothing, follow_smoothing, blend)
	var vertical := lerpf(transition_smoothing, vertical_smoothing, blend)

	_speed_ratio = lerpf(_speed_ratio, _target_speed_ratio(), 1.0 - exp(-framing_smoothing * delta))
	var horizontal := Vector3(xf.origin.x, _focus.y, xf.origin.z)
	_focus = _focus.lerp(horizontal, 1.0 - exp(-follow * delta))
	_focus.y = lerpf(_focus.y, xf.origin.y, 1.0 - exp(-vertical * delta))

	var previous := global_position
	if is_character_mode():
		_place_character()
	else:
		_yaw = lerp_angle(_yaw, _target_yaw(xf), 1.0 - exp(-yaw_smoothing * delta))
		_travel_dir = _travel_dir.slerp(_target_travel_dir(xf), 1.0 - exp(-framing_smoothing * delta)).normalized()
		_place()
	if _transition_left > 0.0:
		global_position = previous.lerp(global_position, 1.0 - exp(-lerpf(4.0, 30.0, blend) * delta))
	_update_fov(delta)


## Switches what the camera follows, blending over transition_time.
func set_target(node: Node3D, blend := true) -> void:
	target = node
	_transition_left = transition_time if blend else 0.0
	if not blend:
		snap_to_target()


func is_character_mode() -> bool:
	return target != null and not (target is Trike)


func is_transitioning() -> bool:
	return _transition_left > 0.0


func snap_to_target() -> void:
	if target == null:
		return
	var xf := target.global_transform
	_focus = xf.origin
	_speed_ratio = _target_speed_ratio()
	_transition_left = 0.0
	if is_character_mode():
		_place_character()
		return
	_yaw = _target_yaw(xf)
	_travel_dir = _target_travel_dir(xf)
	_place()


func _target_speed_ratio() -> float:
	var body := target as Trike
	if body == null:
		return 0.0
	return clampf(body.linear_velocity.length() / full_speed, 0.0, 1.0)


## Direction of travel including slope, so the camera looks down the hill
## instead of over it.
func _target_travel_dir(xf: Transform3D) -> Vector3:
	var body := target as RigidBody3D
	if body and body.linear_velocity.length() > 3.0:
		return body.linear_velocity.normalized()
	var heading := -xf.basis.z
	return heading.normalized() if heading.length_squared() > 0.01 else Vector3.FORWARD


func _target_yaw(xf: Transform3D) -> float:
	var heading := -xf.basis.z
	heading.y = 0.0
	if heading.length_squared() < 0.01:
		return _yaw
	heading = heading.normalized()
	var body := target as RigidBody3D
	if body:
		var flat_velocity := Vector3(body.linear_velocity.x, 0.0, body.linear_velocity.z)
		var speed := flat_velocity.length()
		if speed > 4.0 and flat_velocity.dot(heading) > 0.0:
			var weight := velocity_yaw_weight * clampf((speed - 4.0) / 6.0, 0.0, 1.0)
			heading = heading.lerp(flat_velocity / speed, weight).normalized()
	return atan2(-heading.x, -heading.z)


func _place() -> void:
	var back := Vector3(sin(_yaw), 0.0, cos(_yaw))
	var pivot := _focus + Vector3.UP * look_height
	var cam_distance := distance + distance_at_speed * _speed_ratio
	var cam_height := height + height_at_speed * _speed_ratio
	var desired := _focus + back * cam_distance + Vector3.UP * cam_height
	desired = _resolve_collision(pivot + Vector3.UP * 0.4, desired)
	global_position = desired
	var ahead := look_ahead + look_ahead_at_speed * _speed_ratio
	# Horizontal aim follows the smoothed yaw; vertical aim follows the slope.
	var slope := clampf(_travel_dir.y, -0.5, 0.3)
	var flat := sqrt(maxf(1.0 - slope * slope, 0.01))
	look_at(pivot - back * ahead + Vector3.UP * (slope / flat) * ahead, Vector3.UP)


## Character mode: stay where we are relative to the target, at a fixed
## distance (dragged along), and look at the character.
func _place_character() -> void:
	var away := global_position - _focus
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3(sin(_yaw), 0.0, cos(_yaw))
	away = away.normalized()
	_yaw = atan2(away.x, away.z)  # keeps vehicle mode continuous after the switch
	var pivot := _focus + Vector3.UP * character_look_height
	var desired := _focus + away * character_distance + Vector3.UP * character_height
	global_position = _resolve_collision(pivot + Vector3.UP * 0.4, desired)
	look_at(pivot, Vector3.UP)


func _update_fov(delta: float) -> void:
	var goal := lerpf(base_fov, max_fov, _speed_ratio)
	var trike := target as Trike
	if trike and trike.boost_time > 0.0:
		goal += boost_fov_kick
	fov = lerpf(fov, goal, 1.0 - exp(-3.0 * delta))


## Sphere-cast from the pivot to the desired spot, stopping short of
## anything solid, then keep a little clearance above the ground below.
func _resolve_collision(from: Vector3, to: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	var body := target as CollisionObject3D
	if body:
		exclude.append(body.get_rid())
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _probe
	query.transform = Transform3D(Basis.IDENTITY, from)
	query.motion = to - from
	query.collision_mask = collision_mask
	query.exclude = exclude
	var fractions := space.cast_motion(query)
	var result := from + (to - from) * fractions[0]

	var down := PhysicsRayQueryParameters3D.create(result + Vector3.UP * 1.0, result - Vector3.UP * ground_clearance, collision_mask, exclude)
	var hit := space.intersect_ray(down)
	if not hit.is_empty():
		var ground: Vector3 = hit["position"]
		result.y = maxf(result.y, ground.y + ground_clearance)
	return result
