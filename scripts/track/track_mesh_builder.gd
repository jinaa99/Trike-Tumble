class_name TrackMeshBuilder
extends RefCounted
## Builds render meshes and collision faces from a TrackPath, in chunks.
##
## Collision and rendering are separate passes. Collision is a simple set of
## quads: road (dirt, mud or bridge planks), wall inner/top/outer faces,
## slope bands and gorge cliff faces. The render pass lays more detailed
## geometry over exactly the same surfaces: red/white curbs, a grassy verge,
## tire ruts, mud puddles, bridge planks, plank barriers with posts and a top
## rail, and multi-tone grass slopes. Visuals can get richer without
## changing how anything drives.
##
## Per sample the road has a width (`TrackPath.widths`) and a kind:
## NORMAL (road, walls, slopes), BRIDGE (plank deck and parapets, no slopes:
## open gorge below) or GAP (nothing: a jump gap). Each chunk of
## `chunk_samples` samples gets its own meshes and collision faces, so the
## renderer can cull distant parts of a long map.

enum SampleKind { NORMAL, BRIDGE, GAP }

## Default width when the path has no widths (older callers).
var road_width := 14.0
## Collision strips across the road (render detail is independent).
var road_subdivisions := 4
var wall_height := 1.1
var wall_thickness := 0.7
## Slope cross-section outward from the wall: (outward distance, drop) pairs.
var slope_profile := PackedVector2Array([Vector2(0.0, 0.0), Vector2(6.0, 1.8), Vector2(14.0, 7.0), Vector2(24.0, 22.0)])
## Samples per mesh/collision chunk.
var chunk_samples := 60
## How far gorge cliffs reach below the road at bridge and gap ends (m).
var cliff_depth := 34.0

var dirt_color := Color(0.8, 0.58, 0.38)
var dirt_dark_color := Color(0.62, 0.42, 0.27)
var rut_color := Color(0.66, 0.46, 0.3)
var verge_color := Color(0.58, 0.6, 0.3)
var mud_color := Color(0.4, 0.27, 0.17)
var mud_wet_color := Color(0.3, 0.2, 0.14)
var curb_colors: Array[Color] = [Color(0.93, 0.2, 0.22), Color(0.98, 0.97, 0.93)]
## Samples per curb stripe (2 m each).
var curb_stripe_samples := 2
var plank_colors: Array[Color] = [Color(0.96, 0.9, 0.78), Color(0.91, 0.84, 0.7)]
var plank_gap_color := Color(0.55, 0.42, 0.3)
var post_color := Color(0.5, 0.34, 0.22)
var rail_color := Color(0.9, 0.24, 0.22)
var deck_colors: Array[Color] = [Color(0.7, 0.5, 0.32), Color(0.62, 0.43, 0.27), Color(0.75, 0.55, 0.36)]
var deck_kerb_color := Color(0.42, 0.28, 0.18)
var bridge_wall_colors: Array[Color] = [Color(0.6, 0.41, 0.25), Color(0.53, 0.36, 0.22)]
var cliff_colors: Array[Color] = [Color(0.56, 0.52, 0.48), Color(0.47, 0.44, 0.42)]
## Samples between barrier posts.
var post_spacing_samples := 5
var grass_colors: Array[Color] = [Color(0.5, 0.8, 0.33), Color(0.38, 0.7, 0.32), Color(0.29, 0.58, 0.33)]
var rock_slope_color := Color(0.5, 0.52, 0.5)

## Rising rock wall used instead of `slope_profile` where a "cliff" zone
## puts the road on a cliff ledge: same outward stations, negative drop =
## above the road. A sheer face, a ridge, then back down to the terrain.
var cliff_profile := PackedVector2Array([Vector2(0.0, 0.0), Vector2(6.0, -20.0), Vector2(14.0, -16.0), Vector2(24.0, 22.0)])
var ice_color := Color(0.62, 0.86, 0.98)
var ice_shine_color := Color(0.88, 0.97, 1.0)
## Horizontal rock layers on cliff walls (empty = plain cliff colors).
var cliff_band_colors: Array[Color] = []

## Per sample: SampleKind, and the surface band across the road (u from, u
## to; equal = none) with its kind (TrackSurface.Kind: MUD or ICE). Set by
## Track before build(); empty = all NORMAL, no bands.
var sample_kinds := PackedByteArray()
var mud_bands := PackedVector2Array()
var band_kinds := PackedByteArray()
## Per side (0 left, 1 right) and sample: 0 = normal slope, 1 = cliff wall
## (`cliff_profile`); blended in between. Empty = no cliffs.
var cliff_weights: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array()]

## One entry per chunk: {"first", "last" (sample indices), "road", "walls",
## "slopes" (ArrayMesh or null), "faces": {category: PackedVector3Array}}.
## Face categories: road, mud, ice, wood, wall, slope, cliff.
var chunks: Array[Dictionary] = []

var _noise := FastNoiseLite.new()
# Per-sample caches (filled once in build()): slope stations and their grass
# colors per side, wall rings per side, road band points and colors.
var _stations := PackedFloat32Array()
var _slope_points := [PackedVector3Array(), PackedVector3Array()]
var _slope_colors := [PackedColorArray(), PackedColorArray()]
var _wall_rings := [PackedVector3Array(), PackedVector3Array()]
var _band_points := PackedVector3Array()
var _band_colors := PackedColorArray()


func _init() -> void:
	_noise.seed = 7
	_noise.frequency = 0.08


func build(path: TrackPath) -> void:
	if sample_kinds.size() != path.size():
		sample_kinds.resize(path.size())
		sample_kinds.fill(SampleKind.NORMAL)
	if mud_bands.size() != path.size():
		mud_bands.resize(path.size())
		mud_bands.fill(Vector2.ZERO)
	if band_kinds.size() != path.size():
		band_kinds.resize(path.size())
		band_kinds.fill(TrackSurface.Kind.MUD)
	for slot in 2:
		if cliff_weights[slot].size() != path.size():
			cliff_weights[slot].resize(path.size())
			cliff_weights[slot].fill(0.0)
	_fill_caches(path)
	chunks.clear()
	var last_quad := path.size() - 2
	var first := 0
	while first <= last_quad:
		var last := mini(first + chunk_samples - 1, last_quad)
		chunks.append(_build_chunk(path, first, last))
		first = last + 1


## Kind of the quad between sample i and i + 1: a gap wins over a bridge.
func quad_kind(i: int) -> SampleKind:
	return maxi(sample_kinds[i], sample_kinds[mini(i + 1, sample_kinds.size() - 1)]) as SampleKind


func half_width(path: TrackPath, index: int) -> float:
	if path.widths.size() == path.size():
		return path.widths[index] * 0.5
	return road_width * 0.5


## Outer foot of the wall on one side (side = -1 left, +1 right).
func wall_foot(path: TrackPath, index: int, side: int) -> Vector3:
	var outward := path.rights[index] * float(side)
	return path.points[index] + outward * (half_width(path, index) + wall_thickness) - Vector3.UP * 0.4


## World position of a point on the slope `outward` meters past the wall
## (on a cliff side: on the rock wall).
func slope_point(path: TrackPath, index: int, side: int, outward: float) -> Vector3:
	var drop := _profile_drop(slope_profile, outward)
	var cliff := cliff_weight(index, side)
	if cliff > 0.0:
		drop = lerpf(drop, _profile_drop(cliff_profile, outward), cliff)
	return wall_foot(path, index, side) + path.rights[index] * float(side) * outward - Vector3.UP * drop


## 0 = normal slope, 1 = full cliff wall on that side at sample `index`.
func cliff_weight(index: int, side: int) -> float:
	var weights := cliff_weights[_side_slot(side)]
	return weights[index] if index < weights.size() else 0.0


static func _profile_drop(profile: PackedVector2Array, outward: float) -> float:
	for k in range(1, profile.size()):
		var a := profile[k - 1]
		var b := profile[k]
		if outward <= b.x or k == profile.size() - 1:
			return lerpf(a.y, b.y, clampf((outward - a.x) / (b.x - a.x), 0.0, 1.0))
	return 0.0


func _build_chunk(path: TrackPath, first: int, last: int) -> Dictionary:
	var faces := {"road": PackedVector3Array(), "mud": PackedVector3Array(), "ice": PackedVector3Array(), "wood": PackedVector3Array(),
			"wall": PackedVector3Array(), "slope": PackedVector3Array(), "cliff": PackedVector3Array()}
	_build_collision(path, first, last, faces)
	var road := MeshBatch.new()
	var walls := MeshBatch.new()
	var slopes := MeshBatch.new()
	_build_road(path, first, last, road)
	_build_walls(path, first, last, walls)
	_build_slopes(path, first, last, slopes)
	_build_cliffs(path, first, last, slopes, faces["cliff"])
	return {"first": first, "last": last + 1, "road": road.commit(), "walls": walls.commit(),
			"slopes": slopes.commit(), "faces": faces}


# --- Collision (kept simple; defines how the track drives) ------------------

func _build_collision(path: TrackPath, first: int, last: int, faces: Dictionary) -> void:
	for i in range(first, last + 1):
		var kind := quad_kind(i)
		if kind == SampleKind.GAP:
			continue
		var cuts := _road_cuts(i, road_subdivisions)
		var mud := mud_bands[i]
		var band_faces := "ice" if band_kinds[i] == TrackSurface.Kind.ICE else "mud"
		for j in cuts.size() - 1:
			var u0 := cuts[j]
			var u1 := cuts[j + 1]
			var target: PackedVector3Array = faces["road"]
			if kind == SampleKind.BRIDGE:
				target = faces["wood"]
			elif mud.y > mud.x and u0 >= mud.x - 0.001 and u1 <= mud.y + 0.001:
				target = faces[band_faces]
			_collision_quad(target, _road_point(path, i, u0), _road_point(path, i, u1),
					_road_point(path, i + 1, u1), _road_point(path, i + 1, u0))
	for side: int in [-1, 1]:
		for i in range(first, last + 1):
			var kind := quad_kind(i)
			if kind == SampleKind.GAP:
				continue
			var r0 := _ring(side, i)
			var r1 := _ring(side, i + 1)
			for k in 3:
				_collision_quad(faces["wall"], r0[k], r0[k + 1], r1[k + 1], r1[k])
			if kind == SampleKind.BRIDGE:
				continue
			var slope: PackedVector3Array = _slope_points[_side_slot(side)]
			var count := _stations.size()
			for k in slope_profile.size() - 1:
				# Profile point k is station 3k (see _fill_caches).
				var s0 := 3 * k
				var s1 := 3 * (k + 1)
				_collision_quad(faces["slope"], slope[i * count + s0], slope[i * count + s1],
						slope[(i + 1) * count + s1], slope[(i + 1) * count + s0])


## Collision strip boundaries across the road at sample i, including the
## edges of a mud band so mud gets its own faces.
func _road_cuts(i: int, subdivisions: int) -> PackedFloat32Array:
	var cuts := PackedFloat32Array()
	for j in subdivisions + 1:
		cuts.append(float(j) / subdivisions)
	var mud := mud_bands[i]
	if mud.y > mud.x:
		for u: float in [mud.x, mud.y]:
			var known := false
			for c in cuts:
				known = known or absf(c - u) < 0.001
			if not known:
				cuts.append(u)
		cuts.sort()
	return cuts


func _collision_quad(faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	if (b - a).cross(c - a).length_squared() >= 1e-10:
		faces.append_array(PackedVector3Array([a, b, c]))
	if (c - a).cross(d - a).length_squared() >= 1e-10:
		faces.append_array(PackedVector3Array([a, c, d]))


# --- Render: road -----------------------------------------------------------

## Lateral bands across the road (0 = left edge, 1 = right edge).
const ROAD_BANDS: Array[float] = [0.0, 0.04, 0.09, 0.2, 0.26, 0.31, 0.5, 0.69, 0.74, 0.8, 0.91, 0.96, 1.0]
## Bridge deck: plank kerbs at the edges.
const DECK_BANDS: Array[float] = [0.0, 0.05, 0.5, 0.95, 1.0]
## Lengthwise planks per sample on a bridge deck.
const DECK_PLANKS := 4


func _build_road(path: TrackPath, first: int, last: int, out: MeshBatch) -> void:
	for i in range(first, last + 1):
		match quad_kind(i):
			SampleKind.GAP:
				continue
			SampleKind.BRIDGE:
				_build_deck(path, i, out)
				continue
		@warning_ignore("integer_division")
		var curb := curb_colors[(i / curb_stripe_samples) % curb_colors.size()]
		var mud := mud_bands[i]
		if mud.y <= mud.x:
			_road_row_cached(path, i, curb, out)
			continue
		var bands := ROAD_BANDS.duplicate()
		bands.append(mud.x)
		bands.append(mud.y)
		bands.sort()
		for j in bands.size() - 1:
			var u0: float = bands[j]
			var u1: float = bands[j + 1]
			if u1 - u0 < 0.001:
				continue
			var a := _road_point(path, i, u0)
			var b := _road_point(path, i, u1)
			var c := _road_point(path, i + 1, u1)
			var d := _road_point(path, i + 1, u0)
			var is_curb := u1 <= ROAD_BANDS[1] + 0.001 or u0 >= ROAD_BANDS[ROAD_BANDS.size() - 2] - 0.001
			var in_mud := mud.y > mud.x and u0 >= mud.x - 0.001 and u1 <= mud.y + 0.001
			var colors: Array[Color]
			if is_curb and not in_mud:
				colors = [curb, curb, curb, curb]
			elif in_mud and band_kinds[i] == TrackSurface.Kind.ICE:
				colors = [_ice_color(a), _ice_color(b), _ice_color(c), _ice_color(d)]
			elif in_mud:
				colors = [_mud_color(a), _mud_color(b), _mud_color(c), _mud_color(d)]
			else:
				colors = [_road_color(a, u0), _road_color(b, u1), _road_color(c, u1), _road_color(d, u0)]
			# Curbs sit 2 cm proud so they read as a separate surface; mud 1 cm.
			var lift := path.ups[i] * (0.02 if is_curb and not in_mud else (0.01 if in_mud else 0.0))
			out.quad(a + lift, b + lift, c + lift, d + lift, path.ups[i], colors)


## Plain dirt row between samples i and i + 1 from the cached band points.
func _road_row_cached(path: TrackPath, i: int, curb: Color, out: MeshBatch) -> void:
	var n := ROAD_BANDS.size()
	var lift := path.ups[i] * 0.02
	for j in n - 1:
		var a := _band_points[i * n + j]
		var b := _band_points[i * n + j + 1]
		var c := _band_points[(i + 1) * n + j + 1]
		var d := _band_points[(i + 1) * n + j]
		if j == 0 or j == n - 2:
			out.quad(a + lift, b + lift, c + lift, d + lift, path.ups[i], [curb, curb, curb, curb])
		else:
			out.quad(a, b, c, d, path.ups[i], [_band_colors[i * n + j], _band_colors[i * n + j + 1],
					_band_colors[(i + 1) * n + j + 1], _band_colors[(i + 1) * n + j]])


func _build_deck(path: TrackPath, i: int, out: MeshBatch) -> void:
	for p in DECK_PLANKS:
		var t0 := float(p) / DECK_PLANKS
		var t1 := float(p + 1) / DECK_PLANKS
		var tone := deck_colors[(i * DECK_PLANKS + p) % deck_colors.size()]
		for j in DECK_BANDS.size() - 1:
			var u0 := DECK_BANDS[j]
			var u1 := DECK_BANDS[j + 1]
			var color := deck_kerb_color if j == 0 or j == DECK_BANDS.size() - 2 else tone
			var a := _road_point(path, i, u0).lerp(_road_point(path, i + 1, u0), t0)
			var b := _road_point(path, i, u1).lerp(_road_point(path, i + 1, u1), t0)
			var c := _road_point(path, i, u1).lerp(_road_point(path, i + 1, u1), t1)
			var d := _road_point(path, i, u0).lerp(_road_point(path, i + 1, u0), t1)
			out.flat_quad(a, b, c, d, path.ups[i], color)
	# Deck underside and beam sides, so the bridge reads solid from below.
	var depth := path.ups[i] * -0.7
	var l0 := _road_point(path, i, 0.0)
	var r0 := _road_point(path, i, 1.0)
	var l1 := _road_point(path, i + 1, 0.0)
	var r1 := _road_point(path, i + 1, 1.0)
	out.flat_quad(l0 + depth, r0 + depth, r1 + depth, l1 + depth, -path.ups[i], deck_kerb_color.darkened(0.3))


func _road_color(p: Vector3, u: float) -> Color:
	var n := _noise.get_noise_3dv(p)
	var color := dirt_color.lerp(dirt_dark_color, clampf(0.5 + n, 0.0, 1.0) * 0.45)
	# Two worn tire ruts.
	var rut := maxf(1.0 - absf(u - 0.28) / 0.04, 0.0) + maxf(1.0 - absf(u - 0.72) / 0.04, 0.0)
	color = color.lerp(rut_color, clampf(rut, 0.0, 1.0) * 0.7)
	# Grassy verge next to the curbs.
	var edge := maxf(1.0 - minf(u, 1.0 - u) / 0.09, 0.0)
	return color.lerp(verge_color, edge * 0.85)


func _mud_color(p: Vector3) -> Color:
	var n := clampf(0.5 + _noise.get_noise_3dv(p * 0.7) * 1.4, 0.0, 1.0)
	return mud_color.lerp(mud_wet_color, n)


## Glassy ice: smooth base with polished diagonal streaks.
func _ice_color(p: Vector3) -> Color:
	var streak := clampf(sin((p.x + p.z) * 0.9 + _noise.get_noise_3dv(p * 0.4) * 3.0) * 1.6 - 0.6, 0.0, 1.0)
	return ice_color.lerp(ice_shine_color, streak)


# --- Render: barriers -------------------------------------------------------

func _build_walls(path: TrackPath, first: int, last: int, out: MeshBatch) -> void:
	var bands: Array[float] = [0.0, 0.28, 0.33, 0.6, 0.65, 0.86, 1.0]  # plank, gap, plank, gap, plank, rail
	for side: int in [-1, 1]:
		for i in range(first, last + 1):
			var kind := quad_kind(i)
			if kind == SampleKind.GAP:
				continue
			var bridge := kind == SampleKind.BRIDGE
			var r0 := _ring(side, i)
			var r1 := _ring(side, i + 1)
			var outward := path.rights[i] * float(side)
			var is_post := i % (2 if bridge else post_spacing_samples) == 0
			var palette := bridge_wall_colors if bridge else plank_colors
			@warning_ignore("integer_division")
			var tone := palette[posmod(i / 2 + side, palette.size())]
			var rail := deck_kerb_color if bridge else rail_color
			for k in bands.size() - 1:
				var color := tone
				if k % 2 == 1:
					color = plank_gap_color
				if k == bands.size() - 2:
					color = rail
				if is_post:
					color = post_color if k != bands.size() - 2 else rail.darkened(0.2)
				var a := r0[0].lerp(r0[1], bands[k])
				var b := r0[0].lerp(r0[1], bands[k + 1])
				var c := r1[0].lerp(r1[1], bands[k + 1])
				var d := r1[0].lerp(r1[1], bands[k])
				out.flat_quad(a, b, c, d, -outward, color)
			out.flat_quad(r0[1], r0[2], r1[2], r1[1], Vector3.UP, rail if not is_post else post_color)
			out.flat_quad(r0[2], r0[3], r1[3], r1[2], outward, (post_color if is_post else tone).darkened(0.18))
			if bridge:
				# Under the parapet: continue its outer face down to the deck beam.
				var drop := path.ups[i] * -0.7
				out.flat_quad(r0[3], r0[3] + drop, r1[3] + drop, r1[3], outward, deck_kerb_color.darkened(0.2))


# --- Render: slopes ---------------------------------------------------------

func _build_slopes(path: TrackPath, first: int, last: int, out: MeshBatch) -> void:
	# Same surface as the collision profile, sampled more finely for color.
	var count := _stations.size()
	for side: int in [-1, 1]:
		var points: PackedVector3Array = _slope_points[_side_slot(side)]
		var colors: PackedColorArray = _slope_colors[_side_slot(side)]
		for i in range(first, last + 1):
			if quad_kind(i) != SampleKind.NORMAL:
				continue
			var row0 := i * count
			var row1 := (i + 1) * count
			for k in count - 1:
				out.quad(points[row0 + k], points[row0 + k + 1], points[row1 + k + 1], points[row1 + k], Vector3.UP,
						[colors[row0 + k], colors[row0 + k + 1], colors[row1 + k + 1], colors[row1 + k]], true)


## Grass, or rock (with layer bands) on a cliff wall.
func _slope_color(p: Vector3, depth: float, cliff: float) -> Color:
	var color := _grass_color(p, depth)
	if cliff <= 0.0:
		return color
	var rock := cliff_colors[0].lerp(cliff_colors[1 % cliff_colors.size()], clampf(0.5 + _noise.get_noise_3dv(p * 0.5), 0.0, 1.0))
	if not cliff_band_colors.is_empty():
		var layer := posmod(floori(p.y / 2.6), cliff_band_colors.size())
		rock = rock.lerp(cliff_band_colors[layer], 0.55)
	return color.lerp(rock, clampf(cliff * 1.5, 0.0, 1.0))


func _grass_color(p: Vector3, depth: float) -> Color:
	var n := clampf(0.5 + _noise.get_noise_3dv(p * 0.6) * 1.2, 0.0, 1.0)
	var color := grass_colors[0].lerp(grass_colors[1], n)
	color = color.lerp(grass_colors[2], clampf(depth * 1.3 - 0.2, 0.0, 1.0))
	# Rocky, steep lower slopes.
	var rock := clampf((depth - 0.72) * 4.0, 0.0, 1.0) * clampf(0.4 + _noise.get_noise_3dv(p * 1.7), 0.0, 1.0)
	return color.lerp(rock_slope_color, rock)


# --- Gorge cliffs (bridge and gap ends) ---------------------------------------

## Where the ground stops (start of a bridge or gap) and starts again, a
## rocky cliff face drops from the road/slope cross-section into the gorge.
func _build_cliffs(path: TrackPath, first: int, last: int, out: MeshBatch, faces: PackedVector3Array) -> void:
	for i in range(maxi(first, 1), last + 1):
		var before := quad_kind(i - 1) == SampleKind.NORMAL
		var after := quad_kind(i) == SampleKind.NORMAL
		if before == after:
			continue
		# Face toward the open gorge: forward when the gorge comes next.
		var facing := path.forwards[i] if before else -path.forwards[i]
		var top := _cross_section(path, i)
		var bottom_y := INF
		for p in top:
			bottom_y = minf(bottom_y, p.y)
		bottom_y -= cliff_depth
		for k in top.size() - 1:
			var a := top[k]
			var b := top[k + 1]
			var c := Vector3(b.x, bottom_y, b.z)
			var d := Vector3(a.x, bottom_y, a.z)
			var tone := cliff_colors[k % cliff_colors.size()]
			out.quad(a, b, c, d, facing, [tone, tone, tone.darkened(0.25), tone.darkened(0.25)], true)
			_collision_quad(faces, a, b, c, d)


## Top outline across the whole track at sample i, left slope end to right
## slope end (through the walls and the road).
func _cross_section(path: TrackPath, i: int) -> PackedVector3Array:
	var line := PackedVector3Array()
	for k in range(slope_profile.size() - 1, -1, -1):
		line.append(slope_point(path, i, -1, slope_profile[k].x))
	var left := _wall_ring(path, i, -1)
	line.append_array(PackedVector3Array([left[2], left[1], left[0]]))
	var right := _wall_ring(path, i, 1)
	line.append_array(PackedVector3Array([right[0], right[1], right[2]]))
	for k in slope_profile.size():
		line.append(slope_point(path, i, 1, slope_profile[k].x))
	return line


# --- Caches -------------------------------------------------------------------

func _fill_caches(path: TrackPath) -> void:
	_stations = PackedFloat32Array()
	for k in slope_profile.size() - 1:
		for s in 3:
			_stations.append(lerpf(slope_profile[k].x, slope_profile[k + 1].x, s / 3.0))
	_stations.append(slope_profile[slope_profile.size() - 1].x)
	var far := _stations[_stations.size() - 1]
	var count := path.size()
	for side: int in [-1, 1]:
		var points := PackedVector3Array()
		var colors := PackedColorArray()
		var rings := PackedVector3Array()
		points.resize(count * _stations.size())
		colors.resize(count * _stations.size())
		for i in count:
			rings.append_array(_wall_ring(path, i, side))
			for k in _stations.size():
				var p := slope_point(path, i, side, _stations[k])
				points[i * _stations.size() + k] = p
				colors[i * _stations.size() + k] = _slope_color(p, _stations[k] / far, cliff_weight(i, side))
		_slope_points[_side_slot(side)] = points
		_slope_colors[_side_slot(side)] = colors
		_wall_rings[_side_slot(side)] = rings
	var bands := ROAD_BANDS.size()
	_band_points.resize(count * bands)
	_band_colors.resize(count * bands)
	for i in count:
		for j in bands:
			var p := _road_point(path, i, ROAD_BANDS[j])
			_band_points[i * bands + j] = p
			_band_colors[i * bands + j] = _road_color(p, ROAD_BANDS[j])


static func _side_slot(side: int) -> int:
	return 0 if side < 0 else 1


## Cached wall cross-section (see _wall_ring).
func _ring(side: int, index: int) -> PackedVector3Array:
	return (_wall_rings[_side_slot(side)] as PackedVector3Array).slice(index * 4, index * 4 + 4)


# --- Geometry helpers -------------------------------------------------------

func _road_point(path: TrackPath, index: int, u: float) -> Vector3:
	return path.points[index] + path.rights[index] * (u - 0.5) * half_width(path, index) * 2.0


## Wall cross-section: inner foot, inner top, outer top, outer foot.
func _wall_ring(path: TrackPath, index: int, side: int) -> PackedVector3Array:
	var outward := path.rights[index] * float(side)
	var edge := path.points[index] + outward * half_width(path, index)
	var up := path.ups[index]
	return PackedVector3Array([
		edge - up * 0.2,
		edge + up * wall_height,
		edge + outward * wall_thickness + up * wall_height,
		wall_foot(path, index, side),
	])
