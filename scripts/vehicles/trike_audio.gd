class_name TrikeAudio
extends Node3D
## Trike sounds (positional, SFX bus), from the trike's state only, so a
## network proxy sounds like the real thing. A drift trike is a big bicycle
## wheel, two small rear wheels in plastic sleeves and a rider: there is no
## engine here (docs/AUDIO_DESIGN_V2.md). Everything is driven by wheel
## speed, the ground and what the tyres are doing:
## - Hub whirr: bearings and the wind in the spokes; pitch and level follow
##   wheel speed. Silent at standstill (no idle sound of any kind).
## - Freewheel: the ratchet ticking while coasting, faster with speed; it
##   stops while the rider pushes (throttle) and clatters louder in the air.
## - Rolling: one recorded loop per surface (gravel, mud, planks, snow,
##   ice): the main bed of the sound.
## - Sleeve slide: the rear sleeves skating sideways in slides and drifts
##   (a recorded skid plus a plastic hiss that rises as a drift charges).
## - Frame rattle on rough ground, wind by speed and in the air.
## - One-shots: a push-off scuff, foot-brake skid, soft/hard hits, landing
##   thumps, mud splashes.
## Created by TrikeVisuals.

@export_group("Wheels")
## Hub whirr level (dB) at full speed and its pitch at rest / full speed.
@export var hub_db := -13.0
@export var hub_pitch := Vector2(0.55, 1.8)
## Freewheel tick level (dB) while coasting and its pitch range.
@export var freewheel_db := -12.0
@export var freewheel_pitch := Vector2(0.6, 1.9)
## How fast the heard wheel speed follows the real one (1/s).
@export var wheel_response := 9.0

@export_group("Tyres and wind")
## Sideways slip (m/s) that gives a full skid; below `skid_min_slip` silence.
@export var skid_full_slip := 6.0
@export var skid_min_slip := 1.4
@export var skid_db := -5.0
## Plastic sleeve hiss on top of the skid while drifting.
@export var sleeve_db := -12.0
@export var roll_db := -4.0
@export var rattle_db := -15.0
@export var wind_db := -8.0

@export_group("Impacts")
## Impact strengths (m/s) for a soft and a hard hit sound.
@export var soft_hit := 2.5
@export var hard_hit := 7.0
@export var hit_cooldown := 0.25
## Shortest airtime (s) that thumps on landing.
@export var landing_min_air := 0.3

const ROLL_SOUNDS := {
	TrackSurface.Kind.ROAD: &"roll_dirt", TrackSurface.Kind.GRASS: &"roll_dirt", TrackSurface.Kind.MUD: &"roll_mud",
	TrackSurface.Kind.WOOD: &"roll_wood", TrackSurface.Kind.SNOW: &"roll_snow", TrackSurface.Kind.ICE: &"roll_ice",
}

var trike: Trike
## The hub whirr (always running, silent at standstill).
var hub: AudioStreamPlayer3D
## Kept under its old name for callers and tests that read "the speed-pitched
## loop": it is the hub whirr now, not an engine.
var engine: AudioStreamPlayer3D
var freewheel: AudioStreamPlayer3D
var skid: AudioStreamPlayer3D
var sleeve: AudioStreamPlayer3D
## Current skid intensity 0..1 (tests).
var skid_amount := 0.0
## Heard wheel speed as a share of top speed, 0..1.3 (tests and docs).
var wheel_speed := 0.0
## Freewheel loudness 0..1 right now (tests).
var freewheel_amount := 0.0
var wind: AudioStreamPlayer3D
var rattle: AudioStreamPlayer3D
## Surface kind -> rolling loop player (created on first use).
var rolls := {}

var _hit_timer := 0.0
var _brake_timer := 0.0
var _push_timer := 0.0
var _last_throttle := 0.0
var _last_surface := TrackSurface.Kind.ROAD
var _rider_gain := 0.0


func setup(for_trike: Trike, visuals: TrikeVisuals) -> void:
	trike = for_trike
	hub = _loop(&"hub_whirr", "HubWhirr")
	engine = hub
	freewheel = _loop(&"freewheel_tick", "Freewheel")
	skid = _loop(&"skid_loop", "Skid")
	sleeve = _loop(&"sleeve_slide", "SleeveSlide")
	rattle = _loop(&"roll_rattle", "Rattle")
	wind = _loop(&"wind_loop", "Wind")
	if not trike.network_proxy:
		trike.impact.connect(_on_impact)
	visuals.landed.connect(_on_landed)


func _loop(sound: StringName, node_name: String) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = node_name
	player.bus = SoundBank.SFX_BUS
	player.stream = SoundBank.get_loop(sound)
	player.unit_size = 8.0
	player.max_distance = 90.0
	player.volume_db = -80.0
	player.attenuation_filter_cutoff_hz = 8000.0
	add_child(player)
	# Start each loop at a different point so five trikes never phase together.
	player.play(randf() * maxf(player.stream.get_length() - 0.1, 0.0))
	return player


func _process(delta: float) -> void:
	if trike == null:
		return
	_hit_timer = maxf(_hit_timer - delta, 0.0)
	_brake_timer = maxf(_brake_timer - delta, 0.0)
	_push_timer = maxf(_push_timer - delta, 0.0)
	var speed_ratio := clampf(absf(trike.forward_speed) / trike.config.max_speed, 0.0, 1.3)
	# Proxies have no input: assume the rider pushes while the trike gains speed.
	var throttle := trike.input.throttle if not trike.network_proxy else (0.0 if speed_ratio > 0.5 else 1.0)
	_update_wheels(delta, speed_ratio, throttle)
	_update_tyres(delta, speed_ratio)
	# Foot brake: hard braking at speed (local trikes know the input).
	if not trike.network_proxy and trike.input.brake > 0.6 and trike.forward_speed > 9.0 and _brake_timer <= 0.0 \
			and trike.is_grounded():
		_brake_timer = 1.2
		SoundPlayer.play_at(self, &"brake", global_position, -8.0, randf_range(0.92, 1.08))


## Hub whirr and freewheel tick from wheel speed. Nothing here simulates an
## engine: no revs, no idle, no gears.
func _update_wheels(delta: float, speed_ratio: float, throttle: float) -> void:
	wheel_speed = lerpf(wheel_speed, speed_ratio, 1.0 - exp(-wheel_response * delta))
	_rider_gain = lerpf(_rider_gain, 1.0 if trike.has_rider else 0.35, 1.0 - exp(-5.0 * delta))
	var turning := clampf(wheel_speed, 0.0, 1.0)
	# Hub: nothing at rest, a soft whirr that rises with the wheels.
	# A crawl under ~1 km/h (a trike settling on its springs) makes no sound.
	var hub_gain := pow(clampf((turning - 0.012) / 0.988, 0.0, 1.0), 0.7) * _rider_gain
	hub.volume_db = lerpf(hub.volume_db, maxf(linear_to_db(maxf(hub_gain, 0.0001)) + hub_db, -80.0), 1.0 - exp(-12.0 * delta))
	hub.pitch_scale = clampf(lerpf(hub_pitch.x, hub_pitch.y, wheel_speed), hub_pitch.x, hub_pitch.y * 1.25)
	# Freewheel: ticks while coasting or airborne, quiet while the rider pushes.
	var coasting := clampf(1.0 - throttle * 1.5, 0.0, 1.0)
	if not trike.is_grounded():
		coasting = 1.0
	var target := coasting * clampf(turning * 4.0, 0.0, 1.0) * lerpf(0.55, 1.0, turning)
	freewheel_amount = lerpf(freewheel_amount, target, 1.0 - exp(-8.0 * delta))
	freewheel.volume_db = lerpf(freewheel.volume_db,
			maxf(linear_to_db(maxf(freewheel_amount * _rider_gain, 0.0001)) + freewheel_db, -80.0), 1.0 - exp(-12.0 * delta))
	freewheel.pitch_scale = clampf(lerpf(freewheel_pitch.x, freewheel_pitch.y, wheel_speed), freewheel_pitch.x, freewheel_pitch.y * 1.2)
	# Pushing off from a crawl: a foot scuff (local trikes).
	if not trike.network_proxy and throttle > 0.7 and _last_throttle < 0.2 and _push_timer <= 0.0 and trike.has_rider \
			and trike.is_grounded() and speed_ratio < 0.5:
		_push_timer = 1.5
		SoundPlayer.play_at(self, &"push_kick", global_position, -9.0, randf_range(0.9, 1.15))
	_last_throttle = throttle


func _update_tyres(delta: float, speed_ratio: float) -> void:
	var grounded := trike.is_grounded()
	var surface := trike.surface
	# Skid: tyre slip on the ground (drifting always counts).
	var target := 0.0
	if grounded:
		var velocity := trike.get_motion_velocity()
		var slip := absf(velocity.dot(trike.global_basis.x))
		target = clampf((slip - skid_min_slip) / (skid_full_slip - skid_min_slip), 0.0, 1.0)
		if trike.is_drifting:
			target = maxf(target, 0.75)
		if surface == TrackSurface.Kind.SNOW or surface == TrackSurface.Kind.GRASS:
			target *= 0.6
	skid_amount = lerpf(skid_amount, target, 1.0 - exp(-10.0 * delta))
	skid.volume_db = linear_to_db(maxf(skid_amount, 0.0001)) + skid_db
	skid.pitch_scale = 1.35 if surface == TrackSurface.Kind.ICE else (0.75 if surface == TrackSurface.Kind.SNOW else 1.0)
	# Plastic sleeves skating: only in a real drift, rising as it charges; a
	# clear, higher scrape on ice.
	var sleeve_gain := skid_amount if (trike.is_drifting or surface == TrackSurface.Kind.ICE) else 0.0
	var charge := clampf(trike.drift_charge / maxf(trike.config.drift_boost_tier_times.y, 0.1), 0.0, 1.2)
	sleeve.volume_db = lerpf(sleeve.volume_db, maxf(linear_to_db(maxf(sleeve_gain, 0.0001)) + sleeve_db, -80.0), 1.0 - exp(-10.0 * delta))
	sleeve.pitch_scale = (1.3 if surface == TrackSurface.Kind.ICE else 0.9) + charge * 0.35

	# Rolling loop of the surface under the wheels; the others fade out.
	var rolling := clampf(speed_ratio * 1.25, 0.0, 1.0) if grounded else 0.0
	if not rolls.has(surface):
		rolls[surface] = _loop(ROLL_SOUNDS[surface], "Roll%d" % surface)
	for kind: int in rolls:
		var player: AudioStreamPlayer3D = rolls[kind]
		var gain := rolling if kind == surface else 0.0
		if surface == TrackSurface.Kind.GRASS:
			gain *= 0.6
		var db := linear_to_db(maxf(gain, 0.0001)) + roll_db
		player.volume_db = lerpf(player.volume_db, maxf(db, -80.0), 1.0 - exp(-9.0 * delta))
		player.pitch_scale = lerpf(0.75, 1.25, minf(speed_ratio, 1.0))
		player.stream_paused = player.volume_db < -70.0 and kind != surface
	# Chassis rattle: rough ground shakes the trike, ice and snow hardly do.
	var rough := 1.0
	match surface:
		TrackSurface.Kind.WOOD:
			rough = 1.3
		TrackSurface.Kind.SNOW, TrackSurface.Kind.MUD:
			rough = 0.4
		TrackSurface.Kind.ICE:
			rough = 0.15
	var rattle_gain := rolling * rough
	rattle.volume_db = lerpf(rattle.volume_db, maxf(linear_to_db(maxf(rattle_gain, 0.0001)) + rattle_db, -80.0), 1.0 - exp(-8.0 * delta))
	rattle.pitch_scale = lerpf(0.8, 1.3, minf(speed_ratio, 1.0))

	# Wind: only around the player's own trike; louder in the air.
	var wind_gain := 0.0
	if trike.input_source is PlayerInputSource and trike.has_rider:
		wind_gain = clampf(speed_ratio * speed_ratio * 1.1, 0.0, 1.0)
		if not grounded:
			wind_gain = minf(wind_gain * 1.5 + 0.1, 1.0)
		if trike.boost_time > 0.0 or trike.draft_factor > 0.5:
			wind_gain = minf(wind_gain * 1.35 + 0.08, 1.0)
	wind.volume_db = lerpf(wind.volume_db, maxf(linear_to_db(maxf(wind_gain, 0.0001)) + wind_db, -80.0), 1.0 - exp(-4.0 * delta))
	wind.pitch_scale = lerpf(0.85, 1.25, minf(speed_ratio, 1.0))

	# Driving into mud at speed: a splash.
	if surface == TrackSurface.Kind.MUD and _last_surface != TrackSurface.Kind.MUD and grounded and speed_ratio > 0.25:
		SoundPlayer.play_at(self, &"mud_splash", global_position, lerpf(-10.0, -2.0, minf(speed_ratio, 1.0)), randf_range(0.9, 1.1))
	_last_surface = surface


func _on_impact(strength: float, _velocity: Vector3) -> void:
	if strength < soft_hit or _hit_timer > 0.0:
		return
	_hit_timer = hit_cooldown
	var hard := strength >= hard_hit
	SoundPlayer.play_at(self, &"hit_hard" if hard else &"hit_soft", global_position,
			-1.0 if hard else -5.0, randf_range(0.9, 1.1))


func _on_landed(airtime: float) -> void:
	if airtime >= landing_min_air:
		SoundPlayer.play_at(self, &"landing", global_position, lerpf(-9.0, -1.0, clampf(airtime / 1.5, 0.0, 1.0)),
				randf_range(0.9, 1.05))
		if trike.surface == TrackSurface.Kind.MUD:
			SoundPlayer.play_at(self, &"mud_splash", global_position, -4.0)
