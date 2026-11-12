class_name SceneryKit
extends RefCounted
## Original scenery models, sculpted in code with Sculpt (no model files):
## pines, broadleaf trees, bushes, rocks, hoodoos, stumps, ferns, cacti and
## snow loads. Foliage and rock meshes are light grey so a MultiMesh
## instance colour supplies the palette; trunks carry their own bark colour.
## `detail` 0 = distant/cheap version, 1 = normal.

const BARK := Color(0.42, 0.29, 0.2)
const BARK_DARK := Color(0.3, 0.2, 0.14)


## A pine: {"foliage", "trunk", "snow"} meshes sharing one origin (base of
## the trunk). About 5 m tall at scale 1; `variant` 0..2 changes the build.
static func pine(variant: int, detail := 1) -> Dictionary:
	var s := Sculpt.new(100 + variant)
	var snow := Sculpt.new(200 + variant)
	var tiers: int = [6, 5, 4][variant % 3] if detail > 0 else 3
	var height: float = [5.4, 4.6, 3.4][variant % 3]
	var spread: float = [1.55, 1.75, 1.45][variant % 3]
	var segments := 8 if detail > 0 else 6
	var trunk_height := height * 0.2
	var lean := Vector3(0.05 * (variant - 1), 0, 0.03 * variant)
	for k in tiers:
		var t := float(k) / tiers
		var base_y := lerpf(trunk_height, height * 0.86, t)
		var radius := spread * (1.0 - t * 0.78)
		var tier_height := (height - trunk_height) / tiers * 1.75
		var shade := lerpf(0.72, 1.0, t)
		var xf := Transform3D(Basis(Vector3.UP, k * 0.9), lean * (base_y / height) * 4.0)
		var tip := Color(shade, shade, shade)
		var inner := Color(shade * 0.62, shade * 0.66, shade * 0.62)
		s.lathe(xf, [
			[radius * 0.25, base_y + tier_height * 0.12, inner * 0.8],
			[radius, base_y, tip, 0.2],
			[radius * 0.55, base_y + tier_height * 0.42, inner.lerp(tip, 0.4)],
			[0.04, base_y + tier_height, inner.lerp(tip, 0.75)],
		], segments, 0.1, 0.09 * radius)
		# Snow load: the upper face of each tier, pushed out a little.
		snow.lathe(xf, [
			[radius * 0.86, base_y + tier_height * 0.1, Color(0.84, 0.88, 0.95), 0.16],
			[radius * 0.52, base_y + tier_height * 0.5, Color(1, 1, 1)],
			[0.05, base_y + tier_height * 1.03, Color(1, 1, 1)],
		], segments, 0.08, 0.05 * radius)
	var trunk := Sculpt.new(300 + variant)
	trunk.limb(Vector3(0, -0.4, 0), lean * 2.0 + Vector3(0, height * 0.5, 0), 0.24, 0.1, 7 if detail > 0 else 5, BARK_DARK, BARK, 2)
	if detail > 0:
		# Root flare.
		trunk.lathe(Transform3D.IDENTITY, [[0.42, -0.3, BARK_DARK], [0.3, 0.0, BARK_DARK], [0.22, 0.35, BARK]], 7, 0.18)
	return {"foliage": s.commit(true), "trunk": trunk.commit(true), "snow": snow.commit(true)}


## A broadleaf tree with a lumpy layered canopy. {"foliage", "trunk", "snow"}.
static func broadleaf(variant: int, detail := 1) -> Dictionary:
	var s := Sculpt.new(400 + variant)
	var snow := Sculpt.new(500 + variant)
	var trunk := Sculpt.new(600 + variant)
	var rng := RandomNumberGenerator.new()
	rng.seed = 700 + variant
	var crown_y: float = [3.0, 2.6, 3.5][variant % 3]
	var crown_r: float = [1.45, 1.7, 1.25][variant % 3]
	var top := Color(1, 1, 1)
	var bottom := Color(0.55, 0.6, 0.52)
	var puffs: int = [5, 6, 4][variant % 3] if detail > 0 else 2
	var subdivisions := 2 if detail > 0 else 1
	s.blob(Vector3(0, crown_y, 0), Vector3(crown_r, crown_r * 0.82, crown_r), subdivisions, 0.16, 1.3, top, bottom)
	snow.blob(Vector3(0, crown_y + crown_r * 0.42, 0), Vector3(crown_r * 0.86, crown_r * 0.42, crown_r * 0.86), 1, 0.12, 1.2,
			Color(1, 1, 1), Color(0.82, 0.87, 0.95), 0.2)
	for k in puffs:
		var angle: float = TAU * k / puffs + rng.randf() * 0.6
		var out := crown_r * rng.randf_range(0.55, 0.8)
		var r := crown_r * rng.randf_range(0.5, 0.7)
		var at := Vector3(cos(angle) * out, crown_y + rng.randf_range(-0.5, 0.55) * crown_r, sin(angle) * out)
		s.blob(at, Vector3(r, r * 0.85, r), subdivisions, 0.18, 1.5, top, bottom)
	trunk.limb(Vector3(0, -0.4, 0), Vector3(0.08, crown_y - crown_r * 0.3, 0.05), 0.26, 0.13, 7 if detail > 0 else 5, BARK_DARK, BARK, 3,
			Vector3(0.12, 0, -0.06))
	if detail > 0:
		trunk.lathe(Transform3D.IDENTITY, [[0.46, -0.3, BARK_DARK], [0.32, 0.0, BARK_DARK], [0.24, 0.4, BARK]], 7, 0.2)
		for k in 2:
			var angle := 1.1 + k * 2.6 + variant
			var from := Vector3(0.04, crown_y * (0.5 + 0.12 * k), 0.02)
			trunk.limb(from, from + Vector3(cos(angle) * 0.9, 0.9, sin(angle) * 0.9), 0.09, 0.04, 5, BARK, BARK)
	return {"foliage": s.commit(true), "trunk": trunk.commit(true), "snow": snow.commit(true)}


## Canyon dry tree: twisted trunk, sparse flat canopy pads.
static func dry_tree(variant: int) -> Dictionary:
	var s := Sculpt.new(800 + variant)
	var trunk := Sculpt.new(810 + variant)
	var wood := Color(0.5, 0.38, 0.28)
	var wood_dark := Color(0.36, 0.26, 0.2)
	trunk.limb(Vector3(0, -0.3, 0), Vector3(0.25, 1.7, 0.1), 0.2, 0.11, 6, wood_dark, wood, 3, Vector3(-0.22, 0, 0.12))
	var forks := [Vector3(1.0, 2.7, 0.2), Vector3(-0.6, 2.9, -0.5), Vector3(0.1, 3.1, 0.8)]
	for k in forks.size():
		var tip: Vector3 = forks[k]
		trunk.limb(Vector3(0.25, 1.65, 0.1), tip, 0.1, 0.035, 5, wood, wood, 2, Vector3(0, 0.15, 0))
		if (k + variant) % 3 != 2:
			s.blob(tip + Vector3(0, 0.15, 0), Vector3(0.85, 0.32, 0.75), 1, 0.2, 1.4, Color(1, 1, 1), Color(0.6, 0.62, 0.55))
	return {"foliage": s.commit(true), "trunk": trunk.commit(true)}


## Low rounded bush / shrub cluster (soft: no collider needed).
static func bush(variant: int) -> ArrayMesh:
	var s := Sculpt.new(900 + variant)
	var top := Color(1, 1, 1)
	var bottom := Color(0.5, 0.56, 0.48)
	s.blob(Vector3(0, 0.38, 0), Vector3(0.72, 0.55, 0.7), 1, 0.2, 1.4, top, bottom, 0.6)
	s.blob(Vector3(0.58, 0.3, 0.18), Vector3(0.5, 0.42, 0.5), 1, 0.2, 1.6, top, bottom, 0.6)
	s.blob(Vector3(-0.48, 0.27, -0.26), Vector3(0.46, 0.38, 0.48), 1, 0.2, 1.6, top, bottom, 0.6)
	if variant % 2 == 1:
		s.blob(Vector3(0.1, 0.62, -0.1), Vector3(0.4, 0.36, 0.4), 1, 0.2, 1.6, top, bottom)
	return s.commit(true)


## Faceted boulder inside the unit sphere (instances scale it). The old
## convex collider (a unit sphere scaled the same way) still fits.
static func rock(variant: int, subdivisions := 1) -> ArrayMesh:
	var s := Sculpt.new(1000 + variant)
	s.blob(Vector3.ZERO, Vector3(0.86, 0.8, 0.86), subdivisions, 0.3, 0.9 + 0.2 * variant, Color(1, 1, 1), Color(0.62, 0.62, 0.64), 0.55)
	return s.commit(false)


## Snow sitting on a boulder (same unit-sphere frame).
static func rock_snow() -> ArrayMesh:
	var s := Sculpt.new(1100)
	s.blob(Vector3(0, 0.42, 0), Vector3(0.9, 0.6, 0.9), 1, 0.12, 1.0, Color(1, 1, 1), Color(0.8, 0.86, 0.95), 0.25)
	return s.commit(true)


## Canyon hoodoo: stacked eroded sandstone drums with a balanced cap rock.
## About 9 m tall, base radius ~1.25 (matches the scenery collider).
static func hoodoo(variant: int) -> ArrayMesh:
	var s := Sculpt.new(1200 + variant)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1210 + variant
	var rings := []
	var y := -0.5
	var radius := 1.3
	var layers := 9 + variant
	for k in layers:
		var tone := Color(1, 1, 1) if k % 2 == 0 else Color(0.74, 0.7, 0.7)
		if k % 4 == 3:
			tone = Color(0.6, 0.52, 0.52)
		rings.append([radius, y, tone])
		y += rng.randf_range(0.55, 1.05)
		# Erosion: thin necks under harder, wider layers.
		radius = clampf(radius * rng.randf_range(0.72, 1.08), 0.5, 1.3) * (0.97 if k < layers - 3 else 0.9)
		rings.append([radius * rng.randf_range(0.92, 1.0), y - 0.08, tone.darkened(0.12)])
	s.lathe(Transform3D.IDENTITY, rings, 9, 0.12, 0.0, 0.25)
	s.disc(Transform3D.IDENTITY, radius, y - 0.08, 9, Color(0.9, 0.88, 0.86))
	s.blob(Vector3(0.1, y + 0.3, 0.05), Vector3(radius * 1.7, 0.5, radius * 1.5), 1, 0.25, 1.0, Color(0.95, 0.92, 0.9), Color(0.66, 0.6, 0.6))
	return s.commit(false)


## Cut tree stump with a pale top and root flare (~0.6 m tall).
static func stump() -> ArrayMesh:
	var s := Sculpt.new(1300)
	s.lathe(Transform3D.IDENTITY, [[0.62, -0.25, BARK_DARK], [0.42, 0.05, BARK_DARK], [0.34, 0.3, BARK], [0.33, 0.55, BARK]], 9, 0.16)
	s.disc(Transform3D.IDENTITY, 0.33, 0.55, 9, Color(0.78, 0.62, 0.42), true, Color(0.62, 0.46, 0.3))
	return s.commit(true)


## Fern: a rosette of arching fronds.
static func fern() -> ArrayMesh:
	var s := Sculpt.new(1400)
	for k in 7:
		var angle := TAU * k / 7.0 + 0.2 * (k % 2)
		var dir := Vector3(cos(angle), 0, sin(angle))
		var side := dir.cross(Vector3.UP) * 0.13
		var points := [Vector3.ZERO, dir * 0.3 + Vector3(0, 0.32, 0), dir * 0.62 + Vector3(0, 0.36, 0), dir * 0.9 + Vector3(0, 0.16, 0)]
		var widths := [0.3, 1.0, 0.8, 0.05]
		var previous := []
		for p in points.size():
			var shade := lerpf(0.6, 1.0, float(p) / 3.0)
			var c := Color(shade, shade, shade)
			var row := [s.vertex(points[p] - side * widths[p], c), s.vertex(points[p] + Vector3(0, 0.03, 0), c * 0.85),
					s.vertex(points[p] + side * widths[p], c)]
			if not previous.is_empty():
				s.quad(previous[0], previous[1], row[1], row[0], Vector3.UP)
				s.quad(previous[1], previous[2], row[2], row[1], Vector3.UP)
				s.quad(previous[0], previous[1], row[1], row[0], Vector3.DOWN)
				s.quad(previous[1], previous[2], row[2], row[1], Vector3.DOWN)
			previous = row
	return s.commit(true)


## Saguaro-style cactus (~3 m), ribbed, with one or two arms.
static func cactus(variant: int) -> ArrayMesh:
	var s := Sculpt.new(1500 + variant)
	var light := Color(1, 1, 1)
	var dark := Color(0.62, 0.68, 0.6)
	var body := [[0.3, -0.2, dark, 0.12], [0.34, 0.6, light, 0.12], [0.33, 2.2, light, 0.12], [0.26, 2.75, light, 0.12], [0.05, 2.95, light]]
	s.lathe(Transform3D.IDENTITY, body, 10)
	var arms := [[1.2, 0.0], [1.7, PI]] if variant % 2 == 0 else [[1.45, 0.6]]
	for arm: Array in arms:
		var h: float = arm[0]
		var dir := Vector3(cos(arm[1]), 0, sin(arm[1]))
		s.limb(Vector3(0, h, 0), dir * 0.62 + Vector3(0, h + 0.1, 0), 0.19, 0.19, 8, dark, light, 1, Vector3.ZERO, false)
		s.limb(dir * 0.62 + Vector3(0, h, 0), dir * 0.66 + Vector3(0, h + 0.95, 0), 0.2, 0.14, 8, light, light, 2)
	return s.commit(true)


## Loose pebbles / gravel clump for road verges.
static func pebbles() -> ArrayMesh:
	var s := Sculpt.new(1600)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1601
	for k in 6:
		var at := Vector3(rng.randf_range(-0.6, 0.6), 0.03, rng.randf_range(-0.6, 0.6))
		var r := rng.randf_range(0.08, 0.2)
		s.blob(at, Vector3(r, r * 0.6, r * rng.randf_range(0.8, 1.3)), 0, 0.2, 1.0, Color(1, 1, 1), Color(0.7, 0.7, 0.72), 0.3)
	return s.commit(false)


## Toadstool cluster (forest floor accent).
static func mushrooms() -> ArrayMesh:
	var s := Sculpt.new(1700)
	for k in 3:
		var at := Vector3(0.22 * k - 0.2, 0, 0.12 * (k % 2))
		var h := 0.22 + 0.08 * k
		s.limb(at, at + Vector3(0, h, 0), 0.045, 0.035, 5, Color(0.95, 0.92, 0.85), Color(0.95, 0.92, 0.85), 1, Vector3.ZERO, false)
		s.blob(at + Vector3(0, h, 0), Vector3(0.14, 0.09, 0.14) * (1.0 + 0.25 * k), 1, 0.05, 1.0, Color(0.92, 0.25, 0.2), Color(0.95, 0.9, 0.82), 0.1)
	return s.commit(true)


## Jagged ice shard cluster (snow maps).
static func ice_shards() -> ArrayMesh:
	var s := Sculpt.new(1800)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1801
	for k in 5:
		var from := Vector3(rng.randf_range(-0.5, 0.5), -0.1, rng.randf_range(-0.5, 0.5))
		var to := from + Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(0.7, 1.7), rng.randf_range(-0.4, 0.4))
		s.limb(from, to, rng.randf_range(0.16, 0.3), 0.02, 4, Color(0.7, 0.8, 0.9), Color(1, 1, 1))
	return s.commit(false)


## Cheap pine for the far forest (one mesh, no trunk batch). `snowy` paints
## the upper faces of each tier white.
static func pine_far(snowy := false) -> ArrayMesh:
	var s := Sculpt.new(1900)
	var top := Color(1.6, 1.65, 1.75) if snowy else Color(1, 1, 1)
	for k in 3:
		var base_y := 1.2 + k * 1.5
		var radius := 2.1 - k * 0.55
		var shade := 0.6 + 0.12 * k
		s.lathe(Transform3D(Basis(Vector3.UP, k * 0.7), Vector3.ZERO), [
			[radius * 0.3, base_y + 0.3, Color(shade, shade, shade) * 0.7],
			[radius, base_y, Color(shade, shade, shade) if not snowy else Color(0.5, 0.52, 0.55), 0.18],
			[0.05, base_y + 2.4, top],
		], 7, 0.08, 0.1)
	s.limb(Vector3(0, -0.3, 0), Vector3(0, 1.6, 0), 0.26, 0.18, 5, Color(0.4, 0.3, 0.24), Color(0.4, 0.3, 0.24), 1, Vector3.ZERO, false)
	return s.commit(true)


## Distant mountain in a unit frame (base radius 1, summit height 1; the
## instance transform scales it). Ridged, off-centre summit, faceted, with
## baked rock tones and an uneven snow line. `mesa` gives a flat-topped
## terraced butte with strata bands instead (canyon).
static func mountain(variant: int, rock: Color, snow: Color, snow_line: float, mesa := false) -> ArrayMesh:
	var s := Sculpt.new(2000 + variant)
	var noise := FastNoiseLite.new()
	noise.seed = 2100 + variant
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0
	var rings := 8
	var segments := 16
	var summit := Vector2(0.12 * cos(variant * 2.1), 0.12 * sin(variant * 2.1))
	var rows: Array[PackedInt32Array] = []
	for k in rings + 1:
		var rr := float(k) / rings
		var row := PackedInt32Array()
		for a in segments:
			var angle := TAU * a / segments
			var dir := Vector2(cos(angle), sin(angle))
			var ridge := 1.0 - absf(noise.get_noise_2d(dir.x * 1.6 + variant, dir.y * 1.6))  # sharp spurs
			var reach := rr * (0.78 + 0.34 * ridge + 0.1 * noise.get_noise_2d(dir.x * 4.0, dir.y * 4.0 + 9.0))
			var h: float
			if mesa:
				# Terraces: steep faces between flat benches.
				var t := clampf(1.0 - rr, 0.0, 1.0)
				var steps := 3.0
				var stepped := (floorf(t * steps) + smoothstep(0.55, 0.95, fposmod(t * steps, 1.0))) / steps
				h = minf(stepped * 1.25, 1.0) * (0.92 + 0.08 * ridge)
			else:
				h = pow(clampf(1.0 - rr, 0.0, 1.0), 1.35) * (0.82 + 0.3 * ridge * (1.0 - rr))
				h += noise.get_noise_3d(dir.x * 3.0, rr * 4.0, dir.y * 3.0) * 0.06 * sin(rr * PI)
			var p := Vector3(dir.x * reach + summit.x * (1.0 - rr), h, dir.y * reach + summit.y * (1.0 - rr))
			var tone := rock.darkened(0.22 * (1.0 - ridge)).lerp(rock.lightened(0.12), clampf(noise.get_noise_2d(dir.x * 6.0, h * 9.0), 0.0, 1.0))
			if mesa:
				var band := posmod(floori(h * 11.0 + noise.get_noise_2d(dir.x * 2.0, dir.y * 2.0) * 1.2), 3)
				tone = [rock, rock.darkened(0.2), rock.lightened(0.16)][band]
			elif h > snow_line + noise.get_noise_2d(dir.x * 5.0, dir.y * 5.0) * 0.12:
				tone = snow.darkened(0.12 * (1.0 - ridge))
			row.append(s.vertex(p, tone))
		rows.append(row)
	for k in rings:
		for a in segments:
			var n := (a + 1) % segments
			var mid := (s.vertices[rows[k][a]] + s.vertices[rows[k + 1][n]]) * 0.5
			s.quad(rows[k][a], rows[k][n], rows[k + 1][n], rows[k + 1][a], Vector3(mid.x * 0.3, 1.0, mid.z * 0.3))
	return s.commit(false)


## Puffy cloud: overlapping soft lobes, white on top, shaded underneath.
static func cloud(variant: int) -> ArrayMesh:
	var s := Sculpt.new(2200 + variant)
	var top := Color(1, 1, 1)
	var bottom := Color(0.72, 0.78, 0.9)
	var lobes := [[Vector3(0, 0, 0), 1.0], [Vector3(0.95, -0.12, 0.2), 0.75], [Vector3(-1.0, -0.18, -0.1), 0.7],
			[Vector3(0.3, 0.42, -0.3), 0.62], [Vector3(-0.45, 0.3, 0.25), 0.55], [Vector3(1.7, -0.25, -0.1), 0.45]]
	for k in lobes.size() - (variant % 2):
		var r: float = lobes[k][1]
		s.blob(lobes[k][0], Vector3(r, r * 0.8, r), 1, 0.1, 1.2, top, bottom, 0.45)
	return s.commit(true)


## Natural rock arch (canyon landmark), about 1 unit wide and 0.8 tall.
static func rock_arch(variant: int) -> ArrayMesh:
	var s := Sculpt.new(2300 + variant)
	var light := Color(1, 1, 1)
	var dark := Color(0.68, 0.62, 0.62)
	var steps := 9
	var previous := Vector3.ZERO
	for k in steps + 1:
		var t := float(k) / steps
		var angle := PI * t
		var p := Vector3(-cos(angle) * 0.42, sin(angle) * 0.62 + 0.02, 0.03 * sin(t * 9.0 + variant))
		if k > 0:
			var thick := lerpf(0.2, 0.11, sin(angle))
			s.limb(previous, p, thick * 1.05, thick, 6, dark.lerp(light, t), dark.lerp(light, t), 1, Vector3.ZERO, false)
		previous = p
	s.blob(Vector3(-0.44, 0.05, 0), Vector3(0.26, 0.2, 0.24), 1, 0.3, 1.0, light, dark, 0.3)
	s.blob(Vector3(0.44, 0.05, 0), Vector3(0.24, 0.18, 0.22), 1, 0.3, 1.0, light, dark, 0.3)
	s.blob(Vector3(0.05, 0.66, 0), Vector3(0.2, 0.09, 0.15), 1, 0.3, 1.0, light, dark)
	return s.commit(false)


## Strata ledge: a wide, flat slab of rock that juts from a cliff face.
static func ledge(variant: int) -> ArrayMesh:
	var s := Sculpt.new(2400 + variant)
	s.blob(Vector3.ZERO, Vector3(1.0, 0.22 + 0.06 * variant, 0.55), 1, 0.35, 1.1, Color(1, 1, 1), Color(0.62, 0.58, 0.58))
	return s.commit(false)
