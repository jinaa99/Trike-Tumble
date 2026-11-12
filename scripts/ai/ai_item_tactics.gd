class_name AIItemTactics
extends RefCounted
## When an AI racer presses [use item]. Reads only what a player could see
## (other racers' positions, the road ahead) and answers through TrikeInput,
## so the host validates AI items exactly like a human's.


## True if `racer` should use its held item now.
static func wants_use(racer: Racer, others: Array[Racer], config: AIDriverConfig, road_curvature: float) -> bool:
	if racer == null or not ItemKind.is_valid(racer.held_item) or racer.item_hold_time < config.item_reaction:
		return false
	var held := racer.item_hold_time
	var trike := racer.trike
	var forward := -trike.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var in_line := INF
	var behind := INF
	var beside := INF
	for other in others:
		if other == racer or other.disconnected or other.finished or not is_instance_valid(other.trike):
			continue
		var offset := other.trike.global_position - trike.global_position
		offset.y = 0.0
		var along := offset.dot(forward)
		var distance := offset.length()
		var side := absf(offset.cross(Vector3.UP).dot(forward))
		if along > 6.0 and side < config.item_throw_aim:
			in_line = minf(in_line, distance)
		elif along < -2.0:
			behind = minf(behind, distance)
		if along > -1.5:
			beside = minf(beside, distance)
	match racer.held_item:
		ItemKind.Kind.TURBO_BOTTLE:
			return road_curvature <= config.item_turbo_max_curvature or held > config.item_max_hold
		ItemKind.Kind.BANANA_PEEL:
			return behind <= config.item_drop_range or held > config.item_max_hold
		ItemKind.Kind.MUD_BOMB:
			return in_line <= config.item_throw_range or held > config.item_max_hold
		ItemKind.Kind.SPRING_PUNCH:
			return beside <= config.item_punch_range or held > config.item_max_hold * 2.0
	return false
