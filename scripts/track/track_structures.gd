extends Node3D
## Built map features that come from the track's zones (Forest Rush):
## - bridges: timber trestle legs and cross braces down into the gorge, and
##   a mountain stream under each bridge
## - jump gaps: a creek in the ravine, "BIG AIR" arch and warning boards
## - overlooks: a wooden viewing deck beyond the barrier with a fence,
##   benches, a coin telescope and a flag
## - "rocks" zones: rock pillars right behind both barriers (narrow passage)
## - the finish area: spectator stands on both sides
## Everything sits outside the road corridor. Solid parts get box colliders.
## Build after the Backdrop node: legs and streams follow its terrain.

@export var random_seed := 77
## Trestle leg spacing along a bridge (m).
@export var trestle_spacing := 8.0
@export var stream_width := 12.0
@export var stream_length := 150.0
## Stands at the finish: distance before the finish line (m) and length.
@export var stands_offset := 40.0
@export var stands_length := 30.0
@export_flags_3d_physics var collision_layer := 1

const TIMBER := Color(0.5, 0.33, 0.2)
const TIMBER_LIGHT := Color(0.66, 0.46, 0.29)
const ROCK := Color(0.56, 0.55, 0.58)
const WATER := Color(0.24, 0.58, 0.86)
const CROWD: Array[Color] = [Color(0.95, 0.3, 0.3), Color(0.25, 0.6, 0.95), Color(1.0, 0.8, 0.2),
		Color(0.4, 0.8, 0.4), Color(0.95, 0.55, 0.85), Color(1, 1, 1)]

var _rng := RandomNumberGenerator.new()
var _body: StaticBody3D
var _material := MeshKit.vertex_color_material(0.8)
var _backdrop: Node


func build_for_track(track: Track) -> void:
	_rng.seed = random_seed
	_backdrop = track.get_node_or_null(^"Backdrop")
	_body = StaticBody3D.new()
	_body.name = "StructureCollision"
	_body.collision_layer = collision_layer
	_body.collision_mask = 0
	add_child(_body)
	for zone: Array in track.get_zones("bridge"):
		_build_bridge(track, zone)
	for zone: Array in track.get_zones("gap"):
		_build_gap(track, zone)
	for zone: Array in track.get_zones("overlook"):
		_build_overlook(track, zone)
	for zone: Array in track.get_zones("rocks"):
		_build_rock_gate(track, zone)
	if stands_length > 0.0:
		_build_stands(track)


## Ground height below a point: the backdrop terrain if there is one.
func _ground_y(position: Vector3, fallback: float) -> float:
	if _backdrop and _backdrop.has_method(&"terrain_height"):
		return _backdrop.call(&"terrain_height", position.x, position.z)
	return fallback


# --- Bridges ----------------------------------------------------------------

func _build_bridge(track: Track, zone: Array) -> void:
	var path := track.path
	var parts: Array = []
	var start: float = zone[0]
	var end: float = zone[1]
	var distance := start + trestle_spacing * 0.5
	while distance < end:
		var index := path.index_at_distance(distance)
		var frame := path.get_frame(index)
		var half := track.half_width_at(index) + track.builder.wall_thickness * 0.5
		var deck_bottom := frame.origin - Vector3.UP * 0.75
		var ground := _ground_y(frame.origin, frame.origin.y - 22.0) - 1.0
		var leg_height := deck_bottom.y - ground
		if leg_height > 1.0:
			for side: float in [-1.0, 1.0]:
				var foot := deck_bottom + frame.basis.x * side * (half - 0.3)
				var center := Vector3(foot.x, (deck_bottom.y + ground) * 0.5, foot.z)
				parts.append([MeshKit.box(Vector3(0.55, leg_height, 0.55)), Transform3D(_yaw(frame), center), TIMBER])
				_add_box(center, _yaw(frame), Vector3(0.55, leg_height, 0.55))
			# Cross braces between the two legs, every 6 m down.
			var y := deck_bottom.y - 1.0
			var span := (half - 0.3) * 2.0
			while y > ground + 1.0:
				var mid := Vector3(frame.origin.x, y, frame.origin.z)
				for tilt: float in [1.0, -1.0]:
					var brace := _yaw(frame) * Basis(Vector3(0, 0, 1), tilt * atan2(4.0, span))
					parts.append([MeshKit.box(Vector3(sqrt(span * span + 16.0), 0.22, 0.2)), Transform3D(brace, mid - Vector3.UP * 2.0), TIMBER_LIGHT])
				parts.append([MeshKit.box(Vector3(span, 0.3, 0.3)), Transform3D(_yaw(frame), mid), TIMBER_LIGHT])
				y -= 6.0
		distance += trestle_spacing
	if not parts.is_empty():
		_add_mesh("Bridge_%d" % roundi(start), parts)
	var middle := path.index_at_distance((start + end) * 0.5)
	_build_stream(track, middle)


## A strip of water across the gorge under a bridge or gap, following the
## terrain, with rocks along its banks.
func _build_stream(track: Track, index: int) -> void:
	var path := track.path
	var frame := path.get_frame(index)
	var across := frame.basis.x
	across.y = 0.0
	across = across.normalized()
	var along := Vector3.UP.cross(across).normalized()
	var batch := MeshBatch.new()
	var steps := 24
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for k in steps + 1:
		var t := lerpf(-0.5, 0.5, float(k) / steps) * stream_length
		var center := frame.origin + across * t
		var y := _ground_y(center, frame.origin.y - 22.0) + 0.25
		var l := Vector3(center.x, y, center.z) - along * stream_width * 0.5
		var r := Vector3(center.x, y, center.z) + along * stream_width * 0.5
		if k > 0:
			batch.flat_quad(prev_l, prev_r, r, l, Vector3.UP, WATER.lightened(0.08 * (k % 2)))
			if k % 3 == 0:
				for side: float in [-1.0, 1.0]:
					var spot := Vector3(center.x, y, center.z) + along * side * (stream_width * 0.5 + _rng.randf_range(0.3, 1.5))
					_rock_parts_into(batch, spot, _rng.randf_range(0.6, 1.6))
		prev_l = l
		prev_r = r
	var water := StandardMaterial3D.new()
	water.vertex_color_use_as_albedo = true
	water.vertex_color_is_srgb = true
	water.roughness = 0.1
	water.metallic_specular = 0.8
	var stream := MeshInstance3D.new()
	stream.name = "Stream_%d" % index
	stream.mesh = batch.commit()
	stream.material_override = water
	stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stream)


func _rock_parts_into(batch: MeshBatch, spot: Vector3, size: float) -> void:
	# A squashed low-poly pyramid rock (cheap, no collision: unreachable).
	var top := spot + Vector3.UP * size * 0.7
	var corners: Array[Vector3] = []
	for k in 5:
		var angle := TAU * k / 5.0 + _rng.randf() * 0.5
		corners.append(spot + Vector3(cos(angle), 0.0, sin(angle)) * size)
	for k in 5:
		var a := corners[k]
		var b := corners[(k + 1) % 5]
		var shade := ROCK.darkened(_rng.randf_range(0.0, 0.25))
		batch.quad(a, b, top, top, (a + b) * 0.5 - spot + Vector3.UP * 0.3, [shade, shade, shade, shade], true)


# --- Jump gaps --------------------------------------------------------------

func _build_gap(track: Track, zone: Array) -> void:
	var path := track.path
	var start: float = zone[0]
	var end: float = zone[1]
	_build_stream(track, path.index_at_distance((start + end) * 0.5))
	# Arch over the run-up and warning boards on both barriers.
	var gate: Node3D = Track.GATE_SCRIPT.new()
	gate.name = "BigAirGate"
	var gate_index := path.index_at_distance(start - 32.0)
	gate.span = track.half_width_at(gate_index) * 2.0 + 1.4
	gate.title = "BIG AIR!"
	gate.banner_color = Color(0.2, 0.62, 0.95)
	gate.transform = path.get_frame(gate_index)
	add_child(gate)
	var parts: Array = []
	for back: float in [70.0, 52.0]:
		var index := path.index_at_distance(start - back)
		for side: int in [-1, 1]:
			var spot := track.builder.slope_point(path, index, side, 1.0)
			var facing := _facing_riders(path, index)
			parts.append_array(_warning_board(Transform3D(facing, spot)))
			_add_box(spot + Vector3.UP * 2.2, facing, Vector3(1.8, 1.4, 0.3))
	_add_mesh("JumpBoards_%d" % roundi(start), parts)


## Yellow board with a black up-arrow ("jump ahead"), on a post.
func _warning_board(xf: Transform3D) -> Array:
	var yellow := Color(1.0, 0.82, 0.15)
	var dark := Color(0.12, 0.1, 0.12)
	return [
		[MeshKit.box(Vector3(0.14, 2.6, 0.14)), xf * MeshKit.at(Vector3(0, 1.3, -0.1)), TIMBER],
		[MeshKit.box(Vector3(1.8, 1.4, 0.08)), xf * MeshKit.at(Vector3(0, 2.2, 0)), dark],
		[MeshKit.box(Vector3(1.65, 1.25, 0.1)), xf * MeshKit.at(Vector3(0, 2.2, 0.01)), yellow],
		[MeshKit.box(Vector3(0.22, 0.7, 0.12)), xf * MeshKit.at(Vector3(0, 2.05, 0.03)), dark],
		[MeshKit.box(Vector3(0.6, 0.18, 0.12)), xf * MeshKit.at(Vector3(-0.18, 2.42, 0.03), Vector3(0, 0, -45)), dark],
		[MeshKit.box(Vector3(0.6, 0.18, 0.12)), xf * MeshKit.at(Vector3(0.18, 2.42, 0.03), Vector3(0, 0, 45)), dark],
	]


# --- Overlooks --------------------------------------------------------------

func _build_overlook(track: Track, zone: Array) -> void:
	var path := track.path
	var side := int(zone[3])
	var index := path.index_at_distance((float(zone[0]) + float(zone[1])) * 0.5)
	var frame := path.get_frame(index)
	var outward := path.rights[index] * float(side)
	var yaw := Basis.looking_at(outward, Vector3.UP)  # -Z points out over the valley
	var base := track.builder.wall_foot(path, index, side) + outward * 4.5
	base.y = frame.origin.y - 0.2
	var deck := Vector3(9.0, 0.3, 6.0)
	var parts: Array = [
		[MeshKit.box(deck), Transform3D(yaw, base), TIMBER_LIGHT],
	]
	_add_box(base, yaw, deck)
	# Legs down to the slope.
	for x: float in [-4.0, 4.0]:
		for z: float in [-2.6, 2.6]:
			var top := base + yaw * Vector3(x, 0, z)
			var ground := minf(_ground_y(top, top.y - 6.0), top.y - 1.0)
			var height := maxf(top.y - ground, 1.0) + 2.0
			parts.append([MeshKit.box(Vector3(0.3, height, 0.3)), Transform3D(yaw, top - Vector3.UP * height * 0.5), TIMBER])
	# Fence on the three open sides.
	for rail_y: float in [0.55, 1.05]:
		parts.append([MeshKit.box(Vector3(9.0, 0.12, 0.12)), Transform3D(yaw, base + yaw * Vector3(0, rail_y, -2.95)), TIMBER])
		for x: float in [-4.45, 4.45]:
			parts.append([MeshKit.box(Vector3(0.12, 0.12, 6.0)), Transform3D(yaw, base + yaw * Vector3(x, rail_y, 0)), TIMBER])
	for k in 7:
		parts.append([MeshKit.box(Vector3(0.14, 1.2, 0.14)), Transform3D(yaw, base + yaw * Vector3(-4.4 + k * 1.47, 0.6, -2.95)), TIMBER])
	_add_box(base + yaw * Vector3(0, 0.7, -2.95), yaw, Vector3(9.0, 1.2, 0.2))
	# Benches, a coin telescope and a flag.
	for x: float in [-2.2, 1.6]:
		parts.append([MeshKit.box(Vector3(1.8, 0.1, 0.5)), Transform3D(yaw, base + yaw * Vector3(x, 0.6, 0.8)), TIMBER])
		parts.append([MeshKit.box(Vector3(1.8, 0.5, 0.08)), Transform3D(yaw, base + yaw * Vector3(x, 0.9, 1.05)), TIMBER])
		for leg: float in [-0.75, 0.75]:
			parts.append([MeshKit.box(Vector3(0.1, 0.45, 0.4)), Transform3D(yaw, base + yaw * Vector3(x + leg, 0.38, 0.8)), TIMBER])
	var scope := base + yaw * Vector3(0.0, 0.15, -1.9)
	parts.append([MeshKit.cylinder(0.08, 0.1, 1.2, 8), Transform3D(yaw, scope + Vector3.UP * 0.6), Color(0.3, 0.32, 0.36)])
	parts.append([MeshKit.cylinder(0.16, 0.2, 0.7, 10), Transform3D(yaw * Basis(Vector3.RIGHT, deg_to_rad(80)), scope + Vector3.UP * 1.3), Color(0.2, 0.55, 0.85)])
	var pole := base + yaw * Vector3(3.8, 0.15, 2.4)
	parts.append([MeshKit.cylinder(0.06, 0.08, 5.0, 8), Transform3D(yaw, pole + Vector3.UP * 2.5), Color(0.95, 0.95, 0.95)])
	var flag := PrismMesh.new()
	flag.left_to_right = 0.0
	flag.size = Vector3(1.6, 0.9, 0.04)
	parts.append([flag, Transform3D(yaw * Basis(Vector3.FORWARD, deg_to_rad(-90)), pole + Vector3.UP * 4.5 + yaw * Vector3(0.8, 0, 0)), Color(0.95, 0.3, 0.25)])
	_add_mesh("Overlook_%d" % roundi(float(zone[0])), parts)


# --- Rock gates (narrow passages) -------------------------------------------

func _build_rock_gate(track: Track, zone: Array) -> void:
	var path := track.path
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var distance: float = zone[0]
	while distance <= float(zone[1]):
		var index := path.index_at_distance(distance)
		for side: int in [-1, 1]:
			var height := _rng.randf_range(5.0, 9.0)
			var width := _rng.randf_range(2.6, 4.0)
			var spot := track.builder.slope_point(path, index, side, width + 0.4)
			spot.y -= 1.0
			var xf := MeshKit.at(spot, Vector3(_rng.randf_range(-6, 6), _rng.randf() * 360.0, _rng.randf_range(-6, 6)),
					Vector3(width, height, width * _rng.randf_range(0.8, 1.2)))
			transforms.append(xf)
			colors.append(ROCK.lerp(Color(0.66, 0.6, 0.52), _rng.randf()))
			_add_box(spot + Vector3.UP * height * 0.4, xf.basis.orthonormalized(), Vector3(width * 1.4, height * 0.8, width * 1.4))
		distance += _rng.randf_range(6.0, 9.0)
	var pillar := MeshKit.combine([[MeshKit.cylinder(0.55, 0.85, 1.0, 7), MeshKit.at(Vector3(0, 0.5, 0)), Color.WHITE]])
	pillar.surface_set_material(0, MeshKit.vertex_color_material(1.0))
	add_child(MeshKit.batch("RockGate_%d" % roundi(float(zone[0])), pillar, transforms, colors))


# --- Finish stands ----------------------------------------------------------

func _build_stands(track: Track) -> void:
	var path := track.path
	var finish := track.get_finish_index() * path.spacing
	var parts: Array = []
	var bodies: Array[Transform3D] = []
	var shirts: Array[Color] = []
	var heads: Array[Transform3D] = []
	var skins: Array[Color] = []
	for side: int in [-1, 1]:
		var index := path.index_at_distance(finish - stands_offset)
		var frame := path.get_frame(index)
		var outward := path.rights[index] * float(side)
		outward.y = 0.0
		outward = outward.normalized()
		var yaw := Basis.looking_at(outward, Vector3.UP)  # +Z toward the road
		var base := track.builder.slope_point(path, index, side, 3.5)
		base.y = frame.origin.y - 0.4
		for row in 4:
			var step := base + outward * (row * 1.1) + Vector3.UP * (row * 0.7)
			# Each tier reaches down into the slope, so the stand never floats.
			var drop := 5.0 + row * 1.0
			var tier_height := 0.35 + row * 0.7 + drop
			parts.append([MeshKit.box(Vector3(stands_length, tier_height, 1.1)),
					Transform3D(yaw, Vector3(step.x, base.y + 0.35 + row * 0.7 - tier_height * 0.5, step.z)),
					TIMBER_LIGHT.darkened(0.08 * row)])
			# Spectators: colored blocks with heads.
			var count := int(stands_length / 1.3)
			for k in count:
				if _rng.randf() < 0.25:
					continue
				var x := -stands_length * 0.5 + 0.6 + k * 1.3 + _rng.randf_range(-0.2, 0.2)
				var seat := step + yaw * Vector3(x, 0.35, 0.0)
				bodies.append(Transform3D(yaw, seat + Vector3.UP * 0.35))
				shirts.append(CROWD[_rng.randi() % CROWD.size()])
				heads.append(Transform3D(yaw, seat + Vector3.UP * 0.92))
				skins.append(Color(0.98, 0.8, 0.65).darkened(_rng.randf() * 0.4))
		var depth := 4 * 1.1
		_add_box(base + outward * (depth * 0.5 - 0.55) + Vector3.UP * 1.0, yaw, Vector3(stands_length, 3.0, depth))
	_add_mesh("FinishStands", parts)
	# Spectators: one instanced body and head mesh, tinted per person.
	var body_mesh := MeshKit.combine([[MeshKit.box(Vector3(0.55, 0.7, 0.4)), Transform3D.IDENTITY, Color.WHITE]])
	var head_mesh := MeshKit.combine([[MeshKit.sphere(0.22, 8, 5), Transform3D.IDENTITY, Color.WHITE]])
	body_mesh.surface_set_material(0, _material)
	head_mesh.surface_set_material(0, _material)
	add_child(MeshKit.batch("Spectators", body_mesh, bodies, shirts))
	add_child(MeshKit.batch("SpectatorHeads", head_mesh, heads, skins))


# --- Helpers ----------------------------------------------------------------

func _yaw(frame: Transform3D) -> Basis:
	var forward := -frame.basis.z
	forward.y = 0.0
	return Basis.looking_at(forward.normalized(), Vector3.UP)


func _facing_riders(path: TrackPath, index: int) -> Basis:
	var approach := path.forwards[maxi(index - 6, 0)]
	approach.y = 0.0
	return Basis.looking_at(approach.normalized(), Vector3.UP)  # +Z faces riders


func _add_mesh(node_name: String, parts: Array) -> void:
	var mesh := MeshKit.combine(parts)
	mesh.surface_set_material(0, _material)
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	add_child(instance)


func _add_box(center: Vector3, orientation: Basis, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.transform = Transform3D(orientation.orthonormalized(), center)
	_body.add_child(collider)
