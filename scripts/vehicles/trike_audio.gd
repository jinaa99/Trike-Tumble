class_name TrikeAudio
extends Node3D
## Trike sounds (positional, SFX bus), from the trike's state only, so a
## network proxy sounds like the real thing. Recorded CC0 audio (see
## docs/AUDIO_DESIGN.md):
## - Engine: four recordings of small petrol engines (idle, low, mid, high)
##   crossfaded by a simulated RPM. RPM follows road speed, rises with
##   throttle and boost and free-revs in the air; each layer is pitched only
##   inside its own narrow band, so the motor changes character with revs
##   instead of being one sample pitched up. Lifting off fades in an
##   overrun burble; a throttle stab adds a rev blip.
## - Tyres: a rolling loop per surface (gravel, mud, planks, snow, ice), a
##   chassis rattle, a skid loop for slides and drifts, wind at speed.
## - One-shots: brake skid, soft/hard hits, landing thumps, mud splashes.
## Created by TrikeVisuals.

@export_group("Engine")
## Firing-rate equivalent (Hz) at idle and at full revs.
@export var engine_idle_hz := 84.0
@export var engine_top_hz := 250.0
@export var engine_idle_db := -15.0
@export var engine_full_db := -4.0
## How fast revs rise and fall (1/s).
@export var rev_rise := 7.0
@export var rev_fall := 3.2
## Extra revs (0..1 scale) from an open throttle, a boost and airtime.
@export var throttle_revs := 0.1
@export var boost_revs := 0.14
@export var air_revs := 0.16
## Volume (dB) of the overrun burble when coasting at speed.
@export var overrun_db := -9.0

@export_group("Tyres and wind")
## Sideways slip (m/s) that gives a full skid; below `skid_min_slip` silence.
@export var skid_full_slip := 6.0
@export var skid_min_slip := 1.4
@export var skid_db := -5.0
@export var roll_db := -8.0
@export var rattle_db := -17.0
@export var wind_db := -9.0

@export_group("Impacts")
## Impact strengths (m/s) for a soft and a hard hit sound.
@export var soft_hit := 2.5
@export var hard_hit := 7.0
@export var hit_cooldown := 0.25
## Shortest airtime (s) that thumps on landing.
@export var landing_min_air := 0.3

## Layer name, the recording's own pitch (Hz), pitch limits, and the RPM band
## (0..1): silent below [0], full from [1] to [2], silent above [3].
const LAYERS := [
	[&"engine_idle", 90.0, 0.85, 1.25, [-1.0, 0.0, 0.12, 0.3]],
	[&"engine_low", 93.0, 0.9, 1.75, [0.1, 0.28, 0.36, 0.58]],
	[&"engine_mid", 138.0, 0.5, 1.9, [0.34, 0.56, 0.68, 0.88]],
	[&"engine_high", 200.0, 0.8, 1.45, [0.64, 0.88, 2.0, 3.0]],
]
const ROLL_SOUNDS := {
	TrackSurface.Kind.ROAD: &"roll_dirt", TrackSurface.Kind.GRASS: &"roll_dirt", TrackSurface.Kind.MUD: &"roll_mud",
	TrackSurface.Kind.WOOD: &"roll_wood", TrackSurface.Kind.SNOW: &"roll_snow", TrackSurface.Kind.ICE: &"roll_ice",
}

var trike: Trike
## The mid-range engine layer (always running; tests read its pitch).
var engine: AudioStreamPlayer3D
var skid: AudioStreamPlayer3D
## Current skid intensity 0..1 (tests).
var skid_amount := 0.0
## Simulated revs 0..1.2 (idle to flat out; tests and docs).
var revs := 0.1
## Engine layer players, in LAYERS order, and the overrun layer.
var layers: Array[AudioStreamPlayer3D] = []
var overrun: AudioStreamPlayer3D
var wind: AudioStreamPlayer3D
var rattle: AudioStreamPlayer3D
## Surface kind -> rolling loop player (created on first use).
var rolls := {}

var _hit_timer := 0.0
var _brake_timer := 0.0
var _blip_timer := 0.0
var _load := 0.0
var _last_throttle := 0.0
var _last_surface := TrackSurface.Kind.ROAD
var _engine_gain := 0.0


func setup(for_trike: Trike, visuals: TrikeVisuals) -> void:
	trike = for_trike
	for layer: Array in LAYERS:
		layers.append(_loop(layer[0], String(layer[0]).capitalize().replace(" ", "")))
	engine = layers[2]
	overrun = _loop(&"engine_overrun", "EngineOverrun")
	skid = _loop(&"skid_loop", "Skid")
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
	_blip_timer = maxf(_blip_timer - delta, 0.0)
	var speed_ratio := clampf(absf(trike.forward_speed) / trike.config.max_speed, 0.0, 1.3)
	var throttle := trike.input.throttle if not trike.network_proxy else clampf(speed_ratio * 1.2, 0.0, 1.0)
	_update_engine(delta, speed_ratio, throttle)
	_update_tyres(delta, speed_ratio)
	# Brake skid: hard braking at speed (local trikes know the input).
	if not trike.network_proxy and trike.input.brake > 0.6 and trike.forward_speed > 9.0 and _brake_timer <= 0.0 \
			and trike.is_grounded():
		_brake_timer = 1.2
		SoundPlayer.play_at(self, &"brake", global_position, -8.0, randf_range(0.92, 1.08))


func _update_engine(delta: float, speed_ratio: float, throttle: float) -> void:
	var grounded := trike.is_grounded()
	var boosting := trike.boost_time > 0.0
	# Revs: road speed, plus throttle, boost and free-revving in the air.
	var target := lerpf(0.06, 0.9, minf(speed_ratio, 1.0)) + throttle * throttle_revs
	if boosting:
		target += boost_revs
	if not grounded and throttle > 0.1:
		target += air_revs
	var rate := rev_rise if target > revs else rev_fall
	revs = lerpf(revs, target, 1.0 - exp(-rate * delta))
	_load = lerpf(_load, maxf(throttle, 1.0 if boosting else 0.0), 1.0 - exp(-9.0 * delta))
	# A throttle stab from coasting: a short rev blip on top (local trikes).
	if not trike.network_proxy and throttle > 0.7 and _last_throttle < 0.2 and _blip_timer <= 0.0 and trike.has_rider:
		_blip_timer = 1.5
		SoundPlayer.play_at(self, &"engine_blip", global_position, -10.0, lerpf(0.9, 1.3, minf(revs, 1.0)))
	_last_throttle = throttle

	var hz := lerpf(engine_idle_hz, engine_top_hz, clampf(revs, 0.0, 1.2))
	var master_db := lerpf(engine_idle_db, engine_full_db, clampf(maxf(_load, minf(speed_ratio, 1.0) * 0.55), 0.0, 1.0))
	# Coasting at speed: the main layers duck and the overrun burble comes in.
	var coast := (1.0 - _load) * clampf(speed_ratio * 1.6 - 0.15, 0.0, 1.0)
	master_db -= coast * 5.0
	_engine_gain = lerpf(_engine_gain, 1.0 if trike.has_rider else 0.0, 1.0 - exp(-5.0 * delta))
	var fade_db := linear_to_db(maxf(_engine_gain, 0.0001))
	for i in layers.size():
		var layer: Array = LAYERS[i]
		var band: Array = layer[4]
		var gain := _band_gain(revs, band[0], band[1], band[2], band[3])
		var player := layers[i]
		player.pitch_scale = clampf(hz / float(layer[1]), layer[2], layer[3])
		# Equal-power crossfade between neighbouring layers.
		var layer_db := linear_to_db(maxf(sqrt(gain), 0.0001)) + master_db + fade_db
		player.volume_db = lerpf(player.volume_db, maxf(layer_db, -80.0), 1.0 - exp(-14.0 * delta))
	overrun.pitch_scale = clampf(lerpf(0.75, 1.35, minf(revs, 1.0)), 0.7, 1.4)
	var overrun_target := linear_to_db(maxf(coast, 0.0001)) + overrun_db + fade_db
	overrun.volume_db = lerpf(overrun.volume_db, maxf(overrun_target, -80.0), 1.0 - exp(-8.0 * delta))


## Trapezoid: 0 below `a`, rises to 1 at `b`, holds to `c`, falls to 0 at `d`.
static func _band_gain(x: float, a: float, b: float, c: float, d: float) -> float:
	if x <= a or x >= d:
		return 0.0
	if x < b:
		return (x - a) / (b - a)
	if x <= c:
		return 1.0
	return (d - x) / (d - c)


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
