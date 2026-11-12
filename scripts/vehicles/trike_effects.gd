class_name TrikeEffects
extends Node3D
## Trike particle effects, from state only (work on network proxies too):
## - wheel spray behind the rear wheels, styled by the ground under them:
##   dirt dust, grass bits, mud splash, snow powder, ice glitter (planks: none)
## - skid marks while drifting
## - a boost trail from the exhaust
## - a puff of the ground on landing, an impact burst on hard hits
## Everything stays low and behind the trike so the road ahead stays clear.
## Created by TrikeVisuals.

## Per surface (TrackSurface.Kind): [color, size, upward speed, gravity, amount scale].
const SPRAY := {
	TrackSurface.Kind.ROAD: [Color(0.78, 0.6, 0.42, 0.7), 0.16, 1.2, 3.0, 1.0],
	TrackSurface.Kind.GRASS: [Color(0.45, 0.62, 0.3, 0.85), 0.1, 1.8, 8.0, 0.8],
	TrackSurface.Kind.MUD: [Color(0.32, 0.2, 0.11, 0.95), 0.14, 3.2, 14.0, 1.4],
	TrackSurface.Kind.WOOD: [Color(0.8, 0.7, 0.55, 0.0), 0.1, 0.5, 3.0, 0.0],
	TrackSurface.Kind.SNOW: [Color(0.97, 0.99, 1.0, 0.85), 0.2, 2.0, 2.5, 1.3],
	TrackSurface.Kind.ICE: [Color(0.8, 0.95, 1.0, 0.9), 0.07, 1.2, 5.0, 0.6],
}
## Speed (m/s) above which the wheels throw up their surface.
@export var spray_min_speed := 7.0
@export var landing_min_air := 0.35
@export var impact_burst_min := 5.0

var trike: Trike
var sprays: Array[CPUParticles3D] = []
var skid_marks: Array[CPUParticles3D] = []
var boost_trail: CPUParticles3D
## Bursts spawned so far (tests): "landing", "impact".
var bursts: Array[String] = []

var _surface := -1


func setup(for_trike: Trike, visuals: TrikeVisuals) -> void:
	trike = for_trike
	for side: float in [-1.0, 1.0]:
		var mount := trike.get_wheel_mount(Trike.Wheel.REAR_LEFT if side < 0.0 else Trike.Wheel.REAR_RIGHT)
		var at := Vector3(mount.x, mount.y - trike.config.suspension_rest_length - trike.get_wheel_radius(1) + 0.08, mount.z + 0.25)
		sprays.append(_make_spray(at))
		skid_marks.append(_make_skid(at))
	boost_trail = _make_boost_trail()
	_apply_surface(TrackSurface.Kind.ROAD)
	if not trike.network_proxy:
		trike.impact.connect(_on_impact)
	visuals.landed.connect(_on_landed)


func _process(_delta: float) -> void:
	if trike == null:
		return
	if trike.surface != _surface:
		_apply_surface(trike.surface)
	var speed := absf(trike.forward_speed)
	var grounded := trike.is_grounded()
	var style: Array = SPRAY[trike.surface]
	for i in sprays.size():
		var wheel := Trike.Wheel.REAR_LEFT if i == 0 else Trike.Wheel.REAR_RIGHT
		sprays[i].emitting = grounded and trike.wheel_contact[wheel] and speed > spray_min_speed and float(style[4]) > 0.0
		sprays[i].speed_scale = clampf(speed / 20.0, 0.6, 1.4)
		skid_marks[i].emitting = trike.is_drifting and trike.wheel_contact[wheel]
	boost_trail.emitting = trike.boost_time > 0.0


func _apply_surface(kind: int) -> void:
	_surface = kind
	var style: Array = SPRAY[kind]
	for spray in sprays:
		spray.color = style[0]
		spray.scale_amount_min = float(style[1]) * 0.6
		spray.scale_amount_max = float(style[1])
		spray.initial_velocity_min = float(style[2]) * 0.5
		spray.initial_velocity_max = float(style[2])
		spray.gravity = Vector3(0.0, -float(style[3]), 0.0)
		spray.amount = maxi(roundi(14.0 * float(style[4])), 1)


func _particles(node_name: String, at: Vector3, color: Color, size: float) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = node_name
	particles.position = at
	particles.emitting = false
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 6
	sphere.rings = 3
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material = material
	particles.mesh = sphere
	particles.color = color
	particles.scale_amount_min = size * 0.6
	particles.scale_amount_max = size
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	particles.color_ramp = fade
	add_child(particles)
	return particles


## Thrown backward and a little up from the tyre, falling back quickly.
func _make_spray(at: Vector3) -> CPUParticles3D:
	var spray := _particles("WheelSpray", at, Color.WHITE, 0.16)
	spray.amount = 14
	spray.lifetime = 0.55
	spray.local_coords = false
	spray.direction = Vector3(0.0, 0.45, 1.0)
	spray.spread = 25.0
	spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	spray.emission_sphere_radius = 0.12
	return spray


## Dark tyre marks left on the ground while drifting (world space, fading).
func _make_skid(at: Vector3) -> CPUParticles3D:
	var marks := CPUParticles3D.new()
	marks.name = "SkidMarks"
	marks.position = at + Vector3(0.0, -0.06, -0.2)
	marks.emitting = false
	marks.amount = 60
	marks.lifetime = 2.2
	marks.local_coords = false
	marks.gravity = Vector3.ZERO
	marks.initial_velocity_min = 0.0
	marks.initial_velocity_max = 0.0
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.22, 0.32)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	plane.material = material
	marks.mesh = plane
	marks.color = Color(0.12, 0.1, 0.1, 0.45)
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	marks.color_ramp = fade
	add_child(marks)
	return marks


## Hot streaks out of the exhaust while boosting (turbo or drift boost).
func _make_boost_trail() -> CPUParticles3D:
	var trail := _particles("BoostTrail", Vector3(0.0, 0.4, 1.0), Color(1.0, 0.62, 0.2, 0.9), 0.13)
	trail.amount = 18
	trail.lifetime = 0.3
	trail.local_coords = false
	trail.direction = Vector3(0.0, 0.1, 1.0)
	trail.spread = 8.0
	trail.initial_velocity_min = 2.0
	trail.initial_velocity_max = 4.0
	trail.gravity = Vector3.ZERO
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.75, 0.25, 1.0))
	ramp.set_color(1, Color(1.0, 0.25, 0.1, 0.0))
	trail.color_ramp = ramp
	trail.color = Color.WHITE
	return trail


func _on_landed(airtime: float) -> void:
	if airtime < landing_min_air:
		return
	bursts.append("landing")
	var style: Array = SPRAY[trike.surface]
	var color: Color = style[0]
	color.a = 0.75
	if trike.surface == TrackSurface.Kind.WOOD:
		color = Color(0.85, 0.75, 0.6, 0.6)
	ItemVisuals.burst(get_tree().current_scene if get_tree().current_scene else get_parent(),
			trike.global_position - trike.global_basis.y * 0.35, color, 12, clampf(airtime * 1.6, 1.0, 2.6), 0.5)


func _on_impact(strength: float, _velocity: Vector3) -> void:
	if strength < impact_burst_min:
		return
	bursts.append("impact")
	ItemVisuals.burst(get_tree().current_scene if get_tree().current_scene else get_parent(),
			trike.global_position + Vector3.UP * 0.5, Color(1.0, 0.92, 0.45), 8, clampf(strength * 0.12, 0.8, 2.0), 0.35)
