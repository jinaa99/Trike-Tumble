class_name RollingRock
extends AnimatableBody3D
## Timed canyon hazard (Rocky Canyon), two kinds:
## - FALL ("falling_rock"): a rock breaks off the cliff on one side, drops
##   onto the road, bounces once and rolls across and off the far edge. A dark
##   shadow on the road shows where it will land, `warning_time` seconds early.
## - ROLL ("rolling_rock"): a big boulder rolls off the bank on one side and
##   crosses the road diagonally, drifting downhill as it goes.
##
## Like FallingLog, the motion is a pure function of the race clock
## (`Track.hazard_time`), so every computer in an online race shows the same
## rock at the same time with nothing to sync. A kinematic body: it shoves
## trikes and riders aside and a hit counts as an impact.
##
## Placed by TrackProps in road space: local X across the road (+ = right),
## -Z along it (downhill).

enum Mode { FALL, ROLL }

@export var mode := Mode.FALL
## Seconds between rocks, and the offset of this hazard's cycle.
@export var period := 8.0
@export var phase := 0.0
@export var radius := 0.9
## Road crossing speed (m/s).
@export var roll_speed := 6.5
## -1: rocks come from the left, 1: from the right.
@export var from_side := -1
## Set by TrackProps: half the road width here (m).
@export var half_width := 6.0
## FALL: height above the road the rock falls from and how long it falls.
@export var drop_height := 16.0
@export var drop_time := 1.1
## FALL: the landing shadow shows this long before the rock lands.
@export var warning_time := 1.6
## ROLL: how far (m) the boulder drifts downhill while crossing.
@export var downhill_drift := 9.0
@export var color := Color(0.74, 0.42, 0.3)
@export var random_seed := 5

var track: Track
## 0 waiting, 1 falling / coming down the bank, 2 rolling across, 3 leaving.
var phase_state := 0

var _rest := Transform3D.IDENTITY
var _mesh: MeshInstance3D
var _shadow: MeshInstance3D


func _ready() -> void:
	sync_to_physics = true
	_rest = transform
	_mesh = MeshInstance3D.new()
	_mesh.name = "Mesh"
	_mesh.mesh = _rock_mesh()
	add_child(_mesh)
	var shape := SphereShape3D.new()
	shape.radius = radius
	var collider := CollisionShape3D.new()
	collider.name = "Collision"
	collider.shape = shape
	add_child(collider)
	if mode == Mode.FALL:
		_shadow = MeshInstance3D.new()
		_shadow.name = "Shadow"
		var disc := CylinderMesh.new()
		disc.top_radius = radius * 1.6
		disc.bottom_radius = radius * 1.6
		disc.height = 0.02
		disc.radial_segments = 16
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.1, 0.05, 0.05, 0.55)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		disc.material = material
		_shadow.mesh = disc
		_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_shadow.top_level = true
		add_child(_shadow)
	_apply(-1.0)


func _physics_process(_delta: float) -> void:
	var clock := track.hazard_time if track else 0.0
	_apply(-1.0 if clock <= 0.0 else fposmod(clock + phase, period))


func _apply(t: float) -> void:
	transform = _rest * pose(t)
	if _shadow == null:
		return
	var coming := t >= 0.0 and t < warning_time + drop_time
	_shadow.visible = coming
	if coming:
		# The shadow grows as the rock gets closer to landing.
		var k := clampf(t / (warning_time + drop_time), 0.0, 1.0)
		var parent := get_parent() as Node3D
		var base := parent.global_transform if parent else Transform3D.IDENTITY
		_shadow.global_transform = base * _rest * Transform3D(Basis().scaled(Vector3.ONE * lerpf(0.5, 1.0, k)),
				Vector3(_landing_x(), 0.03, 0.0))


## Cycle length while the hazard is active (the rest of the period it waits).
func active_time() -> float:
	return _lead_time() + _cross_time() + 1.4


## Rock transform in road space at cycle time t (t < 0: waiting).
func pose(t: float) -> Transform3D:
	var side := float(from_side)
	var start_x := side * (half_width + 3.0)
	var lead := _lead_time()
	var cross := _cross_time()
	phase_state = 0
	if t < 0.0 or t > lead + cross + 1.4:
		return Transform3D(Basis.IDENTITY, Vector3(start_x, -6.0, 0.0))
	var x := start_x
	var y := radius
	var z := 0.0
	if t < lead:
		phase_state = 1
		if mode == Mode.FALL:
			if t < warning_time:
				phase_state = 0  # still up on the cliff: only the shadow shows
				return Transform3D(Basis.IDENTITY, Vector3(start_x, drop_height + radius, 0.0))
			var k := (t - warning_time) / drop_time
			x = lerpf(start_x, _landing_x(), k)
			y = lerpf(drop_height, 0.0, k * k) + radius
		else:
			var k := t / lead
			x = lerpf(start_x, side * half_width, k)
			y = radius + lerpf(2.5, 0.0, k)
	elif t < lead + cross:
		phase_state = 2
		var k := (t - lead) / cross
		x = lerpf(_landing_x(), -side * half_width, k)
		if mode == Mode.FALL:
			y = radius + absf(sin(k * PI * 1.5)) * 1.2 * (1.0 - k)  # bounce out of the landing
		z = -downhill_drift * k if mode == Mode.ROLL else 0.0
	else:
		phase_state = 3
		var k := (t - lead - cross) / 1.4
		x = lerpf(-side * half_width, -side * (half_width + 6.0), k)
		y = radius + sin(k * PI) * 2.0 - k * k * 8.0
		z = -downhill_drift if mode == Mode.ROLL else 0.0
	var spin := (x - start_x) / radius * side
	return Transform3D(Basis(Vector3.FORWARD, spin) * Basis(Vector3.RIGHT, z / radius), Vector3(x, y, z))


## Cycle time at which the rock crosses the middle of the road (tests, tools).
func mid_crossing_time() -> float:
	var to_center := absf(_landing_x()) / roll_speed
	return _lead_time() + to_center


## True while the rock is on (or about to land on) the road.
func is_active() -> bool:
	return phase_state == 1 or phase_state == 2


func _lead_time() -> float:
	return warning_time + drop_time if mode == Mode.FALL else 0.8


func _cross_time() -> float:
	return absf(_landing_x() - (-float(from_side) * half_width)) / roll_speed


## FALL: lands a third of the way into the road from its side.
func _landing_x() -> float:
	if mode == Mode.FALL:
		return float(from_side) * half_width * 0.35
	return float(from_side) * half_width


func _rock_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var sphere := MeshKit.sphere(radius, 8, 6)
	var arrays := sphere.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var lumps := {}
	var batch := MeshBatch.new()
	var points := PackedVector3Array()
	for v in vertices:
		var key := v.snapped(Vector3.ONE * 0.001)
		if not lumps.has(key):
			lumps[key] = rng.randf_range(0.88, 1.08)
		points.append(v * float(lumps[key]))
	for t in range(0, indices.size(), 3):
		var a := points[indices[t]]
		var b := points[indices[t + 1]]
		var c := points[indices[t + 2]]
		var shade := color.darkened(clampf(0.2 - (a.y + b.y + c.y) / (3.0 * radius) * 0.2, 0.0, 0.35))
		batch.quad(a, b, c, c, (a + b + c) / 3.0, [shade, shade, shade, shade], true)
	var mesh := batch.commit()
	mesh.surface_set_material(0, MeshKit.vertex_color_material(0.95))
	return mesh
