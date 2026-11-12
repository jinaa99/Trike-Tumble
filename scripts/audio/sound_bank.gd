class_name SoundBank
extends RefCounted
## Every sound in the game by name, synthesized once on first use (see
## SoundSynth; all original, no files). Components play these through their
## own AudioStreamPlayer(3D)s on the SFX or UI bus.
##
## `played` records every one-shot request (tests check audio triggers
## without listening; headless runs have no audio output).

const SFX_BUS := &"SFX"
const UI_BUS := &"UI"

static var _cache := {}
## Names of sounds requested so far (one-shots), oldest first.
static var played: Array[StringName] = []


static func get_stream(sound: StringName) -> AudioStreamWAV:
	if not _cache.has(sound):
		_cache[sound] = _build(sound)
	return _cache[sound]


## Notes the request (for tests) and returns the stream.
static func use(sound: StringName) -> AudioStreamWAV:
	played.append(sound)
	if played.size() > 2000:
		played = played.slice(1000)
	return get_stream(sound)


static func count(sound: StringName) -> int:
	return played.count(sound)


static func _build(sound: StringName) -> AudioStreamWAV:
	match sound:
		# --- Vehicle -------------------------------------------------------
		&"engine_loop":  # buzzy little motor; pitch follows speed
			return SoundSynth.loop(92.0, 46, 0.9, 0.12, 0.25, 0.42, 11)
		&"skid_loop":  # tyre scrub / drift hiss
			return SoundSynth.loop(310.0, 155, 0.2, 0.85, 0.75, 0.45, 12)
		&"wind_loop":  # speed rush
			return SoundSynth.loop(60.0, 30, 0.0, 1.0, 0.12, 0.35, 13)
		&"brake":
			return SoundSynth.sweep(1300.0, 900.0, 0.35, 0.22, 0.35, 9.0, 14)
		&"hit_soft":
			return SoundSynth.burst(0.16, 0.35, 0.55, 110.0, 15)
		&"hit_hard":
			return SoundSynth.mix([SoundSynth.burst(0.3, 0.55, 0.75, 70.0, 16),
					SoundSynth.sweep(420.0, 180.0, 0.35, 0.3, 0.0, 14.0, 16)])
		&"landing":
			return SoundSynth.burst(0.22, 0.2, 0.7, 60.0, 17)
		# --- Rider -----------------------------------------------------------
		&"eject":  # "whoa!" — a rising-falling wobbly voice blip
			return SoundSynth.mix([SoundSynth.sweep(320.0, 640.0, 0.22, 0.4, 0.05, 7.0, 18),
					SoundSynth.sweep(900.0, 300.0, 0.5, 0.25, 0.5, 0.0, 19)])
		&"fall_thud":
			return SoundSynth.burst(0.28, 0.25, 0.75, 55.0, 20)
		&"get_up":  # boing + dizzy chime
			return SoundSynth.mix([SoundSynth.sweep(150.0, 520.0, 0.3, 0.35, 0.0, 12.0, 21),
					SoundSynth.melody([[0.0, 0.25], [1568.0, 0.08], [1319.0, 0.08], [1568.0, 0.12]], 0.22, 0.1)])
		&"step":
			return SoundSynth.burst(0.07, 0.6, 0.35, 0.0, 22)
		&"step_snow":
			return SoundSynth.burst(0.11, 0.85, 0.3, 0.0, 23)
		&"mount":
			return SoundSynth.sweep(260.0, 700.0, 0.16, 0.35, 0.0, 0.0, 24)
		# --- Items -----------------------------------------------------------
		&"item_pickup":
			return SoundSynth.melody([[880.0, 0.07], [1175.0, 0.07], [1568.0, 0.14]], 0.5)
		&"item_throw":
			return SoundSynth.sweep(300.0, 900.0, 0.18, 0.45, 0.35, 0.0, 25)
		&"item_splat":
			return SoundSynth.sweep(220.0, 70.0, 0.28, 0.5, 0.9, 0.0, 26)
		&"item_punch":
			return SoundSynth.sweep(160.0, 520.0, 0.22, 0.55, 0.15, 0.0, 27)
		&"item_slip":
			return SoundSynth.sweep(900.0, 250.0, 0.35, 0.4, 0.2, 6.0, 28)
		&"item_turbo":
			return SoundSynth.sweep(200.0, 1400.0, 0.5, 0.45, 0.5, 0.0, 29)
		&"item_denied":
			return SoundSynth.melody([[330.0, 0.08], [247.0, 0.12]], 0.4)
		# --- Race ------------------------------------------------------------
		&"countdown":
			return SoundSynth.melody([[440.0, 0.18]], 0.45, 0.4, 0.6)
		&"go":
			return SoundSynth.mix([SoundSynth.melody([[880.0, 0.5]], 0.4, 0.4, 0.8),
					SoundSynth.melody([[1109.0, 0.5]], 0.25, 0.2, 0.8), SoundSynth.melody([[1319.0, 0.5]], 0.25, 0.2, 0.8)])
		&"finish":  # little fanfare
			return SoundSynth.melody([[523.0, 0.1], [659.0, 0.1], [784.0, 0.1], [1047.0, 0.35]], 0.45, 0.35, 0.5)
		&"victory":  # longer jingle for a podium place
			return SoundSynth.melody([[784.0, 0.12], [784.0, 0.12], [784.0, 0.12], [1047.0, 0.3], [0.0, 0.05],
					[932.0, 0.12], [1047.0, 0.12], [1175.0, 0.12], [1319.0, 0.5]], 0.42, 0.35, 0.6)
		&"results":  # soft chord for a finish off the podium / results screen
			return SoundSynth.melody([[523.0, 0.15], [659.0, 0.15], [784.0, 0.4]], 0.35, 0.2, 0.8)
		&"wipeout_horn":
			return SoundSynth.sweep(500.0, 160.0, 0.45, 0.3, 0.0, 10.0, 30)
		# --- UI --------------------------------------------------------------
		&"ui_click":
			return SoundSynth.melody([[1200.0, 0.04], [1600.0, 0.05]], 0.35, 0.2, 2.0)
		&"ui_hover":
			return SoundSynth.melody([[1800.0, 0.03]], 0.18, 0.1, 2.0)
		&"ui_back":
			return SoundSynth.melody([[1200.0, 0.04], [800.0, 0.06]], 0.35, 0.2, 2.0)
	push_warning("SoundBank: unknown sound %s" % sound)
	return SoundSynth.melody([[440.0, 0.05]], 0.1)
