class_name TrikeInput
extends RefCounted
## Per-physics-tick control state for one player (riding or on foot).
##
## Kept as plain data so it can come from the local keyboard, an AI, the test
## suite or (later) the network, without the trike knowing the difference.

## 0..1
var throttle := 0.0
## 0..1. Brakes while rolling forward, reverses when nearly stopped.
var brake := 0.0
## -1 (left) .. 1 (right)
var steer := 0.0
## Drift / handbrake held.
var drift := false
## One-shot reset request; the trike clears it after handling.
var reset_pressed := false
## One-shot interact request (E). Used on foot to get back on the trike.
var interact_pressed := false
## One-shot "use held item" request (Q). ItemManager consumes it.
var use_item_pressed := false
## Optional world-space on-foot direction (length 0..1) for AI and network
## input. When non-zero it replaces the camera-relative WASD movement.
var move_direction := Vector3.ZERO


func clear() -> void:
	throttle = 0.0
	brake = 0.0
	steer = 0.0
	drift = false
	reset_pressed = false
	interact_pressed = false
	use_item_pressed = false
	move_direction = Vector3.ZERO
