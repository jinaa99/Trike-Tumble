class_name ItemRules
extends RefCounted
## Pure item rules (host side), kept separate so tests can check them
## without a race: who a spring punch hits and how hard.


## The racer a spring punch from `from` (heading `forward`) hits: the
## nearest other racer within range and the cone that is riding, racing and
## not immune. Returns null for a miss.
static func pick_punch_target(config: ItemConfig, attacker: Racer, from: Vector3, forward: Vector3,
		candidates: Array[Racer], immune: Callable) -> Racer:
	var flat_forward := Vector3(forward.x, 0.0, forward.z).normalized()
	var best: Racer = null
	var best_distance := INF
	for racer in candidates:
		if racer == attacker or racer.disconnected or racer.finished or not is_instance_valid(racer.trike):
			continue
		if racer.rider and not racer.rider.is_riding():
			continue
		if immune.call(racer.id):
			continue
		var offset := racer.trike.global_position - from
		var distance := offset.length()
		if distance > config.punch_range or distance >= best_distance:
			continue
		var flat := Vector3(offset.x, 0.0, offset.z)
		if flat.length() > 0.3 and flat_forward != Vector3.ZERO \
				and rad_to_deg(flat_forward.angle_to(flat.normalized())) > config.punch_cone_deg:
			continue
		best = racer
		best_distance = distance
	return best


## Knock speed (m/s): strongest point-blank, weakest at the edge of range.
static func punch_speed(config: ItemConfig, distance: float) -> float:
	var t := clampf(distance / maxf(config.punch_range, 0.01), 0.0, 1.0)
	return lerpf(config.punch_max_speed, config.punch_min_speed, t)


## Sideways (relative to the target's heading) away from the attacker, plus a
## small hop.
static func punch_velocity(config: ItemConfig, from: Vector3, target: Trike, speed: float) -> Vector3:
	var right := target.global_basis.x
	right.y = 0.0
	right = right.normalized() if right.length() > 0.01 else Vector3.RIGHT
	var side := signf((target.global_position - from).dot(right))
	if side == 0.0:
		side = 1.0
	return right * side * speed + Vector3.UP * config.punch_up_speed


## True if the racer may be thrown off by a punch this strong.
static func punch_ejects(config: ItemConfig, speed: float) -> bool:
	return speed >= config.punch_eject_speed
