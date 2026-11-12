class_name TrikeDetail
extends RefCounted
## Visual Overhaul V2: mechanical detail added on top of the trike scene's
## existing nodes (nothing is renamed, moved or removed, so every script
## that reaches into `Visuals` keeps working). Purely cosmetic: no
## collision, no physics. Detail meshes are merged per material and cached,
## so five trikes share them and each adds only a few draw calls.
##
## Adds: knobby front tread, wire spokes, hub flanges, valve stem, brake disc
## and caliper, fork brace, axle nuts, headlight bezel, plate bolts, brake
## levers, bar ends, crossbar pad, a small finned engine with air filter and
## pull-start cover, twin exhausts ending where the boost flames appear,
## chain guard and sprocket, axle bearing blocks, side pods, seat trim,
## footpeg treads, rear tyre grooves, lug nuts and frame bolts.

static var _meshes := {}
static var _materials := {}

const X_AXIS := Vector3(0, 0, 90)  # cylinder along X


static func build(visuals: Node3D) -> void:
	if visuals.has_node(^"DetailChrome"):
		return
	var frame := _material_of(visuals, ^"DownTube")
	var chrome := _material_of(visuals, ^"Axle")
	var rubber := _material_of(visuals, ^"FootPegL")
	var body := _material_of(visuals, ^"Tank")
	var accent := _material_of(visuals, ^"TankStripe")
	var tire := _material_of(visuals, ^"FrontPivot/FrontWheel/Spin/Tire")
	_add_tire_detail(tire)

	# --- Chassis --------------------------------------------------------------
	_add(visuals, "DetailChrome", chrome, _chassis_chrome)
	_add(visuals, "DetailEngine", _brushed(), _engine)
	_add(visuals, "DetailFrame", frame, _chassis_frame)
	_add(visuals, "DetailRubber", rubber, _chassis_rubber)
	_add(visuals, "DetailAccent", accent, _chassis_accent)
	_add(visuals, "DetailBody", body, _chassis_body).add_to_group(&"body_paint")

	# --- Front end --------------------------------------------------------------
	var pivot := visuals.get_node(^"FrontPivot") as Node3D
	_add(pivot, "DetailChrome", chrome, _fork_chrome)
	_add(pivot, "DetailRubber", rubber, _fork_rubber)
	var front := pivot.get_node(^"FrontWheel") as Node3D
	_add(front, "DetailChrome", chrome, _front_fixed_chrome)
	_add(front, "Caliper", accent, _caliper)
	var spin := front.get_node(^"Spin") as Node3D
	_add(spin, "Tread", tire, _tread)
	_add(spin, "DetailChrome", chrome, _front_spin_chrome)
	_add(spin, "BrakeDisc", _brushed(), _brake_disc)

	# --- Handlebar ----------------------------------------------------------------
	var bar := visuals.get_node(^"Handlebar") as Node3D
	_add(bar, "DetailChrome", chrome, _bar_chrome)
	_add(bar, "DetailFrame", frame, _bar_frame)
	_add(bar, "BarPad", accent, _bar_pad)

	# --- Rear wheels ----------------------------------------------------------------
	for side: int in [-1, 1]:
		var rear := visuals.get_node("RearWheelLeft/Spin" if side < 0 else "RearWheelRight/Spin") as Node3D
		var flip := Basis(Vector3.UP, PI) if side < 0 else Basis.IDENTITY
		_add(rear, "Grooves", _groove_material(), _rear_grooves).basis = flip
		_add(rear, "LugNuts", chrome, _rear_nuts).basis = flip


static func release() -> void:
	_meshes.clear()
	_materials.clear()


static func _material_of(root: Node, path: NodePath) -> Material:
	var node := root.get_node_or_null(path) as MeshInstance3D
	return node.material_override if node else null


static func _add(parent: Node3D, node_name: String, material: Material, parts_fn: Callable) -> MeshInstance3D:
	var key := "%s/%s" % [parent.name, node_name]
	if not _meshes.has(key):
		_meshes[key] = MeshKit.merge(parts_fn.call())
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = _meshes[key]
	instance.material_override = material
	parent.add_child(instance)
	return instance


## Brushed bare metal (engine, brake disc).
static func _brushed() -> StandardMaterial3D:
	if not _materials.has("brushed"):
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.62, 0.63, 0.66)
		material.metallic = 0.9
		material.roughness = 0.42
		material.anisotropy_enabled = true
		material.anisotropy = 0.6
		_materials["brushed"] = material
	return _materials["brushed"]


## Dark moulded plastic for the grooves in the rear wheel sleeves.
static func _groove_material() -> StandardMaterial3D:
	if not _materials.has("groove"):
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.5, 0.48, 0.44)
		material.roughness = 0.7
		_materials["groove"] = material
	return _materials["groove"]


## Gives the tyre rubber a fine moulded grain (shared by every trike).
static func _add_tire_detail(tire: Material) -> void:
	var material := tire as StandardMaterial3D
	if material == null or material.normal_enabled:
		return
	var noise := FastNoiseLite.new()
	noise.frequency = 0.25
	var grain := NoiseTexture2D.new()
	grain.width = 128
	grain.height = 128
	grain.seamless = true
	grain.as_normal_map = true
	grain.bump_strength = 3.0
	grain.noise = noise
	grain.generate_mipmaps = true
	material.normal_enabled = true
	material.normal_texture = grain
	material.normal_scale = 0.6
	material.uv1_scale = Vector3(8, 2, 1)


static func _bolt(at: Vector3, rotation_deg := Vector3.ZERO, size := 0.016) -> Array:
	return [MeshKit.cylinder(size, size, size * 1.1, 6), MeshKit.at(at, rotation_deg)]


# --- Part lists ([Mesh, Transform3D]) ---------------------------------------------

static func _tread() -> Array:
	var parts := []
	var knob := MeshKit.rounded_box(Vector3(0.036, 0.024, 0.034), 0.006)
	var count := 30
	for k in count:
		var angle := TAU * k / count
		var offset := 0.022 if k % 2 == 0 else -0.022
		var radius := 0.377
		var basis := Basis(Vector3.RIGHT, angle)
		parts.append([knob, Transform3D(basis, basis * Vector3(offset, radius, 0))])
		if k % 2 == 0:
			# Shoulder knobs on both sides.
			for side: float in [-1.0, 1.0]:
				var lean := Basis(Vector3.RIGHT, angle) * Basis(Vector3.FORWARD, side * 0.75)
				parts.append([knob, Transform3D(lean, Basis(Vector3.RIGHT, angle) * Vector3(side * 0.045, 0.36, 0.0))])
	return parts


static func _front_spin_chrome() -> Array:
	var parts := []
	var spoke := MeshKit.cylinder(0.005, 0.005, 0.235, 4)
	for k in 16:
		var angle := TAU * (k + 0.5) / 16.0
		var dish := 0.03 if k % 2 == 0 else -0.03
		var basis := Basis(Vector3.RIGHT, angle) * Basis(Vector3.FORWARD, -dish * 3.0)
		parts.append([spoke, Transform3D(basis, Basis(Vector3.RIGHT, angle) * Vector3(dish * 0.5, 0.135, 0))])
	for side: float in [-1.0, 1.0]:
		parts.append([MeshKit.cylinder(0.055, 0.045, 0.012, 14), MeshKit.at(Vector3(side * 0.045, 0, 0), X_AXIS)])
	parts.append([MeshKit.cylinder(0.03, 0.03, 0.12, 10), MeshKit.at(Vector3.ZERO, X_AXIS)])
	# Valve stem.
	parts.append([MeshKit.cylinder(0.006, 0.008, 0.035, 5), MeshKit.at(Vector3(0, -0.225, 0))])
	return parts


static func _brake_disc() -> Array:
	var parts := [[MeshKit.cylinder(0.15, 0.15, 0.006, 20), MeshKit.at(Vector3(0.075, 0, 0), X_AXIS)]]
	parts.append([MeshKit.cylinder(0.06, 0.06, 0.02, 12), MeshKit.at(Vector3(0.065, 0, 0), X_AXIS)])
	return parts


static func _caliper() -> Array:
	return [
		[MeshKit.rounded_box(Vector3(0.05, 0.085, 0.1), 0.014), MeshKit.at(Vector3(0.082, 0.045, 0.125), Vector3(-25, 0, 0))],
	]


static func _front_fixed_chrome() -> Array:
	var parts := []
	for side: float in [-1.0, 1.0]:
		parts.append([MeshKit.cylinder(0.026, 0.026, 0.03, 6), MeshKit.at(Vector3(side * 0.175, 0, 0), X_AXIS)])
		parts.append([MeshKit.cylinder(0.042, 0.042, 0.03, 10), MeshKit.at(Vector3(side * 0.13, 0.33, 0))])  # fork seals
	parts.append(_bolt(Vector3(0.105, 0.07, 0.1), X_AXIS, 0.012))
	return parts


static func _fork_chrome() -> Array:
	var parts := []
	# Fork brace over the tyre and a bezel around the headlight.
	parts.append([MeshKit.rounded_box(Vector3(0.3, 0.035, 0.05), 0.012), MeshKit.at(Vector3(0, 0.2, 0))])
	parts.append([MeshKit.torus(0.06, 0.084, 18, 6), MeshKit.at(Vector3(0, 0.42, -0.105), Vector3(90, 0, 0))])
	parts.append([MeshKit.cylinder(0.02, 0.02, 0.1, 6), MeshKit.at(Vector3(0, 0.42, -0.03), Vector3(90, 0, 0))])
	for x: float in [-0.12, 0.12]:
		for y: float in [0.51, 0.69]:
			parts.append(_bolt(Vector3(x, y, -0.095), Vector3(90, 0, 0), 0.013))
		parts.append(_bolt(Vector3(x, 0.485, 0), Vector3.ZERO, 0.02))
	return parts


static func _fork_rubber() -> Array:
	var parts := []
	# Fork gaiters: stacked rubber rings.
	for side: float in [-1.0, 1.0]:
		for k in 5:
			parts.append([MeshKit.torus(0.022, 0.044, 10, 5), MeshKit.at(Vector3(side * 0.13, 0.03 + k * 0.03, 0))])
	return parts


static func _bar_chrome() -> Array:
	var parts := []
	for side: float in [-1.0, 1.0]:
		# Brake lever, its ball end and the bar-end cap.
		parts.append([MeshKit.capsule(0.008, 0.13, 5), MeshKit.at(Vector3(side * 0.275, 0.078, 0.282), Vector3(0, side * 8.0, 90))])
		parts.append([MeshKit.sphere(0.013, 6, 4), MeshKit.at(Vector3(side * 0.34, 0.078, 0.274))])
		parts.append([MeshKit.sphere(0.03, 8, 5), MeshKit.at(Vector3(side * 0.385, 0.08, 0.33), Vector3.ZERO, Vector3(0.6, 1, 1))])
	for x: float in [-0.035, 0.035]:
		parts.append(_bolt(Vector3(x, 0.115, 0.33), Vector3.ZERO, 0.012))
	return parts


static func _bar_frame() -> Array:
	var parts := []
	for side: float in [-1.0, 1.0]:
		parts.append([MeshKit.rounded_box(Vector3(0.035, 0.04, 0.05), 0.01), MeshKit.at(Vector3(side * 0.21, 0.08, 0.315))])
	parts.append([MeshKit.rounded_box(Vector3(0.11, 0.05, 0.06), 0.015), MeshKit.at(Vector3(0, 0.085, 0.33))])
	return parts


static func _bar_pad() -> Array:
	return [[MeshKit.capsule(0.04, 0.26, 10), MeshKit.at(Vector3(0, 0.15, 0.33), X_AXIS)],
			[MeshKit.cylinder(0.01, 0.01, 0.07, 5), MeshKit.at(Vector3(-0.1, 0.115, 0.33))],
			[MeshKit.cylinder(0.01, 0.01, 0.07, 5), MeshKit.at(Vector3(0.1, 0.115, 0.33))]]


static func _rear_grooves() -> Array:
	var parts := []
	for x: float in [-0.055, 0.0, 0.055]:
		parts.append([MeshKit.cylinder(0.3015, 0.3015, 0.012, 24), MeshKit.at(Vector3(x, 0, 0), X_AXIS)])
	return parts


static func _rear_nuts() -> Array:
	var parts := []
	for k in 5:
		var angle := TAU * k / 5.0
		parts.append(_bolt(Vector3(0.123, cos(angle) * 0.11, sin(angle) * 0.11), X_AXIS, 0.02))
	parts.append([MeshKit.torus(0.2, 0.225, 20, 5), MeshKit.at(Vector3(0.118, 0, 0), X_AXIS)])
	return parts


static func _engine() -> Array:
	var parts := []
	var lean := Vector3(-14, 0, 0)
	# Crankcase, finned cylinder, head.
	parts.append([MeshKit.rounded_box(Vector3(0.2, 0.15, 0.24), 0.03), MeshKit.at(Vector3(0, -0.04, 0.0))])
	for k in 6:
		parts.append([MeshKit.rounded_box(Vector3(0.17, 0.012, 0.16), 0.005), MeshKit.at(Vector3(0, 0.045 + k * 0.021, -0.02 - k * 0.005), lean)])
	parts.append([MeshKit.cylinder(0.06, 0.062, 0.14, 10), MeshKit.at(Vector3(0, 0.1, -0.03), lean)])
	parts.append([MeshKit.rounded_box(Vector3(0.15, 0.03, 0.14), 0.012), MeshKit.at(Vector3(0, 0.178, -0.05), lean)])
	# Pull-start cover (right) and carburettor stub (left).
	parts.append([MeshKit.cylinder(0.075, 0.085, 0.03, 14), MeshKit.at(Vector3(0.112, -0.04, 0.0), X_AXIS)])
	parts.append([MeshKit.cylinder(0.022, 0.022, 0.07, 8), MeshKit.at(Vector3(-0.1, 0.09, 0.03), X_AXIS)])
	# Sprocket on the axle.
	parts.append([MeshKit.cylinder(0.085, 0.085, 0.012, 16), MeshKit.at(Vector3(-0.2, -0.2, 0.6), X_AXIS)])
	return parts


static func _chassis_chrome() -> Array:
	var parts := []
	# Twin exhausts: down from the head, back under the seat, up to the
	# megaphone tips where the boost flames appear.
	for side: float in [-1.0, 1.0]:
		var x := side * 0.16
		parts.append([MeshKit.capsule(0.022, 0.2, 8), MeshKit.at(Vector3(side * 0.1, 0.07, -0.1), Vector3(40, 0, side * -35.0))])
		parts.append([MeshKit.capsule(0.022, 0.78, 8), MeshKit.at(Vector3(x, -0.07, 0.3), Vector3(90, 0, 0))])
		parts.append([MeshKit.capsule(0.024, 0.2, 8), MeshKit.at(Vector3(x, -0.045, 0.74), Vector3(72, 0, 0))])
		parts.append([MeshKit.cylinder(0.04, 0.05, 0.22, 12), MeshKit.at(Vector3(x, -0.02, 0.9), Vector3(-90, 0, 0))])
		parts.append([MeshKit.torus(0.035, 0.056, 12, 5), MeshKit.at(Vector3(x, -0.02, 1.01), Vector3(90, 0, 0))])
	# Frame bolts.
	for at: Vector3 in [Vector3(0.06, 0.6, -0.95), Vector3(-0.06, 0.6, -0.95), Vector3(0.06, 0.66, -0.95), Vector3(-0.06, 0.66, -0.95)]:
		parts.append(_bolt(at, X_AXIS))
	for side: float in [-1.0, 1.0]:
		parts.append(_bolt(Vector3(side * 0.3, -0.14, 0.6)))
		parts.append(_bolt(Vector3(side * 0.215, 0.36, 0.6), X_AXIS))
		parts.append(_bolt(Vector3(side * 0.215, 0.52, 0.56), X_AXIS))
		parts.append(_bolt(Vector3(side * 0.165, 0.0, -0.45), X_AXIS, 0.03))
	parts.append(_bolt(Vector3(0, 0.34, -0.4), Vector3.ZERO, 0.035))  # fuel cap
	parts.append([MeshKit.cylinder(0.022, 0.03, 0.02, 10), MeshKit.at(Vector3(0, 0.355, -0.4))])
	return parts


static func _chassis_frame() -> Array:
	var parts := []
	for side: float in [-1.0, 1.0]:
		parts.append([MeshKit.rounded_box(Vector3(0.07, 0.11, 0.11), 0.02), MeshKit.at(Vector3(side * 0.3, -0.2, 0.6))])  # bearing blocks
		parts.append([MeshKit.rounded_box(Vector3(0.15, 0.085, 0.05), 0.015), MeshKit.at(Vector3(side * 0.27, 0.03, 0.885))])  # tail-light housings
	# Head-tube gusset, engine cradle and chain guard.
	parts.append([MeshKit.rounded_box(Vector3(0.03, 0.16, 0.2), 0.012), MeshKit.at(Vector3(0, 0.5, -0.86), Vector3(-35, 0, 0))])
	parts.append([MeshKit.rounded_box(Vector3(0.24, 0.025, 0.3), 0.01), MeshKit.at(Vector3(0, -0.125, 0.0))])
	parts.append([MeshKit.rounded_box(Vector3(0.035, 0.085, 0.66), 0.015), MeshKit.at(Vector3(-0.2, -0.115, 0.3), Vector3(-9, 0, 0))])
	return parts


static func _chassis_rubber() -> Array:
	var parts := []
	for side: float in [-1.0, 1.0]:
		for k in 4:
			parts.append([MeshKit.torus(0.026, 0.04, 10, 4), MeshKit.at(Vector3(side * (0.185 + k * 0.036), 0.02, -0.45), X_AXIS)])
		parts.append([MeshKit.rounded_box(Vector3(0.2, 0.16, 0.012), 0.005), MeshKit.at(Vector3(side * 0.62, -0.33, 0.92), Vector3(12, 0, 0))])  # mud flaps
	# Air filter and spark-plug lead.
	parts.append([MeshKit.cylinder(0.05, 0.05, 0.085, 12), MeshKit.at(Vector3(-0.165, 0.09, 0.03), X_AXIS)])
	parts.append([MeshKit.capsule(0.009, 0.1, 5), MeshKit.at(Vector3(0.03, 0.22, -0.07), Vector3(-30, 0, 30))])
	return parts


static func _chassis_accent() -> Array:
	var parts := []
	parts.append([MeshKit.rounded_box(Vector3(0.47, 0.03, 0.47), 0.014), MeshKit.at(Vector3(0, 0.168, 0.32))])  # seat trim
	parts.append([MeshKit.cylinder(0.052, 0.052, 0.02, 12), MeshKit.at(Vector3(-0.212, 0.09, 0.03), X_AXIS)])  # filter cap
	parts.append([MeshKit.rounded_box(Vector3(0.012, 0.05, 0.3), 0.005), MeshKit.at(Vector3(-0.236, 0.1, 0.42))])
	parts.append([MeshKit.rounded_box(Vector3(0.012, 0.05, 0.3), 0.005), MeshKit.at(Vector3(0.236, 0.1, 0.42))])
	return parts


static func _chassis_body() -> Array:
	var parts := []
	for side: float in [-1.0, 1.0]:
		# Side pods under the seat and a belly pan under the engine.
		parts.append([MeshKit.rounded_box(Vector3(0.07, 0.17, 0.46), 0.03), MeshKit.at(Vector3(side * 0.215, 0.07, 0.42), Vector3(0, side * -4.0, 0))])
	parts.append([MeshKit.rounded_box(Vector3(0.26, 0.04, 0.4), 0.018), MeshKit.at(Vector3(0, -0.15, 0.02), Vector3(4, 0, 0))])
	return parts
