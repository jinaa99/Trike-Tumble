# TRIKE TUMBLE — Audio design (Visual Overhaul V2)

Written 2026-11-12. Sources and licenses: `docs/ASSET_CREDITS.md`.

> **Not listened to.** This pass was built and checked by measurement
> (levels, envelopes, spectra, loop seams) and by automated tests. Nobody
> has heard the result yet. The first thing to do with this document is a
> headphone pass over the checklist at the end.

## 1. What changed

| Before | Now |
|---|---|
| Every sound synthesized in code (sine tones, sweeps, noise) | Vehicle, surface, rider and item sounds are recorded CC0 audio |
| One buzzy engine loop, pitch follows speed | Four recorded small engines crossfaded by simulated RPM, plus overrun and a throttle blip |
| One skid hiss | Rolling loop per surface, chassis rattle, skid loop, wind |
| No music | Menu theme and race track with crossfades and ducking |
| No limiter | Hard limiter on the Master bus |

Kept synthesized on purpose: countdown beeps, GO, finish fanfare, victory
jingle, results chord and UI clicks (short, musical, already in key with
each other).

## 2. Files

```
assets/audio/
  engine/       engine_idle, engine_low, engine_mid, engine_high (loops), engine_overrun (loop), engine_blip
  vehicles/     roll_dirt, roll_mud, roll_wood, roll_snow, roll_ice, roll_rattle, skid_loop (loops),
                brake_skid, hit_soft, hit_wood_1-2, hit_hard, landing, mud_splash
  character/    yelp_1-2, oof, ouch, body_fall, dizzy, mount, woohoo, cheer, step_dirt_1-4, step_snow_1-4
  environment/  wind_loop
  items/        item_pickup, item_throw, mud_bomb_splat, spring_punch, spring_bounce, banana_slip, turbo_boost, item_denied
  music/        menu_flowerbed_fields.ogg, race_sky_blue_street.ogg
```

All effects are mono 44.1 kHz WAV (Godot stores them QOA-compressed),
music is stereo Ogg Vorbis. Total about 11 MB.

Rebuilding the effects from the raw recordings:
`tools/asset_pipeline/fs_get.py` downloads the Freesound previews (and
refuses anything whose page is not CC0), `afconvert` turns them into WAV,
`tools/asset_pipeline/build_audio.py` cuts, loops and levels them. The
build is deterministic. Loops are made by picking the steadiest stretch of
a recording and equal-power crossfading its tail into its head; textures
with no steady stretch (mud, skid) are built granularly from short grains
and wrapped, so they loop by construction.

## 3. Code

| Piece | File | Role |
|---|---|---|
| `SoundBank` | `scripts/audio/sound_bank.gd` | Sound name → stream. `FILES` maps names to recorded takes (random take per play); names not in `FILES` are synthesized. `get_loop()` gives a seamless looping copy. `played` still records every request for tests |
| `SoundPlayer` | `scripts/audio/sound_player.gd` | One-shots (3D or flat), timer-freed |
| `TrikeAudio` | `scripts/vehicles/trike_audio.gd` | Engine layers, tyres, wind, impacts |
| `RiderAudio` | `scripts/rider/rider_audio.gd` | Yelp, thud + grunt, dizzy whistle, footsteps, mount |
| `ItemSounds` | `scripts/items/item_sounds.gd` | Item one-shots (unchanged API) |
| `RaceAudio` | `scripts/race/race_audio.gd` | Countdown, finish, podium cheer, music state |
| `MusicPlayer` | `scripts/audio/music_player.gd` (autoload) | Two decks on the Music bus, crossfade, duck |

Everything still reads synced state only, so network proxies sound the
same as local racers (the throttle blip and brake skid need real input and
play for locally simulated trikes only, as before).

## 4. Engine model

Recordings: a 250 cc single at idle, a quad bike, a petrol mower at working
speed and a small generator flat out. Each was level-matched to the same
RMS so crossfades keep constant loudness.

`revs` (0 = idle, ~1 = flat out) is simulated per trike:

```
target = lerp(0.06, 0.9, speed / max_speed)
       + throttle × throttle_revs (0.10)
       + boost_revs (0.14) while boosting
       + air_revs (0.16) with the throttle open and no wheel on the ground
revs  → target at rev_rise (7/s) going up, rev_fall (3.2/s) coming down
```

`revs` maps to a firing rate of 84–250 Hz. Each layer plays at
`rate / its own recorded rate`, clamped to a narrow band, and is audible
only inside its RPM band (equal-power crossfade with its neighbours):

| Layer | Recorded rate | Pitch range | Full between revs |
|---|---|---|---|
| idle | 90 Hz | 0.85–1.25 | 0.00–0.12 (gone by 0.30) |
| low | 93 Hz | 0.90–1.75 | 0.28–0.36 |
| mid | 138 Hz | 0.50–1.90 | 0.56–0.68 |
| high | 200 Hz | 0.80–1.45 | 0.88 and up |

So the timbre changes with revs (a different engine recording takes over)
instead of one sample being pitched across the whole range.

Load: `load` follows the throttle (boost counts as full). Loudness runs from
−15 dB (idle) to −4 dB (full load). Coasting at speed ducks the main layers
by up to 5 dB and fades in the **overrun** loop. A throttle stab from
coasting plays the **blip** on top (at most every 1.5 s). Without a rider
the engine fades out.

All values are `@export`s on `TrikeAudio`.

## 5. Tyres, surfaces and wind

| Surface | Rolling loop | Rattle | Skid |
|---|---|---|---|
| Dirt / road | gravel under bicycle tyres | full | gravel skid |
| Grass | gravel loop at 60 % | full | 60 % |
| Mud | wet squelch texture; splash on entering at speed and on landing | 40 % | full |
| Bridge planks | wheels on a wooden bridge | 130 % | full |
| Snow | snow crunch | 40 % | 60 %, lower pitch |
| Ice | ice scrape | 15 % | higher pitch |

Rolling volume and pitch follow speed; only the current surface's loop is
audible, the previous one fades out and pauses. Wind plays only around the
player's own trike, rises with the square of speed and jumps up while
airborne.

## 6. One-shots

- **Hits:** soft (three takes: a smack and two wood knocks) from 2.5 m/s,
  hard (plastic crash + thud) from 7 m/s; 0.25 s cooldown.
- **Landing:** thud scaled by airtime.
- **Rider:** yelp (two takes, pitched up for a cartoon voice) when thrown,
  body fall + grunt on the ground, slide whistle on getting up, zip on
  mounting, four footstep takes each for dirt and snow, a cheer on a podium
  finish.
- **Items:** pickup = two cork pops; throw = swoosh; mud bomb = splash +
  boot squelch, low-passed; spring punch = boing (two takes); banana peel =
  vocal slip; turbo = swoosh into a rising engine scream; denied = dull knock.

## 7. Music

- Menu and in-race lobby: *Flowerbed Fields* (−9 dB).
- Countdown, race and results: *Sky Blue Street* (−13 dB), ducked a further
  7 dB on the results screen.
- `MusicPlayer.play(track)` crossfades over 1.2 s; calling it with the
  current track does nothing. Both tracks loop.
- The Music slider in Settings drives the Music bus as before.

## 8. Mix

| Group | Level |
|---|---|
| Engine | −15 … −4 dB |
| Rolling | −8 dB at speed |
| Skid | −5 dB at full slide |
| Wind | −9 dB at top speed |
| Rattle | −17 dB |
| Hits | −5 dB soft, −1 dB hard |
| Race music | −13 dB |

Sources peak at −1 to −6 dBFS; the Master bus has a hard limiter at
−0.5 dB. 3D sounds use `unit_size` 8–10 and are cut off at 90–120 m.

## 9. Known limits

- Nobody has listened to it. Levels, the choice of takes and the engine
  crossover points are educated guesses and will need tuning.
- The engine recordings are different machines; the crossfades are level-
  and pitch-matched but the character change between layers may be audible.
- Source audio is Freesound's preview quality (MP3), not the lossless
  originals (those need a logged-in download).
- Remote players' crashes are still silent (unchanged).
- Headless runs print "resources still in use at exit" when a sound is
  still playing at quit (the dummy audio driver never releases playbacks).

## 10. Listening checklist

- [ ] Engine: idle → full throttle sweeps smoothly, no layer pops in or out
- [ ] Engine: lifting off at speed burbles; a throttle stab blips
- [ ] Five trikes together are not a wall of noise
- [ ] Each surface is recognisable: dirt, mud, planks, snow, ice
- [ ] Wind is present at top speed without masking the engine
- [ ] Rider yelps are funny, not annoying, after ten crashes
- [ ] Every item has its own sound and none is too loud
- [ ] Music sits under the effects on both tracks; loops have no gap
- [ ] Nothing clips with the Master slider at 100 %
