class_name SkillRules
extends RefCounted
## Pure skill rules (host side), separate so tests can check them without a
## race: who a slingshot may tow from, who a bonk hits and how hard.


static func _usable(racer: Racer, attacker: Racer) -> bool:
	if racer == attacker or racer.disconnected or racer.finished or not is_instance_valid(racer.trike):
		return false
	return racer.rider == null or racer.rider.is_riding()


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## The rival Zip can slingshot past: the nearest riding racer between
## `slingshot_min_ahead` and `slingshot_max_ahead` in front, no more than
## `slingshot_max_side` off the attacker's heading line. Null = no target.
static func pick_slingshot_target(config: SkillConfig, attacker: Racer, from: Vector3, forward: Vector3,
		candidates: Array[Racer]) -> Racer:
	var heading := _flat(forward).normalized()
	if heading == Vector3.ZERO:
		return null
	var best: Racer = null
	var best_ahead := INF
	for racer in candidates:
		if not _usable(racer, attacker):
			continue
		var offset := _flat(racer.trike.global_position - from)
		var ahead := offset.dot(heading)
		var side := (offset - heading * ahead).length()
		if ahead < config.slingshot_min_ahead or ahead > config.slingshot_max_ahead or side > config.slingshot_max_side:
			continue
		if absf(racer.trike.global_position.y - from.y) > 4.0:
			continue
		if ahead < best_ahead:
			best = racer
			best_ahead = ahead
	return best


## The racer Pip's bonk hits: the nearest riding, non-immune racer within
## `bonk_range` and the cone. Null = a whiff.
static func pick_bonk_target(config: SkillConfig, attacker: Racer, from: Vector3, forward: Vector3,
		candidates: Array[Racer], immune: Callable) -> Racer:
	var heading := _flat(forward).normalized()
	var best: Racer = null
	var best_distance := INF
	for racer in candidates:
		if not _usable(racer, attacker) or (immune.is_valid() and immune.call(racer.id)):
			continue
		var offset := racer.trike.global_position - from
		var distance := offset.length()
		if distance > config.bonk_range or distance >= best_distance:
			continue
		var flat := _flat(offset)
		if flat.length() > 0.3 and heading != Vector3.ZERO \
				and rad_to_deg(heading.angle_to(flat.normalized())) > config.bonk_cone_deg:
			continue
		best = racer
		best_distance = distance
	return best


## Shove speed (m/s): strongest point-blank, weakest at the edge of range.
static func bonk_speed(config: SkillConfig, distance: float) -> float:
	return lerpf(config.bonk_max_speed, config.bonk_min_speed, clampf(distance / maxf(config.bonk_range, 0.01), 0.0, 1.0))


## Sideways (relative to the target's heading) away from the attacker, plus
## a small hop.
static func bonk_velocity(config: SkillConfig, from: Vector3, target: Trike, speed: float) -> Vector3:
	var right := _flat(target.global_basis.x)
	right = right.normalized() if right.length() > 0.01 else Vector3.RIGHT
	var side := signf((target.global_position - from).dot(right))
	if side == 0.0:
		side = 1.0
	return right * side * speed + Vector3.UP * config.bonk_up_speed


## Cooldown factor for a race position (1 = leader) among `count` racers.
static func cooldown_factor(config: SkillConfig, position: int, count: int) -> float:
	if count <= 1:
		return 1.0
	return lerpf(config.leader_cooldown_factor, config.last_cooldown_factor,
			clampf(float(position - 1) / float(count - 1), 0.0, 1.0))


## Slipstream geometry: is `me` in the tow of `other`? Behind it along its
## direction of travel, close to its line, both fast enough.
static func in_slipstream(config: SkillConfig, me: Trike, other: Trike) -> bool:
	var other_velocity := _flat(other.get_motion_velocity())
	var my_velocity := _flat(me.get_motion_velocity())
	if other_velocity.length() < config.draft_min_speed or my_velocity.length() < config.draft_min_speed:
		return false
	var direction := other_velocity.normalized()
	if my_velocity.normalized().dot(direction) < 0.8:
		return false
	var offset := _flat(me.global_position - other.global_position)
	var behind := -offset.dot(direction)
	var side := (offset + direction * behind).length()
	return behind >= config.draft_min_behind and behind <= config.draft_max_behind and side <= config.draft_max_side \
			and absf(me.global_position.y - other.global_position.y) < 3.0
