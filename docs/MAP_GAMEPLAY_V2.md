# Map gameplay V2

What changed on the three maps in Fun-First V2 (2026-11-13/14), and why.
All distances are along the built track (m); route segment edits used
equal-length, equal-turn swaps, so features further down the road moved by
less than a metre.

Hard-AI full-route times (`--only=map`, seed 0), before → after:

| Map | Before | After | Resets |
|---|---|---|---|
| Forest Rush | 5:22 | 5:53 | 0 |
| Rocky Canyon | 5:12 | 5:07 | 0 |
| Snow Slide | 5:22 | 5:22 | 0 |

All three stay inside the 5–10 minute window. Human races with five racers,
items and skills will be longer.

## Forest Rush — Wild Forest Chaos

Before: 2.4 km of fast sweepers at the end with nothing but crates and
ramps; every hazard sat between 2990 and 4250 m; mud 307 m (4 %).

Route:
- 800 m: one sweeper became an S (left 60°, right 100°, left 60°, R 29–48 m).
- 3270 m: a three-corner S-bend chain.
- 5640 m: a fast left-right flick.
- 6275 m: a second hairpin pair (130° and 125°), so the race ends technical.
- 6757 m: a sweeper split into straight-arc-straight.
- Corners of 50 m radius or tighter: 19 (test requires 18+).

Falling trees (`FallingTree`, prop kind `falling_tree`), 7 events from
alternating sides, periods 19–26 s, so a racer meets roughly one tree-fall
per 45–60 s of driving:

| m | Side | Covers | Note |
|---|---|---|---|
| 990 | left | 60 % | inside the new S-bend |
| 1340 | right | 50 % | one-lane block, on a mud stretch |
| 2470 | left | 72 % | before the first bridge |
| 4350 | right | 60 % | after the big jump; road trees on both edges |
| 5560 | left | 50 % | fast descent |
| 6130 | right | 70 % | before the late hairpins |
| 6850 | left | 60 % | just before the final mud bog |

Every tree leaves at least 4.2 m free at the far end; the warning (shake,
birds, red strip, crack, lean) lasts 2.3 s before it falls.

Mud: 12 zones, 837 m of road with mud on it (11.2 % of the route).
- Clean line beside the mud: 850, 1190, 3480, 3560, 4010, 4150, 5260, 5930,
  6630.
- Full-width: 3020 (the original crossing), 3745, 6935 (a bog, with a ramp
  at 6922 to hop the first stretch).
- Test: `_test_mud` checks that a side-lane trap has mud on one line and
  firm road on the other, measured at the wheels.

## Rocky Canyon — Rockslide Chaos

Route: three cliff corners tightened from R 130–140 m to R 57–69 m with
straights either side (570, 930, 1380 m); the finale (6535–6900 m) is now
two left-right flicks instead of sweepers.

Hazards:
- **Rockslides** (prop kind `rockslide`) at 1040, 3480 and 4420 m: three
  rocks 9 m apart, half a second apart, landing in different lanes; the
  middle one **rests** on the road for 3–3.5 s. A dust puff and a crack
  from the cliff 1.6 s before the first lands; landing shadows as before.
- **Resting rocks** at 1700, 4660, 5290 m land in different lanes (`land`
  0.1, 0.6, 0.0) and stay 3–3.5 s.
- **Rolling boulders**: two more, between the bridges (2690 m) and in the
  finale (7045 m); 6 in total.
- **Second narrows** 4205–4290 m (9.5 m wide, rock pillars), with a crate
  **barricade** (prop kind `barricade`) at 4250 m across the middle that
  breaks when hit; drive through it (slow) or squeeze past at an edge.

## Snow Slide — Frozen Mountain

The ice used to feel like snow. Measured cause and fix are in
`docs/DEVELOPMENT_PROGRESS.md` ("Ice investigation"); in short: ice grip
0.32 → 0.22, ice now also halves cornering force and weakens brakes to
40 %, mixed ground leans toward the slipperiest wheel, and the ice moved
into corners.

Route: an S at 753 m, an S chain at 5883 m, a second hairpin pair at
6495 m (135°/140°), a split sweeper at 6967 m. Hairpins 4 → 6.

Ice: 9 zones, 12.8 % of the drivable surface (band length × band width
plus the frozen bridges; test window 12–18 %).
- **Frozen lake** 5250–5510 m: the road widens to 20 m and is ice from
  barrier to barrier.
- **Ice descent** 6170–6310 m: full width, downhill into the S chain.
- Partial bands (≤ 60 % of the width, a snow lane stays): the original
  three around the bridges, 1655 m (inside of a windy bend), 1865 m
  (outside of the next one), 3320–3412 m (the run-in to the first hairpin;
  it ends 20 m before the hairpin so there is snow to scrub speed), 6820 m.
- Removed after testing: a band through the second hairpin (3505 m) and a
  band ending right at the first hairpin. In five-bot packs they spun AI
  riders backwards or tipped them over on the barrier, and the AI could not
  turn around on the 11 m hairpin road (found with `ai_probe ... mixed`).
- **Windy frozen bridges**: a new wind zone 2480–2810 m pushes left across
  both ice bridges.

AI: plans corner speed with 40 % of the normal cornering force when its
line crosses ice, and never drifts on ice.

## Tools

- `tests/tools/ai_probe.tscn -- forest|canyon|snow easy|medium|hard [seed]`:
  one AI drives a map alone and prints every wipeout, reset and respawn with
  its distance. Use it after any map edit, with and without a seed.
- Route edits were checked with a small Python script mirroring
  `TrackRoute.build_points` and the clearance rules of `tests/map_tests.gd`;
  `--only=map` remains the authority.
