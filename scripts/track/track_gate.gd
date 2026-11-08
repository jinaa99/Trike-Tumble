extends Node3D
## Start/finish arch: striped posts standing on the barriers, a rounded banner
## with a title on both faces, and pennants on top. The posts have collision;
## the banner is high above riders.

@export var span := 15.0
@export var height := 5.5
@export var checkered := false
@export var title := ""
@export var post_color := Color(0.18, 0.24, 0.48)
@export var stripe_color := Color(1.0, 0.8, 0.18)
@export var banner_color := Color(0.98, 0.4, 0.22)


func _ready() -> void:
	var material := MeshKit.vertex_color_material(0.55)
	var parts: Array = []
	var body := StaticBody3D.new()
	add_child(body)
	for side: float in [-1.0, 1.0]:
		var x := side * span * 0.5
		parts.append([MeshKit.cylinder(0.3, 0.36, height, 12), MeshKit.at(Vector3(x, height * 0.5, 0)), post_color])
		for k in 4:
			parts.append([MeshKit.cylinder(0.34, 0.37, 0.25, 12), MeshKit.at(Vector3(x, 0.6 + k * 1.1, 0)), stripe_color])
		parts.append([MeshKit.sphere(0.42, 12, 6), MeshKit.at(Vector3(x, height + 0.25, 0)), stripe_color])
		parts.append([MeshKit.cylinder(0.03, 0.03, 1.4, 6), MeshKit.at(Vector3(x, height + 1.0, 0)), Color(0.95, 0.95, 0.95)])
		var pennant := PrismMesh.new()
		pennant.left_to_right = 0.0
		pennant.size = Vector3(0.9, 0.5, 0.03)
		parts.append([pennant, MeshKit.at(Vector3(x + 0.45, height + 1.4, 0), Vector3(0, 0, -90)), banner_color])
		var shape := CylinderShape3D.new()
		shape.radius = 0.36
		shape.height = height
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position = Vector3(x, height * 0.5, 0)
		body.add_child(collider)

	var banner_size := Vector3(span + 0.4, 1.3, 0.3)
	var frame := RoundedBoxMesh.new()
	frame.size = banner_size + Vector3(0.2, 0.2, -0.05)
	frame.radius = 0.12
	parts.append([frame, MeshKit.at(Vector3(0, height - 0.45, 0)), post_color])
	var mesh := MeshKit.combine(parts)
	mesh.surface_set_material(0, material)
	var arch := MeshInstance3D.new()
	arch.name = "Arch"
	arch.mesh = mesh
	add_child(arch)

	var banner_mesh := RoundedBoxMesh.new()
	banner_mesh.size = banner_size
	banner_mesh.radius = 0.1
	var banner := MeshInstance3D.new()
	banner.name = "Banner"
	banner.mesh = banner_mesh
	banner.position = Vector3(0.0, height - 0.45, 0.0)
	var banner_material := StandardMaterial3D.new()
	banner_material.roughness = 0.6
	if checkered:
		banner_material.albedo_texture = _checker_texture()
		banner_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		banner_material.uv1_scale = Vector3(3.0, 1.0, 1.0)
	else:
		banner_material.albedo_color = banner_color
	banner.material_override = banner_material
	add_child(banner)

	if title != "":
		for facing: float in [1.0, -1.0]:
			banner.add_child(_title_label(facing, banner_size.z * 0.5 + 0.02))


func _title_label(facing: float, depth: float) -> Label3D:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Arial Rounded MT Bold", "Arial Black", "Segoe UI Black", "Arial"])
	font.font_weight = 800
	var label := Label3D.new()
	label.text = title
	label.font = font
	label.font_size = 160
	label.pixel_size = 0.006
	label.outline_size = 36
	label.modulate = Color.WHITE
	label.outline_modulate = Color(0.12, 0.1, 0.25)
	label.double_sided = false
	label.position = Vector3(0, 0, depth * facing)
	label.rotation.y = 0.0 if facing > 0.0 else PI
	return label


func _checker_texture() -> ImageTexture:
	var image := Image.create(16, 4, false, Image.FORMAT_RGB8)
	for x in 16:
		for y in 4:
			image.set_pixel(x, y, Color.WHITE if (x + y) % 2 == 0 else Color(0.08, 0.08, 0.1))
	return ImageTexture.create_from_image(image)
