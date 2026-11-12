class_name MudBomb
extends Node3D
## A thrown mud bomb in flight. Its path is plain ballistics from the
## throw (origin, velocity, gravity), so every computer shows the same arc.
## Only the host decides where it lands or whom it hits (ItemManager).

var bomb_id := 0
var thrower_id := 0
var velocity := Vector3.ZERO
var gravity := 20.0
var age := 0.0
## Position before the latest step (for swept hit tests).
var previous_position := Vector3.ZERO

var _visual: MeshInstance3D


func _ready() -> void:
	_visual = ItemVisuals.instance(ItemVisuals.mud_bomb_mesh(), "Ball")
	add_child(_visual)


## Moves the bomb one tick along its arc.
func step(delta: float) -> void:
	previous_position = global_position
	velocity += Vector3.DOWN * gravity * delta
	global_position += velocity * delta
	age += delta
	if _visual:
		_visual.rotation += Vector3(7.0, 3.0, 0.0) * delta
