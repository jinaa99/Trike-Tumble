# Development progress — Fun-First Gameplay V2

Log for the overhaul in `docs/FUN_FIRST_GAMEPLAY_V2.md` (started
2026-11-13). "Tested" = an automated check exists and passes. "Written" =
code exists, no dedicated check. "Not done" = not started.

Baseline before any change: full suite 740/740, network suite green,
hard-AI times 5:12–5:25.

## Status by phase

| Phase | Content | State |
|---|---|---|
| A | Investigation (3 read-only specialist reviews), design doc, baseline | Done |
| B | Skills, slipstream, near miss, perfect drift, tricks, landings, awards | Tested (`fun` group, network `skills` scenario) |
| C | Forest Rush: 7 falling trees, mud 4 % → 11 %, S-bends, 2nd hairpin pair | Tested (`fun`, `map`, timed races, AI probes) |
| D | Rocky Canyon: rockslides, resting rocks, tighter cliff corners, narrows + barricade | Tested (`map`, timed races, AI probes) |
| E | Snow Slide: ice physics (per-wheel), ice ~6 % → 12.8 %, frozen lake, windy bridges | Tested (`fun` ice measurements, `map`, timed races) |
| F | Personality: reaction faces/gestures, blink, per-rider taunt, voice pitch, barks | Tested (taunt/reaction/bark checks). **New models/rigs not done** (no Blender) |
| G | Wheel-based audio (no engine), skill/hazard sounds, per-map music mood | Tested (levels, triggers, no clipping). **Not listened to** |
| H | HUD skill slot, slipstream meter, perfect bands, awards screen, rider picker (lobby, online and offline; Settings), surface readout, rebindable keys, protocol 3, trike engine part replaced, performance re-measured | Tested |

## Ice investigation (Phase E)

Measured, not guessed (`tests/fun_tests.gd` `_test_ice_physics`):

- Before: ice only scaled the sideways-slip decay rate (grip 12 × 0.32 =
  3.8/s, still more than a road drift's 2.6/s); it did not touch cornering
  force, braking or the yaw controller, and the grip of the three wheels was
  a plain average. All ice bands were on near-straight road, where nothing
  needs grip. That is why ice felt like snow.
- After (measured, full slab, 15 m/s, full lock for 1.2 s): direction of
  travel turned 88° on dirt, 87° on snow, 45° on ice; slide angle 55° on
  ice vs 9° on snow; sideways speed 12.7 vs 2.7 m/s. Stopping from 15 m/s:
  4.6 m dirt, 4.6 m snow, 10.5 m ice. From 8 m/s ice still turns 158° in
  2.5 s (controllable when slow).
- Per wheel, effective grip with 0/1/2/3 wheels on ice: 1.00 / 0.43 / 0.32 /
  0.22 (`surface_grip_min_bias` 0.6 leans toward the slipperiest wheel).
- The development readout: Settings › Player › "Show wheel surfaces and
  grip" (front / rear-left / rear-right surface, grip, speed, cornering and
  brake factors, sideways speed, slide angle).

## Test results (2026-11-14)

| Run | Result |
|---|---|
| Full suite (`test_runner.tscn`) | 933 passed, 0 failed (before the last two Snow Slide ice edits; final rerun below) |
| Strict warnings-as-errors | 933 passed, 0 failed (same build) |
| `--only=map` after the last Snow edits | 194 passed, 0 failed |
| `--only=fun` | 176 passed, 0 failed |
| Network suite (all old scenarios, protocol 3) | 50 passed, 0 failed |
| Network `skills` scenario (3 peers, Forest Rush) | 11 passed, 0 failed |
| Timed races (`map_test_runner`), Snow Slide after the fix, twice | 14/14 and 14/14 |
| AI probes, hard, 3 maps × seeds 0 / 1234567 / 99887766 | all finish, 0 resets, ≤ 1 wipeout |
| AI probes, Snow Slide five-bot mixed and hard fields | all finish, 0 resets |
| Visual captures | `docs/screenshots/fun_first_v2/` (tree warning/falling/down, rockslide, rubble, frozen lake, ice hairpin) |
| Performance (`perfmap perfcanyon perfsnow`, M4, 5 racers) | 120 fps average everywhere, worst frame 34 ms |

Final rerun after the last Snow Slide edits (2026-11-14): full suite
**932 passed, 0 failed** (one check fewer: one ice band, one per-band check);
timed races on all three maps **42 passed, 0 failed**.

Hard-AI full-route times (seed 0, final run): Forest 5:53, Canyon 5:07, Snow 5:22.

## Problems found and fixed during the work

- Air nose-down lean dipped the front wheel into the far lip of the Snow
  Slide gap (rider thrown off) → nose-down only while falling.
- A backflip counted as "overturned" and ejected the rider mid-air → tricks
  are exempt from the tilt rule.
- `FallingTree` scaled its physics body, which also reset its position →
  only the visual child scales.
- Forest AI wiped out 42 times on the first tree layout → trees publish
  avoidance points from the first warning, 4.2 m minimum free lane.
- Snow AI tipped over or spun backwards at the hairpins after new ice bands
  → AI plans braking with weaker deceleration on ice, never drifts on ice;
  one band removed, one moved 20 m earlier.
- Map tests depend on authored hazard phases → race scenes in tests pin
  the seed to 0.

## Continue from here (next steps, in order)

1. **Owner playtest** with `docs/FUN_FIRST_PLAYTEST.md`. Tune in
   `default_skill_config.tres`, `default_trike_config.tres` and the map
   scenes, not in code.
2. Done 2026-11-14: performance re-measured; lobby rider picker (online
   too, protocol 3 not yet released, so no extra bump); the trike's engine
   part replaced by a bottle, the freewheel hub and turbo-bottle canisters.
   Network suite with all scenarios: 61 passed, 0 failed.
   Full suite in strict warnings-as-errors mode after all of it: 941
   passed, 0 failed.
   Then: a riding posture per rider (spine/neck only, IK error 0.000 m,
   tested) and a fix for two timer callbacks that reported "Lambda capture
   was freed" when a race was freed mid-effect. Full suite: 943 passed,
   0 failed, no such errors.
3. Character models: with Blender installed, proper rigs per
   `docs/ART_DIRECTION_BIBLE.md`; keep `Rider.react()` and the IK targets.
4. Per-map music tracks (CC0, licence check + ASSET_CREDITS) if the speed
   variation isn't enough.
5. Decide whether to delete the unused engine recordings.
6. Snow Slide: AI riders still sometimes tip over (allowed, no reset) on the
   landing after the 3215 m gap in five-bot packs. Look at it if players
   do too.
