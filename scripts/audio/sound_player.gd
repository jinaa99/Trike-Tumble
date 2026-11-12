class_name SoundPlayer
extends RefCounted
## One-shot sounds placed in the world or played flat, freed afterwards.


## A positioned one-shot at `position` (child of `parent`). Freed on a timer
## (headless runs never emit `finished`).
static func play_at(parent: Node, sound: StringName, position: Vector3, volume_db := 0.0, pitch := 1.0,
		unit_size := 10.0) -> AudioStreamPlayer3D:
	var stream := SoundBank.use(sound)
	if parent == null or not parent.is_inside_tree():
		return null
	var player := AudioStreamPlayer3D.new()
	player.bus = SoundBank.SFX_BUS
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.unit_size = unit_size
	player.max_distance = 120.0
	parent.add_child(player)
	player.global_position = position
	player.play()
	parent.get_tree().create_timer(stream.get_length() / maxf(pitch, 0.1) + 0.2).timeout.connect(player.queue_free)
	return player


## A flat (non-positional) one-shot, e.g. race countdown or UI.
static func play_flat(parent: Node, sound: StringName, volume_db := 0.0, bus := SoundBank.SFX_BUS) -> AudioStreamPlayer:
	var stream := SoundBank.use(sound)
	if parent == null or not parent.is_inside_tree():
		return null
	var player := AudioStreamPlayer.new()
	player.bus = bus
	player.stream = stream
	player.volume_db = volume_db
	parent.add_child(player)
	player.play()
	parent.get_tree().create_timer(stream.get_length() + 0.2).timeout.connect(player.queue_free)
	return player
