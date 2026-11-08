class_name TrackMeshBuilder
extends RefCounted
## Builds render meshes and collision faces from a TrackPath.
##
## Collision and rendering are separate passes. Collision is a simple set of
## quads: road, wall inner/top/outer faces and slope bands. The render pass
## lays more detailed geometry over exactly the same surfaces: red/white
## curbs, a grassy verge, tire ruts, plank barriers with posts and a top rail,
## and multi-tone grass slopes. Visuals can get richer without changing how
## anything drives.

var road_width := 14.0
## Collision strips across the road (render detail is independent).
var road_subdivisions := 4
var wall_height := 1.1
var wall_thickness := 0.7
## Slope cross-section outward from the wall: (outward distance, drop) pairs.
var slope_profile := PackedVector2Array([Vector2(0.0, 0.0), Vector2(6.0, 1.8), Vector2(14.0, 7.0), Vector2(24.0, 22.0)])

var dirt_color := Color(0.8, 0.58, 0.38)
var dirt_dark_color := Color(0.62, 0.42, 0.27)
var rut_color := Color(0.66, 0.46, 0.3)
var verge_color := Color(0.58, 0.6, 0.3)
var curb_colors: Array[Color] = [Color(0.93, 0.2, 0.22), Color(0.98, 0.97, 0.93)]
## Samples per curb stripe (2 m each).
var curb_stripe_samples := 2
var plank_colors: Array[Color] = [Color(0.96, 0.9, 0.78), Color(0.91, 0.84, 0.7)]
var plank_gap_color := Color(0.55, 0.42, 0.3)
var post_color := Color(0.5, 0.34, 0.22)
var rail_color := Color(0.9, 0.24, 0.22)
## Samples between barrier posts.
var post_spacing_samples := 5
var grass_colors: Array[Color] = [Color(0.5, 0.8, 0.33), Color(0.38, 0.7, 0.32), Color(0.29, 0.58, 0.33)]
var rock_slope_color := Color(0.5, 0.52, 0.5)

var road_mesh: ArrayMesh
var wall_mesh: ArrayMesh
var slope_mesh: ArrayMesh
var road_faces := PackedVector3Array()
var wall_faces := PackedVector3Array()
var slope_faces := PackedVector3Array()

var _noise := FastNoiseLite.new()


func _init() -> void:
	_noise.seed = 7
	_noise.frequency = 0.08


func build(path: TrackPath) -> void:
	_build_collision(path)
	road_mesh = _build_road(path)
	wall_mesh = _build_walls(path)
	slope_mesh = _build_slopes(path)


## Outer foot of the wall on one side (side = -1 left, +1 right).
func wall_foot(path: TrackPath, index: int, side: int) -> Vector3:
	var outward := path.rights[index] * float(side)
	return path.points[index] + outward * (road_width * 0.5 + wall_thickness) - Vector3.UP * 0.4


## World position of a point on the slope `outward` meters past the wall.
func slope_point(path: TrackPath, index: int, side: int, outward: float) -> Vector3:
	var drop := 0.0
	for k in range(1, slope_profile.size()):
		var a := slope_profile[k - 1]
		var b := slope_profile[k]
		if outward <= b.x or k == slope_profile.size() - 1:
			drop = lerpf(a.y, b.y, clampf((outward - a.x) / (b.x - a.x), 0.0, 1.0))
			break
	return wall_foot(path, index, side) + path.rights[index] * float(side) * outward - Vector3.UP * drop


# --- Collision (kept simple; defines how the track drives) ------------------

func _build_collision(path: TrackPath) -> void:
	road_faces.clear()
	wall_faces.clear()
	slope_faces.clear()
	for i in path.size() - 1:
		for j in road_subdivisions:
			var u0 := float(j) / road_subdivisions
			var u1 := float(j + 1) / road_subdivisions
			_collision_quad(road_faces, _road_point(path, i, u0), _road_point(path, i, u1),
					_road_point(path, i + 1, u1), _road_point(path, i + 1, u0))
	for side: int in [-1, 1]:
		for i in path.size() - 1:
			var r0 := _wall_ring(path, i, side)
			var r1 := _wall_ring(path, i + 1, side)
			for k in 3:
				_collision_quad(wall_faces, r0[k], r0[k + 1], r1[k + 1], r1[k])
			for k in slope_profile.size() - 1:
				var x0 := slope_profile[k].x
				var x1 := slope_profile[k + 1].x
				_collision_quad(slope_faces, slope_point(path, i, side, x0), slope_point(path, i, side, x1),
						slope_point(path, i + 1, side, x1), slope_point(path, i + 1, side, x0))


func _collision_quad(faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for tri: PackedVector3Array in [PackedVector3Array([a, b, c]), PackedVector3Array([a, c, d])]:
		if (tri[1] - tri[0]).cross(tri[2] - tri[0]).length_squared() >= 1e-10:
			faces.append_array(tri)


# --- Render: road -----------------------------------------------------------

## Lateral bands across the road (0 = left edge, 1 = right edge).
const ROAD_BANDS: Array[float] = [0.0, 0.04, 0.09, 0.2, 0.26, 0.31, 0.5, 0.69, 0.74, 0.8, 0.91, 0.96, 1.0]


func _build_road(path: TrackPath) -> ArrayMesh:
	var st := _begin()
	for i in path.size() - 1:
		@warning_ignore("integer_division")
		var curb := curb_colors[(i / curb_stripe_samples) % curb_colors.size()]
		for j in ROAD_BANDS.size() - 1:
			var u0 := ROAD_BANDS[j]
			var u1 := ROAD_BANDS[j + 1]
			var a := _road_point(path, i, u0)
			var b := _road_point(path, i, u1)
			var c := _road_point(path, i + 1, u1)
			var d := _road_point(path, i + 1, u0)
			var colors: Array[Color]
			if j == 0 or j == ROAD_BANDS.size() - 2:
				colors = [curb, curb, curb, curb]
			else:
				colors = [_road_color(a, u0), _road_color(b, u1), _road_color(c, u1), _road_color(d, u0)]
			# Curbs sit 2 cm proud so they read as a separate surface.
			var lift := path.ups[i] * (0.02 if colors[0] == curb else 0.0)
			_emit(st, a + lift, b + lift, c + lift, d + lift, path.ups[i], colors)
	return st.commit()


func _road_color(p: Vector3, u: float) -> Color:
	var n := _noise.get_noise_3dv(p)
	var color := dirt_color.lerp(dirt_dark_color, clampf(0.5 + n, 0.0, 1.0) * 0.45)
	# Two worn tire ruts.
	var rut := maxf(1.0 - absf(u - 0.28) / 0.04, 0.0) + maxf(1.0 - absf(u - 0.72) / 0.04, 0.0)
	color = color.lerp(rut_color, clampf(rut, 0.0, 1.0) * 0.7)
	# Grassy verge next to the curbs.
	var edge := maxf(1.0 - minf(u, 1.0 - u) / 0.09, 0.0)
	return color.lerp(verge_color, edge * 0.85)


# --- Render: barriers -------------------------------------------------------

func _build_walls(path: TrackPath) -> ArrayMesh:
	var st := _begin()
	var bands: Array[float] = [0.0, 0.28, 0.33, 0.6, 0.65, 0.86, 1.0]  # plank, gap, plank, gap, plank, rail
	for side: int in [-1, 1]:
		for i in path.size() - 1:
			var r0 := _wall_ring(path, i, side)
			var r1 := _wall_ring(path, i + 1, side)
			var outward := path.rights[i] * float(side)
			var is_post := i % post_spacing_samples == 0
			@warning_ignore("integer_division")
			var tone := plank_colors[posmod(i / 2 + side, plank_colors.size())]
			for k in bands.size() - 1:
				var color := tone
				if k % 2 == 1:
					color = plank_gap_color
				if k == bands.size() - 2:
					color = rail_color
				if is_post:
					color = post_color if k != bands.size() - 2 else rail_color.darkened(0.2)
				var a := r0[0].lerp(r0[1], bands[k])
				var b := r0[0].lerp(r0[1], bands[k + 1])
				var c := r1[0].lerp(r1[1], bands[k + 1])
				var d := r1[0].lerp(r1[1], bands[k])
				_emit_flat(st, a, b, c, d, -outward, color)
			_emit_flat(st, r0[1], r0[2], r1[2], r1[1], Vector3.UP, rail_color if not is_post else post_color)
			_emit_flat(st, r0[2], r0[3], r1[3], r1[2], outward, (post_color if is_post else tone).darkened(0.18))
	return st.commit()


# --- Render: slopes ---------------------------------------------------------

func _build_slopes(path: TrackPath) -> ArrayMesh:
	var st := _begin()
	# Same surface as the collision profile, sampled more finely for color.
	var stations := PackedFloat32Array()
	for k in slope_profile.size() - 1:
		for s in 3:
			stations.append(lerpf(slope_profile[k].x, slope_profile[k + 1].x, s / 3.0))
	stations.append(slope_profile[slope_profile.size() - 1].x)
	var far := stations[stations.size() - 1]
	for side: int in [-1, 1]:
		for i in path.size() - 1:
			for k in stations.size() - 1:
				var a := slope_point(path, i, side, stations[k])
				var b := slope_point(path, i, side, stations[k + 1])
				var c := slope_point(path, i + 1, side, stations[k + 1])
				var d := slope_point(path, i + 1, side, stations[k])
				var colors: Array[Color] = [
					_grass_color(a, stations[k] / far), _grass_color(b, stations[k + 1] / far),
					_grass_color(c, stations[k + 1] / far), _grass_color(d, stations[k] / far),
				]
				_emit(st, a, b, c, d, Vector3.UP, colors, true)
	return st.commit()


func _grass_color(p: Vector3, depth: float) -> Color:
	var n := clampf(0.5 + _noise.get_noise_3dv(p * 0.6) * 1.2, 0.0, 1.0)
	var color := grass_colors[0].lerp(grass_colors[1], n)
	color = color.lerp(grass_colors[2], clampf(depth * 1.3 - 0.2, 0.0, 1.0))
	# Rocky, steep lower slopes.
	var rock := clampf((depth - 0.72) * 4.0, 0.0, 1.0) * clampf(0.4 + _noise.get_noise_3dv(p * 1.7), 0.0, 1.0)
	return color.lerp(rock_slope_color, rock)


# --- Geometry helpers -------------------------------------------------------

func _road_point(path: TrackPath, index: int, u: float) -> Vector3:
	return path.points[index] + path.rights[index] * (u - 0.5) * road_width


## Wall cross-section: inner foot, inner top, outer top, outer foot.
func _wall_ring(path: TrackPath, index: int, side: int) -> PackedVector3Array:
	var outward := path.rights[index] * float(side)
	var edge := path.points[index] + outward * road_width * 0.5
	var up := path.ups[index]
	return PackedVector3Array([
		edge - up * 0.2,
		edge + up * wall_height,
		edge + outward * wall_thickness + up * wall_height,
		wall_foot(path, index, side),
	])


func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


func _emit_flat(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, facing: Vector3, color: Color) -> void:
	_emit(st, a, b, c, d, facing, [color, color, color, color], true)


## Adds quad a-b-c-d with per-corner colors. `flat` uses the face normal
## (faceted low-poly look); otherwise `facing` is used as a smooth normal.
## Godot treats clockwise winding (seen from the front) as front-facing.
func _emit(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, facing: Vector3,
		colors: Array[Color], flat := false) -> void:
	var normal := (c - a).cross(b - d)
	if normal.length_squared() < 1e-10:
		return
	normal = normal.normalized()
	if normal.dot(facing) < 0.0:
		normal = -normal
	if not flat:
		normal = facing.normalized()
	var corners := [a, b, c, d]
	for tri: Array in [[0, 1, 2], [0, 2, 3]]:
		var p0: Vector3 = corners[tri[0]]
		var p1: Vector3 = corners[tri[1]]
		var p2: Vector3 = corners[tri[2]]
		var cross := (p1 - p0).cross(p2 - p0)
		if cross.length_squared() < 1e-10:
			continue
		var order: Array = tri if cross.dot(normal) <= 0.0 else [tri[0], tri[2], tri[1]]
		for idx: int in order:
			st.set_normal(normal)
			st.set_color(colors[idx])
			st.add_vertex(corners[idx])
