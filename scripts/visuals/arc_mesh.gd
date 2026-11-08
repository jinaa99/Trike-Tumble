@tool
class_name ArcMesh
extends PrimitiveMesh
## Curved strip with a rectangular cross-section, bent around the X axis.
## Used for wheel fenders, and (rotated) for small curves like a smile.
## Angle 0 points up (+Y); positive angles sweep toward the front (-Z).

@export var inner_radius := 0.4:
	set(value):
		inner_radius = value
		request_update()
@export var thickness := 0.03:
	set(value):
		thickness = value
		request_update()
@export var width := 0.15:
	set(value):
		width = value
		request_update()
@export_range(-360.0, 360.0) var start_angle_deg := -60.0:
	set(value):
		start_angle_deg = value
		request_update()
@export_range(-360.0, 360.0) var end_angle_deg := 60.0:
	set(value):
		end_angle_deg = value
		request_update()
@export_range(2, 64) var segments := 14:
	set(value):
		segments = value
		request_update()


func _create_mesh_array() -> Array:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var r0 := inner_radius
	var r1 := inner_radius + thickness
	var hx := width * 0.5

	# Four long faces: outer, inner, left side, right side.
	for face in 4:
		var base := vertices.size()
		for s in segments + 1:
			var theta := deg_to_rad(lerpf(start_angle_deg, end_angle_deg, float(s) / segments))
			var radial := Vector3(0.0, cos(theta), -sin(theta))
			var pair: Array[Vector3] = []
			var n := Vector3.ZERO
			match face:
				0:
					pair = [Vector3(-hx, 0, 0) + radial * r1, Vector3(hx, 0, 0) + radial * r1]
					n = radial
				1:
					pair = [Vector3(-hx, 0, 0) + radial * r0, Vector3(hx, 0, 0) + radial * r0]
					n = -radial
				2:
					pair = [Vector3(-hx, 0, 0) + radial * r0, Vector3(-hx, 0, 0) + radial * r1]
					n = Vector3.LEFT
				_:
					pair = [Vector3(hx, 0, 0) + radial * r0, Vector3(hx, 0, 0) + radial * r1]
					n = Vector3.RIGHT
			for p in pair:
				vertices.append(p)
				normals.append(n)
		for s in segments:
			var a := base + s * 2
			_add_quad(indices, vertices, normals, a, a + 1, a + 3, a + 2)

	# End caps.
	for theta_deg: float in [start_angle_deg, end_angle_deg]:
		var theta := deg_to_rad(theta_deg)
		var radial := Vector3(0.0, cos(theta), -sin(theta))
		var tangent := Vector3(0.0, -sin(theta), -cos(theta))
		var n := -tangent if theta_deg == start_angle_deg else tangent
		var base := vertices.size()
		for p: Vector3 in [Vector3(-hx, 0, 0) + radial * r0, Vector3(hx, 0, 0) + radial * r0,
				Vector3(hx, 0, 0) + radial * r1, Vector3(-hx, 0, 0) + radial * r1]:
			vertices.append(p)
			normals.append(n)
		_add_quad(indices, vertices, normals, base, base + 1, base + 2, base + 3)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


func _add_quad(indices: PackedInt32Array, vertices: PackedVector3Array, normals: PackedVector3Array,
		a: int, b: int, c: int, d: int) -> void:
	for tri: PackedInt32Array in [PackedInt32Array([a, b, c]), PackedInt32Array([a, c, d])]:
		var cross := (vertices[tri[1]] - vertices[tri[0]]).cross(vertices[tri[2]] - vertices[tri[0]])
		if cross.dot(normals[tri[0]]) > 0.0:
			indices.append_array([tri[0], tri[2], tri[1]])
		else:
			indices.append_array(tri)
