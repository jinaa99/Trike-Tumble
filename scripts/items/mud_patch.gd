class_name MudPatch
extends Node3D
## A temporary slippery mud puddle on the road (from a mud bomb). Purely an
## area: trikes inside it get slippery handling from ItemManager, nothing
## collides with it. Fades out at the end of its life.

var patch_id := 0
## Racer who threw it (see ItemConfig.mud_owner_grace).
var thrower_id := 0
var radius := 3.8
var time_left := 8.0

var _visual: MeshInstance3D
var _total := 8.0


func _ready() -> void:
	_total = maxf(time_left, 0.01)
	_visual = ItemVisuals.instance(ItemVisuals.mud_patch_mesh(), "Puddle")
	_visual.scale = Vector3(radius, 1.0, radius)
	_visual.position.y = 0.04
	_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_visual)
	scale = Vector3.ONE * 0.2
	create_tween().tween_property(self, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Ages the patch; false once it has dried up.
func tick(delta: float) -> bool:
	time_left -= delta
	if time_left < 0.6 and _visual:
		_visual.scale = Vector3(radius, 1.0, radius) * maxf(time_left / 0.6, 0.05)
	return time_left > 0.0


func get_age() -> float:
	return _total - time_left


func contains(point: Vector3) -> bool:
	var offset := point - global_position
	return absf(offset.y) < 2.0 and Vector2(offset.x, offset.z).length() <= radius
