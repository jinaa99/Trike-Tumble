class_name AIDriver
extends TrikeInputSource
## AI racer brain. Writes the same TrikeInput a keyboard does, so the AI drives
## the real trike physics (no teleporting, no speed bonus) and uses the
## normal rider state machine when it falls off.
##
## Riding (polled by the Trike):
##   - follows the track centerline plus a lane offset, aiming at a look-ahead
##     point that moves further out with speed
##   - plans its speed from the curvature ahead (corner speed + braking distance)
##   - cuts to the inside of corners and drifts some of them (by difficulty)
##   - dodges props and slower racers by picking a free lateral gap
##   - lines up with ramps, keeps the heading straight in the air
##   - reverses out when stuck; presses R (the player's respawn) as a last resort
##   - brakes to a stop after finishing
## On foot (polled by RiderController): waits out the fall and get-up, runs to
## its own trike and presses E when the GET ON prompt is available.

## Half the trike's width plus a little paint (m), for obstacle clearance.
@export var vehicle_half_width := 0.8
## Other racers count as obstacles when we close in on them faster than this (m/s)...
@export var racer_closing_speed := 1.0
## ...or are this close ahead (m), whatever their speed.
@export var racer_near_distance := 4.0
@export var racer_radius := 1.0
## Prop kinds a trike can push through when there is no clean gap.
@export var soft_obstacle_kinds: Array[String] = ["crate", "cone"]
## Corner curvature (1/m) at which corner cutting reaches its full amount.
@export var full_cut_curvature := 0.04
## Path samples on each side used to measure curvature.
@export var curvature_span := 4
## Drifting is abandoned when the heading error grows past this (rad) or the
## AI wants to counter-steer more than this (over-rotating).
@export var drift_bail_heading := 0.45
@export var drift_bail_counter_steer := 0.3
## Heading error (rad) above which the AI treats itself as pointing the wrong
## way and slows down to turn around.
@export var wrong_way_angle := 1.1
@export var wrong_way_speed := 7.0
## Lowest planned speed (m/s); braking never asks for less than this.
@export var min_planned_speed := 6.0
## After finishing: brake input used to roll to a stop, and how much faster
## than a normal lane change the AI pulls over to the side of the road.
@export_range(0.0, 1.0) var finish_brake := 0.5
@export var finish_pull_over_factor := 2.0
## On foot: moving less than detour_min_move (m) in detour_check_time (s)
## means something is in the way; side-step at detour_angle_deg for
## detour_time (s), alternating sides.
@export var detour_check_time := 0.4
@export var detour_min_move := 0.1
@export var detour_angle_deg := 80.0
@export var detour_time := 0.9
## Lines up with a ramp when it is this far ahead (s at current speed, plus lookahead).
@export var ramp_line_up_time := 1.2

var config: AIDriverConfig
var trike: Trike
var rider: RiderController
var track: Track
## Optional: source of props and other racers to avoid.
var manager: RacerManager
var racer_id := 0
var lane_offset := 0.0
## False until the race starts; the AI holds still.
var active := false
## True once this racer's finish is confirmed: brake and pull aside.
var finished := false

# Observable state (HUD/debug/tests).
var path_index := 0
var planned_lateral := 0.0
var target_speed := 0.0
var heading_error := 0.0
var dodging := false
## Lining up with a ramp ahead (no drifting, no dodging).
var lining_up_ramp := false
## Props or racers in the avoidance window (no new drifts).
var obstacles_near := false
var blocked := false
var is_reversing := false
var unstick_attempts := 0
var reset_count := 0
var emergency_count := 0
var mount_count := 0
var detour_count := 0
var drift_count := 0

var _curvature := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _noise_phase := Vector2.ZERO
var _time := 0.0
var _active_time := 0.0
var _steer := 0.0
var _stuck_timer := 0.0
var _reverse_timer := 0.0
var _best_index := 0
var _no_progress_timer := 0.0
var _mount_timer := 0.0
var _on_foot_timer := 0.0
var _was_riding := true
var _in_corner := false
var _drift_this_corner := false
## obstacle instance id -> time first seen (reaction time)
var _seen := {}
var _foot_check_position := Vector3.ZERO
var _foot_check_timer := 0.0
var _detour_timer := 0.0
var _detour_side := 1.0
var _hard_intervals: Array[Vector2] = []
var _soft_intervals: Array[Vector2] = []
## Slowest hard obstacle ahead (m/s along the road), INF if none.
var _blocker_speed := INF


func setup(p_trike: Trike, p_rider: RiderController, p_track: Track, p_config: AIDriverConfig,
		p_seed := 0, p_manager: RacerManager = null) -> void:
	trike = p_trike
	rider = p_rider
	track = p_track
	config = p_config if p_config else AIDriverConfig.new()
	manager = p_manager
	_rng.seed = p_seed
	_noise_phase = Vector2(_rng.randf() * TAU, _rng.randf() * TAU)
	_build_curvature()
	path_index = track.path.find_nearest(trike.global_position)
	_best_index = path_index
	planned_lateral = _lateral_of(trike.global_position, path_index)


func start() -> void:
	active = true
	_active_time = 0.0


## New race on the same grid: inactive, not finished, all driving state cleared.
func reset_for_race() -> void:
	active = false
	finished = false
	_active_time = 0.0
	path_index = track.path.find_nearest(trike.global_position)  # unhinted: the trike moved far
	_on_remounted()
	_in_corner = false
	_drift_this_corner = false
	_seen.clear()
	_detour_timer = 0.0
	planned_lateral = _lateral_of(trike.global_position, path_index)


func is_riding() -> bool:
	return rider == null or rider.is_riding()


func poll(into: TrikeInput) -> void:
	var dt := 1.0 / Engine.physics_ticks_per_second
	_time += dt
	into.reset_pressed = false
	into.interact_pressed = false
	into.move_direction = Vector3.ZERO
	if trike == null or not is_instance_valid(trike) or track == null:
		into.clear()
		return
	var riding := is_riding()
	if riding and not _was_riding:
		_on_remounted()
	_was_riding = riding
	if riding:
		_poll_riding(into, dt)
	else:
		_poll_on_foot(into, dt)


# --- Riding -----------------------------------------------------------------

func _poll_riding(into: TrikeInput, dt: float) -> void:
	_on_foot_timer = 0.0
	var path := track.path
	path_index = path.find_nearest(trike.global_position, path_index)
	if not active:
		_hold_still(into)
		return
	_active_time += dt
	if _active_time < config.start_delay:
		_hold_still(into)
		return

	var speed := trike.forward_speed
	var lookahead := maxf(config.lookahead_min, absf(speed) * config.lookahead_time)
	var target_index := mini(path_index + roundi(lookahead / path.spacing), path.size() - 1)
	var corner := _curvature[target_index]

	var lane_speed := config.lane_change_speed * (finish_pull_over_factor if finished else 1.0)
	planned_lateral = move_toward(planned_lateral, _choose_lateral(corner, lookahead), lane_speed * dt)
	var target := path.points[target_index] + path.rights[target_index] * planned_lateral
	heading_error = _heading_error_to(target)

	var desired_steer := clampf(-heading_error * config.steer_gain + _steer_noise(), -1.0, 1.0)
	target_speed = _plan_speed(speed)
	if finished:
		target_speed = 0.0
	elif absf(heading_error) > wrong_way_angle:
		target_speed = minf(target_speed, wrong_way_speed)
	if blocked:
		# Walled in: follow the slowest blocker until a gap opens.
		target_speed = minf(target_speed, maxf(_blocker_speed, min_planned_speed))

	if trike.grounded_wheel_count == 0:
		_poll_airborne(into, dt)
		return
	if _update_unstick(into, desired_steer, dt):
		return

	_steer = move_toward(_steer, desired_steer, config.steer_rate * dt)
	into.steer = _steer
	_apply_speed(into, speed)
	into.drift = _want_drift(corner, speed, desired_steer)
	if into.drift:
		into.brake = 0.0
	_track_progress(into, dt)
	if manager and not finished and AIItemTactics.wants_use(manager.get_racer(racer_id), manager.get_racers(), config,
			absf(corner)):
		into.use_item_pressed = true


func _hold_still(into: TrikeInput) -> void:
	into.throttle = 0.0
	into.brake = 0.0
	into.steer = 0.0
	into.drift = false
	_steer = 0.0


func _apply_speed(into: TrikeInput, speed: float) -> void:
	into.throttle = 0.0
	into.brake = 0.0
	if finished:
		into.brake = finish_brake if speed > 0.5 else 0.0
		return
	if speed > target_speed + config.brake_margin:
		into.brake = clampf((speed - target_speed - config.brake_margin) / 4.0 + 0.3, 0.3, 1.0)
	elif speed < target_speed - 1.0:
		into.throttle = 1.0
	elif speed < target_speed:
		into.throttle = config.cruise_throttle


## Keep the nose pointing down the road while airborne (air control) and
## don't drift or brake mid-jump.
func _poll_airborne(into: TrikeInput, dt: float) -> void:
	var forward := -trike.global_basis.z
	forward.y = 0.0
	var road := track.path.forwards[path_index]
	road.y = 0.0
	var error := 0.0
	if forward.length_squared() > 0.01 and road.length_squared() > 0.01:
		error = forward.signed_angle_to(road, Vector3.UP)
	_steer = move_toward(_steer, clampf(-error * config.steer_gain, -1.0, 1.0), config.steer_rate * dt)
	into.steer = _steer
	into.throttle = 0.0 if finished else 1.0
	into.brake = 0.0
	into.drift = false


## Planned speed: the trike's top speed (scaled by difficulty), lowered so the
## AI can still brake down to the corner speed of every corner within reach.
func _plan_speed(speed: float) -> float:
	var path := track.path
	var limit := config.top_speed_ratio * trike.config.max_speed
	var decel := config.planning_deceleration
	var scan := speed * speed / (2.0 * decel) + config.lookahead_min * 2.0
	var count := mini(ceili(scan / path.spacing), path.size() - 1 - path_index)
	for k in count + 1:
		var c := absf(_curvature[path_index + k])
		if c < 1e-4:
			continue
		var corner_speed := sqrt(config.corner_lateral_accel / c)
		limit = minf(limit, sqrt(corner_speed * corner_speed + 2.0 * decel * k * path.spacing))
	return maxf(limit, min_planned_speed)


func _want_drift(corner: float, speed: float, desired_steer: float) -> bool:
	var sharp := absf(corner) >= config.drift_min_curvature
	if sharp and not _in_corner:
		_in_corner = true
		_drift_this_corner = _rng.randf() < config.drift_chance
	elif absf(corner) < config.drift_min_curvature * 0.5:
		_in_corner = false
		_drift_this_corner = false
	if not _drift_this_corner or dodging or lining_up_ramp or finished:
		return false
	var half := track.half_width_at(path_index) - config.edge_margin
	var lateral := _lateral_of(trike.global_position, path_index)
	# Bail out of the drift near the barrier or when the line is lost.
	var counter_steer := trike.is_drifting and desired_steer * trike.drift_direction < -drift_bail_counter_steer
	if absf(lateral) > half or absf(heading_error) > drift_bail_heading or counter_steer:
		_drift_this_corner = false
		return false
	if trike.is_drifting:
		# Keep sliding while the corner lasts and we turn the same way.
		var same_way := signf(-corner) == float(trike.drift_direction)
		if sharp and same_way:
			return true
		_drift_this_corner = false
		return false
	if obstacles_near or speed < config.drift_min_speed or absf(_steer) < trike.config.drift_steer_threshold:
		return false
	if signf(_steer) != signf(-corner):
		return false
	drift_count += 1
	return true


# --- Lane choice, corners, obstacles, ramps ----------------------------------

func _choose_lateral(corner: float, lookahead: float) -> float:
	var half := track.half_width_at(path_index) - config.edge_margin
	var desired := lane_offset
	if finished:
		desired = (signf(lane_offset) if lane_offset != 0.0 else 1.0) * half
	else:
		# Inside of the corner: a left turn (corner > 0) is toward -X.
		var cut := clampf(absf(corner) / full_cut_curvature, 0.0, 1.0) * config.corner_cut * half
		desired = lane_offset - signf(corner) * cut
	desired = clampf(desired, -half, half)

	var ramp_lateral := _ramp_ahead(lookahead)
	lining_up_ramp = not is_nan(ramp_lateral)
	if lining_up_ramp:
		obstacles_near = false
		dodging = false
		blocked = false
		return ramp_lateral

	_update_intervals()
	obstacles_near = not (_hard_intervals.is_empty() and _soft_intervals.is_empty())
	dodging = false
	blocked = false
	if not obstacles_near:
		return desired
	var best := _free_lateral(desired, half, _hard_intervals + _soft_intervals)
	if is_nan(best):
		# No clean gap: push through light props (crates, cones) rather than
		# stop; slow down only when walled in by rocks or racers.
		best = _free_lateral(desired, half, _hard_intervals)
	if is_nan(best):
		blocked = true
		return planned_lateral
	dodging = absf(best - desired) > 0.05
	return best


## The free lateral position closest to `desired` (and to the current line),
## or NAN if every position on the road is blocked.
func _free_lateral(desired: float, half: float, intervals: Array[Vector2]) -> float:
	if intervals.is_empty():
		return desired
	var candidates: Array[float] = [desired]
	for interval in intervals:
		candidates.append(interval.x)
		candidates.append(interval.y)
	var best := NAN
	var best_cost := INF
	for candidate in candidates:
		var c := clampf(candidate, -half, half)
		if _inside_any(c, intervals):
			continue
		var cost := absf(c - desired) + 0.5 * absf(c - planned_lateral)
		if cost < best_cost:
			best_cost = cost
			best = c
	return best


static func _inside_any(value: float, intervals: Array[Vector2]) -> bool:
	for interval in intervals:
		if value > interval.x + 0.01 and value < interval.y - 0.01:
			return true
	return false


## Lateral ranges (m) blocked ahead: hard (rocks, slower racers) and soft
## (crates, cones: light props a trike can push through).
func _update_intervals() -> void:
	_hard_intervals.clear()
	_soft_intervals.clear()
	_blocker_speed = INF
	if manager == null:
		return
	var seen_now := {}
	var forward := track.path.forwards[path_index]
	var my_position := trike.global_position
	var range_sq := config.avoid_distance * config.avoid_distance
	for obstacle: Dictionary in manager.get_obstacles():
		var node: Node3D = obstacle["node"]
		if not is_instance_valid(node):
			continue
		if obstacle["kind"] == "cone" and not config.avoid_cones:
			continue
		# Timed hazards only matter while they're on the road.
		if node.has_method(&"is_active") and not node.call(&"is_active"):
			continue
		var position := node.global_position
		if my_position.distance_squared_to(position) > range_sq:
			continue
		var along := (position - my_position).dot(forward)
		if along < 0.0:
			continue
		if _reacted_to(node.get_instance_id(), seen_now):
			var interval := _interval_for(position, along, obstacle["radius"])
			if soft_obstacle_kinds.has(obstacle["kind"]):
				_soft_intervals.append(interval)
			else:
				_hard_intervals.append(interval)
				_blocker_speed = 0.0
	for racer: Racer in manager.get_racers():
		if racer.id == racer_id or not is_instance_valid(racer.trike):
			continue
		var other := racer.trike
		var position := other.global_position
		if my_position.distance_squared_to(position) > range_sq:
			continue
		var along := (position - my_position).dot(forward)
		if along < 0.0:
			continue
		var closing := trike.linear_velocity.dot(forward) - other.get_motion_velocity().dot(forward)
		if closing < racer_closing_speed and along > racer_near_distance:
			continue
		if _reacted_to(other.get_instance_id(), seen_now):
			_hard_intervals.append(_interval_for(position, along, racer_radius))
			_blocker_speed = minf(_blocker_speed, maxf(other.get_motion_velocity().dot(forward), 0.0))
	_seen = seen_now


func _reacted_to(key: int, seen_now: Dictionary) -> bool:
	var first: float = _seen.get(key, _time)
	seen_now[key] = first
	return _time - first >= config.reaction_time


func _interval_for(position: Vector3, along: float, radius: float) -> Vector2:
	var index := mini(path_index + roundi(along / track.path.spacing), track.path.size() - 1)
	var lateral := _lateral_of(position, index)
	var gap := radius + vehicle_half_width + config.avoid_margin
	return Vector2(lateral - gap, lateral + gap)


## Lateral position of the next ramp we would partly hit, or NAN. Ramps are
## taken straight and centered (clipping a ramp edge flips a trike).
func _ramp_ahead(lookahead: float) -> float:
	if manager == null:
		return NAN
	var forward := track.path.forwards[path_index]
	var reach := lookahead + absf(trike.forward_speed) * ramp_line_up_time
	for ramp: Dictionary in manager.get_ramps():
		var node: Node3D = ramp["node"]
		var along := (node.global_position - trike.global_position).dot(forward)
		if along < -2.0 or along > reach:
			continue
		var index := mini(path_index + maxi(roundi(along / track.path.spacing), 0), track.path.size() - 1)
		var lateral := _lateral_of(node.global_position, index)
		var half_width: float = ramp["half_width"]
		if absf(planned_lateral - lateral) < half_width + vehicle_half_width + 0.5:
			return lateral
	return NAN


# --- Recovery ---------------------------------------------------------------

## Returns true while it is handling a stuck trike (reversing).
func _update_unstick(into: TrikeInput, desired_steer: float, dt: float) -> bool:
	if is_reversing:
		_reverse_timer -= dt
		into.throttle = 0.0
		into.brake = 1.0
		into.drift = false
		# Reversing turns the nose the other way: steer opposite.
		_steer = -signf(desired_steer) if absf(desired_steer) > 0.1 else 0.0
		into.steer = _steer
		if _reverse_timer <= 0.0:
			is_reversing = false
			_stuck_timer = 0.0
		return true
	var trying := not finished and target_speed > min_planned_speed * 0.5
	if trying and absf(trike.forward_speed) < 1.0 and trike.is_grounded():
		_stuck_timer += dt
	else:
		_stuck_timer = 0.0
	if _stuck_timer < config.stuck_time:
		return false
	_stuck_timer = 0.0
	unstick_attempts += 1
	if unstick_attempts > config.max_unstick_attempts:
		_press_reset(into)
		return true
	is_reversing = true
	_reverse_timer = config.reverse_time
	return true


## Long-term progress: no new ground for no_progress_time = press R.
func _track_progress(into: TrikeInput, dt: float) -> void:
	if finished:
		_no_progress_timer = 0.0
		return
	if path_index > _best_index:
		_best_index = path_index
		_no_progress_timer = 0.0
		if absf(trike.forward_speed) > 3.0:
			unstick_attempts = 0
		return
	_no_progress_timer += dt
	if _no_progress_timer >= config.no_progress_time:
		_press_reset(into)


func _press_reset(into: TrikeInput) -> void:
	into.reset_pressed = true
	reset_count += 1
	unstick_attempts = 0
	_no_progress_timer = 0.0
	is_reversing = false
	_best_index = 0  # respawn point may be behind the best index


func _on_remounted() -> void:
	_steer = 0.0
	_stuck_timer = 0.0
	_no_progress_timer = 0.0
	is_reversing = false
	unstick_attempts = 0
	_best_index = 0
	_mount_timer = 0.0
	_on_foot_timer = 0.0
	path_index = track.path.find_nearest(trike.global_position, path_index)
	planned_lateral = _lateral_of(trike.global_position, path_index)


# --- On foot ----------------------------------------------------------------

func _poll_on_foot(into: TrikeInput, dt: float) -> void:
	into.throttle = 0.0
	into.brake = 0.0
	into.steer = 0.0
	into.drift = false
	_steer = 0.0
	if rider.state != RiderController.State.ON_FOOT:
		_mount_timer = 0.0
		_detour_timer = 0.0
		_foot_check_timer = 0.0
		if rider.on_foot.is_active():
			_foot_check_position = rider.on_foot.global_position
		return  # falling, getting up or mounting: nothing to do
	_on_foot_timer += dt
	if config.on_foot_give_up_time > 0.0 and _on_foot_timer >= config.on_foot_give_up_time:
		into.reset_pressed = true  # same emergency recovery as the player's R
		emergency_count += 1
		_on_foot_timer = 0.0
		return
	if rider.can_mount:
		_mount_timer += dt
		if _mount_timer >= config.mount_delay:
			into.interact_pressed = true
			mount_count += 1
		return
	_mount_timer = 0.0
	var to_trike := trike.global_position - rider.on_foot.global_position
	to_trike.y = 0.0
	var distance := to_trike.length()
	if distance < 0.05:
		return
	# Walk the last bit so we stop inside the mount distance instead of
	# bumping the trike away.
	var pace := clampf(distance / config.on_foot_slow_radius, 0.25, 1.0)
	var direction := to_trike / distance
	_update_detour(dt)
	if _detour_timer > 0.0:
		direction = direction.rotated(Vector3.UP, deg_to_rad(detour_angle_deg) * _detour_side)
		pace = 1.0
	into.move_direction = direction * pace


## Walking into a rock, a barrier post or the trike's own wreckage: step
## around it, trying the other side each time.
func _update_detour(dt: float) -> void:
	var position := rider.on_foot.global_position
	if _detour_timer > 0.0:
		_detour_timer -= dt
		_foot_check_position = position
		_foot_check_timer = 0.0
		return
	_foot_check_timer += dt
	if _foot_check_timer < detour_check_time:
		return
	var moved := position.distance_to(_foot_check_position)
	_foot_check_position = position
	_foot_check_timer = 0.0
	if moved < detour_min_move:
		_detour_timer = detour_time
		_detour_side = -_detour_side
		detour_count += 1


# --- Helpers ----------------------------------------------------------------

func _build_curvature() -> void:
	var path := track.path
	var span := curvature_span
	_curvature.resize(path.size())
	for i in path.size():
		var first := clampi(i - span, 0, path.size() - 1)
		var last := clampi(i + span, 0, path.size() - 1)
		var length := maxf((last - first) * path.spacing, path.spacing)
		_curvature[i] = path.turn_angle(i, span) / length


## Signed curvature (1/m, + = left turn) at a path sample.
func get_curvature(index: int) -> float:
	return _curvature[clampi(index, 0, _curvature.size() - 1)]


func _lateral_of(position: Vector3, index: int) -> float:
	return (position - track.path.points[index]).dot(track.path.rights[index])


## Heading error (rad, + = target to the left) to a world point.
func _heading_error_to(target: Vector3) -> float:
	var forward := -trike.global_basis.z
	forward.y = 0.0
	var to_target := target - trike.global_position
	to_target.y = 0.0
	if forward.length_squared() < 1e-4 or to_target.length_squared() < 1e-4:
		return 0.0
	return forward.signed_angle_to(to_target, Vector3.UP)


func _steer_noise() -> float:
	if config.steer_noise <= 0.0:
		return 0.0
	var t := _time * config.steer_noise_frequency * TAU
	return config.steer_noise * (0.65 * sin(t + _noise_phase.x) + 0.35 * sin(t * 2.3 + _noise_phase.y))
