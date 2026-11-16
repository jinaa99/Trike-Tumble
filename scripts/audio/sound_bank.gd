class_name SoundBank
extends RefCounted
## Every sound in the game by name. Vehicle, surface, rider and item sounds
## are recorded CC0 audio (res://assets/audio, see docs/ASSET_CREDITS.md and
## docs/AUDIO_DESIGN.md); a name can have several takes, picked at random.
## The trike's wheel sounds, skill and hazard sounds, voice barks, race
## jingles and UI clicks are synthesized once on first use (SoundSynth).
## Components play these through their own AudioStreamPlayer(3D)s on the SFX
## or UI bus.
##
## `played` records every one-shot request (tests check audio triggers
## without listening; headless runs have no audio output).

const SFX_BUS := &"SFX"
const UI_BUS := &"UI"

const AUDIO := "res://assets/audio/"
## name -> recorded takes (paths under AUDIO, without ".wav").
const FILES := {
	# Tyre and surface loops (TrikeAudio). The wheel sounds themselves (hub
	# whirr, freewheel tick, sleeve hiss) are synthesized below: no engine.
	&"skid_loop": ["vehicles/skid_loop"], &"wind_loop": ["environment/wind_loop"],
	&"roll_dirt": ["vehicles/roll_dirt"], &"roll_mud": ["vehicles/roll_mud"], &"roll_wood": ["vehicles/roll_wood"],
	&"roll_snow": ["vehicles/roll_snow"], &"roll_ice": ["vehicles/roll_ice"], &"roll_rattle": ["vehicles/roll_rattle"],
	&"brake": ["vehicles/brake_skid"],
	&"hit_soft": ["vehicles/hit_soft", "vehicles/hit_wood_1", "vehicles/hit_wood_2"],
	&"hit_hard": ["vehicles/hit_hard"], &"landing": ["vehicles/landing"],
	&"mud_splash": ["vehicles/mud_splash"],
	# Rider.
	&"eject": ["character/yelp_1", "character/yelp_2"], &"fall_thud": ["character/body_fall"],
	&"oof": ["character/oof", "character/ouch"], &"get_up": ["character/dizzy"], &"mount": ["character/mount"],
	&"step": ["character/step_dirt_1", "character/step_dirt_2", "character/step_dirt_3", "character/step_dirt_4"],
	&"step_snow": ["character/step_snow_1", "character/step_snow_2", "character/step_snow_3", "character/step_snow_4"],
	&"cheer": ["character/woohoo", "character/cheer"],
	# Items.
	&"item_pickup": ["items/item_pickup"], &"item_throw": ["items/item_throw"], &"item_splat": ["items/mud_bomb_splat"],
	&"item_punch": ["items/spring_punch", "items/spring_bounce"], &"item_slip": ["items/banana_slip"],
	&"item_denied": ["items/item_denied"],
}

static var _cache := {}
static var _takes := {}
static var _loops := {}
## Names of sounds requested so far (one-shots), oldest first.
static var played: Array[StringName] = []


static func get_stream(sound: StringName) -> AudioStreamWAV:
	if not _cache.has(sound):
		_cache[sound] = _build(sound)
	return _cache[sound]


## Notes the request (for tests) and returns the stream: a random take when
## the sound has several.
static func use(sound: StringName) -> AudioStreamWAV:
	played.append(sound)
	if played.size() > 2000:
		played = played.slice(1000)
	var stream := get_stream(sound)
	var takes: Array = _takes.get(sound, [])
	if takes.size() > 1:
		return takes[randi() % takes.size()]
	return stream


## Seamlessly looping copy of a sound (tyre loops, wheel loops).
static func get_loop(sound: StringName) -> AudioStreamWAV:
	if not _loops.has(sound):
		var loop := get_stream(sound).duplicate() as AudioStreamWAV
		loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
		loop.loop_begin = 0
		loop.loop_end = int(loop.get_length() * loop.mix_rate)
		_loops[sound] = loop
	return _loops[sound]


## Drops every cached stream (when the game quits).
static func release() -> void:
	_cache.clear()
	_takes.clear()
	_loops.clear()


static func count(sound: StringName) -> int:
	return played.count(sound)


static func _build(sound: StringName) -> AudioStreamWAV:
	if FILES.has(sound):
		var takes: Array = []
		for file: String in FILES[sound]:
			var stream := load("%s%s.wav" % [AUDIO, file]) as AudioStreamWAV
			if stream:
				takes.append(stream)
		if not takes.is_empty():
			_takes[sound] = takes
			return takes[0]
		push_warning("SoundBank: missing audio files for %s, using the synthesized fallback" % sound)
	match sound:
		# --- Vehicle -------------------------------------------------------
		&"hub_whirr":  # bearings and spokes: an airy whirr, pitch follows wheel speed
			return SoundSynth.loop(172.0, 344, 0.12, 0.6, 0.42, 0.3, 11)
		&"freewheel_tick":  # ratchet pawls, 16 clicks a second at pitch 1
			return SoundSynth.ticks(16.0, 32, 3100.0, 0.5, 31)
		&"sleeve_slide":  # plastic rear sleeves skating sideways
			return SoundSynth.loop(520.0, 1040, 0.05, 0.94, 0.5, 0.36, 32)
		&"push_kick":  # a foot scuffing off the ground
			return SoundSynth.mix([SoundSynth.burst(0.14, 0.45, 0.45, 95.0, 33), SoundSynth.burst(0.09, 0.8, 0.2, 0.0, 34)])
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
		&"item_turbo":  # a bottle fizzing off: a rising whoosh, no engine
			return SoundSynth.mix([SoundSynth.sweep(220.0, 1500.0, 0.55, 0.42, 0.72, 0.0, 29),
					SoundSynth.burst(0.5, 0.85, 0.22, 0.0, 30)])
		&"item_denied":
			return SoundSynth.melody([[330.0, 0.08], [247.0, 0.12]], 0.4)
		# --- Skills and style (Fun-First V2) -----------------------------------
		&"skill_slingshot":  # a rising whoosh
			return SoundSynth.mix([SoundSynth.sweep(180.0, 1500.0, 0.55, 0.4, 0.75, 0.0, 41),
					SoundSynth.sweep(600.0, 1800.0, 0.3, 0.2, 0.1, 0.0, 42)])
		&"skill_bonk":  # spring twang + thump
			return SoundSynth.mix([SoundSynth.sweep(140.0, 620.0, 0.26, 0.5, 0.05, 22.0, 43),
					SoundSynth.burst(0.2, 0.3, 0.6, 85.0, 44)])
		&"skill_snare_drop":  # woody creak
			return SoundSynth.sweep(210.0, 120.0, 0.32, 0.4, 0.35, 16.0, 45)
		&"skill_snare_hit":  # roots snap shut
			return SoundSynth.mix([SoundSynth.burst(0.18, 0.5, 0.6, 95.0, 46),
					SoundSynth.sweep(520.0, 160.0, 0.3, 0.35, 0.3, 12.0, 47)])
		&"skill_fake_drop":
			return SoundSynth.melody([[784.0, 0.07], [659.0, 0.07], [523.0, 0.12]], 0.4)
		&"skill_fake_hit":  # party horn
			return SoundSynth.mix([SoundSynth.sweep(420.0, 880.0, 0.28, 0.4, 0.05, 30.0, 48),
					SoundSynth.melody([[0.0, 0.2], [1319.0, 0.06], [1047.0, 0.06], [784.0, 0.14]], 0.3)])
		&"skill_shield_up":  # soft fwoomp
			return SoundSynth.mix([SoundSynth.sweep(120.0, 360.0, 0.3, 0.45, 0.25, 0.0, 49),
					SoundSynth.melody([[0.0, 0.12], [659.0, 0.1], [988.0, 0.2]], 0.22, 0.1)])
		&"skill_shield_pop":  # pillow thump and a boing
			return SoundSynth.mix([SoundSynth.burst(0.22, 0.25, 0.7, 75.0, 50),
					SoundSynth.sweep(260.0, 700.0, 0.28, 0.35, 0.0, 18.0, 51)])
		&"style_near_miss":
			return SoundSynth.melody([[1175.0, 0.05], [1568.0, 0.05], [2093.0, 0.14]], 0.34, 0.15, 1.2)
		&"style_perfect":
			return SoundSynth.melody([[1047.0, 0.06], [1319.0, 0.06], [1568.0, 0.06], [2093.0, 0.22]], 0.38, 0.2, 0.9)
		&"style_trick":
			return SoundSynth.melody([[1319.0, 0.05], [1760.0, 0.12]], 0.3, 0.15, 1.2)
		&"style_rough":
			return SoundSynth.melody([[294.0, 0.09], [220.0, 0.16]], 0.38, 0.4)
		&"draft_on":
			return SoundSynth.sweep(500.0, 1100.0, 0.3, 0.25, 0.7, 0.0, 52)
		# --- Hazards -------------------------------------------------------------
		&"tree_rustle":  # leaves and startled wings
			return SoundSynth.mix([SoundSynth.burst(0.9, 0.75, 0.35, 0.0, 61), SoundSynth.burst(0.5, 0.9, 0.25, 0.0, 62),
					SoundSynth.sweep(1800.0, 2600.0, 0.25, 0.12, 0.2, 30.0, 63)])
		&"tree_crack":  # wood splitting
			return SoundSynth.mix([SoundSynth.burst(0.12, 0.9, 0.9, 140.0, 64), SoundSynth.sweep(260.0, 90.0, 0.7, 0.45, 0.45, 34.0, 65),
					SoundSynth.burst(0.5, 0.6, 0.4, 0.0, 66)])
		&"tree_crash":  # trunk hits the road
			return SoundSynth.mix([SoundSynth.burst(0.55, 0.22, 0.95, 48.0, 67), SoundSynth.burst(0.7, 0.8, 0.35, 0.0, 68)])
		&"rock_crack":
			return SoundSynth.mix([SoundSynth.burst(0.1, 0.85, 0.85, 180.0, 69), SoundSynth.burst(0.8, 0.35, 0.45, 60.0, 70)])
		&"rock_thud":
			return SoundSynth.mix([SoundSynth.burst(0.4, 0.2, 0.95, 42.0, 71), SoundSynth.burst(0.3, 0.6, 0.3, 0.0, 72)])
		&"log_rumble":
			return SoundSynth.mix([SoundSynth.burst(0.6, 0.18, 0.7, 70.0, 73), SoundSynth.sweep(180.0, 110.0, 0.5, 0.25, 0.3, 20.0, 74)])
		# --- Voice barks (pitched per character by RiderAudio) -----------------
		&"bark_laugh":  # "ha-ha-ha-ha"
			return SoundSynth.mix([SoundSynth.melody([[620.0, 0.09], [0.0, 0.03], [700.0, 0.09], [0.0, 0.03], [640.0, 0.09],
					[0.0, 0.03], [560.0, 0.14]], 0.4, 0.55, 1.6), SoundSynth.sweep(700.0, 520.0, 0.5, 0.12, 0.2, 9.0, 53)])
		&"bark_taunt":  # "nyah-nyah"
			return SoundSynth.melody([[660.0, 0.12], [520.0, 0.12], [700.0, 0.12], [520.0, 0.2]], 0.4, 0.6, 1.0)
		&"bark_heh":
			return SoundSynth.melody([[480.0, 0.08], [0.0, 0.03], [420.0, 0.14]], 0.34, 0.5, 1.4)
		&"bark_huh":  # rising "huh?"
			return SoundSynth.sweep(360.0, 760.0, 0.26, 0.4, 0.04, 6.0, 54)
		&"bark_grr":
			return SoundSynth.sweep(240.0, 200.0, 0.35, 0.34, 0.12, 26.0, 55)
		&"bark_hup":
			return SoundSynth.sweep(420.0, 620.0, 0.14, 0.4, 0.05, 0.0, 56)
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
