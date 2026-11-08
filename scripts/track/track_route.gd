class_name TrackRoute
extends RefCounted
## Turns a list of route segments into track control points.
##
## Each segment is Vector3(length m, turn degrees (+ = left), grade % downhill).
## A segment is a constant-radius arc (a straight if turn is 0), so the
## tightest corner of a map is simply min(length / turn) and can be checked.
## The grade eases from the previous segment's grade over `grade_blend`
## meters, so slope changes never form a sharp crest.


## Points every `step` meters, starting at `start` heading along
## `heading_deg` (0 = -Z, + = turned left).
static func build_points(start: Vector3, heading_deg: float, segments: PackedVector3Array,
		step := 8.0, grade_blend := 30.0) -> PackedVector3Array:
	var points := PackedVector3Array([start])
	if segments.is_empty():
		return points
	var position := start
	var heading := deg_to_rad(heading_deg)
	var previous_grade := segments[0].z
	for segment in segments:
		var count := maxi(roundi(segment.x / step), 1)
		var ds := segment.x / count
		for k in count:
			var along := (k + 0.5) * ds
			var grade := lerpf(previous_grade, segment.z, minf(along / grade_blend, 1.0))
			heading += deg_to_rad(segment.y) / count
			position += Vector3(-sin(heading), 0.0, -cos(heading)) * ds
			position.y -= grade * 0.01 * ds
			points.append(position)
		previous_grade = segment.z
	return points


## Sum of all segment lengths (m).
static func total_length(segments: PackedVector3Array) -> float:
	var total := 0.0
	for segment in segments:
		total += segment.x
	return total


## Smallest corner radius in the route (m), INF if there are no turns.
static func min_radius(segments: PackedVector3Array) -> float:
	var smallest := INF
	for segment in segments:
		if absf(segment.y) > 0.01:
			smallest = minf(smallest, segment.x / deg_to_rad(absf(segment.y)))
	return smallest
