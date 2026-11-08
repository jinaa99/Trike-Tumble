extends Node3D
## Built (wooden) set dressing that also helps readability:
## - chevron signs on the outside of sharp turns, facing oncoming riders
## - hay bale stacks at the start, finish and big corners
## - a small cabin and log piles near the start
## - festival bunting over the barriers at start and finish
## Everything sits outside the barriers. Solid objects get box collision
## that matches what you see.

@export var random_seed := 99
## A corner gets a sign when the road turns this much over 2 x sign_turn_span samples.
@export_range(10.0, 90.0) var sign_turn_threshold_deg := 25.0
@export var sign_turn_span := 12
@export var sign_min_spacing_samples := 35
@export var bunting_length_samples := 30
@export_flags_3d_physics var collision_layer := 1

const WOOD := Color(0.62, 0.42, 0.26)
const WOOD_DARK := Color(0.45, 0.3, 0.19)
const STRAW := Color(0.96, 0.8, 0.4)
const SIGN_RED := Color(0.92, 0.22, 0.2)
## Board height above the slope foot: clears the 1.1 m barrier as seen from the road.
const SIGN_BOARD_Y := 2.5
const BUNTING: Array[Color] = [Color(0.95, 0.25, 0.3), Color(1.0, 0.8, 0.2), Color(0.2, 0.7, 0.9), Color(0.35, 0.8, 0.4), Color(0.95, 0.5, 0.85)]

var _rng := RandomNumberGenerator.new()
var _body: StaticBody3D
var _material := MeshKit.vertex_color_material(0.75)


func build_for_track(track: Track) -> void:
	_rng.seed = random_seed
	_body = StaticBody3D.new()
	_body.name = "LandmarkCollision"
	_body.collision_layer = collision_layer
	_body.collision_mask = 0
	add_child(_body)
	_place_turn_signs(track)
	_place_hay_bales(track)
	_place_cabin(track)
	_place_bunting(track)


# --- Turn signs -------------------------------------------------------------

func _place_turn_signs(track: Track) -> void:
	var path := track.path
	var threshold := deg_to_rad(sign_turn_threshold_deg)
	var last := -1000
	var transforms: Array[Transform3D] = []
	var mirrored: Array[Transform3D] = []
	var sign_mesh := _sign_mesh()
	for i in range(12, path.size() - 12):
		var turn := path.turn_angle(i, sign_turn_span)
		if absf(turn) < threshold or i - last < sign_min_spacing_samples:
			continue
		# Wait for the sharpest point of this corner.
		if absf(path.turn_angle(i + 1, sign_turn_span)) > absf(turn):
			continue
		last = i
		var outside := 1 if turn > 0.0 else -1  # left turn (+) -> sign on the right
		var spot := track.builder.slope_point(path, i, outside, 1.2)
		# Face riders approaching from before the corner.
		var approach := path.forwards[maxi(i - 8, 0)]
		approach.y = 0.0
		var facing := Basis.looking_at(approach.normalized(), Vector3.UP)  # +Z faces riders
		var xf := Transform3D(facing, spot)
		# Chevrons point toward the turn direction: left turn -> "<".
		if turn > 0.0:
			mirrored.append(xf)
		else:
			transforms.append(xf)
		_add_box_collider(xf * Vector3(0, SIGN_BOARD_Y, 0), facing, Vector3(2.7, 1.05, 0.25))
		for x: float in [-1.0, 1.0]:
			_add_box_collider(xf * Vector3(x, SIGN_BOARD_Y * 0.5, -0.05), facing, Vector3(0.16, SIGN_BOARD_Y, 0.16))
	add_child(MeshKit.batch("TurnSignsRight", sign_mesh, transforms))
	add_child(MeshKit.batch("TurnSignsLeft", _sign_mesh(true), mirrored))


## Board with chevrons pointing right ("> > >") or left, on two posts.
## Built in sign space: +Z faces the rider.
func _sign_mesh(point_left := false) -> ArrayMesh:
	var parts := [
		[MeshKit.box(Vector3(0.14, SIGN_BOARD_Y + 0.5, 0.14)), MeshKit.at(Vector3(-1.0, (SIGN_BOARD_Y + 0.5) * 0.5, -0.05)), WOOD],
		[MeshKit.box(Vector3(0.14, SIGN_BOARD_Y + 0.5, 0.14)), MeshKit.at(Vector3(1.0, (SIGN_BOARD_Y + 0.5) * 0.5, -0.05)), WOOD],
		[MeshKit.box(Vector3(2.6, 0.95, 0.1)), MeshKit.at(Vector3(0, SIGN_BOARD_Y, 0.03)), Color(0.98, 0.96, 0.9)],
		[MeshKit.box(Vector3(2.7, 1.05, 0.06)), MeshKit.at(Vector3(0, SIGN_BOARD_Y, -0.02)), SIGN_RED],
	]
	var direction := -1.0 if point_left else 1.0
	for k in 3:
		var x := (float(k) - 1.0) * 0.75
		for half: float in [1.0, -1.0]:
			parts.append([MeshKit.box(Vector3(0.14, 0.48, 0.04)),
					MeshKit.at(Vector3(x + direction * 0.06, SIGN_BOARD_Y + half * 0.17, 0.1), Vector3(0, 0, half * direction * 40.0)),
					SIGN_RED])
	var mesh := MeshKit.combine(parts)
	mesh.surface_set_material(0, _material)
	return mesh


# --- Hay bales --------------------------------------------------------------

func _place_hay_bales(track: Track) -> void:
	var path := track.path
	var bale := MeshKit.combine([
		[RoundedBoxMesh.new(), MeshKit.at(Vector3(0, 0.36, 0), Vector3.ZERO, Vector3(1.3, 0.72, 0.8)), STRAW],
		[MeshKit.box(Vector3(0.08, 0.76, 0.84)), MeshKit.at(Vector3(-0.35, 0.36, 0)), Color(0.75, 0.55, 0.25)],
		[MeshKit.box(Vector3(0.08, 0.76, 0.84)), MeshKit.at(Vector3(0.35, 0.36, 0)), Color(0.75, 0.55, 0.25)],
	])
	bale.surface_set_material(0, _material)
	var transforms: Array[Transform3D] = []
	var spots: Array[int] = []
	for i in range(2, 22, 5):
		spots.append(i)
	var finish := track.get_finish_index()
	for i in range(finish - 12, mini(finish + 12, path.size() - 2), 6):
		spots.append(i)
	for index in spots:
		for side: int in [-1, 1]:
			_stack_bales(track, index, side, transforms)
	add_child(MeshKit.batch("HayBales", bale, transforms))


func _stack_bales(track: Track, index: int, side: int, out: Array[Transform3D]) -> void:
	var base := track.builder.slope_point(track.path, index, side, 1.0)
	var forward := track.path.forwards[index]
	forward.y = 0.0
	var facing := Basis.looking_at(forward.normalized(), Vector3.UP)
	var layout: Array[Vector3] = [Vector3(-0.68, 0, 0), Vector3(0.68, 0, 0), Vector3(0, 0.72, 0)]
	for offset in layout:
		var xf := Transform3D(facing.rotated(Vector3.UP, _rng.randf_range(-0.08, 0.08)), base + facing * offset)
		out.append(xf)
		_add_box_collider(xf * Vector3(0, 0.36, 0), xf.basis, Vector3(1.3, 0.72, 0.8))


# --- Cabin and logs ---------------------------------------------------------

func _place_cabin(track: Track) -> void:
	var index := track.path.index_at_distance(26.0)
	var side := -1
	var spot := track.builder.slope_point(track.path, index, side, 7.5)
	var toward_road := -track.path.rights[index] * float(side)
	toward_road.y = 0.0
	var facing := Basis.looking_at(toward_road.normalized(), Vector3.UP)
	var xf := Transform3D(facing, spot)
	var roof_red := Color(0.85, 0.28, 0.25)
	var mesh := MeshKit.combine([
		[MeshKit.box(Vector3(4.2, 2.0, 3.4)), MeshKit.at(Vector3(0, -0.9, 0)), Color(0.55, 0.55, 0.58)],  # stone footing
		[MeshKit.box(Vector3(3.8, 2.4, 3.0)), MeshKit.at(Vector3(0, 1.2, 0)), WOOD],
		[MeshKit.box(Vector3(3.9, 0.12, 3.1)), MeshKit.at(Vector3(0, 0.8, 0)), WOOD_DARK],
		[MeshKit.box(Vector3(3.9, 0.12, 3.1)), MeshKit.at(Vector3(0, 1.6, 0)), WOOD_DARK],
		[MeshKit.box(Vector3(2.8, 0.25, 3.8)), MeshKit.at(Vector3(-1.0, 3.05, 0), Vector3(0, 0, 38)), roof_red],
		[MeshKit.box(Vector3(2.8, 0.25, 3.8)), MeshKit.at(Vector3(1.0, 3.05, 0), Vector3(0, 0, -38)), roof_red],
		[PrismMesh.new(), MeshKit.at(Vector3(0, 3.0, 0), Vector3.ZERO, Vector3(3.8, 1.3, 2.98)), WOOD],
		[MeshKit.box(Vector3(0.9, 1.6, 0.1)), MeshKit.at(Vector3(-0.8, 0.8, -1.5)), WOOD_DARK],  # door
		[MeshKit.box(Vector3(0.8, 0.7, 0.1)), MeshKit.at(Vector3(0.9, 1.4, -1.5)), Color(0.55, 0.85, 1.0)],  # window
		[MeshKit.box(Vector3(1.0, 0.12, 0.14)), MeshKit.at(Vector3(0.9, 1.0, -1.55)), Color(0.98, 0.96, 0.9)],
		[MeshKit.box(Vector3(0.5, 1.2, 0.5)), MeshKit.at(Vector3(1.2, 3.6, 0.6)), Color(0.6, 0.58, 0.6)],  # chimney
	])
	mesh.surface_set_material(0, _material)
	var cabin := MeshInstance3D.new()
	cabin.name = "Cabin"
	cabin.mesh = mesh
	cabin.transform = xf
	add_child(cabin)
	_add_box_collider(xf * Vector3(0, 1.4, 0), facing, Vector3(4.2, 4.6, 3.4))
	# Log pile next to the cabin.
	var log_mesh := MeshKit.cylinder(0.22, 0.22, 2.0, 8)
	var logs: Array = []
	var log_layout: Array[Vector3] = [Vector3(-0.45, 0.22, 0), Vector3(0, 0.22, 0), Vector3(0.45, 0.22, 0),
			Vector3(-0.22, 0.6, 0), Vector3(0.22, 0.6, 0), Vector3(0, 0.98, 0)]
	for p in log_layout:
		logs.append([log_mesh, MeshKit.at(p, Vector3(90, 0, 0)), WOOD.lightened(_rng.randf_range(0.0, 0.15))])
	var pile_mesh := MeshKit.combine(logs)
	pile_mesh.surface_set_material(0, _material)
	var pile := MeshInstance3D.new()
	pile.name = "LogPile"
	pile.mesh = pile_mesh
	pile.transform = Transform3D(facing, xf * Vector3(3.3, 0, -0.5))
	add_child(pile)
	_add_box_collider(pile.transform * Vector3(0, 0.6, 0), facing, Vector3(1.4, 1.2, 2.0))


# --- Bunting ----------------------------------------------------------------

func _place_bunting(track: Track) -> void:
	var path := track.path
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var poles: Array[Transform3D] = []
	var finish := track.get_finish_index()
	var ranges: Array[Vector2i] = [Vector2i(0, bunting_length_samples), Vector2i(finish - 15, mini(finish + 12, path.size() - 1))]
	for span in ranges:
		for side: int in [-1, 1]:
			var previous := Vector3.ZERO
			for i in range(span.x, span.y + 1, 4):
				var top := _wall_top(track, i, side) + Vector3.UP * 1.5
				poles.append(MeshKit.at(_wall_top(track, i, side) + Vector3.UP * 0.75, Vector3.ZERO, Vector3(1, 1.5, 1)))
				if i > span.x:
					_flags_between(previous, top, transforms, colors)
				previous = top
	var flag := PrismMesh.new()
	flag.size = Vector3(0.32, 0.4, 0.02)
	var flag_mesh := MeshKit.combine([[flag, MeshKit.at(Vector3(0, -0.2, 0), Vector3(0, 0, 180)), Color.WHITE]])
	flag_mesh.surface_set_material(0, _material)
	add_child(MeshKit.batch("Bunting", flag_mesh, transforms, colors, false))
	var pole_mesh := MeshKit.combine([[MeshKit.cylinder(0.04, 0.05, 1.0, 6), Transform3D.IDENTITY, Color(0.98, 0.97, 0.94)]])
	pole_mesh.surface_set_material(0, _material)
	add_child(MeshKit.batch("BuntingPoles", pole_mesh, poles, [], false))


func _flags_between(a: Vector3, b: Vector3, out: Array[Transform3D], colors: Array[Color]) -> void:
	var count := maxi(int(a.distance_to(b) / 0.55), 2)
	var along := (b - a)
	along.y = 0.0
	var facing := Basis.looking_at(along.normalized().cross(Vector3.UP), Vector3.UP)
	for k in count:
		var t := (k + 0.5) / count
		var sag := sin(t * PI) * 0.35
		out.append(Transform3D(facing, a.lerp(b, t) - Vector3.UP * sag))
		colors.append(BUNTING[(out.size()) % BUNTING.size()])


func _wall_top(track: Track, index: int, side: int) -> Vector3:
	var path := track.path
	var outward := path.rights[index] * float(side)
	return path.points[index] + outward * (track.road_width * 0.5 + track.builder.wall_thickness * 0.5) \
			+ path.ups[index] * track.wall_height


func _add_box_collider(center: Vector3, orientation: Basis, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.transform = Transform3D(orientation.orthonormalized(), center)
	_body.add_child(collider)
