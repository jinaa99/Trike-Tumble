class_name BananaPeel
extends Node3D
## A banana peel lying on the road. Any racer driving over it slips (the
## dropper only after it is armed). ItemManager detects and resolves it.

var peel_id := 0
var dropper_id := 0
var age := 0.0


func _ready() -> void:
	var visual := ItemVisuals.instance(ItemVisuals.banana_mesh(), "Peel")
	visual.rotation.y = peel_id * 1.3
	add_child(visual)
	scale = Vector3.ONE * 1.4
