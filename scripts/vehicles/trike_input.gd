class_name TrikeInput
extends RefCounted
## Per-physics-tick control state for one trike.
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


func clear() -> void:
	throttle = 0.0
	brake = 0.0
	steer = 0.0
	drift = false
	reset_pressed = false
