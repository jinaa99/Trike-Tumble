class_name RacePositions
extends RefCounted
## Ranks racers by real race progress:
##   1. finished racers, in finishing order
##   2. then more checkpoints passed (in order)
##   3. then more valid distance along the track (CheckpointProgress.distance,
##      measured along the path, not straight-line distance to the finish)
## Two racers on the same checkpoint within `swap_margin` meters keep their
## previous order, so positions don't flicker side by side.


static func rank(racers: Array[Racer], previous: Array[Racer], swap_margin := 1.0) -> Array[Racer]:
	var order: Array[Racer] = racers.duplicate()
	order.sort_custom(_is_ahead)
	# Hysteresis: undo near-tie swaps against the previous order.
	for i in order.size() - 1:
		var a := order[i]
		var b := order[i + 1]
		if a.finished or b.finished or a.checkpoints == null or b.checkpoints == null:
			continue
		if a.checkpoints.get_passed_count() != b.checkpoints.get_passed_count():
			continue
		var was_a := previous.find(a)
		var was_b := previous.find(b)
		if was_a >= 0 and was_b >= 0 and was_b < was_a \
				and a.checkpoints.distance - b.checkpoints.distance < swap_margin:
			order[i] = b
			order[i + 1] = a
	return order


static func _is_ahead(a: Racer, b: Racer) -> bool:
	if a.finished != b.finished:
		return a.finished
	if a.finished:
		return a.finish_position < b.finish_position
	if a.checkpoints == null or b.checkpoints == null:
		return a.id < b.id
	var passed_a := a.checkpoints.get_passed_count()
	var passed_b := b.checkpoints.get_passed_count()
	if passed_a != passed_b:
		return passed_a > passed_b
	if a.checkpoints.distance != b.checkpoints.distance:
		return a.checkpoints.distance > b.checkpoints.distance
	return a.spawn_slot < b.spawn_slot
