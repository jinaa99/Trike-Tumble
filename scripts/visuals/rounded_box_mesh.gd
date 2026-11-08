@tool
class_name RoundedBoxMesh
extends PrimitiveMesh
## Box with rounded edges and corners. Gives toy-like, soft shapes for
## seats, panels, boots and similar parts. Built as six subdivided faces
## projected onto an inner box plus `radius`, so faces meet seamlessly.

@export var size := Vector3.ONE:
	set(value):
		size = value
		request_update()
@export_range(0.0, 1.0, 0.005) var radius := 0.1:
	set(value):
		radius = value
		request_update()
@export_range(1, 8) var round_segments := 3:
	set(value):
		round_segments = value
		request_update()


func _create_mesh_array() -> Array:
	var half := size * 0.5
	var r := minf(radius, minf(half.x, minf(half.y, half.z)))
	var inner := half - Vector3.ONE * r
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	for axis in 3:
		for sign_value: float in [-1.0, 1.0]:
			var u_axis := (axis + 1) % 3
			var v_axis := (axis + 2) % 3
			var face_normal := Vector3.ZERO
			face_normal[axis] = sign_value
			var us := _axis_coords(half[u_axis], inner[u_axis], r)
			var vs := _axis_coords(half[v_axis], inner[v_axis], r)
			var base := vertices.size()
			for i in us.size():
				for j in vs.size():
					var q := Vector3.ZERO
					q[axis] = sign_value * half[axis]
					q[u_axis] = us[i]
					q[v_axis] = vs[j]
					var core := q.clamp(-inner, inner)
					var n := q - core
					n = n.normalized() if n.length_squared() > 1e-12 else face_normal
					vertices.append(core + n * r)
					normals.append(n)
					uvs.append(Vector2(float(i) / (us.size() - 1), float(j) / (vs.size() - 1)))
			for i in us.size() - 1:
				for j in vs.size() - 1:
					var a := base + i * vs.size() + j
					var b := a + vs.size()
					_add_tri(indices, vertices, face_normal, a, b, b + 1)
					_add_tri(indices, vertices, face_normal, a, b + 1, a + 1)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


## Sample positions along one face axis: dense in the rounded bands (evenly
## spaced in angle), a single flat span in the middle.
func _axis_coords(half_extent: float, inner_extent: float, r: float) -> PackedFloat32Array:
	var coords := PackedFloat32Array()
	var steps := round_segments if r > 0.0 else 0
	for k in range(steps, 0, -1):
		coords.append(-(inner_extent + r * tan(PI * 0.25 * k / steps)))
	coords.append(-inner_extent)
	if inner_extent > 1e-6:
		coords.append(inner_extent)
	for k in range(1, steps + 1):
		coords.append(inner_extent + r * tan(PI * 0.25 * k / steps))
	if coords.size() < 2:
		coords = PackedFloat32Array([-half_extent, half_extent])
	return coords


## Godot treats clockwise winding (seen from outside) as front-facing.
func _add_tri(indices: PackedInt32Array, vertices: PackedVector3Array, outward: Vector3, a: int, b: int, c: int) -> void:
	var cross := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
	if cross.dot(outward) > 0.0:
		indices.append_array([a, c, b])
	else:
		indices.append_array([a, b, c])
