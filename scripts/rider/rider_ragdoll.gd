class_name RiderRagdoll
extends RigidBody3D
## The thrown rider: one rounded rigid body that flies, spins, bounces and
## rolls to a stop. The Rider model rides on it while the limbs flail
## procedurally ("cartoon ragdoll"), which reads well and stays stable.
## Disabled (removed from physics) whenever the rider isn't falling.

var _air_time := 0.0
var _settled_time := 0.0
var _touched_ground := false


func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	deactivate()


## Starts a fall from `xf` with the given velocities.
func launch(xf: Transform3D, velocity: Vector3, spin: Vector3) -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	freeze = false
	global_transform = xf
	linear_velocity = velocity
	angular_velocity = spin
	linear_damp = 0.0
	angular_damp = 0.0
	_air_time = 0.0
	_settled_time = 0.0
	_touched_ground = false
	reset_physics_interpolation()


func deactivate() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	process_mode = Node.PROCESS_MODE_DISABLED


func is_active() -> bool:
	return process_mode != Node.PROCESS_MODE_DISABLED


func has_touched_ground() -> bool:
	return _touched_ground


## Called every physics tick by the rider controller.
func update_fall(delta: float, config: RiderConfig) -> void:
	_air_time += delta
	if not _touched_ground and get_contact_count() > 0 and _air_time > 0.08:
		_touched_ground = true
		linear_damp = config.ground_linear_damp
		angular_damp = config.ground_angular_damp
	var slow := linear_velocity.length() < config.settle_speed and angular_velocity.length() < config.settle_spin
	_settled_time = _settled_time + delta if slow and _touched_ground else 0.0


func is_settled(config: RiderConfig) -> bool:
	return _settled_time >= config.settle_time
