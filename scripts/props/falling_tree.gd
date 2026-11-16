class_name FallingTree
extends AnimatableBody3D
## Timed forest hazard: a tall pine beside the road that falls across it.
##
## One cycle (seconds from the start of the cycle):
##   SHAKE   birds scatter, the crown shakes, a red strip on the road shows
##           where the trunk will land
##   LEAN    a loud crack; the trunk tilts over the road (strip blinks fast)
##   FALL    it comes down
##   DOWN    it lies across part of the road: drive around the free end
##   CLEAR   it sinks away
##   (rest)  a new tree stands there until the next cycle
##
## Like FallingLog, everything is a pure function of the race clock
## (`Track.hazard_time`) plus the track's shared hazard seed, so every
## computer in an online race sees the same tree fall at the same moment and
## nothing needs syncing. A kinematic body: the falling trunk shoves and
## crushes, and a hit counts as an impact (it can throw riders off).
##
## Placed by TrackProps in road space, centred on the road: local X across
## the road (+ = right), -Z along it. `from_side` is the side it stands on.
## The trunk never covers more than `reach` of the road and always leaves
## `min_gap` m free on the far side.

enum Stage { STANDING, SHAKE, LEAN, FALL, DOWN, CLEAR }
const STAGE_NAMES: Array[String] = ["STANDING", "SHAKE", "LEAN", "FALL", "DOWN", "CLEAR"]

## Seconds between two falls of this tree, and the offset of its cycle.
@export var period := 22.0
@export var phase := 0.0
@export var shake_time := 1.3
@export var lean_time := 1.0
@export var fall_time := 0.65
## How long the trunk lies on the road, and how long it takes to sink away.
@export var down_time := 6.0
@export var clear_time := 1.2
## -1: stands on the left of the road, 1: on the right.
@export var from_side := -1
## Set by TrackProps: half the road width here (m) and the distance along
## the track (seeds the cycle).
@export var half_width := 7.0
@export var track_distance := 0.0
## Share of the road width the fallen trunk covers.
@export_range(0.3, 0.9) var reach := 0.62
## Road that always stays free at the far end (m).
@export var min_gap := 4.2
## How far behind the barrier the tree stands (m).
@export var set_back := 1.3
@export var trunk_radius := 0.42
@export var lean_deg := 9.0
@export var leaf_color := Color(0.17, 0.5, 0.36)

var track: Track
var stage := Stage.STANDING
## Trunk length (m) and how much road it covers when down (m).
var trunk_length := 10.0
var blocked_width := 8.0

var _rest := Transform3D.IDENTITY
var _crown: Node3D
var _visual: Node3D
var _strip: MeshInstance3D
var _strip_material: StandardMaterial3D
var _landing: Node3D
var _markers: Array[HazardMarker] = []
var _last_stage := Stage.STANDING
var _time := 0.0


func _ready() -> void:
	sync_to_physics = true
	_rest = transform
	var road := half_width * 2.0
	blocked_width = minf(road * reach, road - min_gap)
	trunk_length = set_back + blocked_width
	_build_tree()
	_build_landing()
	_apply(-1.0)


## Avoidance points for AI drivers (on the road where the trunk lands).
func get_ai_obstacles() -> Array[HazardMarker]:
	return _markers


## True from the crack until the trunk is gone: the road here is blocked or
## about to be.
func is_active() -> bool:
	return stage == Stage.LEAN or stage == Stage.FALL or stage == Stage.DOWN


## True from the first warning until the trunk has sunk away (what AI
## drivers and the near-miss check react to).
func is_threat() -> bool:
	return stage != Stage.STANDING


## True while the warning is showing (shake and lean).
func is_warning() -> bool:
	return stage == Stage.SHAKE or stage == Stage.LEAN


func cycle_length() -> float:
	return shake_time + lean_time + fall_time + down_time + clear_time


## Cycle time at which the trunk is fully down.
func impact_time() -> float:
	return shake_time + lean_time + fall_time


## Lateral range of the road (m, + = right) the fallen trunk covers.
func blocked_range() -> Vector2:
	var edge := float(from_side) * half_width
	var tip := edge - float(from_side) * blocked_width
	return Vector2(minf(edge, tip), maxf(edge, tip))


## This tree's cycle time for a race clock value (< 0 before the race).
func cycle_time(clock: float) -> float:
	if clock <= 0.0:
		return -1.0
	var shift := track.hazard_phase(track_distance, period) if track else 0.0
	return fposmod(clock + phase + shift, period)


func _physics_process(delta: float) -> void:
	_time += delta
	_apply(cycle_time(track.hazard_time if track else 0.0))
	if stage != _last_stage:
		_on_stage(stage)
		_last_stage = stage


## Stage, tilt angle (rad, 0 = upright, PI/2 = down) and sink depth (m) at
## cycle time t (t < 0: waiting for the race).
func pose(t: float) -> Dictionary:
	var lean := deg_to_rad(lean_deg)
	if t < 0.0 or t >= cycle_length():
		return {"stage": Stage.STANDING, "angle": 0.0, "sink": 0.0, "grow": clampf((t - cycle_length()) / 1.5, 0.0, 1.0) if t > 0.0 else 1.0}
	if t < shake_time:
		return {"stage": Stage.SHAKE, "angle": sin(t * 26.0) * 0.02, "sink": 0.0, "grow": 1.0}
	t -= shake_time
	if t < lean_time:
		var k := t / lean_time
		return {"stage": Stage.LEAN, "angle": lean * k * k + sin(t * 30.0) * 0.012, "sink": 0.0, "grow": 1.0}
	t -= lean_time
	if t < fall_time:
		var k := t / fall_time
		return {"stage": Stage.FALL, "angle": lerpf(lean, PI * 0.5, k * k), "sink": 0.0, "grow": 1.0}
	t -= fall_time
	if t < down_time:
		# One small bounce as it lands.
		var bounce := maxf(sin(clampf(t / 0.35, 0.0, 1.0) * PI), 0.0) * 0.06
		return {"stage": Stage.DOWN, "angle": PI * 0.5 - bounce, "sink": 0.0, "grow": 1.0}
	t -= down_time
	return {"stage": Stage.CLEAR, "angle": PI * 0.5, "sink": (t / clear_time) * (trunk_radius * 2.0 + 2.2), "grow": 1.0}


func _apply(t: float) -> void:
	var p := pose(t)
	stage = p["stage"]
	var side := float(from_side)
	var base := Vector3(side * (half_width + set_back), trunk_radius * 0.9 - float(p["sink"]), 0.0)
	# Tilting toward the road centre: +Y turns toward -X for a tree on the right.
	transform = _rest * Transform3D(Basis(Vector3.BACK, side * float(p["angle"])), base)
	# The new tree grows back (visual only: a physics body is never scaled,
	# and writing its transform twice in a tick would undo the move above).
	if _visual:
		_visual.scale = Vector3.ONE * lerpf(0.05, 1.0, float(p["grow"]))
	if _crown:
		var shaking := stage == Stage.SHAKE or stage == Stage.LEAN
		_crown.rotation = Vector3(sin(_time * 31.0) * 0.05, sin(_time * 23.0) * 0.12, 0.0) if shaking else Vector3.ZERO
	if _strip:
		_strip.visible = stage == Stage.SHAKE or stage == Stage.LEAN or stage == Stage.FALL
		if _strip.visible:
			var rate := 5.0 if stage == Stage.SHAKE else 14.0
			_strip_material.albedo_color.a = 0.3 + 0.35 * (0.5 + 0.5 * sin(_time * rate))


## Sounds and one-shot effects at each stage change (the same on every
## computer: stages come from the shared clock).
func _on_stage(new_stage: Stage) -> void:
	if not is_inside_tree():
		return
	var crown_at := global_transform * Vector3(0.0, trunk_length * 0.8, 0.0)
	match new_stage:
		Stage.SHAKE:
			SoundPlayer.play_at(self, &"tree_rustle", crown_at, 2.0, 1.0, 22.0)
			_scatter_birds(crown_at)
		Stage.LEAN:
			SoundPlayer.play_at(self, &"tree_crack", global_position, 4.0, randf_range(0.92, 1.08), 26.0)
		Stage.DOWN:
			var middle := _landing.global_transform * Vector3((blocked_range().x + blocked_range().y) * 0.5, 0.4, 0.0)
			SoundPlayer.play_at(self, &"tree_crash", middle, 5.0, 1.0, 26.0)
			ItemVisuals.burst(get_parent(), middle, Color(0.62, 0.5, 0.36, 0.8), 14, 3.2, 0.6)
			ItemVisuals.burst(get_parent(), middle + Vector3.UP * 0.6, leaf_color.lightened(0.15), 12, 2.6, 0.7)


## A handful of small dark birds flapping up and away from the crown.
func _scatter_birds(at: Vector3) -> void:
	var birds := CPUParticles3D.new()
	birds.name = "Birds"
	var wing := BoxMesh.new()
	wing.size = Vector3(0.5, 0.05, 0.16)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.12, 0.16)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wing.material = material
	birds.mesh = wing
	birds.amount = 9
	birds.one_shot = true
	birds.explosiveness = 0.85
	birds.lifetime = 2.6
	birds.direction = Vector3(0.0, 1.0, 0.0)
	birds.spread = 55.0
	birds.initial_velocity_min = 5.0
	birds.initial_velocity_max = 9.0
	birds.gravity = Vector3(0.0, 1.5, 0.0)
	birds.angular_velocity_min = 300.0
	birds.angular_velocity_max = 700.0
	birds.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	birds.emission_sphere_radius = 1.5
	birds.top_level = true
	add_child(birds)
	birds.global_position = at
	birds.emitting = true
	# Bound to the node itself: freed with the scene first, the connection just goes away.
	get_tree().create_timer(3.2).timeout.connect(birds.queue_free)


func _build_tree() -> void:
	var length := trunk_length
	var crown_start := length * 0.42
	var trunk := MeshKit.combine([
		[MeshKit.cylinder(trunk_radius * 0.6, trunk_radius, length, 8), MeshKit.at(Vector3(0, length * 0.5, 0)), Color(0.46, 0.3, 0.19)],
		[MeshKit.cylinder(trunk_radius * 1.5, trunk_radius * 2.2, 0.4, 8), MeshKit.at(Vector3(0, 0.1, 0)), Color(0.4, 0.27, 0.17)],
	])
	trunk.surface_set_material(0, MeshKit.vertex_color_material(0.9))
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var trunk_node := MeshInstance3D.new()
	trunk_node.name = "Trunk"
	trunk_node.mesh = trunk
	_visual.add_child(trunk_node)
	_crown = Node3D.new()
	_crown.name = "Crown"
	_crown.position.y = crown_start
	_visual.add_child(_crown)
	var tiers := []
	var span := length - crown_start + 1.2
	for i in 4:
		var k := float(i) / 3.0
		tiers.append([MeshKit.cone(lerpf(2.5, 0.9, k), span * 0.42), MeshKit.at(Vector3(0, span * (0.16 + 0.24 * i), 0), Vector3(0, 25 * i, 0)),
				leaf_color.lightened(0.06 * i)])
	var leaves := MeshKit.combine(tiers)
	leaves.surface_set_material(0, MeshKit.vertex_color_material(0.9))
	var leaves_node := MeshInstance3D.new()
	leaves_node.name = "Leaves"
	leaves_node.mesh = leaves
	_crown.add_child(leaves_node)
	# Solid trunk, plus the crown as a lower, wider block (branches).
	var trunk_shape := BoxShape3D.new()
	trunk_shape.size = Vector3(trunk_radius * 1.9, length, trunk_radius * 1.9)
	var trunk_collider := CollisionShape3D.new()
	trunk_collider.name = "Collision"
	trunk_collider.shape = trunk_shape
	trunk_collider.position.y = length * 0.5
	add_child(trunk_collider)
	var crown_shape := BoxShape3D.new()
	crown_shape.size = Vector3(1.5, (length - crown_start) * 0.8, 2.4)
	var crown_collider := CollisionShape3D.new()
	crown_collider.name = "CrownCollision"
	crown_collider.shape = crown_shape
	crown_collider.position.y = crown_start + (length - crown_start) * 0.45
	add_child(crown_collider)


## The warning strip and the AI avoidance points: fixed on the road where the
## trunk will land (they don't tilt with the tree).
func _build_landing() -> void:
	_landing = Node3D.new()
	_landing.name = "Landing"
	_landing.top_level = true
	add_child(_landing)
	var parent := get_parent() as Node3D
	_landing.global_transform = (parent.global_transform if parent else Transform3D.IDENTITY) * _rest
	var blocked := blocked_range()
	_strip = MeshInstance3D.new()
	_strip.name = "WarningStrip"
	var plane := PlaneMesh.new()
	plane.size = Vector2(blocked.y - blocked.x, 2.6)
	_strip_material = StandardMaterial3D.new()
	_strip_material.albedo_color = Color(1.0, 0.25, 0.15, 0.5)
	_strip_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_strip_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	plane.material = _strip_material
	_strip.mesh = plane
	_strip.position = Vector3((blocked.x + blocked.y) * 0.5, 0.06, 0.0)
	_strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_strip.visible = false
	_landing.add_child(_strip)
	var count := maxi(ceili((blocked.y - blocked.x) / 1.8), 2)
	for i in count:
		var marker := HazardMarker.new()
		marker.name = "Avoid%d" % i
		marker.hazard = self
		marker.position = Vector3(lerpf(blocked.x, blocked.y, float(i) / (count - 1)), 0.5, 0.0)
		_landing.add_child(marker)
		_markers.append(marker)
