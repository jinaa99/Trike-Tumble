@tool
class_name Ramp
extends StaticBody3D
## Wedge-shaped jump ramp rising toward -Z (the direction of travel).
## Mesh and collision are built from the same points, so they always match.

@export var width := 4.0:
	set(value):
		width = value
		_rebuild()
@export var length := 6.0:
	set(value):
		length = value
		_rebuild()
@export var height := 1.2:
	set(value):
		height = value
		_rebuild()
@export var color := Color(1.0, 0.62, 0.2):
	set(value):
		color = value
		_rebuild()


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	var w := width * 0.5
	var l := length * 0.5
	# Back edge on the ground, front edge raised.
	var bl := Vector3(-w, 0.0, l)
	var br := Vector3(w, 0.0, l)
	var fl := Vector3(-w, 0.0, -l)
	var fr := Vector3(w, 0.0, -l)
	var tl := Vector3(-w, height, -l)
	var tr := Vector3(w, height, -l)

	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([bl, br, fl, fr, tl, tr])
	($Collision as CollisionShape3D).shape = shape

	# Visual: wooden planks across the slope (alternating tones), a red/white
	# lip stripe at the take-off edge, darker side boards. Same wedge as the
	# collision shape.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var planks := 8
	for k in planks:
		var t0 := float(k) / planks
		var t1 := float(k + 1) / planks
		var tint := color if k % 2 == 0 else color.lerp(Color(0.98, 0.93, 0.8), 0.55)
		if k == planks - 1:
			tint = Color(0.95, 0.25, 0.22)
		var a := bl.lerp(tl, t0)
		var b := br.lerp(tr, t0)
		var c := br.lerp(tr, t1)
		var d := bl.lerp(tl, t1)
		_quad(st, a, b, c, d, Vector3(0, length, height).normalized(), tint)
	var side := color.lerp(Color(0.45, 0.3, 0.2), 0.6)
	_quad(st, fl, fr, tr, tl, Vector3.FORWARD, side.darkened(0.15))
	_tri(st, PackedVector3Array([bl, fl, tl]), Vector3.LEFT, side)
	_tri(st, PackedVector3Array([br, fr, tr]), Vector3.RIGHT, side)
	var mesh := st.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.75
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	material.albedo_texture = TrackMaterials.detail_texture(0.82, 0.2)
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	mesh.surface_set_material(0, material)
	($Mesh as MeshInstance3D).mesh = mesh


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, facing: Vector3, tint: Color) -> void:
	_tri(st, PackedVector3Array([a, b, c]), facing, tint)
	_tri(st, PackedVector3Array([a, c, d]), facing, tint)


## Flat-shaded triangle facing `facing` (Godot front faces wind clockwise).
func _tri(st: SurfaceTool, vertices: PackedVector3Array, facing: Vector3, tint: Color) -> void:
	var cross := (vertices[1] - vertices[0]).cross(vertices[2] - vertices[0])
	var normal := -cross.normalized()
	if normal.dot(facing) < 0.0:
		vertices = PackedVector3Array([vertices[0], vertices[2], vertices[1]])
		normal = -normal
	for v in vertices:
		st.set_color(tint)
		st.set_normal(normal)
		st.add_vertex(v)
