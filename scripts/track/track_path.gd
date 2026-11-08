class_name TrackPath
extends RefCounted
## Evenly spaced samples along a smoothed track centerline.
##
## Each sample has a frame: `forwards` follows the road (including slope),
## `rights` is always horizontal (the road is level side to side), and `ups`
## is perpendicular to both.

var points := PackedVector3Array()
var forwards := PackedVector3Array()
var rights := PackedVector3Array()
var ups := PackedVector3Array()
var length := 0.0
var spacing := 2.0


func build(control_points: PackedVector3Array, sample_spacing: float) -> void:
	assert(control_points.size() >= 2, "A track needs at least two control points.")
	spacing = sample_spacing
	points.clear()
	forwards.clear()
	rights.clear()
	ups.clear()

	# Catmull-Rom style handles give a smooth curve through every control point.
	var curve := Curve3D.new()
	curve.bake_interval = 0.5
	var n := control_points.size()
	for i in n:
		var previous := control_points[maxi(i - 1, 0)]
		var next := control_points[mini(i + 1, n - 1)]
		var handle := (next - previous) / 6.0
		curve.add_point(control_points[i], -handle, handle)

	length = curve.get_baked_length()
	var count := int(floor(length / spacing)) + 1
	for i in count:
		points.append(curve.sample_baked(minf(i * spacing, length), true))

	for i in count:
		var forward := (points[mini(i + 1, count - 1)] - points[maxi(i - 1, 0)]).normalized()
		var right := forward.cross(Vector3.UP).normalized()
		forwards.append(forward)
		rights.append(right)
		ups.append(right.cross(forward).normalized())


func size() -> int:
	return points.size()


## Frame at a sample: -Z along the road, +X to the right, +Y road-up.
func get_frame(index: int) -> Transform3D:
	index = clampi(index, 0, points.size() - 1)
	return Transform3D(Basis(rights[index], ups[index], -forwards[index]), points[index])


func index_at_distance(distance: float) -> int:
	return clampi(roundi(distance / spacing), 0, points.size() - 1)


## Nearest sample to `position`. With a hint, only searches hint ± window,
## which keeps per-frame tracking cheap and stops it jumping between
## sections of the road that pass close to each other.
func find_nearest(position: Vector3, hint := -1, window := 30) -> int:
	var first := 0
	var last := points.size() - 1
	if hint >= 0:
		first = maxi(hint - window, 0)
		last = mini(hint + window, last)
	var best := first
	var best_distance := INF
	for i in range(first, last + 1):
		var d := points[i].distance_squared_to(position)
		if d < best_distance:
			best_distance = d
			best = i
	return best


## Signed heading change (radians, + = left turn) from `span` samples before
## `index` to `span` samples after it. Used to find corners for signage.
func turn_angle(index: int, span := 10) -> float:
	var a := forwards[clampi(index - span, 0, points.size() - 1)]
	var b := forwards[clampi(index + span, 0, points.size() - 1)]
	a.y = 0.0
	b.y = 0.0
	return a.signed_angle_to(b, Vector3.UP)
