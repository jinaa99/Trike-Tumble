class_name SkillVisuals
extends RefCounted
## Procedural meshes and one-shot effects for the signature skills (all
## original, built in code). Cosmetic only: nothing here collides.

const CONFETTI: Array[Color] = [Color(1.0, 0.35, 0.4), Color(1.0, 0.85, 0.2), Color(0.35, 0.8, 1.0), Color(0.5, 0.9, 0.4)]


## Bramble's snare: a ring of gnarled roots with leaves and a glowing warning
## disc under it (≈ 2.4 m across).
static func snare() -> Node3D:
	var root := Node3D.new()
	root.name = "Snare"
	var parts := []
	for i in 7:
		var angle := i * TAU / 7.0
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		parts.append([MeshKit.cylinder(0.07, 0.13, 1.25, 6),
				Transform3D(Basis(Vector3.UP, -angle) * Basis(Vector3.FORWARD, 1.15), dir * 0.55 + Vector3.UP * 0.22),
				Color(0.42, 0.27, 0.14).darkened(0.08 * (i % 3))])
		parts.append([MeshKit.sphere(0.16, 6, 4), MeshKit.at(dir * 1.08 + Vector3.UP * 0.42, Vector3.ZERO, Vector3(1.3, 0.5, 0.8)),
				Color(0.36, 0.72, 0.28)])
	parts.append([MeshKit.sphere(0.3, 7, 5), MeshKit.at(Vector3(0, 0.2, 0), Vector3.ZERO, Vector3(1, 0.7, 1)), Color(0.36, 0.23, 0.12)])
	var mesh := MeshKit.combine(parts)
	mesh.surface_set_material(0, MeshKit.vertex_color_material(0.85))
	root.add_child(ItemVisuals.instance(mesh, "Roots"))
	var disc := MeshInstance3D.new()
	disc.name = "Warning"
	var plate := CylinderMesh.new()
	plate.top_radius = 1.25
	plate.bottom_radius = 1.25
	plate.height = 0.03
	plate.radial_segments = 20
	var glow := ItemVisuals.flat_material(Color(0.55, 1.0, 0.35, 0.45), 1.4)
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	plate.material = glow
	disc.mesh = plate
	disc.position.y = 0.04
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(disc)
	return root


## Nutmeg's fake item box: the real box's shape in a hot orange-red no real
## box uses, with the "?" upside down.
static func fake_box() -> Node3D:
	var root := Node3D.new()
	root.name = "FakeBox"
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.3, 0.12)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.25, 0.1)
	material.emission_energy_multiplier = 0.5
	material.roughness = 0.4
	var box := MeshInstance3D.new()
	box.name = "Box"
	var mesh := RoundedBoxMesh.new()
	mesh.size = Vector3.ONE * 1.3
	mesh.radius = 0.23
	mesh.material = material
	box.mesh = mesh
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(box)
	for i in 4:
		var mark := Label3D.new()
		mark.text = "?"
		mark.font_size = 96
		mark.pixel_size = 0.008
		mark.outline_size = 18
		mark.modulate = Color(1.0, 0.95, 0.6)
		mark.outline_modulate = Color(0.3, 0.05, 0.05)
		mark.rotation = Vector3(0.0, i * PI * 0.5, PI)  # upside down: the tell
		mark.position = Basis(Vector3.UP, i * PI * 0.5) * Vector3(0, 0, 0.66)
		box.add_child(mark)
	return root


## Rusty's pillow shield: a soft translucent bubble around trike and rider
## that wobbles. Returned node is added to the trike.
static func shield_bubble() -> MeshInstance3D:
	var bubble := MeshInstance3D.new()
	bubble.name = "PillowShield"
	var sphere := SphereMesh.new()
	sphere.radius = 1.45
	sphere.height = 2.5
	sphere.radial_segments = 16
	sphere.rings = 8
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.96, 0.9, 0.3)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Color(1.0, 0.9, 0.95)
	material.emission_energy_multiplier = 0.35
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.9
	sphere.material = material
	bubble.mesh = sphere
	bubble.position = Vector3(0, 0.75, 0.05)
	bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return bubble


## Several puffs in party colors (fake box, shield pop, perfect landing).
static func confetti(parent: Node, position: Vector3, radius := 2.0) -> void:
	for i in CONFETTI.size():
		ItemVisuals.burst(parent, position + Vector3.UP * (0.2 * i), CONFETTI[i], 7, radius * (0.7 + 0.15 * i), 0.55)


## A fan of pale streaks rushing backwards past `trike` (slingshot launch).
static func wind_burst(trike: Node3D, color := Color(0.8, 0.95, 1.0)) -> void:
	if trike == null or not trike.is_inside_tree():
		return
	var streaks := CPUParticles3D.new()
	streaks.name = "WindBurst"
	var quad := BoxMesh.new()
	quad.size = Vector3(0.05, 0.05, 1.6)
	var material := ItemVisuals.flat_material(color, 1.2)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color.a = 0.7
	quad.material = material
	streaks.mesh = quad
	streaks.amount = 18
	streaks.lifetime = 0.45
	streaks.one_shot = false
	streaks.explosiveness = 0.2
	streaks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	streaks.emission_box_extents = Vector3(1.2, 0.8, 0.4)
	streaks.direction = Vector3(0, 0, 1)
	streaks.spread = 4.0
	streaks.initial_velocity_min = 14.0
	streaks.initial_velocity_max = 22.0
	streaks.gravity = Vector3.ZERO
	streaks.position = Vector3(0, 0.9, -1.2)
	trike.add_child(streaks)
	streaks.emitting = true
	# Bound to the node itself: freed with the trike first, the connection just goes away.
	trike.get_tree().create_timer(1.3).timeout.connect(streaks.queue_free)
