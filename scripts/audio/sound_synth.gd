class_name SoundSynth
extends RefCounted
## Builds original sound effects in code (no audio files): tone melodies,
## pitch sweeps, noise bursts and seamless loops, as 16-bit mono WAV streams.
## Everything is deterministic (seeded noise), so every computer makes the
## same sounds.

const MIX_RATE := 22050


## Notes: [[frequency Hz (0 = rest), seconds], ...]. `harmonics` adds the
## 2nd/3rd partials (brighter), `decay` shapes each note's tail.
static func melody(notes: Array, volume := 0.5, harmonics := 0.3, decay := 1.0) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	for note: Array in notes:
		var frequency := float(note[0])
		var count := int(float(note[1]) * MIX_RATE)
		for i in count:
			var t := float(i) / MIX_RATE
			var k := float(i) / count
			var envelope := minf(1.0, i / 120.0) * pow(1.0 - k, decay)
			var wave := 0.0
			if frequency > 0.0:
				wave = sin(TAU * frequency * t) + harmonics * sin(TAU * frequency * 2.0 * t) \
						+ harmonics * 0.5 * sin(TAU * frequency * 3.0 * t)
			samples.append(wave * envelope * volume * 0.7)
	return to_wav(samples)


## Pitch sweep from `from_hz` to `to_hz` mixed with `noise` (0..1). `vibrato`
## (Hz) wobbles the pitch, for cartoon voices.
static func sweep(from_hz: float, to_hz: float, seconds: float, volume := 0.5, noise := 0.0, vibrato := 0.0,
		seed := 1) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	var count := int(seconds * MIX_RATE)
	var phase := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in count:
		var k := float(i) / count
		var hz := lerpf(from_hz, to_hz, k) * (1.0 + 0.06 * sin(TAU * vibrato * i / MIX_RATE))
		phase += TAU * hz / MIX_RATE
		var envelope := minf(1.0, i / 120.0) * pow(1.0 - k, 1.4)
		var tone := sin(phase) + 0.25 * sin(phase * 2.0)
		samples.append((tone * (1.0 - noise) + rng.randf_range(-1.0, 1.0) * noise) * envelope * volume)
	return to_wav(samples)


## Short noise burst through a one-pole low-pass (`brightness` 0 dull .. 1
## bright), optionally with a low sine `body` (Hz) for weight: thuds, hits,
## footsteps.
static func burst(seconds: float, brightness: float, volume := 0.6, body_hz := 0.0, seed := 2) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	var count := int(seconds * MIX_RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var low := 0.0
	var alpha := lerpf(0.04, 0.9, brightness)
	for i in count:
		var k := float(i) / count
		low += (rng.randf_range(-1.0, 1.0) - low) * alpha
		var envelope := minf(1.0, i / 40.0) * pow(1.0 - k, 2.5)
		var body := sin(TAU * body_hz * i / MIX_RATE) * (1.0 - k) if body_hz > 0.0 else 0.0
		samples.append((low * 1.6 + body * 0.8) * envelope * volume)
	return to_wav(samples)


## A seamless loop: `cycles` whole periods of a buzzy tone at `hz` (so it
## repeats without a click) plus filtered noise. Engines, skids, wind.
static func loop(hz: float, cycles: int, buzz: float, noise: float, brightness := 0.3, volume := 0.4, seed := 3) -> AudioStreamWAV:
	var count := roundi(cycles * MIX_RATE / hz)
	var samples := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var low := 0.0
	var alpha := lerpf(0.04, 0.9, brightness)
	for i in count:
		var phase := TAU * cycles * float(i) / count
		# Buzz: a few odd harmonics (square-ish, softened).
		var tone := sin(phase) + buzz * (sin(phase * 3.0) / 3.0 + sin(phase * 5.0) / 5.0 + sin(phase * 2.0) * 0.3)
		low += (rng.randf_range(-1.0, 1.0) - low) * alpha
		samples.append((tone * (1.0 - noise) + low * 2.0 * noise) * volume)
	# Cross-fade the first samples into the end so the noise loops cleanly.
	var fade := mini(400, count >> 2)
	for i in fade:
		var w := float(i) / fade
		samples[i] = samples[i] * w + samples[count - fade + i] * (1.0 - w)
	var stream := to_wav(samples.slice(0, count - fade))
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = count - fade
	return stream


## Several streams mixed into one (e.g. a thud under a boing).
static func mix(streams: Array[AudioStreamWAV]) -> AudioStreamWAV:
	var longest := 0
	for stream in streams:
		longest = maxi(longest, stream.data.size() >> 1)
	var samples := PackedFloat32Array()
	samples.resize(longest)
	samples.fill(0.0)
	for stream in streams:
		var data := stream.data
		for i in data.size() >> 1:
			samples[i] += float(data.decode_s16(i * 2)) / 32767.0
	return to_wav(samples)


static func to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, clampi(int(samples[i] * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream
