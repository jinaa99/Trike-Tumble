class_name MeshKit
extends RefCounted
## Helpers for procedural low-poly scenery: merge primitives into one
## flat-shaded, vertex-colored mesh, and batch instances with MultiMesh so a
## whole forest costs only a few draw calls.


## parts: Array of [Mesh, Transform3D, Color]. Returns one flat-shaded surface.
static func combine(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part: Array in parts:
		var mesh: Mesh = part[0]
		var xf: Transform3D = part[1]
		var color: Color = part[2]
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			indices = PackedInt32Array(range(vertices.size()))
		for t in range(0, indices.size(), 3):
			var a := xf * vertices[indices[t]]
			var b := xf * vertices[indices[t + 1]]
			var c := xf * vertices[indices[t + 2]]
			var cross := (b - a).cross(c - a)
			if cross.length_squared() < 1e-12:
				continue
			# Clockwise front faces: the outward normal opposes the winding cross product.
			var normal := -cross.normalized()
			for v in [a, b, c]:
				st.set_color(color)
				st.set_normal(normal)
				st.add_vertex(v)
	return st.commit()


static func vertex_color_material(roughness := 0.85, toon := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = roughness
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON if toon else BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	return material


## One MultiMeshInstance3D. `colors` (optional) tints each instance.
static func batch(node_name: String, mesh: Mesh, transforms: Array[Transform3D], colors: Array[Color] = [],
		cast_shadows := true) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = not colors.is_empty()
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
		if multimesh.use_colors:
			multimesh.set_instance_color(i, colors[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	if not cast_shadows:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


static func cone(radius: float, height: float, segments := 7) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	return mesh


static func cylinder(top: float, bottom: float, height: float, segments := 7) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	return mesh


static func sphere(radius: float, segments := 8, rings := 5) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = rings
	return mesh


static func box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


static func at(position: Vector3, rotation_deg := Vector3.ZERO, scale := Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(rotation_deg * (PI / 180.0)) * Basis.from_scale(scale), position)
