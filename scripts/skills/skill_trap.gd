class_name SkillTrap
extends Node3D
## A trap lying on the road: Bramble's root snare or Nutmeg's fake item box.
## Purely a marker with a visual: SkillManager detects who drives over it
## and the host resolves the hit. Both have a deliberate tell (see
## docs/SKILL_DESIGN.md): the snare glows and twitches from the moment it is
## dropped; the fake box is tinted hot orange, spins the wrong way and its
## "?" hangs upside down.

var trap_id := 0
var kind := SkillKind.Kind.SNARE
var owner_id := 0
var age := 0.0
var lifetime := 14.0
var arm_time := 0.8

var _visual: Node3D
var _time := 0.0


func _ready() -> void:
	_visual = SkillVisuals.fake_box() if kind == SkillKind.Kind.FAKE_BOX else SkillVisuals.snare()
	add_child(_visual)
	scale = Vector3.ONE * 0.1
	create_tween().tween_property(self, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func is_armed_for(racer_id: int) -> bool:
	return age >= arm_time and (racer_id != owner_id or age >= arm_time + 1.0)


func _process(delta: float) -> void:
	_time += delta
	if kind == SkillKind.Kind.FAKE_BOX:
		# Wrong way round compared with a real box (ItemBox spins +Y).
		_visual.rotation = Vector3(0.35, -_time * 1.6, 0.2)
		_visual.position.y = 1.0 + sin(_time * 3.4) * 0.22
	else:
		# Roots twitch; faster while still arming (the warning).
		var rate := 14.0 if age < arm_time else 5.0
		_visual.rotation.y = sin(_time * rate) * 0.12
		_visual.scale = Vector3.ONE * (1.0 + sin(_time * rate * 0.5) * 0.06)
	if age > lifetime - 0.6:
		scale = Vector3.ONE * clampf((lifetime - age) / 0.6, 0.05, 1.0)
