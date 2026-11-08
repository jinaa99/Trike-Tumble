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

### What the suite covers (68 checks)

| Area | Checks |
|---|---|
| Input map | all 7 actions exist with bindings |
| Keyboard | real key events (W/S/A/D, arrows, SPACE, R) reach the trike through `PlayerInputSource` |
| Suspension | 3 wheels down, upright, settles without bounce, no creep |
| Engine | 0→12 m/s in 1 s, top speed near config, upright at speed |
| Brakes | stop from ~78 km/h < 1.5 s, reverse works and is capped |
| Steering | turns both ways > 25° in 1 s, no tip-over, low slip |
| Drift | starts with SPACE + steer, slides > 12°, charges tiers, boost on release, boost adds speed |
| Handbrake | SPACE without steer slows, doesn't drift |
| Collision | can't pass through a wall, impact stops it, crates get knocked away |
| Recovery | auto-recover when upside down, R reset, stuck (high-centered) detection |
| Main scene | track builds, spawns on road, holds still on slope, HUD km/h matches, camera behind, timer runs |
| Out of bounds | falling off the course respawns on the road |
| Pause | ESC action pauses and resumes |
| Visuals ↔ physics | visual wheels sit exactly on the physics wheels; gloves/boots stay on IK targets while steering and drifting |
| Scenery collision | scenery has colliders, none of them inside the road corridor |
| Full run | autopilot finishes the whole track with ≤ 3 respawns |

Last result (milestone 2): **68 passed, 0 failed**, zero GDScript warnings
in strict mode. Driving numbers are identical to milestone 1 (autopilot run
49.2 s, 0 respawns, top 88 km/h, 3.8 s airtime): visual work did not change physics.

## 2. Visual capture (renders the real game)

Needs a visible window (not headless). Captures inspection screenshots:

```sh
$GODOT --path . --fixed-fps 60 --always-on-top --resolution 1280x720 \
  --scene res://tests/visual_capture.tscn -- /some/output/dir [modes...]
```

Modes (default: all four):

| Mode | Output |
|---|---|
| `closeup` | trike front 3/4, side, rear 3/4, top; rider face; hands on grips |
| `overview` | aerial of the whole track (fog thinned for this shot only), start area, mid section |
| `drive` | 8 shots of an autopilot run with HUD, including a forced drift and boost |
| `pause` | pause menu |
| `perf` | real-time frame rate, draw calls, primitives (run **without** `--fixed-fps`) |

Keep the window visible. On macOS a covered window may stop drawing, which
delays shots or returns stale frames (`--always-on-top` prevents this).

Reference screenshots: `docs/screenshots/milestone_02/` (1280×720) and
`docs/screenshots/milestone_02/1080p/` (UI scaling check).

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
- [ ] R resets onto the road; flipping over recovers automatically
- [ ] Driving off the edge respawns you on the road
- [ ] ESC pauses; Resume/Restart/Quit work with the mouse
- [ ] Camera stays stable and doesn't clip through walls or terrain
- [ ] The road edges (curbs, barriers) are easy to read at speed
- [ ] Gloves stay on the handlebar and boots on the footrests at full lock
- [ ] Chevron signs warn of sharp corners
- [ ] Speed HUD, timer and FINISH message look right
- [ ] Gamepad (if available): RT/LT throttle/brake, left stick steer, RB/B drift, Y reset, Start pause

Record tuning feedback in terms of `TrikeConfig` values where possible.
