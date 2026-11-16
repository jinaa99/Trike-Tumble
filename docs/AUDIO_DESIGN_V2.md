# Audio design V2 — a trike, not a motorbike

Supersedes the engine sections of `docs/AUDIO_DESIGN.md` (kept for
history). Code: `scripts/vehicles/trike_audio.gd`, `scripts/audio/`.

## The correction

The V1 trike sound was four petrol-engine recordings (250 cc enduro, quad
bike, mower, generator) crossfaded by a simulated RPM, plus a throttle blip
and an overrun burble. A drift trike has no engine. V2 removes every engine
sound and the RPM model.

- `SoundBank.FILES` no longer lists `engine_*` or `turbo_boost`. The WAV
  files are still in `assets/audio/engine/` and `assets/audio/items/` and
  still credited in `docs/ASSET_CREDITS.md`; they are simply unused. The
  owner can delete them (not deleted here: rule 6, never delete work
  without saying why — they could still be wanted for something else).
- The Turbo Bottle is now a synthesized fizz-and-whoosh.

## The trike layers

All positional (`AudioStreamPlayer3D`, SFX bus), all driven by state that
network proxies also have, all silent at standstill.

| Layer | Source | Driven by | Level | Pitch |
|---|---|---|---|---|
| Hub whirr | synthesized airy loop (`hub_whirr`) | wheel speed | −80 dB at rest → −13 dB at top speed | 0.55 → 1.8 |
| Freewheel tick | synthesized ratchet, 16 clicks/s at pitch 1 (`freewheel_tick`) | coasting (no push) or airborne, × wheel speed | up to −12 dB | 0.6 → 1.9 (≈10–30 clicks/s) |
| Rolling | CC0 recordings: `roll_dirt`, `roll_mud`, `roll_wood`, `roll_snow`, `roll_ice` | surface under the wheels × speed | up to −4 dB: **the main bed** | 0.75 → 1.25 |
| Skid | CC0 `skid_loop` | sideways slip, drifting | up to −5 dB | ice 1.35, snow 0.75 |
| Sleeve slide | synthesized plastic hiss (`sleeve_slide`) | drifting or sliding on ice | up to −12 dB | rises as the drift charges; higher on ice |
| Rattle | CC0 `roll_rattle` | speed × roughness (planks 1.3, dirt 1, mud/snow 0.4, ice 0.15) | up to −15 dB | 0.8 → 1.3 |
| Wind | CC0 `wind_loop` | speed², more in the air, boost or a tow (own trike only) | up to −8 dB | 0.85 → 1.25 |

One-shots: push-off scuff (throttle from a crawl), foot-brake skid, soft and
hard hits, landing thump, mud splash on entering mud and on landing in it.

The throttle (W) is the rider pushing and pumping: it quiets the freewheel
(the pawls stop ticking when the wheel is driven) and adds a scuff when
pushing off.

## Surface identity

| Surface | What you hear |
|---|---|
| Dirt | bicycle tyre on gravel (recording), rattle, freewheel |
| Mud | wet granular squelch (recording), splash on entry, little rattle |
| Wood | skateboard-on-bridge roll (recording), loud rattle |
| Snow | snow crunch (recording), muffled skid |
| Ice | ice scrape (recording), high skid, sleeve hiss on any slide, no rattle |

## Hazards, skills, characters

All synthesized (`SoundSynth`, deterministic): tree rustle, tree crack,
tree crash, rock crack, rock thud, log rumble; slingshot whoosh, bonk
twang, snare creak and snap, fake-box party horn, shield fwoomp and pop;
near-miss, perfect and trick chimes, rough-landing buzz, slipstream swish.

Voice barks (`RiderAudio.bark`): laugh, yelp, cheer, taunt, smug "heh",
confused "huh?", grumble, skill "hup". Each rider has a voice pitch (Zip
1.1, Pip 1.26, Bramble 0.94, Nutmeg 1.42, Rusty 0.78). Anti-spam: a
per-kind cooldown (1.2–5 s), 0.7 s between any two barks of one rider, and
at most two barks starting within 0.6 s in the whole scene.

## Music

Still the two CC0 tracks (menu and race). Each map now has a mood through
`TrackTheme.music_pitch` / `music_db`: Forest 1.04 (brighter), Canyon 0.97,
Snow 0.93 and −1.5 dB (calmer, colder). No new music was downloaded.
Separate per-map tracks would need new CC0 files (licence check and an
ASSET_CREDITS entry each).

## Tests

`tests/overhaul_tests.gd` `_test_wheel_audio` (replaces the engine layer
test): wheel layers exist, no engine recording or RPM model, silent at
rest, hub rises smoothly with speed and stays under the rolling bed,
freewheel ticks when coasting and not when pushing, loops are seamless and
never clip, sounds are positioned. `tests/polish_tests.gd` still checks
skids, landings and proxy sounds.

## Not verified

Whether it *sounds right* — a trike, not a toy or a hairdryer — needs ears.
Headless tests have no audio output.
