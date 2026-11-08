class_name RiderOnFoot
extends CharacterBody3D
## The rider walking/running back to the trike. Simple arcade character
## movement: camera-relative direction in, acceleration toward run speed,
## turn to face the movement, gravity. Disabled while riding or falling.

## Facing (yaw) the model should show; smoothly turns toward movement.
var facing := Basis.IDENTITY


func _ready() -> void:
	deactivate()


func activate(at: Vector3, face: Vector3) -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	global_position = at
	velocity = Vector3.ZERO
	face.y = 0.0
	facing = Basis.looking_at(face.normalized(), Vector3.UP) if face.length_squared() > 1e-4 else Basis.IDENTITY
	global_basis = Basis.IDENTITY
	reset_physics_interpolation()


func deactivate() -> void:
	velocity = Vector3.ZERO
	process_mode = Node.PROCESS_MODE_DISABLED


func is_active() -> bool:
	return process_mode != Node.PROCESS_MODE_DISABLED


## direction: desired horizontal movement (length 0..1) in world space.
func move(direction: Vector3, delta: float, config: RiderConfig) -> void:
	direction.y = 0.0
	if direction.length() > 1.0:
		direction = direction.normalized()
	var target := direction * config.run_speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(target, config.acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		velocity.y = minf(velocity.y, 0.0)
	else:
		velocity.y -= config.gravity * delta
	move_and_slide()
	if direction.length_squared() > 0.01:
		var goal := Basis.looking_at(direction.normalized(), Vector3.UP)
		facing = facing.slerp(goal, 1.0 - exp(-config.turn_speed * delta)).orthonormalized()


## 0..1 of run speed, for the run animation.
func get_speed_ratio(config: RiderConfig) -> float:
	return clampf(Vector3(velocity.x, 0.0, velocity.z).length() / config.run_speed, 0.0, 1.0)
