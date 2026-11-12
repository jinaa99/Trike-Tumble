class_name FallingLog
extends AnimatableBody3D
## Timed hazard: a log drops off the bank on one side of the road, rolls
## across it and tumbles away down the other side, then the next one comes.
##
## Motion is a pure function of the track's race clock (`Track.hazard_time`),
## so every computer in an online race shows the same log at the same time
## and nothing needs syncing. Before the race starts the log waits off the
## road. It's a kinematic body: it shoves trikes and riders aside, and a hit
## counts as an impact (it can throw riders off).
##
## Placed by TrackProps in road space: local X across the road (+ = right),
## -Z along it. `from_side` is where the logs come from.

## Seconds between logs, and the offset of this hazard's cycle.
@export var period := 7.0
@export var phase := 0.0
@export var drop_time := 0.7
## Road crossing speed (m/s).
@export var roll_speed := 7.0
@export var log_length := 4.6
@export var log_radius := 0.45
## -1: logs come from the left bank, 1: from the right.
@export var from_side := -1
## Set by TrackProps: half the road width here (m).
@export var half_width := 7.0
## Bank height and distance beyond the barrier the log starts from (m).
@export var bank_height := 3.5
@export var bank_out := 4.0

var track: Track
## Where the log is now (0 waiting, 1 dropping, 2 rolling, 3 leaving).
var phase_state := 0

var _rest := Transform3D.IDENTITY
var _mesh: MeshInstance3D


func _ready() -> void:
	sync_to_physics = true
	_rest = transform
	var log_mesh := MeshKit.combine([
		[MeshKit.cylinder(log_radius, log_radius, log_length, 10), MeshKit.at(Vector3.ZERO, Vector3(90, 0, 0)), Color(0.55, 0.36, 0.22)],
		[MeshKit.cylinder(log_radius * 0.8, log_radius * 0.8, log_length + 0.04, 10), MeshKit.at(Vector3.ZERO, Vector3(90, 0, 0)), Color(0.93, 0.8, 0.55)],
		[MeshKit.box(Vector3(0.1, log_radius * 2.05, 0.5)), MeshKit.at(Vector3(0, 0, 1.2)), Color(0.45, 0.29, 0.18)],
		[MeshKit.box(Vector3(0.1, log_radius * 2.05, 0.5)), MeshKit.at(Vector3(0, 0, -1.4)), Color(0.45, 0.29, 0.18)],
	])
	log_mesh.surface_set_material(0, MeshKit.vertex_color_material(0.9))
	_mesh = MeshInstance3D.new()
	_mesh.name = "Mesh"
	_mesh.mesh = log_mesh
	add_child(_mesh)
	var shape := CylinderShape3D.new()
	shape.radius = log_radius
	shape.height = log_length
	var collider := CollisionShape3D.new()
	collider.name = "Collision"
	collider.shape = shape
	collider.rotation_degrees = Vector3(90, 0, 0)
	add_child(collider)
	transform = _rest * _pose(-1.0)


func _physics_process(_delta: float) -> void:
	var clock := track.hazard_time if track else 0.0
	var t := -1.0 if clock <= 0.0 else fposmod(clock + phase, period)
	transform = _rest * _pose(t)


## Log transform in road space at cycle time t (t < 0: waiting).
func _pose(t: float) -> Transform3D:
	var start_x := float(from_side) * (half_width + bank_out)
	var end_x := -float(from_side) * (half_width + bank_out + 2.0)
	var roll_time := (half_width * 2.0) / roll_speed
	var x := start_x
	var y := bank_height
	phase_state = 0
	if t < 0.0 or t > drop_time + roll_time + 1.2:
		# Waiting out of sight below the starting bank.
		return Transform3D(Basis.IDENTITY, Vector3(start_x, -4.0, 0.0))
	if t < drop_time:
		phase_state = 1
		var k := t / drop_time
		x = lerpf(start_x, float(from_side) * half_width, k)
		y = lerpf(bank_height, log_radius, k * k) + sin(k * PI) * 0.8
	elif t < drop_time + roll_time:
		phase_state = 2
		var k := (t - drop_time) / roll_time
		x = lerpf(float(from_side) * half_width, -float(from_side) * half_width, k)
		y = log_radius
	else:
		phase_state = 3
		var k := (t - drop_time - roll_time) / 1.2
		x = lerpf(-float(from_side) * half_width, end_x, k)
		y = log_radius + sin(k * PI) * 2.5 - k * k * 6.0
	var spin := -(x - start_x) / log_radius * float(-from_side)
	return Transform3D(Basis(Vector3.FORWARD, spin), Vector3(x, y, 0.0))


## Cycle time at which the log crosses the middle of the road (tests, tools).
func mid_crossing_time() -> float:
	return drop_time + (half_width * 2.0 / roll_speed) * 0.5


## True while the log is on (or dropping onto) the road.
func is_active() -> bool:
	return phase_state == 1 or phase_state == 2
