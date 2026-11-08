# TRIKE TUMBLE — Testing

`$GODOT` = path to the Godot 4.7.2 binary
(on the owner's Mac: `~/Downloads/Godot.app/Contents/MacOS/Godot`).

## 1. Automated gameplay suite

```sh
$GODOT --headless --path . --import          # once, or after adding class_name scripts
$GODOT --headless --path . --fixed-fps 60 --scene res://tests/test_runner.tscn
```

`--fixed-fps 60` makes the simulation deterministic and faster than real
time (the whole suite takes seconds). Exit code 0 = all passed. Each check
prints `PASS`/`FAIL` with measured values.

Strict mode, which fails on any GDScript warning:

```sh
printf '[debug]\n\ngdscript/warnings/treat_warnings_as_errors=true\n' > override.cfg
$GODOT --headless --path . --fixed-fps 60 --scene res://tests/test_runner.tscn; rm override.cfg
```

### What the suite covers (143 checks)

| Area | Checks |
|---|---|
| Input map | all 8 actions exist with bindings (incl. `interact`); E is mapped to `interact` |
| Keyboard | real key events (W/S/A/D, arrows, SPACE, R, E) reach the input through `PlayerInputSource` |
| Suspension | 3 wheels down, upright, settles without bounce, no creep |
| Engine | 0→12 m/s in 1 s, top speed near config, upright at speed |
| Brakes | stop from ~78 km/h < 1.5 s, reverse works and is capped |
| Steering | turns both ways > 25° in 1 s, no tip-over, low slip |
| Drift | starts with SPACE + steer, slides > 12°, charges tiers, boost on release, boost adds speed |
| Handbrake | SPACE without steer slows, doesn't drift |
| Collision | can't pass through a wall, impact stops it, crates get knocked away |
| Recovery | standalone trike without a rider system (arena only): auto-recover when upside down; R reset; stuck (high-centered) detection. In the game, flips eject the rider instead (see Rider rows) |
| Main scene | track builds, spawns on road, holds still on slope, HUD km/h matches, camera behind, timer runs |
| Out of bounds | falling off the course respawns on the road |
| Pause | ESC action pauses and resumes |
| Visuals ↔ physics | visual wheels sit exactly on the physics wheels; gloves/boots stay on IK targets while steering and drifting |
| Scenery collision | scenery has colliders, none of them inside the road corridor |
| Rider: normal riding | accelerating, drifting, braking never eject |
| Rider: weak impacts | 18 km/h wall bump and smashing a crate don't eject |
| Rider: full loop | 65 km/h wall crash ejects; states EJECTED→RAGDOLL→GETTING_UP→ON_FOOT; no repeat ejection; rider flies clear; fall 1–2 s; get-up ~1 s; camera follows ragdoll then rider; trike never teleports and comes to rest; WASD camera-relative; walking doesn't drive the trike; E ignored at 6 m, prompt at 1.4 m; E mounts; hands back on bars; camera back on trike; no camera cuts; controls work again |
| Rider: overturn | flipping ejects; empty overturned trike isn't auto-recovered; mounting rights it without a respawn |
| Rider: no auto respawn | 10 s idle on foot: no respawn, no auto-mount, trike stays put |
| Rider: race scene | camera follows rider; race clock runs; HUD prompt shows/hides; R on foot = emergency recovery |
| Rider: real track crash | missing a corner into the barrier ejects; rider gets up on the road near the trike |
| Rider: attach_to lifecycle | attach before `_ready` deferred and completed; `impact` connected once; repeated calls no duplicates; switching trikes moves the binding and restores flip recovery; null rejected; freed trike released safely; re-attach works |
| Rider: real E key | real `InputEventKey` E outside the mount distance does nothing; inside it offers the prompt and mounts |
| Finish: mounted | riding across the line finishes 1st, time recorded, clock stops, exactly once even with extra crossings |
| Finish: after ejection | thrown before the line → empty trike crossing = pending (not finished) → still not finished on foot → remount confirms 1st; official time = confirmation time; exactly once |
| Finish: player-specific | each vehicle resolves to its owner; player 2's trike finishes only player 2; unregistered bodies ignored; player 1 then finishes 2nd |
| Full run | autopilot finishes the whole track with ≤ 3 respawns and **0 ejections** |

Last result (final-demo milestone 01): **143 passed, 0 failed**, zero GDScript
warnings in strict mode. Driving numbers are still identical to milestone 1
(autopilot run 49.2 s, 0 respawns, top 88 km/h, 3.8 s airtime).

## 2. Visual capture (renders the real game)

Needs a visible window (not headless). Captures inspection screenshots:

```sh
$GODOT --path . --fixed-fps 60 --always-on-top --resolution 1280x720 \
  --scene res://tests/visual_capture.tscn -- /some/output/dir [modes...]
```

Modes (default: all five):

| Mode | Output |
|---|---|
| `closeup` | trike front 3/4, side, rear 3/4, top; rider face; hands on grips |
| `overview` | aerial of the whole track (fog thinned for this shot only), start area, mid section |
| `drive` | 8 shots of an autopilot run with HUD, including a forced drift and boost |
| `pause` | pause menu |
| `eject` | wipeout sequence (thrown, flying, tumble, push-up, head shake, confused, running, prompt, mounting, riding again, dizzy close-up) plus a real corner crash on the track |
| `perf` | real-time frame rate, draw calls, primitives (run **without** `--fixed-fps`) |

Keep the window visible. On macOS a covered window may stop drawing, which
delays shots or returns stale frames (`--always-on-top` prevents this).

Reference screenshots: `docs/screenshots/milestone_02/` (1280×720),
`docs/screenshots/milestone_02/1080p/` (UI scaling check) and
`docs/screenshots/milestone_03/` (wipeout sequence).

Performance (milestone 2, MacBook Air M4 16 GB, Mobile renderer, 18 s of
driving): locked at the display's 120 fps at both 1280×720 and 1920×1080, worst
frame 11–12 ms, about 477 draw calls and 725k primitives per frame (shadow
passes included). Godot reports no GPU timings on Metal, so the true GPU
headroom is unmeasured.

## 3. Manual playtest checklist (needs a human)

Run `$GODOT --path .` (or press Play in the editor) and check:

- [ ] W/↑ accelerates, S/↓ brakes then reverses, A/D/←/→ steer
- [ ] Steering feels responsive but not twitchy at top speed
- [ ] SPACE + steer drifts; sparks turn blue, then orange; release gives BOOST
- [ ] SPACE alone slows you down like a handbrake
- [ ] Ramps launch you and landings feel OK
- [ ] Crashing into crates/cones/rocks/walls feels good, not sticky
- [ ] R resets onto the road (emergency recovery, works riding and on foot)
- [ ] Flipping over throws the rider off; the empty trike stays flipped until you get back on (E rights it)
- [ ] Driving off the edge respawns you on the road
- [ ] ESC pauses; Resume/Restart/Quit work with the mouse
- [ ] Camera stays stable and doesn't clip through walls or terrain
- [ ] The road edges (curbs, barriers) are easy to read at speed
- [ ] Gloves stay on the handlebar and boots on the footrests at full lock
- [ ] Chevron signs warn of sharp corners
- [ ] Speed HUD, timer and FINISH message look right (FINISH shows position, e.g. "1st")
- [ ] Finish edge case: crash into a barrier just before the finish line so the empty trike rolls over it → "Get back on to finish!" → run to the trike, press E → FINISH appears once, timer stops
- [ ] **Wipeouts:** crash head-on into a rock/barrier at speed → thrown off with a WIPEOUT!-style message
- [ ] Scraping barriers, hitting crates/cones and landing ramps do NOT throw you off
- [ ] Fall feels funny and short (about 1–2 s); get-up shows the head shake and dizzy stars
- [ ] On foot: W runs away from the camera, A/D strafe, S toward the camera; camera stays calm
- [ ] The trike rolls to a stop nearby; it never jumps to you
- [ ] [E] GET ON appears near the trike (not from far away); E hops you on, hands on the bars
- [ ] Flip the trike: rider falls off; getting back on rights the trike
- [ ] R while on foot puts you back on the road on your trike
- [ ] Whole wipeout costs only a few seconds; it never feels stuck
- [ ] Gamepad (if available): RT/LT throttle/brake, left stick steer, RB/B drift, Y reset, Start pause

Record tuning feedback in terms of `TrikeConfig` values where possible.
