class_name MeshBatch
extends RefCounted
## Collects colored triangles in packed arrays and commits them as one
## ArrayMesh surface. Much faster than SurfaceTool for the thousands of
## quads a long track needs (no per-vertex method calls into the engine).

var vertices := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()


func is_empty() -> bool:
	return vertices.is_empty()


## Quad a-b-c-d with per-corner colors. `flat` uses the face normal
## (faceted low-poly look); otherwise `facing` is the (smooth) normal.
## Godot treats clockwise winding (seen from the front) as front-facing.
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, facing: Vector3, corner_colors: Array[Color],
		flat := false) -> void:
	var normal := (c - a).cross(b - d)
	if normal.length_squared() < 1e-10:
		return
	normal = normal.normalized()
	if normal.dot(facing) < 0.0:
		normal = -normal
	if not flat:
		normal = facing.normalized()
	_triangle(a, b, c, corner_colors[0], corner_colors[1], corner_colors[2], normal)
	_triangle(a, c, d, corner_colors[0], corner_colors[2], corner_colors[3], normal)


func flat_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, facing: Vector3, color: Color) -> void:
	quad(a, b, c, d, facing, [color, color, color, color], true)


func commit() -> ArrayMesh:
	if vertices.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _triangle(p0: Vector3, p1: Vector3, p2: Vector3, c0: Color, c1: Color, c2: Color, normal: Vector3) -> void:
	var cross := (p1 - p0).cross(p2 - p0)
	if cross.length_squared() < 1e-10:
		return
	if cross.dot(normal) <= 0.0:
		vertices.append_array(PackedVector3Array([p0, p1, p2]))
		colors.append_array(PackedColorArray([c0, c1, c2]))
	else:
		vertices.append_array(PackedVector3Array([p0, p2, p1]))
		colors.append_array(PackedColorArray([c0, c2, c1]))
	normals.append_array(PackedVector3Array([normal, normal, normal]))
