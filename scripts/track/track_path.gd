class_name TrackPath
extends RefCounted
## Evenly spaced samples along a smoothed track centerline.
##
## Each sample has a frame: `forwards` follows the road (including slope),
## `rights` is always horizontal (the road is level side to side), and `ups`
## is perpendicular to both. `widths` is the road width at each sample.
##
## Unhinted nearest-sample lookups use a coarse spatial grid, so they stay
## cheap on long maps (thousands of samples).

## Grid cell size (m) for unhinted nearest-sample lookups.
const GRID_CELL := 40.0
## Beyond this many grid rings an unhinted lookup scans every sample (the
## position is far away from the whole track).
const GRID_MAX_RINGS := 8

var points := PackedVector3Array()
var forwards := PackedVector3Array()
var rights := PackedVector3Array()
var ups := PackedVector3Array()
var widths := PackedFloat32Array()
var length := 0.0
var spacing := 2.0

var _grid := {}


## `width_profile`: (distance m, road width m) keys, eased between keys.
## Empty: `default_width` everywhere.
func build(control_points: PackedVector3Array, sample_spacing: float, default_width := 14.0,
		width_profile := PackedVector2Array()) -> void:
	assert(control_points.size() >= 2, "A track needs at least two control points.")
	spacing = sample_spacing
	points.clear()
	forwards.clear()
	rights.clear()
	ups.clear()
	widths.clear()

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
		widths.append(width_at_distance(width_profile, i * spacing, default_width))

	for i in count:
		var forward := (points[mini(i + 1, count - 1)] - points[maxi(i - 1, 0)]).normalized()
		var right := forward.cross(Vector3.UP).normalized()
		forwards.append(forward)
		rights.append(right)
		ups.append(right.cross(forward).normalized())
	_build_grid()


## Width from a (distance, width) key list, smoothstepped between keys.
static func width_at_distance(profile: PackedVector2Array, distance: float, default_width: float) -> float:
	if profile.is_empty():
		return default_width
	if distance <= profile[0].x:
		return profile[0].y
	for k in range(1, profile.size()):
		if distance <= profile[k].x:
			var a := profile[k - 1]
			var b := profile[k]
			return lerpf(a.y, b.y, smoothstep(a.x, b.x, distance))
	return profile[profile.size() - 1].y


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
## sections of the road that pass close to each other. Without a hint, the
## spatial grid is searched ring by ring around the position.
func find_nearest(position: Vector3, hint := -1, window := 30) -> int:
	if hint >= 0:
		return _scan(position, maxi(hint - window, 0), mini(hint + window, points.size() - 1))
	var center := _cell_of(position)
	var best := -1
	var best_distance := INF
	for ring in GRID_MAX_RINGS + 1:
		# Everything in this ring is at least (ring - 1) cells away.
		if best >= 0 and pow((ring - 1) * GRID_CELL, 2.0) > best_distance:
			return best
		for cell in _ring_cells(center, ring):
			var bucket: PackedInt32Array = _grid.get(cell, PackedInt32Array())
			for i in bucket:
				var d := points[i].distance_squared_to(position)
				if d < best_distance:
					best_distance = d
					best = i
	if best >= 0 and pow(GRID_MAX_RINGS * GRID_CELL, 2.0) > best_distance:
		return best
	return _scan(position, 0, points.size() - 1)


## Signed heading change (radians, + = left turn) from `span` samples before
## `index` to `span` samples after it. Used to find corners for signage.
func turn_angle(index: int, span := 10) -> float:
	var a := forwards[clampi(index - span, 0, points.size() - 1)]
	var b := forwards[clampi(index + span, 0, points.size() - 1)]
	a.y = 0.0
	b.y = 0.0
	return a.signed_angle_to(b, Vector3.UP)


## Samples whose horizontal distance to `position` is below `radius`
## (grid lookup; used by scenery placement).
func samples_near(position: Vector3, radius: float) -> PackedInt32Array:
	var found := PackedInt32Array()
	var center := _cell_of(position)
	var rings := ceili(radius / GRID_CELL)
	var radius_sq := radius * radius
	for dz in range(-rings, rings + 1):
		for dx in range(-rings, rings + 1):
			var bucket: PackedInt32Array = _grid.get(center + Vector2i(dx, dz), PackedInt32Array())
			for i in bucket:
				var p := points[i]
				if (p.x - position.x) * (p.x - position.x) + (p.z - position.z) * (p.z - position.z) < radius_sq:
					found.append(i)
	return found


func _scan(position: Vector3, first: int, last: int) -> int:
	var best := first
	var best_distance := INF
	for i in range(first, last + 1):
		var d := points[i].distance_squared_to(position)
		if d < best_distance:
			best_distance = d
			best = i
	return best


func _build_grid() -> void:
	var buckets := {}
	for i in points.size():
		var cell := _cell_of(points[i])
		if not buckets.has(cell):
			buckets[cell] = []
		(buckets[cell] as Array).append(i)
	_grid.clear()
	for cell: Vector2i in buckets:
		_grid[cell] = PackedInt32Array(buckets[cell])


func _cell_of(position: Vector3) -> Vector2i:
	return Vector2i(floori(position.x / GRID_CELL), floori(position.z / GRID_CELL))


static func _ring_cells(center: Vector2i, ring: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if ring == 0:
		cells.append(center)
		return cells
	for d in range(-ring, ring + 1):
		cells.append(center + Vector2i(d, -ring))
		cells.append(center + Vector2i(d, ring))
	for d in range(-ring + 1, ring):
		cells.append(center + Vector2i(-ring, d))
		cells.append(center + Vector2i(ring, d))
	return cells
