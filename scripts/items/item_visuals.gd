class_name ItemVisuals
extends RefCounted
## Procedural meshes and one-shot effects for items (all original, built in
## code). Purely cosmetic: nothing here has collision or drives gameplay.


static func flat_material(color: Color, emission := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.6
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	return material


## Brown ball with a lighter splotch band (the thrown mud bomb).
static func mud_bomb_mesh() -> Mesh:
	var mesh := MeshKit.combine([
		[MeshKit.sphere(0.32, 9, 6), Transform3D.IDENTITY, Color(0.42, 0.27, 0.15)],
		[MeshKit.sphere(0.16, 6, 4), MeshKit.at(Vector3(0.18, 0.18, 0.1)), Color(0.55, 0.36, 0.2)],
		[MeshKit.sphere(0.13, 6, 4), MeshKit.at(Vector3(-0.2, 0.05, -0.15)), Color(0.33, 0.21, 0.11)],
	])
	mesh.surface_set_material(0, MeshKit.vertex_color_material(0.9))
	return mesh


## Flat lumpy puddle of radius 1 (scaled by the patch radius): a wet brown
## base with darker blobs around the rim and a few lighter splats on top.
static func mud_patch_mesh() -> Mesh:
	var parts := [[MeshKit.cylinder(0.92, 0.92, 0.04, 16), Transform3D.IDENTITY, Color(0.3, 0.17, 0.07)]]
	for i in 9:
		var angle := i * TAU / 9.0 + 0.4
		var r := 0.72 + 0.16 * sin(i * 2.3)
		var size := 0.26 + 0.08 * cos(i * 1.7)
		parts.append([MeshKit.cylinder(size, size, 0.045, 9), MeshKit.at(Vector3(cos(angle) * r, 0.003, sin(angle) * r)),
				Color(0.24, 0.13, 0.05)])
	for spot: Vector3 in [Vector3(0.3, 0.02, -0.2), Vector3(-0.35, 0.02, 0.25), Vector3(0.05, 0.02, 0.4)]:
		parts.append([MeshKit.sphere(0.14, 7, 4), MeshKit.at(spot, Vector3.ZERO, Vector3(1, 0.35, 1)), Color(0.5, 0.33, 0.16)])
	var mesh := MeshKit.combine(parts)
	mesh.surface_set_material(0, MeshKit.vertex_color_material(0.5))
	return mesh


## A cartoon banana peel: a yellow core with three floppy flaps.
static func banana_mesh() -> Mesh:
	var yellow := Color(1.0, 0.85, 0.2)
	var parts := [[MeshKit.sphere(0.16, 7, 5), MeshKit.at(Vector3(0, 0.1, 0), Vector3.ZERO, Vector3(1, 1.3, 1)), yellow]]
	for i in 3:
		var angle := i * TAU / 3.0
		var dir := Vector3(cos(angle), 0, sin(angle))
		parts.append([MeshKit.box(Vector3(0.18, 0.05, 0.5)),
				Transform3D(Basis(Vector3.UP, -angle + PI * 0.5) * Basis(Vector3.RIGHT, 0.25), dir * 0.28 + Vector3.UP * 0.04),
				yellow.darkened(0.08 * i)])
		parts.append([MeshKit.box(Vector3(0.12, 0.06, 0.1)),
				Transform3D(Basis(Vector3.UP, -angle + PI * 0.5), dir * 0.52 + Vector3.UP * 0.03), Color(0.45, 0.32, 0.12)])
	parts.append([MeshKit.cylinder(0.04, 0.05, 0.14, 5), MeshKit.at(Vector3(0, 0.3, 0)), Color(0.4, 0.3, 0.12)])
	var mesh := MeshKit.combine(parts)
	mesh.surface_set_material(0, MeshKit.vertex_color_material(0.5))
	return mesh


static func instance(mesh: Mesh, node_name: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	return node


## Expanding, fading puff of small spheres (pickup pop, splats, turbo).
static func burst(parent: Node, position: Vector3, color: Color, count := 10, radius := 1.6, duration := 0.45) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var root := Node3D.new()
	root.name = "ItemBurst"
	parent.add_child(root)
	root.global_position = position
	var material := flat_material(color, 0.8)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var tween := root.create_tween().set_parallel(true)
	for i in count:
		var piece := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.16
		sphere.height = 0.32
		sphere.radial_segments = 6
		sphere.rings = 3
		sphere.material = material
		piece.mesh = sphere
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(piece)
		var angle := i * TAU / count
		var dir := Vector3(cos(angle), 0.6 + 0.4 * sin(i * 1.7), sin(angle)).normalized()
		tween.tween_property(piece, "position", dir * radius, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(piece, "scale", Vector3.ONE * 0.2, duration)
	tween.tween_property(material, "albedo_color:a", 0.0, duration)
	tween.chain().tween_callback(root.queue_free)


## Spring punch: a boxing glove on a zig-zag spring shooting out from `from`
## toward `to` and snapping back.
static func punch(parent: Node, from: Vector3, to: Vector3, hit: bool) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var root := Node3D.new()
	root.name = "SpringPunch"
	parent.add_child(root)
	root.global_position = from
	var reach := from.distance_to(to)
	if reach > 0.01:
		var up := Vector3.UP if absf((to - from).normalized().y) < 0.95 else Vector3.RIGHT
		root.look_at(to, up)
	var glove := MeshInstance3D.new()
	var glove_mesh := SphereMesh.new()
	glove_mesh.radius = 0.45
	glove_mesh.height = 0.8
	glove_mesh.material = flat_material(ItemKind.color_of(ItemKind.Kind.SPRING_PUNCH), 0.3)
	glove.mesh = glove_mesh
	root.add_child(glove)
	var spring := MeshInstance3D.new()
	var spring_mesh := CylinderMesh.new()
	spring_mesh.top_radius = 0.09
	spring_mesh.bottom_radius = 0.09
	spring_mesh.height = 1.0
	spring_mesh.material = flat_material(Color(0.85, 0.85, 0.9), 0.1)
	spring.mesh = spring_mesh
	spring.rotation.x = PI * 0.5
	root.add_child(spring)
	var tween := root.create_tween()
	tween.tween_method(func(t: float) -> void:
		glove.position = Vector3(0, 0, -reach * t)
		spring.position = Vector3(0, 0, -reach * t * 0.5)
		spring.scale = Vector3(1, maxf(reach * t, 0.05), 1), 0.0, 1.0, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.12 if hit else 0.05)
	tween.tween_method(func(t: float) -> void:
		glove.position = Vector3(0, 0, -reach * t)
		spring.position = Vector3(0, 0, -reach * t * 0.5)
		spring.scale = Vector3(1, maxf(reach * t, 0.05), 1), 1.0, 0.0, 0.2)
	tween.tween_callback(root.queue_free)
