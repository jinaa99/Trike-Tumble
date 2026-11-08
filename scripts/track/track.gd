class_name Track
extends Node3D
## A procedurally built downhill track.
##
## The centerline comes from `control_points`. On _ready the track builds its
## road, walls, slopes, collision, start/finish gates and finish trigger, then
## calls `build_for_track(track)` on any child that has it (props, decor).
## Race logic asks the track for spawn/respawn transforms and bounds.

signal finish_crossed(body: Node3D)

const GATE_SCRIPT := preload("res://scripts/track/track_gate.gd")

@export var control_points := PackedVector3Array()
@export var sample_spacing := 2.0
@export var road_width := 14.0
@export var wall_height := 1.1
@export var start_distance := 14.0
@export var finish_distance_from_end := 30.0
## Spacing between grid slots on the start line (for up to 5 racers).
@export var grid_slot_spacing := Vector2(2.6, 3.5)
## Falling this far below the road counts as out of bounds.
@export var out_of_bounds_depth := 12.0
## Horizontal distance from the centerline that counts as out of bounds.
@export var out_of_bounds_radius := 45.0
@export_flags_3d_physics var collision_layer := 1

var path := TrackPath.new()
var builder := TrackMeshBuilder.new()


func _ready() -> void:
	build()


func build() -> void:
	path.build(control_points, sample_spacing)
	builder.road_width = road_width
	builder.wall_height = wall_height
	builder.build(path)

	_add_mesh("Road", builder.road_mesh, TrackMaterials.road())
	_add_mesh("Walls", builder.wall_mesh, TrackMaterials.barrier())
	_add_mesh("Slopes", builder.slope_mesh, TrackMaterials.grass())

	var body := StaticBody3D.new()
	body.name = "TrackBody"
	body.collision_layer = collision_layer
	body.collision_mask = 0
	add_child(body)
	for faces in [builder.road_faces, builder.wall_faces, builder.slope_faces]:
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)

	_add_end_blocker(body, 0, 1.0)
	_add_end_blocker(body, path.size() - 1, -1.0)
	_add_gate("StartGate", path.index_at_distance(start_distance - 4.0), false, "TRIKE TUMBLE")
	var finish_index := path.index_at_distance(path.length - finish_distance_from_end)
	_add_gate("FinishGate", finish_index, true, "FINISH")
	_add_finish_trigger(finish_index)

	for child in get_children():
		if child.has_method("build_for_track"):
			child.build_for_track(self)


# --- Queries ----------------------------------------------------------------

func get_start_index() -> int:
	return path.index_at_distance(start_distance)


## Grid slot 0 is the pole (center), then alternating left/right rows.
func get_start_transform(slot: int) -> Transform3D:
	@warning_ignore("integer_division")
	var row := (slot + 1) / 2
	var side := 0.0 if slot == 0 else (-1.0 if slot % 2 == 1 else 1.0)
	var index := path.index_at_distance(start_distance - row * grid_slot_spacing.y)
	var frame := path.get_frame(index)
	frame.origin += frame.basis.x * side * grid_slot_spacing.x * (1.0 + row * 0.3) + frame.basis.y * 0.8
	return frame


func get_respawn_transform(index: int, lateral := 0.0) -> Transform3D:
	var frame := path.get_frame(index)
	frame.origin += frame.basis.x * lateral + frame.basis.y * 1.0
	return frame


func is_on_road(position: Vector3, index: int) -> bool:
	var offset := position - path.points[index]
	return absf(offset.dot(path.rights[index])) < road_width * 0.5 + 0.5 \
			and absf(offset.dot(path.ups[index])) < 3.0


func is_out_of_bounds(position: Vector3, index: int) -> bool:
	var center := path.points[index]
	var flat := Vector2(position.x - center.x, position.z - center.z)
	return position.y < center.y - out_of_bounds_depth or flat.length() > out_of_bounds_radius


func get_finish_index() -> int:
	return path.index_at_distance(path.length - finish_distance_from_end)


# --- Construction helpers ---------------------------------------------------

func _add_mesh(node_name: String, mesh: ArrayMesh, material: Material) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	add_child(instance)


## Invisible-ish wall closing the road at the start and end.
func _add_end_blocker(body: StaticBody3D, index: int, push_dir: float) -> void:
	var frame := path.get_frame(index)
	var shape := BoxShape3D.new()
	shape.size = Vector3(road_width + 4.0, 4.0, 1.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.transform = frame
	collider.position += frame.basis.y * 1.5 + frame.basis.z * push_dir * 0.5
	body.add_child(collider)

	var mesh := BoxMesh.new()
	mesh.size = shape.size
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.62, 0.42, 0.26)
	material.albedo_texture = TrackMaterials.detail_texture(0.8, 0.2)
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	visual.material_override = material
	visual.transform = collider.transform
	add_child(visual)


func _add_gate(node_name: String, index: int, checkered: bool, title: String) -> void:
	var gate: Node3D = GATE_SCRIPT.new()
	gate.name = node_name
	gate.span = road_width + 1.4
	gate.checkered = checkered
	gate.title = title
	gate.transform = path.get_frame(index)
	add_child(gate)


func _add_finish_trigger(index: int) -> void:
	var area := Area3D.new()
	area.name = "FinishTrigger"
	area.collision_layer = 0
	area.collision_mask = 2  # vehicles
	area.monitorable = false
	var shape := BoxShape3D.new()
	shape.size = Vector3(road_width + 2.0, 6.0, 2.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 2.5
	area.add_child(collider)
	area.transform = path.get_frame(index)
	area.body_entered.connect(func(body: Node3D) -> void: finish_crossed.emit(body))
	add_child(area)
