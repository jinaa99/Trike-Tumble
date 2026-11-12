class_name RiderDetail
extends RefCounted
## Visual Overhaul V2: character detail added on top of the rider scene's
## existing nodes. The rig, the IK targets and every node the state machine
## or the face animation uses stay exactly as they are; this only adds child
## meshes, smooths the existing primitives and enriches the shared materials.
##
## Adds: coloured irises and a second eye highlight, helmet racing stripe,
## side vents and a rim, collar, chest pocket, shoulder stripes, elbow and
## knee pads, trouser stripes, boot toe caps, laces and heel tabs.
## Parts whose name starts with "Kit_" can be switched per look (RiderStyle).

const HEAD := "Hips/Spine/Chest/Neck/Head"

static var _fabric: NoiseTexture2D


static func build(rider: Node3D) -> void:
	if rider.has_node(HEAD + "/IrisL"):
		return
	_smooth(rider)
	var head := rider.get_node(HEAD) as Node3D
	var skin := _material(rider, HEAD + "/Face")
	var helmet := _material(rider, HEAD + "/Helmet")
	var accent := _material(rider, HEAD + "/Crest")
	var dark := _material(rider, HEAD + "/BrowL")
	var white := _material(rider, HEAD + "/EyeL")
	var jacket := _material(rider, "Hips/Spine/Torso")
	var jacket_dark := _material(rider, "Hips/Spine/Torso/JacketPanel")
	var pants := _material(rider, "Hips/Pelvis")
	var boot := _material(rider, "FootL/Boot")
	var sole := _material(rider, "FootL/Sole")
	_enrich(helmet, 0.22, true)
	_enrich(skin, 0.52, false)
	_cloth(jacket)
	_cloth(jacket_dark)
	_cloth(pants)

	# --- Face ---------------------------------------------------------------
	for side: float in [-1.0, 1.0]:
		var tag := "L" if side < 0.0 else "R"
		var eye := head.get_node("Eye" + tag) as Node3D
		var iris := _part(eye, "Iris" + tag, MeshKit.sphere(0.058, 20, 10), _iris_material(Color(0.25, 0.6, 0.7)),
				eye.transform.affine_inverse() * Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.45)), Vector3(side * 0.092, 0.012, -0.262)))
		iris.set_meta(&"iris", true)
		var shine := head.get_node("EyeShine" + tag) as Node3D
		_part(shine, "Glint" + tag, MeshKit.sphere(0.007, 8, 5), white,
				shine.transform.affine_inverse() * Transform3D(Basis(), Vector3(side * 0.112, -0.012, -0.303)))

	# --- Helmet -------------------------------------------------------------
	var stripe := ArcMesh.new()
	stripe.inner_radius = 0.3
	stripe.thickness = 0.012
	stripe.width = 0.075
	stripe.start_angle_deg = -115.0
	stripe.end_angle_deg = 38.0
	_part(head, "Kit_HelmetStripe", stripe, accent, Transform3D(Basis(), Vector3(0, 0.1, 0.07)))
	for side: float in [-1.0, 1.0]:
		_part(head, "HelmetVent%d" % int(side), MeshKit.rounded_box(Vector3(0.03, 0.03, 0.11), 0.012), dark,
				Transform3D(Basis(Vector3.UP, side * -0.35), Vector3(side * 0.262, 0.22, 0.0)))
		_part(head, "HelmetBolt%d" % int(side), MeshKit.cylinder(0.022, 0.022, 0.02, 10), white,
				Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(side * 0.288, 0.02, 0.07)))

	# --- Torso --------------------------------------------------------------
	var chest := rider.get_node("Hips/Spine/Chest") as Node3D
	_part(chest, "Collar", MeshKit.torus(0.07, 0.125, 20, 8), jacket_dark, Transform3D(Basis.from_scale(Vector3(1, 0.7, 1)), Vector3(0, 0.045, -0.01)))
	var torso := rider.get_node("Hips/Spine/Torso") as Node3D
	_part(torso, "Pocket", MeshKit.rounded_box(Vector3(0.085, 0.075, 0.02), 0.009), jacket_dark, Transform3D(Basis(), Vector3(0.085, 0.07, -0.153)))
	_part(torso, "PocketFlap", MeshKit.rounded_box(Vector3(0.09, 0.025, 0.024), 0.008), accent, Transform3D(Basis(), Vector3(0.085, 0.105, -0.153)))

	# --- Limbs (rings, so the IK's limb roll never matters) ------------------
	for tag: String in ["L", "R"]:
		var upper := rider.get_node("UpperArm" + tag) as Node3D
		for k in 2:
			_part(upper, "Kit_ShoulderStripe%d" % k, MeshKit.torus(0.058, 0.073, 16, 5), accent,
					Transform3D(Basis.from_scale(Vector3(1, 0.7, 1)), Vector3(0, 0.1 + k * 0.045, 0)))
		_part(rider.get_node("Forearm" + tag) as Node3D, "Kit_ElbowPad", MeshKit.torus(0.045, 0.082, 16, 7), jacket_dark,
				Transform3D(Basis.from_scale(Vector3(1, 1.3, 1)), Vector3(0, 0.0, 0)))
		_part(rider.get_node("Shin" + tag) as Node3D, "Kit_KneePad", MeshKit.torus(0.055, 0.104, 16, 7), accent,
				Transform3D(Basis.from_scale(Vector3(1, 1.4, 1)), Vector3(0, 0.0, 0)))
		_part(rider.get_node("Thigh" + tag) as Node3D, "Kit_ThighStripe", MeshKit.torus(0.08, 0.095, 16, 5), jacket_dark,
				Transform3D(Basis.from_scale(Vector3(1, 0.8, 1)), Vector3(0, 0.3, 0)))
		# --- Boots ------------------------------------------------------------
		var foot := rider.get_node("Foot" + tag) as Node3D
		_part(foot, "Kit_ToeCap", MeshKit.rounded_box(Vector3(0.168, 0.1, 0.11), 0.045), accent, Transform3D(Basis(), Vector3(0, -0.025, -0.155)))
		for k in 3:
			_part(foot, "Lace%d" % k, MeshKit.rounded_box(Vector3(0.085, 0.014, 0.02), 0.006), sole,
					Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(0, 0.062 - k * 0.006, -0.03 - k * 0.04)))
		_part(foot, "HeelTab", MeshKit.rounded_box(Vector3(0.05, 0.07, 0.02), 0.008), accent, Transform3D(Basis(), Vector3(0, 0.03, 0.082)))
		_part(foot, "Tread", MeshKit.rounded_box(Vector3(0.15, 0.02, 0.26), 0.008), dark, Transform3D(Basis(), Vector3(0, -0.105, -0.06)))
	if boot is StandardMaterial3D:
		(boot as StandardMaterial3D).roughness = 0.5


## Sets the iris colour of this rider (per-look copy of the iris material).
static func set_eye_color(rider: Node3D, color: Color) -> void:
	var material := _iris_material(color)
	for tag: String in ["L", "R"]:
		var iris := rider.get_node_or_null("%s/Eye%s/Iris%s" % [HEAD, tag, tag]) as MeshInstance3D
		if iris:
			iris.material_override = material


static var _iris_cache := {}


static func _iris_material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _iris_cache.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.12
		material.metallic_specular = 0.8
		material.rim_enabled = true
		material.rim = 0.5
		material.rim_tint = 0.3
		_iris_cache[key] = material
	return _iris_cache[key]


static func _material(rider: Node, path: String) -> Material:
	var node := rider.get_node_or_null(path) as MeshInstance3D
	return node.material_override if node else null


static func _part(parent: Node3D, node_name: String, mesh: Mesh, material: Material, xf: Transform3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.transform = xf
	parent.add_child(instance)
	return instance


## Rounder silhouettes: more segments on the scene's primitive meshes (the
## resources are shared by every rider, so this happens once in effect).
static func _smooth(rider: Node) -> void:
	for node in rider.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if mesh is SphereMesh and (mesh as SphereMesh).radial_segments < 28:
			(mesh as SphereMesh).radial_segments = 28
			(mesh as SphereMesh).rings = 14
		elif mesh is CapsuleMesh and (mesh as CapsuleMesh).radial_segments < 18:
			(mesh as CapsuleMesh).radial_segments = 18
			(mesh as CapsuleMesh).rings = 6
		elif mesh is CylinderMesh and (mesh as CylinderMesh).radial_segments < 20:
			(mesh as CylinderMesh).radial_segments = 20
		elif mesh is TorusMesh and (mesh as TorusMesh).rings < 28:
			(mesh as TorusMesh).rings = 28
			(mesh as TorusMesh).ring_segments = 10


static func _enrich(material: Material, roughness: float, clearcoat: bool) -> void:
	var standard := material as StandardMaterial3D
	if standard == null:
		return
	standard.roughness = roughness
	if clearcoat:
		standard.clearcoat_enabled = true
		standard.clearcoat = 0.7
		standard.clearcoat_roughness = 0.12


## Woven fabric: matte with a fine weave in the normal map.
static func _cloth(material: Material) -> void:
	var standard := material as StandardMaterial3D
	if standard == null or standard.normal_enabled:
		return
	if _fabric == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_CELLULAR
		noise.frequency = 0.35
		_fabric = NoiseTexture2D.new()
		_fabric.width = 128
		_fabric.height = 128
		_fabric.seamless = true
		_fabric.as_normal_map = true
		_fabric.bump_strength = 2.5
		_fabric.noise = noise
		_fabric.generate_mipmaps = true
	standard.roughness = 0.85
	standard.normal_enabled = true
	standard.normal_texture = _fabric
	standard.normal_scale = 0.5
	standard.uv1_triplanar = true
	standard.uv1_scale = Vector3.ONE * 6.0
