class_name RoadTree
extends StaticBody3D
## A big pine growing in the middle of the road: go left or right of it.
## The trunk is solid; the canopy starts above rider height.

@export var scale_factor := 1.6
@export var trunk_radius := 0.42
@export var trunk_height := 3.2
@export var leaf_color := Color(0.17, 0.5, 0.36)


func _ready() -> void:
	var s := scale_factor
	var mesh := MeshKit.combine([
		[MeshKit.cylinder(trunk_radius * 0.75, trunk_radius, trunk_height, 8), MeshKit.at(Vector3(0, trunk_height * 0.5, 0)), Color(0.46, 0.3, 0.19)],
		[MeshKit.cylinder(trunk_radius * 1.6, trunk_radius * 2.4, 0.3, 8), MeshKit.at(Vector3(0, 0.1, 0)), Color(0.4, 0.27, 0.17)],
		[MeshKit.cone(1.9 * s, 2.2 * s), MeshKit.at(Vector3(0, trunk_height + 0.6 * s, 0)), leaf_color],
		[MeshKit.cone(1.5 * s, 1.9 * s), MeshKit.at(Vector3(0, trunk_height + 1.8 * s, 0), Vector3(0, 25, 0)), leaf_color.lightened(0.08)],
		[MeshKit.cone(1.05 * s, 1.6 * s), MeshKit.at(Vector3(0, trunk_height + 2.9 * s, 0), Vector3(0, 50, 0)), leaf_color.lightened(0.15)],
	])
	mesh.surface_set_material(0, MeshKit.vertex_color_material(0.9))
	var visual := MeshInstance3D.new()
	visual.name = "Mesh"
	visual.mesh = mesh
	add_child(visual)
	var shape := CylinderShape3D.new()
	shape.radius = trunk_radius
	shape.height = trunk_height + 1.0
	var collider := CollisionShape3D.new()
	collider.name = "Collision"
	collider.shape = shape
	collider.position.y = (trunk_height + 1.0) * 0.5
	add_child(collider)
