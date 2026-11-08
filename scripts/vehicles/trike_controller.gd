class_name Trike
extends RigidBody3D
## Arcade three-wheel trike (one front wheel, two rear wheels).
##
## Movement model: a RigidBody3D held up by three raycast wheels with
## spring/damper suspension. Drive, braking, sideways grip, yaw and
## self-righting are arcade velocity changes applied in _integrate_forces
## instead of Godot's VehicleBody3D tire model. The body still collides,
## tumbles and takes impulses physically, but handling stays predictable and
## every value is tunable in TrikeConfig.
##
## Per-tick flow: _physics_process reads input and updates drift/recovery
## state, then the physics step calls _integrate_forces to apply forces.
##
## The trike knows nothing about the rider. A rider system calls
## set_rider_aboard() and listens to `impact`, which reports the sudden
## velocity change from collisions (anything the trike's own forces,
## suspension and gravity don't explain).

signal respawn_requested(trike: Trike)
signal respawned
signal drift_started(direction: int)
signal drift_ended(boost_tier: int)
## strength: unexplained velocity change in m/s this tick.
## velocity_before: the velocity the trike would have had without the hit.
signal impact(strength: float, velocity_before: Vector3)

enum Wheel { FRONT, REAR_LEFT, REAR_RIGHT }
const WHEEL_COUNT := 3

@export var config: TrikeConfig
## Optional. When null, the trike is driven by writing to `input` directly
## (tests, AI, network).
@export var input_source: TrikeInputSource
@export_flags_3d_physics var wheel_collision_mask := 0b101
## Respawn automatically after lying overturned. A rider system turns this
## off because it handles flips itself (the rider is thrown off instead).
@export var auto_recover_when_flipped := true

var input := TrikeInput.new()

# Read-only state for visuals, HUD, camera and race logic.
var steer_amount := 0.0  ## Smoothed steering, -1..1.
var steer_angle := 0.0  ## Visual front wheel angle in radians (+ = left).
var forward_speed := 0.0  ## m/s along the ground-projected heading.
var is_drifting := false
var drift_direction := 0  ## -1 left, +1 right.
var drift_charge := 0.0
var boost_time := 0.0
var grounded_wheel_count := 0
var wheel_contact: Array[bool] = [false, false, false]
var wheel_suspension_length := PackedFloat32Array([0.0, 0.0, 0.0])
## Ground under each wheel (TrackSurface.Kind) and the main one under the trike.
var wheel_surface: Array[TrackSurface.Kind] = [TrackSurface.Kind.ROAD, TrackSurface.Kind.ROAD, TrackSurface.Kind.ROAD]
var surface := TrackSurface.Kind.ROAD
## False while the rider is off the trike: input is ignored and it brakes gently.
var has_rider := true
## Race control (lobby, countdown, race over): input is ignored and the trike
## holds still, but physics keep running.
var input_locked := false
## Network proxy: another computer simulates this trike. It is a frozen
## kinematic body moved by NetRacerSync (so local trikes still bump into it);
## no input, no forces, visual state comes from the owner's snapshots.
var network_proxy := false
## Owner-reported velocity of a proxy (frozen bodies report none).
var network_velocity := Vector3.ZERO
## Counts teleports (respawns, resets), so network proxies snap instead of
## sliding across the map between two snapshots.
var teleport_count := 0
## Strength of the latest impact (m/s), for debugging and tests.
var last_impact_strength := 0.0

var _wheel_mounts := PackedVector3Array()
# Handling of the ground under the wheels (averaged over grounded wheels).
var _surface_speed := 1.0
var _surface_drag := 0.0
var _surface_grip := 1.0
var _wheel_radii := PackedFloat32Array()
var _ray_query := PhysicsRayQueryParameters3D.new()
var _hop_requested := false
var _upside_down_time := 0.0
var _stuck_time := 0.0
var _pending_teleport := false
var _teleport_transform := Transform3D.IDENTITY
# Impact measurement: the velocity we left the body with last tick, plus the
# velocity change our suspension forces will add during integration.
var _baseline_valid := false
var _velocity_after_forces := Vector3.ZERO
var _force_dv := Vector3.ZERO
var _suspension_force_sum := Vector3.ZERO


# Wheel setup happens on enter_tree (parent before children) so child
# visuals can query wheel geometry from their own _ready.
func _enter_tree() -> void:
	if not _wheel_mounts.is_empty():
		return
	if config == null:
		config = TrikeConfig.new()
	var rear := config.rear_wheel_mount
	_wheel_mounts = PackedVector3Array([
		config.front_wheel_mount,
		Vector3(-absf(rear.x), rear.y, rear.z),
		Vector3(absf(rear.x), rear.y, rear.z),
	])
	_wheel_radii = PackedFloat32Array([
		config.front_wheel_radius, config.rear_wheel_radius, config.rear_wheel_radius,
	])
	wheel_suspension_length.fill(config.suspension_rest_length)
	_ray_query.exclude = [get_rid()]
	_ray_query.collision_mask = wheel_collision_mask


func _ready() -> void:
	can_sleep = false


func _physics_process(delta: float) -> void:
	if network_proxy:
		return
	if not has_rider or input_locked:
		input.clear()
	elif input_source:
		input_source.poll(input)
	if input.reset_pressed:
		input.reset_pressed = false
		request_respawn()

	steer_amount = move_toward(steer_amount, clampf(input.steer, -1.0, 1.0), config.steer_speed * delta)
	var speed_ratio := clampf(absf(forward_speed) / config.max_speed, 0.0, 1.0)
	steer_angle = -steer_amount * deg_to_rad(config.max_steer_angle_deg) \
			* lerpf(1.0, config.high_speed_steer_factor, speed_ratio)

	boost_time = maxf(boost_time - delta, 0.0)
	_update_drift(delta)
	_update_recovery(delta)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if network_proxy:
		return
	if _pending_teleport:
		_pending_teleport = false
		_baseline_valid = false
		state.transform = _teleport_transform
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		return

	# Physics callbacks run before _physics_process each tick, so input written
	# since the last tick must be dropped here too while locked or riderless.
	if input_locked or not has_rider:
		input.clear()
	var dt := state.step
	_measure_impact(state, dt)
	var xf := state.transform
	var body_basis := xf.basis.orthonormalized()
	var up := body_basis.y

	var ground_normal := _apply_suspension(state, xf, up)
	var traction := grounded_wheel_count / float(WHEEL_COUNT)

	if grounded_wheel_count == 0:
		# Air control and self-righting need someone aboard; an empty
		# overturned trike stays put until its rider gets back on.
		if has_rider:
			_apply_air_control(state, up, dt)
		forward_speed = state.linear_velocity.dot(-body_basis.z)
		_apply_drag(state, dt)
		_store_impact_baseline(state)
		return

	# Heading and side directions projected onto the ground plane.
	var flat_forward := (-body_basis.z - ground_normal * (-body_basis.z).dot(ground_normal)).normalized()
	var flat_right := flat_forward.cross(ground_normal).normalized()
	var velocity := state.linear_velocity
	forward_speed = velocity.dot(flat_forward)

	velocity = _apply_drive(velocity, flat_forward, dt)
	velocity = _apply_grip(velocity, flat_right, traction, dt)
	if _hop_requested:
		_hop_requested = false
		velocity += ground_normal * config.drift_hop_speed
	state.linear_velocity = velocity
	_apply_drag(state, dt)

	_apply_yaw(state, up, traction, dt)
	_apply_upright(state, up, ground_normal, config.upright_strength, config.upright_damping, dt)
	_store_impact_baseline(state)


# --- Public API -------------------------------------------------------------

## Asks the race logic for a respawn. Without a listener the trike rights
## itself where it is.
func request_respawn() -> void:
	_upside_down_time = 0.0
	_stuck_time = 0.0
	if respawn_requested.get_connections().is_empty():
		teleport(_upright_transform_here())
	else:
		respawn_requested.emit(self)


## Rider system hook. Without a rider the trike ignores input, drops any
## drift/boost and brakes gently until it stops (it never moves on its own).
func set_rider_aboard(aboard: bool) -> void:
	has_rider = aboard
	# The rider's collision capsule leaves with the rider.
	var rider_shape := get_node_or_null(^"RiderShape") as CollisionShape3D
	if rider_shape:
		rider_shape.set_deferred(&"disabled", not aboard)
	input.clear()
	steer_amount = 0.0
	if is_drifting:
		_end_drift(false)
	boost_time = 0.0
	_upside_down_time = 0.0
	_stuck_time = 0.0


## Puts an overturned trike back on its wheels where it is (same spot,
## same heading, lifted slightly). Not a respawn: emits no `respawned`.
func set_upright() -> void:
	teleport(_upright_transform_here(0.4), false)


## Instantly moves the trike, clearing velocities and drift/boost state.
## `notify` emits `respawned` (race logic and camera react to it).
func teleport(target: Transform3D, notify := true) -> void:
	_baseline_valid = false
	_teleport_transform = target
	_pending_teleport = true
	global_transform = target
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	forward_speed = 0.0
	steer_amount = 0.0
	is_drifting = false
	drift_direction = 0
	drift_charge = 0.0
	boost_time = 0.0
	_hop_requested = false
	_upside_down_time = 0.0
	_stuck_time = 0.0
	teleport_count += 1
	reset_physics_interpolation()
	if notify:
		respawned.emit()


## Turns this trike into a network proxy (see `network_proxy`).
func set_network_proxy(enabled: bool) -> void:
	network_proxy = enabled
	input_source = null
	input.clear()
	auto_recover_when_flipped = false
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = enabled


## Velocity for other systems (AI avoidance): real for simulated trikes, the
## owner's reported one for proxies.
func get_motion_velocity() -> Vector3:
	return network_velocity if network_proxy else linear_velocity


## Owner side: everything another computer needs to show this trike.
func get_network_state() -> Dictionary:
	return {
		"xf": global_transform, "vel": linear_velocity, "steer_amount": steer_amount,
		"steer_angle": steer_angle, "forward_speed": forward_speed, "drift_dir": drift_direction if is_drifting else 0,
		"drift_charge": drift_charge, "boost": boost_time, "susp": wheel_suspension_length,
		"contact": int(wheel_contact[0]) | (int(wheel_contact[1]) << 1) | (int(wheel_contact[2]) << 2),
		"has_rider": has_rider, "teleports": teleport_count,
	}


## Proxy side: shows a (interpolated) owner state. Moves the kinematic body.
func apply_network_state(state: Dictionary) -> void:
	global_transform = state["xf"]
	network_velocity = state["vel"]
	steer_amount = state["steer_amount"]
	steer_angle = state["steer_angle"]
	forward_speed = state["forward_speed"]
	drift_direction = state["drift_dir"]
	is_drifting = drift_direction != 0
	drift_charge = state["drift_charge"]
	boost_time = state["boost"]
	wheel_suspension_length = state["susp"]
	var contact: int = state["contact"]
	for i in WHEEL_COUNT:
		wheel_contact[i] = contact & (1 << i) != 0
	grounded_wheel_count = wheel_contact.count(true)
	var teleports: int = state.get("teleports", teleport_count)
	if teleports != teleport_count:
		teleport_count = teleports
		reset_physics_interpolation()  # no smeared frame across a respawn


## For future items/collisions between racers.
func apply_knockback(impulse: Vector3, spin: Vector3 = Vector3.ZERO) -> void:
	apply_central_impulse(impulse)
	if spin != Vector3.ZERO:
		apply_torque_impulse(spin)
	if is_drifting:
		_end_drift(false)


func get_wheel_mount(wheel: int) -> Vector3:
	return _wheel_mounts[wheel]


func get_wheel_radius(wheel: int) -> float:
	return _wheel_radii[wheel]


## 0 = none, 1 and 2 = boost tiers reached by the current drift.
func get_drift_tier() -> int:
	if not is_drifting:
		return 0
	if drift_charge >= config.drift_boost_tier_times.y:
		return 2
	if drift_charge >= config.drift_boost_tier_times.x:
		return 1
	return 0


func is_grounded() -> bool:
	return grounded_wheel_count >= 2


# --- Physics helpers --------------------------------------------------------

## Compares the velocity at the start of this tick with what our own forces,
## the suspension and gravity should have produced. The difference came from
## contacts: crashes, bumps, landings on the chassis.
func _measure_impact(state: PhysicsDirectBodyState3D, dt: float) -> void:
	if not _baseline_valid:
		last_impact_strength = 0.0
		return
	var expected := _velocity_after_forces + _force_dv + state.total_gravity * dt
	var strength := (state.linear_velocity - expected).length()
	last_impact_strength = strength
	if strength >= config.impact_report_threshold:
		impact.emit(strength, expected)


func _store_impact_baseline(state: PhysicsDirectBodyState3D) -> void:
	_velocity_after_forces = state.linear_velocity
	_force_dv = _suspension_force_sum * (state.step * state.inverse_mass)
	_baseline_valid = true


## Raycast suspension. Returns the averaged ground normal (world up if airborne).
func _apply_suspension(state: PhysicsDirectBodyState3D, xf: Transform3D, up: Vector3) -> Vector3:
	var space := state.get_space_state()
	var normal_sum := Vector3.ZERO
	var rest := config.suspension_rest_length
	grounded_wheel_count = 0
	_suspension_force_sum = Vector3.ZERO

	for i in WHEEL_COUNT:
		var radius := _wheel_radii[i]
		var origin := xf * _wheel_mounts[i]
		_ray_query.from = origin
		_ray_query.to = origin - up * (rest + radius)
		var hit := space.intersect_ray(_ray_query)
		if hit.is_empty():
			wheel_contact[i] = false
			wheel_suspension_length[i] = rest
			continue

		var hit_position: Vector3 = hit["position"]
		var hit_normal: Vector3 = hit["normal"]
		var length := clampf(origin.distance_to(hit_position) - radius, 0.0, rest)
		var compression := rest - length
		var offset := origin - xf.origin
		var compression_speed := -state.get_velocity_at_local_position(offset).dot(up)
		var force := config.spring_strength * compression + config.spring_damping * compression_speed
		force = clampf(force, 0.0, config.max_suspension_force)
		state.apply_force(up * force, offset)
		_suspension_force_sum += up * force

		wheel_contact[i] = true
		wheel_suspension_length[i] = length
		wheel_surface[i] = TrackSurface.of(hit.get("collider"))
		grounded_wheel_count += 1
		normal_sum += hit_normal

	_update_surface()
	if grounded_wheel_count == 0:
		return Vector3.UP
	return normal_sum.normalized()


## Averages the handling of the surfaces under the grounded wheels.
func _update_surface() -> void:
	_surface_speed = 1.0
	_surface_drag = 0.0
	_surface_grip = 1.0
	if grounded_wheel_count == 0:
		return
	var speed := 0.0
	var drag := 0.0
	var grip := 0.0
	var counts := [0, 0, 0, 0]
	for i in WHEEL_COUNT:
		if not wheel_contact[i]:
			continue
		var kind := wheel_surface[i]
		counts[kind] += 1
		match kind:
			TrackSurface.Kind.GRASS:
				speed += config.grass_speed_factor
				drag += config.grass_drag
				grip += config.grass_grip_factor
			TrackSurface.Kind.MUD:
				speed += config.mud_speed_factor
				drag += config.mud_drag
				grip += config.mud_grip_factor
			_:
				speed += 1.0
				grip += 1.0
	_surface_speed = speed / grounded_wheel_count
	_surface_drag = drag / grounded_wheel_count
	_surface_grip = grip / grounded_wheel_count
	var most := 0
	for kind in counts.size():
		if counts[kind] > counts[most]:
			most = kind
	surface = most as TrackSurface.Kind


func _apply_drive(velocity: Vector3, flat_forward: Vector3, dt: float) -> Vector3:
	var rear_grounded := wheel_contact[Wheel.REAR_LEFT] or wheel_contact[Wheel.REAR_RIGHT]
	if not rear_grounded:
		return velocity

	var throttle := input.throttle
	var brake := input.brake
	var coasting := throttle < 0.05 and brake < 0.05 and boost_time <= 0.0
	var handbrake := input.drift and not is_drifting and absf(forward_speed) > 1.0

	# Propulsion (engine, reverse, boost).
	var drive := 0.0
	var top_speed := config.max_speed * _surface_speed
	if throttle > 0.0 and forward_speed < top_speed:
		var ratio := clampf(forward_speed / top_speed, 0.0, 1.0)
		drive += config.acceleration * throttle * (1.0 - ratio * ratio)
	if brake > 0.0 and forward_speed <= 0.5 and forward_speed > -config.max_reverse_speed:
		drive -= config.reverse_acceleration * brake
	var boost_top := config.boost_max_speed * _surface_speed
	if boost_time > 0.0 and forward_speed < boost_top:
		drive += config.boost_acceleration

	# Resistance never reverses the direction of travel on its own.
	var resist := 0.0
	if brake > 0.0 and forward_speed > 0.5:
		resist += config.brake_deceleration * brake
	if coasting:
		resist += config.rolling_resistance
	if handbrake:
		resist += config.handbrake_deceleration
	if not has_rider or input_locked:
		resist += config.riderless_brake_deceleration
	# Grass and mud: slow down to the surface's top speed.
	if forward_speed > (boost_top if boost_time > 0.0 else top_speed):
		resist += _surface_drag
	var resist_dv := minf(resist * dt, absf(forward_speed)) * signf(forward_speed)

	velocity += flat_forward * (drive * dt - resist_dv)
	if coasting and not is_drifting and absf(forward_speed) < config.idle_hold_speed:
		velocity -= flat_forward * velocity.dot(flat_forward)
	return velocity


func _apply_grip(velocity: Vector3, flat_right: Vector3, traction: float, dt: float) -> Vector3:
	var grip := config.grip * _surface_grip
	var max_accel := config.max_lateral_accel
	var retention := config.grip_speed_retention
	if is_drifting:
		grip = config.drift_grip * _surface_grip
		max_accel = config.drift_max_lateral_accel
		retention = config.drift_speed_retention
	elif input.drift and absf(forward_speed) > 1.0:
		grip = config.handbrake_grip * _surface_grip
		retention = 0.0
	var lateral := velocity.dot(flat_right)
	var max_dv := max_accel * dt
	var dv := clampf(-lateral * (1.0 - exp(-grip * dt)), -max_dv, max_dv) * traction
	var speed_before := velocity.length()
	velocity += flat_right * dv
	# Redirect part of the scrubbed speed along the new direction of travel.
	var speed_after := velocity.length()
	if speed_after > 0.5:
		velocity *= lerpf(speed_after, speed_before, retention) / speed_after
	return velocity


func _apply_yaw(state: PhysicsDirectBodyState3D, up: Vector3, traction: float, dt: float) -> void:
	var target_yaw := 0.0
	if is_drifting:
		var tighten := input.steer * drift_direction
		target_yaw = -drift_direction * (config.drift_yaw_rate + tighten * config.drift_steer_range)
	else:
		var speed_ratio := clampf(absf(forward_speed) / config.max_speed, 0.0, 1.0)
		var authority := clampf(absf(forward_speed) / config.steer_full_speed, 0.0, 1.0)
		var direction := -1.0 if forward_speed < -0.5 else 1.0
		target_yaw = -steer_amount * config.turn_rate * authority * direction \
				* lerpf(1.0, config.high_speed_turn_factor, speed_ratio)

	var yaw_rate := state.angular_velocity.dot(up)
	var max_step := config.max_yaw_accel * dt
	var step := clampf((target_yaw - yaw_rate) * (1.0 - exp(-config.yaw_response * dt)), -max_step, max_step)
	state.angular_velocity += up * step * traction


## Rotates `up` toward `target_up` with a damped spring on the non-yaw spin.
func _apply_upright(state: PhysicsDirectBodyState3D, up: Vector3, target_up: Vector3,
		strength: float, damping: float, dt: float) -> void:
	var w := state.angular_velocity
	var tilt_spin := w - up * w.dot(up)
	var correction := up.cross(target_up) * strength - tilt_spin * damping
	state.angular_velocity += correction * dt


func _apply_air_control(state: PhysicsDirectBodyState3D, up: Vector3, dt: float) -> void:
	_apply_upright(state, up, Vector3.UP, config.air_upright_strength, config.air_upright_damping, dt)
	var target_yaw := -input.steer * config.air_turn_rate
	var yaw_rate := state.angular_velocity.dot(up)
	state.angular_velocity += up * (target_yaw - yaw_rate) * (1.0 - exp(-3.0 * dt))


func _apply_drag(state: PhysicsDirectBodyState3D, dt: float) -> void:
	var v := state.linear_velocity
	state.linear_velocity = v - v * minf(v.length() * config.air_drag * dt, 1.0)


# --- Gameplay state ---------------------------------------------------------

func _update_drift(delta: float) -> void:
	if input.drift:
		if not is_drifting and is_grounded() \
				and absf(input.steer) >= config.drift_steer_threshold \
				and forward_speed > config.drift_min_speed:
			is_drifting = true
			drift_direction = 1 if input.steer > 0.0 else -1
			drift_charge = 0.0
			_hop_requested = config.drift_hop_speed > 0.0
			drift_started.emit(drift_direction)
	elif is_drifting:
		_end_drift(true)

	if not is_drifting:
		return
	if forward_speed < config.drift_min_speed * 0.5:
		_end_drift(false)
	elif is_grounded():
		# Steering into the drift charges faster.
		var into_turn := (input.steer * drift_direction + 1.0) * 0.5
		drift_charge += delta * lerpf(0.6, 1.4, into_turn)


func _end_drift(award_boost: bool) -> void:
	var tier := get_drift_tier() if award_boost else 0
	if tier == 2:
		boost_time = config.drift_boost_durations.y
	elif tier == 1:
		boost_time = config.drift_boost_durations.x
	is_drifting = false
	drift_direction = 0
	drift_charge = 0.0
	drift_ended.emit(tier)


func _update_recovery(delta: float) -> void:
	var overturned := global_basis.y.dot(Vector3.UP) < config.flipped_up_threshold
	if overturned and grounded_wheel_count < 2 and auto_recover_when_flipped:
		_upside_down_time += delta
	else:
		_upside_down_time = 0.0

	var trying := input.throttle > 0.1 or input.brake > 0.1
	if trying and has_rider and grounded_wheel_count < 2 and linear_velocity.length() < config.stuck_speed:
		_stuck_time += delta
	else:
		_stuck_time = 0.0

	if _upside_down_time > config.flipped_recover_time or _stuck_time > config.stuck_recover_time:
		request_respawn()


func _upright_transform_here(lift := 1.5) -> Transform3D:
	var forward := -global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		forward = global_basis.y if absf(global_basis.y.y) < 0.9 else Vector3.FORWARD
		forward.y = 0.0
	return Transform3D(Basis.looking_at(forward.normalized(), Vector3.UP), global_position + Vector3.UP * lift)
