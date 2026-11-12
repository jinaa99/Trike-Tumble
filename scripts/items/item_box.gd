class_name ItemBox
extends Node3D
## One item box on the track: a floating, spinning "?" crate with no
## collision (trikes drive straight through it). ItemManager decides when it
## is collected and when it comes back; this node only shows it.

const COLORS: Array[Color] = [Color(1.0, 0.45, 0.25), Color(0.3, 0.7, 1.0), Color(1.0, 0.8, 0.2), Color(0.5, 0.85, 0.35)]

@export var spin_speed := 1.6
@export var bob_height := 0.18
@export var size := 1.3

var box_id := 0
var active := true

var _time := 0.0
var _mesh: MeshInstance3D
var _pop_tween: Tween


func _ready() -> void:
	_time = box_id * 0.7
	var material := StandardMaterial3D.new()
	material.albedo_color = COLORS[box_id % COLORS.size()]
	material.emission_enabled = true
	material.emission = material.albedo_color
	material.emission_energy_multiplier = 0.35
	material.roughness = 0.4
	_mesh = MeshInstance3D.new()
	_mesh.name = "Box"
	var mesh := RoundedBoxMesh.new()
	mesh.size = Vector3.ONE * size
	mesh.radius = size * 0.18
	mesh.material = material
	_mesh.mesh = mesh
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	for i in 4:
		var mark := Label3D.new()
		mark.text = "?"
		mark.font_size = 96
		mark.pixel_size = 0.008
		mark.outline_size = 18
		mark.modulate = Color.WHITE
		mark.outline_modulate = Color(0.15, 0.1, 0.25)
		mark.rotation.y = i * PI * 0.5
		mark.position = Basis(Vector3.UP, i * PI * 0.5) * Vector3(0, 0, size * 0.5 + 0.01)
		_mesh.add_child(mark)


func _process(delta: float) -> void:
	_time += delta
	_mesh.rotation = Vector3(0.35, _time * spin_speed, 0.2)
	_mesh.position.y = sin(_time * 2.2) * bob_height


## Shown or hidden. `animate` pops it (collected) or grows it back (respawn).
func set_active(value: bool, animate := true) -> void:
	active = value
	if _pop_tween:
		_pop_tween.kill()
	if not animate or not is_inside_tree():
		visible = value
		scale = Vector3.ONE
		return
	visible = true
	_pop_tween = create_tween()
	if value:
		scale = Vector3.ONE * 0.05
		_pop_tween.tween_property(self, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_pop_tween.tween_property(self, "scale", Vector3.ONE * 1.5, 0.08)
		_pop_tween.tween_property(self, "scale", Vector3.ONE * 0.05, 0.12)
		_pop_tween.tween_callback(func() -> void: visible = false)
