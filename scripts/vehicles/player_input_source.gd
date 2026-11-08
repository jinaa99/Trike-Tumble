class_name PlayerInputSource
extends Node
## Reads the local keyboard/gamepad (see Project Settings > Input Map) into a TrikeInput.


func poll(into: TrikeInput) -> void:
	into.throttle = Input.get_action_strength(&"accelerate")
	into.brake = Input.get_action_strength(&"brake")
	into.steer = Input.get_axis(&"steer_left", &"steer_right")
	into.drift = Input.is_action_pressed(&"drift")
	if Input.is_action_just_pressed(&"reset"):
		into.reset_pressed = true
	if Input.is_action_just_pressed(&"interact"):
		into.interact_pressed = true
