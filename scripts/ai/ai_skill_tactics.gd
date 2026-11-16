class_name AISkillTactics
extends RefCounted
## When an AI racer presses [skill]. Like AIItemTactics it reads only what a
## player could see and answers through TrikeInput, so the host validates AI
## skills exactly like a human's.


## True if `racer` should use its signature skill now.
static func wants_use(racer: Racer, manager: RacerManager, config: AIDriverConfig, road_curvature: float) -> bool:
	var skills := manager.skills
	if racer == null or skills == null or not skills.is_ready(racer.id) or not is_instance_valid(racer.trike):
		return false
	var trike := racer.trike
	var forward := -trike.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var behind := INF
	var beside := INF
	for other in manager.get_racers():
		if other == racer or other.disconnected or other.finished or not is_instance_valid(other.trike):
			continue
		if other.rider and not other.rider.is_riding():
			continue
		var offset := other.trike.global_position - trike.global_position
		offset.y = 0.0
		var along := offset.dot(forward)
		if along < -2.0:
			behind = minf(behind, offset.length())
		if absf(along) < 6.0:
			beside = minf(beside, offset.length())
	match racer.get_skill():
		SkillKind.Kind.SLINGSHOT:
			# Only where there is room to use the speed.
			return road_curvature <= config.item_turbo_max_curvature and skills.find_slingshot_target(racer) != null
		SkillKind.Kind.BONK:
			return skills.find_bonk_target(racer) != null
		SkillKind.Kind.SNARE, SkillKind.Kind.FAKE_BOX:
			return behind <= config.skill_trap_range
		SkillKind.Kind.SHIELD:
			return behind <= config.skill_shield_range or beside <= config.skill_shield_range * 0.6
	return false
