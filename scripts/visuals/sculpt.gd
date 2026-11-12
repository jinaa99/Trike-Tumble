class_name Sculpt
extends RefCounted
## Small mesh sculpting kit for original procedural models (Visual Overhaul
## V2): lathed shapes with jagged or wobbly rings, noise-displaced blobs and
## tapered limbs, with per-vertex colour gradients. `commit(true)` gives
## smooth shading (foliage, snow, bodywork), `commit(false)` facets (rock, ice).
## Everything is deterministic (seeded), so every computer builds the same mesh.

var vertices := PackedVector3Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()


func _init(seed_value := 1) -> void:
	_rng.seed = seed_value
	_noise.seed = seed_value
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0


func vertex(p: Vector3, color: Color) -> int:
	vertices.append(p)
	colors.append(color)
	return vertices.size() - 1


## Triangle wound so its front faces `outward` (Godot: clockwise = front).
func tri(a: int, b: int, c: int, outward: Vector3) -> void:
	var cross := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
	if cross.length_squared() < 1e-12:
		return
	if cross.dot(outward) > 0.0:
		indices.append_array(PackedInt32Array([a, c, b]))
	else:
		indices.append_array(PackedInt32Array([a, b, c]))


func quad(a: int, b: int, c: int, d: int, outward: Vector3) -> void:
	tri(a, b, c, outward)
	tri(a, c, d, outward)


## Surface of revolution around `xf`'s Y axis. `rings`: [[radius, y, Color,
## jag], ...] following the outline counter-clockwise in the (radius, y)
## plane (bottom → outside → top), so the outside is on the right of the
## travel direction. `jag` (optional) alternates that ring's radius per
## segment (pine skirts, petals); `wobble` adds random radius noise; `droop`
## lowers every other point of jagged rings.
func lathe(xf: Transform3D, rings: Array, segments: int, wobble := 0.0, droop := 0.0, twist := 0.0) -> void:
	var ids: Array[PackedInt32Array] = []
	var phase := _rng.randf() * TAU
	var lumps := PackedFloat32Array()
	for s in segments:
		lumps.append(_rng.randf_range(-1.0, 1.0))
	for r in rings.size():
		var ring: Array = rings[r]
		var jag: float = ring[3] if ring.size() > 3 else 0.0
		var row := PackedInt32Array()
		for s in segments:
			var angle := TAU * s / segments + phase + twist * r
			var radius: float = ring[0]
			var y: float = ring[1]
			if jag != 0.0:
				var sign_s := 1.0 if s % 2 == 0 else -1.0
				radius *= 1.0 + jag * sign_s
				y -= droop * maxf(sign_s, 0.0) * absf(jag) * 4.0
			radius *= 1.0 + wobble * lumps[s]
			row.append(vertex(xf * Vector3(cos(angle) * radius, y, sin(angle) * radius), ring[2]))
		ids.append(row)
	for r in rings.size() - 1:
		var dr: float = rings[r + 1][0] - rings[r][0]
		var dy: float = rings[r + 1][1] - rings[r][1]
		for s in segments:
			var n := (s + 1) % segments
			var angle := TAU * (s + 0.5) / segments + phase + twist * r
			var outward := xf.basis * Vector3(cos(angle) * dy, -dr, sin(angle) * dy)
			quad(ids[r][s], ids[r][n], ids[r + 1][n], ids[r + 1][s], outward)


## Closes a lathe end with a fan at height y (radius = last ring radius).
func disc(xf: Transform3D, radius: float, y: float, segments: int, color: Color, up := true, center_color := Color(-1, 0, 0)) -> void:
	var center := vertex(xf * Vector3(0, y, 0), color if center_color.r < 0.0 else center_color)
	var first := vertices.size()
	for s in segments:
		var angle := TAU * s / segments
		vertex(xf * Vector3(cos(angle) * radius, y, sin(angle) * radius), color)
	for s in segments:
		tri(center, first + s, first + (s + 1) % segments, xf.basis.y * (1.0 if up else -1.0))


## Noise-displaced ellipsoid (canopy puff, boulder, snow mound). Colour
## runs from `bottom` to `top` by the surface direction. `flatten` cuts the
## underside flat at that fraction below the centre (0 = none).
func blob(center: Vector3, radii: Vector3, subdivisions: int, bump: float, frequency: float, top: Color, bottom: Color,
		flatten := 0.0) -> void:
	var base := vertices.size()
	var ico := _icosphere(subdivisions)
	var points: PackedVector3Array = ico[0]
	var offset := Vector3(_rng.randf(), _rng.randf(), _rng.randf()) * 50.0
	for p in points:
		var d := 1.0 + bump * _noise.get_noise_3dv(p * frequency + offset)
		var local := Vector3(p.x * radii.x, p.y * radii.y, p.z * radii.z) * d
		if flatten > 0.0 and local.y < -radii.y * flatten:
			local.y = -radii.y * flatten
		var shade := clampf(p.y * 0.65 + 0.5 + _noise.get_noise_3dv(p * frequency * 2.0 - offset) * 0.25, 0.0, 1.0)
		vertex(center + local, bottom.lerp(top, shade))
	var faces: PackedInt32Array = ico[1]
	for f in range(0, faces.size(), 3):
		var a := base + faces[f]
		var b := base + faces[f + 1]
		var c := base + faces[f + 2]
		tri(a, b, c, (vertices[a] + vertices[b] + vertices[c]) / 3.0 - center)


## Tapered limb from `from` to `to` (trunk, branch, post), with optional bend.
func limb(from: Vector3, to: Vector3, radius_from: float, radius_to: float, segments: int, color_from: Color, color_to: Color,
		steps := 1, bend := Vector3.ZERO, cap := true) -> void:
	var axis := to - from
	var length := axis.length()
	if length < 1e-5:
		return
	var up := axis / length
	var side := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var front := side.cross(up)
	var rows: Array[PackedInt32Array] = []
	var centers := PackedVector3Array()
	for k in steps + 1:
		var t := float(k) / steps
		var center := from.lerp(to, t) + bend * sin(t * PI)
		centers.append(center)
		var radius := lerpf(radius_from, radius_to, t)
		var row := PackedInt32Array()
		for s in segments:
			var angle := TAU * s / segments
			row.append(vertex(center + (side * cos(angle) + front * sin(angle)) * radius, color_from.lerp(color_to, t)))
		rows.append(row)
	for k in steps:
		for s in segments:
			var n := (s + 1) % segments
			var mid := (vertices[rows[k][s]] + vertices[rows[k + 1][n]]) * 0.5
			quad(rows[k][s], rows[k][n], rows[k + 1][n], rows[k + 1][s], mid - (centers[k] + centers[k + 1]) * 0.5)
	if cap:
		var tip := vertex(to + bend * 0.0, color_to)
		for s in segments:
			tri(tip, rows[steps][s], rows[steps][(s + 1) % segments], up)


## Box with optional per-face shading (darker sides) for crisp props.
func box(xf: Transform3D, size: Vector3, color: Color, shade := 0.12) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3.UP, Vector3.RIGHT, Vector3.BACK, 0.0], [Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD, 2.0],
		[Vector3.RIGHT, Vector3.BACK, Vector3.UP, 1.0], [Vector3.LEFT, Vector3.FORWARD, Vector3.UP, 1.0],
		[Vector3.BACK, Vector3.LEFT, Vector3.UP, 0.5], [Vector3.FORWARD, Vector3.RIGHT, Vector3.UP, 0.5],
	]
	for face: Array in faces:
		var n: Vector3 = face[0]
		var u: Vector3 = face[1]
		var v: Vector3 = face[2]
		var c := color.darkened(shade * float(face[3]))
		var o := n * h.abs().dot(n.abs())
		var eu := u * h.abs().dot(u.abs())
		var ev := v * h.abs().dot(v.abs())
		var a := vertex(xf * (o - eu - ev), c)
		var b := vertex(xf * (o + eu - ev), c)
		var cc := vertex(xf * (o + eu + ev), c)
		var d := vertex(xf * (o - eu + ev), c)
		quad(a, b, cc, d, xf.basis * n)


func triangle_count() -> int:
	@warning_ignore("integer_division")
	return indices.size() / 3


## One surface. Smooth: vertex normals averaged over the faces that share a
## vertex. Flat: every face gets its own vertices and the face normal.
func commit(smooth := true, material: Material = null) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	if smooth:
		var normals := PackedVector3Array()
		normals.resize(vertices.size())
		for t in range(0, indices.size(), 3):
			var a := indices[t]
			var b := indices[t + 1]
			var c := indices[t + 2]
			var n := -(vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
			normals[a] += n
			normals[b] += n
			normals[c] += n
		for i in normals.size():
			normals[i] = normals[i].normalized() if normals[i].length_squared() > 1e-16 else Vector3.UP
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
	else:
		var flat_vertices := PackedVector3Array()
		var flat_normals := PackedVector3Array()
		var flat_colors := PackedColorArray()
		for t in range(0, indices.size(), 3):
			var a := vertices[indices[t]]
			var b := vertices[indices[t + 1]]
			var c := vertices[indices[t + 2]]
			var n := (-(b - a).cross(c - a)).normalized()
			# One colour per face keeps facets crisp.
			var color := (colors[indices[t]] + colors[indices[t + 1]] + colors[indices[t + 2]]) / 3.0
			flat_vertices.append_array(PackedVector3Array([a, b, c]))
			flat_normals.append_array(PackedVector3Array([n, n, n]))
			flat_colors.append_array(PackedColorArray([color, color, color]))
		arrays[Mesh.ARRAY_VERTEX] = flat_vertices
		arrays[Mesh.ARRAY_NORMAL] = flat_normals
		arrays[Mesh.ARRAY_COLOR] = flat_colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if material:
		mesh.surface_set_material(0, material)
	return mesh


static var _ico_cache := {}


## [points on the unit sphere, triangle indices].
static func _icosphere(subdivisions: int) -> Array:
	if _ico_cache.has(subdivisions):
		return _ico_cache[subdivisions]
	var t := (1.0 + sqrt(5.0)) / 2.0
	var points := PackedVector3Array([
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)])
	for i in points.size():
		points[i] = points[i].normalized()
	var faces := PackedInt32Array([0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
			3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1])
	for level in subdivisions:
		var next := PackedInt32Array()
		var mids := {}
		for f in range(0, faces.size(), 3):
			var corner := [faces[f], faces[f + 1], faces[f + 2]]
			var mid := []
			for e in 3:
				var a: int = corner[e]
				var b: int = corner[(e + 1) % 3]
				var key := Vector2i(mini(a, b), maxi(a, b))
				if not mids.has(key):
					points.append(((points[a] + points[b]) * 0.5).normalized())
					mids[key] = points.size() - 1
				mid.append(mids[key])
			next.append_array(PackedInt32Array([corner[0], mid[0], mid[2], corner[1], mid[1], mid[0],
					corner[2], mid[2], mid[1], mid[0], mid[1], mid[2]]))
		faces = next
	_ico_cache[subdivisions] = [points, faces]
	return _ico_cache[subdivisions]
