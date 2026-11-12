class_name TrikeAudio
extends Node3D
## Trike sounds (positional, SFX bus), from the trike's state only, so a
## network proxy sounds like the real thing:
## - engine loop: pitch and volume follow speed (and throttle when known),
##   a boost lifts it; idles low when stopped, fades out without a rider
## - skid loop: sideways tyre slip and drifting (softer on snow, a hiss on ice)
## - brake squeal, hits (soft/hard by impact strength), landing thumps
## Created by TrikeVisuals.

@export var engine_idle_pitch := 0.55
@export var engine_top_pitch := 1.65
@export var engine_idle_db := -16.0
@export var engine_full_db := -5.0
## Sideways slip (m/s) that gives a full skid; below `skid_min_slip` silence.
@export var skid_full_slip := 6.0
@export var skid_min_slip := 1.4
@export var skid_db := -4.0
## Impact strengths (m/s) for a soft and a hard hit sound.
@export var soft_hit := 2.5
@export var hard_hit := 7.0
@export var hit_cooldown := 0.25
## Shortest airtime (s) that thumps on landing.
@export var landing_min_air := 0.3

var trike: Trike
var engine: AudioStreamPlayer3D
var skid: AudioStreamPlayer3D
## Current skid intensity 0..1 (tests).
var skid_amount := 0.0

var _hit_timer := 0.0
var _brake_timer := 0.0


func setup(for_trike: Trike, visuals: TrikeVisuals) -> void:
	trike = for_trike
	engine = _loop(&"engine_loop", "Engine")
	skid = _loop(&"skid_loop", "Skid")
	if not trike.network_proxy:
		trike.impact.connect(_on_impact)
	visuals.landed.connect(_on_landed)


func _loop(sound: StringName, node_name: String) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = node_name
	player.bus = SoundBank.SFX_BUS
	player.stream = SoundBank.get_stream(sound)
	player.unit_size = 8.0
	player.max_distance = 90.0
	player.volume_db = -80.0
	add_child(player)
	player.play()
	return player


func _process(delta: float) -> void:
	if trike == null:
		return
	_hit_timer = maxf(_hit_timer - delta, 0.0)
	_brake_timer = maxf(_brake_timer - delta, 0.0)
	var speed_ratio := clampf(absf(trike.forward_speed) / trike.config.max_speed, 0.0, 1.3)
	var throttle := trike.input.throttle if not trike.network_proxy else clampf(speed_ratio * 1.2, 0.0, 1.0)
	var pitch := lerpf(engine_idle_pitch, engine_top_pitch, minf(speed_ratio, 1.0)) + throttle * 0.08
	if trike.boost_time > 0.0:
		pitch += 0.2
	engine.pitch_scale = lerpf(engine.pitch_scale, pitch, 1.0 - exp(-8.0 * delta))
	var engine_db := lerpf(engine_idle_db, engine_full_db, maxf(throttle, minf(speed_ratio, 1.0) * 0.7))
	if not trike.has_rider:
		engine_db = -40.0
	engine.volume_db = lerpf(engine.volume_db, engine_db, 1.0 - exp(-6.0 * delta))
	# Skid: tyre slip on the ground (drifting always counts).
	var target := 0.0
	if trike.is_grounded():
		var velocity := trike.get_motion_velocity()
		var slip := absf(velocity.dot(trike.global_basis.x))
		target = clampf((slip - skid_min_slip) / (skid_full_slip - skid_min_slip), 0.0, 1.0)
		if trike.is_drifting:
			target = maxf(target, 0.75)
		if trike.surface == TrackSurface.Kind.SNOW or trike.surface == TrackSurface.Kind.GRASS:
			target *= 0.6
	skid_amount = lerpf(skid_amount, target, 1.0 - exp(-10.0 * delta))
	skid.volume_db = linear_to_db(maxf(skid_amount, 0.0001)) + skid_db
	skid.pitch_scale = 1.35 if trike.surface == TrackSurface.Kind.ICE else (0.75 if trike.surface == TrackSurface.Kind.SNOW else 1.0)
	# Brake squeal: hard braking at speed (local trikes know the input).
	if not trike.network_proxy and trike.input.brake > 0.6 and trike.forward_speed > 9.0 and _brake_timer <= 0.0 \
			and trike.is_grounded():
		_brake_timer = 1.2
		SoundPlayer.play_at(self, &"brake", global_position, -6.0)


func _on_impact(strength: float, _velocity: Vector3) -> void:
	if strength < soft_hit or _hit_timer > 0.0:
		return
	_hit_timer = hit_cooldown
	var hard := strength >= hard_hit
	SoundPlayer.play_at(self, &"hit_hard" if hard else &"hit_soft", global_position,
			0.0 if hard else -4.0, randf_range(0.9, 1.1))


func _on_landed(airtime: float) -> void:
	if airtime >= landing_min_air:
		SoundPlayer.play_at(self, &"landing", global_position, lerpf(-8.0, 0.0, clampf(airtime / 1.5, 0.0, 1.0)))
