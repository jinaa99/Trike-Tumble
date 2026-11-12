class_name RiderStyle
extends RefCounted
## Applies a RiderLook to a Rider model: per-rider copies of the shared
## materials, helmet style meshes, accessory, goggles, head size and face.
## Re-applying replaces the previous look. Never touches the rig: limb nodes,
## IK targets and lengths stay as they are.

## Material role -> a part that uses it (the scene shares one material per role).
const ROLE_PARTS := {
	"helmet": "Hips/Spine/Chest/Neck/Head/Helmet",
	"accent": "Hips/Spine/Chest/Neck/Head/Crest",
	"jacket": "Hips/Spine/Torso",
	"jacket_dark": "Hips/Spine/Torso/JacketPanel",
	"pants": "Hips/Pelvis",
	"glove": "HandL/Glove",
	"boot": "FootL/Boot",
	"skin": "Hips/Spine/Chest/Neck/Head/Face",
	"lens": "Hips/Spine/Chest/Neck/Head/GoggleLensL",
}
const HEAD := "Hips/Spine/Chest/Neck/Head"
const EAR_PARTS: Array[String] = ["EarL", "EarR", "EarInnerL", "EarInnerR"]
const GOGGLE_PARTS: Array[String] = ["GoggleLensL", "GoggleLensR", "GoggleFrameL", "GoggleFrameR", "GoggleStrap"]
const SCARF_PARTS: Array[String] = ["Hips/Spine/Chest/Scarf", "Hips/Spine/Chest/ScarfTail"]
const ADDED_PREFIX := "Look_"


static func apply(rider: Rider, look: RiderLook) -> void:
	if rider == null or look == null:
		return
	_recolor(rider, look)
	var head := rider.get_node(HEAD) as Node3D
	for child in head.get_children() + rider.get_node("Hips/Spine/Chest").get_children():
		if child.name.begins_with(ADDED_PREFIX):
			child.queue_free()
			(child as Node).get_parent().remove_child(child)
	var accent := (rider.get_node(ROLE_PARTS["accent"]) as MeshInstance3D).material_override
	var helmet := (rider.get_node(ROLE_PARTS["helmet"]) as MeshInstance3D).material_override
	var bears := look.helmet_style == RiderLook.HelmetStyle.BEAR_EARS
	for part in EAR_PARTS:
		(head.get_node(part) as Node3D).visible = bears
	(head.get_node("Crest") as Node3D).visible = bears
	for part in GOGGLE_PARTS:
		(head.get_node(part) as Node3D).visible = look.goggles
	match look.helmet_style:
		RiderLook.HelmetStyle.MOHAWK:
			for k in 5:
				var z := lerpf(-0.12, 0.26, k / 4.0)
				var tall := 0.16 + 0.07 * sin(k / 4.0 * PI)
				_add(head, "Spike%d" % k, MeshKit.cone(0.055, tall, 6), Transform3D(Basis(Vector3.RIGHT, -0.25 + k * 0.12),
						Vector3(0.0, 0.36 + tall * 0.3, z)), accent)
		RiderLook.HelmetStyle.HORNS:
			var horn := StandardMaterial3D.new()
			horn.albedo_color = Color(0.98, 0.93, 0.8)
			horn.roughness = 0.5
			for side: float in [-1.0, 1.0]:
				# One tapered piece rooted in the helmet shell, leaning out.
				_add(head, "Horn%d" % int(side), MeshKit.cylinder(0.008, 0.07, 0.26, 8),
						Transform3D(Basis(Vector3.FORWARD, -0.55 * side), Vector3(0.2 * side, 0.36, 0.06)), horn)
		RiderLook.HelmetStyle.ANTENNA:
			_add(head, "Stalk", MeshKit.cylinder(0.012, 0.016, 0.3, 6), Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(0.0, 0.48, 0.12)), helmet)
			_add(head, "Ball", MeshKit.sphere(0.055, 10, 6), Transform3D(Basis(), Vector3(0.0, 0.62, 0.17)), accent)
		RiderLook.HelmetStyle.POMPOM:
			_add(head, "Pompom", MeshKit.sphere(0.1, 10, 6), Transform3D(Basis(), Vector3(0.0, 0.44, 0.08)), accent)
			for k in 2:
				var band := MeshKit.cylinder(0.255 - k * 0.04, 0.27 - k * 0.04, 0.035, 16)
				_add(head, "Stripe%d" % k, band, Transform3D(Basis(), Vector3(0.0, 0.18 + k * 0.1, 0.07)), accent)
	var scarf := look.accessory == RiderLook.Accessory.SCARF
	for path in SCARF_PARTS:
		(rider.get_node(path) as Node3D).visible = scarf
	var chest := rider.get_node("Hips/Spine/Chest") as Node3D
	match look.accessory:
		RiderLook.Accessory.BACKPACK:
			var pack := RoundedBoxMesh.new()
			pack.size = Vector3(0.36, 0.38, 0.17)
			pack.radius = 0.06
			_add(chest, "Backpack", pack, Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0.0, -0.02, 0.24)), accent)
			_add(chest, "PackFlap", MeshKit.box(Vector3(0.3, 0.1, 0.05)), Transform3D(Basis(), Vector3(0.0, 0.12, 0.33)), helmet)
		RiderLook.Accessory.BANDANA:
			# A neckerchief: a diamond half tucked into the jacket reads as a triangle.
			_add(chest, "Bandana", MeshKit.box(Vector3(0.17, 0.17, 0.03)),
					Transform3D(Basis(Vector3.FORWARD, PI * 0.25), Vector3(0.0, 0.02, -0.19)), accent)
		RiderLook.Accessory.BELL:
			_add(chest, "BellCollar", MeshKit.cylinder(0.14, 0.15, 0.04, 14), Transform3D(Basis(), Vector3(0.0, 0.14, -0.01)), helmet)
			var gold := StandardMaterial3D.new()
			gold.albedo_color = Color(1.0, 0.82, 0.25)
			gold.metallic = 0.6
			gold.roughness = 0.3
			_add(chest, "Bell", MeshKit.sphere(0.06, 10, 6), Transform3D(Basis(), Vector3(0.0, 0.06, -0.15)), gold)
	var kit := {"Kit_HelmetStripe": look.helmet_stripe, "Kit_ShoulderStripe": look.shoulder_stripes, "Kit_ElbowPad": look.elbow_pads,
			"Kit_KneePad": look.knee_pads, "Kit_ThighStripe": look.thigh_stripes, "Kit_ToeCap": look.toe_caps}
	for node in rider.find_children("Kit_*", "MeshInstance3D", true, false):
		for prefix: String in kit:
			if node.name.begins_with(prefix):
				(node as Node3D).visible = kit[prefix]
	RiderDetail.set_eye_color(rider, look.eye_color)
	head.scale = Vector3.ONE * look.head_scale
	rider.set_base_face(look.face)


## Every role's material duplicated for this rider and recolored.
static func _recolor(rider: Rider, look: RiderLook) -> void:
	var colors := {
		"helmet": look.helmet_color, "accent": look.accent_color, "jacket": look.jacket_color,
		"jacket_dark": look.jacket_dark_color, "pants": look.pants_color, "glove": look.glove_color,
		"boot": look.boot_color, "skin": look.skin_color, "lens": look.lens_color,
	}
	var originals := {}
	for role: String in ROLE_PARTS:
		var part := rider.get_node(ROLE_PARTS[role]) as MeshInstance3D
		var source := part.material_override as StandardMaterial3D
		if source and not source.has_meta(&"look_role"):
			originals[source] = role
	var copies := {}
	for node in rider.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var source := mesh.material_override as StandardMaterial3D
		if source == null:
			continue
		if source.has_meta(&"look_role"):
			# Already a per-rider copy from an earlier look: recolor in place.
			source.albedo_color = colors[source.get_meta(&"look_role")]
			continue
		if not originals.has(source):
			continue
		if not copies.has(source):
			var copy := source.duplicate() as StandardMaterial3D
			copy.set_meta(&"look_role", originals[source])
			copy.albedo_color = colors[originals[source]]
			copies[source] = copy
		mesh.material_override = copies[source]


static func _add(parent: Node3D, node_name: String, mesh: Mesh, xf: Transform3D, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = ADDED_PREFIX + node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.transform = xf
	parent.add_child(instance)
	return instance
