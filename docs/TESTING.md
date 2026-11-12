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

`-- --only=core|racers|flow|ui|net|items|polish|map` runs one group while you work on it
(`-- --only=map --map=rocky_canyon` runs one map).

### What the suite covers (682 checks)

`tests/test_runner.gd` runs everything. The racer/AI checks live in
`tests/racer_tests.gd` and the race-flow checks in `tests/race_flow_tests.gd`, the menu/UI
checks in `tests/ui_tests.gd`, in-process networking checks in
`tests/net_unit_tests.gd`, the item checks in `tests/item_tests.gd` and the Forest Rush map checks in
`tests/map_tests.gd`; they run last. The runner first switches
`GameSettings` to a test profile (`user://test_settings.cfg`, default
controls). Older tests load the race scene with
`RaceSession.skip_countdown = true` (they drive from the first tick as
before), and the finish tests' teleport helper credits the checkpoints it
jumps over. Their checks are unchanged.

| Area | Checks |
|---|---|
| Input map | all 9 actions exist with bindings (incl. `interact`, `use_item`); E is mapped to `interact` |
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
| Racers: one human | default race = 1 racer, HUMAN, id 1, owns the scene trike/rider, keyboard source, own progress, pole slot |
| Racers: five racers | 1 human + 4 AI; unique ids, slots, trikes, progress trackers; each rider bound only to its own trike; bodies and finish entries resolve to the owner; all spawn upright on the road, facing downhill, ≥ 2.5 m apart; AI wait on the grid; 6th racer and duplicate ids refused, no stray nodes |
| Racers: launch options | `race_five.tscn` = 1 human + hard/medium/medium/easy AI; `--ai=4 --difficulty=hard` = 4 hard AI |
| Racers: input isolation | AI trikes/riders have no `PlayerInputSource`; real W/D keys in the lobby move nobody and don't start the race; after GO real D/E keys reach only the human (AI brains paused to expose leaks); AI input never reaches the human trike |
| AI: one AI racer | race with a single AI and no human; holds still before the start; > 12 m/s 2 s after it |
| AI: steering | starting 35° off, steers the right way and lines up within 2 s, stays on the road |
| AI: path following | 25 s run: > 450 m, 100 % of ticks on the road, mean line error < 0.8 m, no backwards/respawn/crash; lines up with ramps and jumps them; lands < 20° off |
| AI: corner braking | sharp 90° bend on a custom track: easy, medium and hard all brake before it and finish cleanly; corner speed easy < medium < hard |
| AI: difficulty | config ordering (speed, reactions, look-ahead, drifting, steering noise); real 500 m times hard < medium < easy; hard holds its line more tightly than easy |
| Racers: vehicle collisions | trikes collide with trikes; a 4 m/s bump ejects nobody; a 20 m/s rear-end ejects the stationary rider |
| AI: eject/recover/mount | real crash into an unavoidable wall ejects the AI; EJECTED → RAGDOLL → GETTING_UP → ON_FOOT → MOUNTING → RIDING; walks to its trike; mounts with E (no emergency); no teleports; races on afterwards |
| AI: on-foot detour | wall between rider and trike: side-steps round it and mounts, no emergency recovery |
| AI: recovery | nose against the barrier at a standstill: reverses out and carries on, no reset |
| AI: full race | mixed 4-AI race around an idle human: all 4 finish 1st–4th, no resets/emergencies, the idle human isn't finished by anyone else, finished AI pull over and stop |
| Race flow: state machine | starts in LOBBY; illegal jumps refused; LOBBY → COUNTDOWN → RACING → FINISHED → RESULTS → LOBBY each announced; COUNTDOWN only to RACING or LOBBY |
| Checkpoints: every map | every track scene in `scenes/tracks/` has ≥ 3 strictly ordered checkpoints from after the start to the finish line, ≤ 122 m apart |
| Race flow: countdown | 5 racers wait in LOBBY; countdown 3, 2, 1, GO! one second apart, shown on the HUD; nobody moves during it even with throttle held; AI and clock wait for GO; after GO the player and the AI drive; the clock starts at GO |
| Checkpoints: order/reverse | pass in order while driving; reversing back over a checkpoint never raises progress and keeps passed checkpoints; driving through again doesn't re-register |
| Checkpoints: skipping | jumping past a checkpoint doesn't pass it and caps progress there; crossing the finish line then doesn't finish (no pending either); finish stays locked |
| Checkpoints: ejection | passed checkpoints survive the whole wipeout → remount loop |
| Positions: rules | more checkpoints beat more raw distance; 0.6 m lead doesn't flip (hysteresis), a clear lead does; finished racers first, in order |
| Race flow: five-racer race | autopiloted player + 4 AI to the end: positions always 1st–5th, consistent with track progress, change calmly; FINISHED when all done; each finishes once; order = confirmation order with ascending official times; duration = last time; results screen with 1st–5th names and times; clock stops |
| Race flow: pending finish | thrown off before the line → empty trike = pending; an AI finishes 1st meanwhile; remount confirms 2nd with the confirmation time |
| Race flow: finish timeout | others keep racing after the first finisher; race ends exactly `finish_timeout` later; unfinished = DNF; results show time / DNF / DNF |
| Menu: title | opens on the title; the five buttons; PLAY/HOST/JOIN/SETTINGS open their screens; ESC and Back return; QUIT quits (hooked) |
| Menu: map select | 3 cards (Forest Rush, Rocky Canyon, Snow Slide), all READY and selectable; previews are route maps drawn from the track data with the real length and drop; descriptions and characteristics; Continue → solo lobby |
| Menu: host | default port valid; 8 invalid ports disable Host Game with an error; limit 2–5; LAN info and status; Host Game → hosted lobby with the limit, transport HOSTING; Leave Lobby closes it |
| Menu: join | 10 invalid IPs and invalid/empty ports rejected with messages and no connection attempt; valid input reaches the transport and its error is shown; stays on the screen |
| Menu: lobby | count, host row with HOST/NOT READY; Start blocked until ready; Add AI to 5 then disabled; Remove AI; difficulty button cycles; Ready enables Start; Change Map round trip with preview; Leave Lobby |
| Menu: lobby → race → lobby | Start Race loads the map's scene; the race uses the lobby's names and AI difficulties; pause → Return to Lobby goes back to the same menu lobby |
| Settings | tabs; sliders set bus volumes (and mute at 0); resolution; fullscreen; Low/High quality change MSAA, 3D scale and sun shadows; name (empty → Player); everything reloads from the file like after a relaunch; Back |
| Settings: keys | rebinding with a real key press; new key drives the action; used key refused; ESC cancels; saved; Reset Controls |
| Pause menu | the five buttons; ESC pauses; Resume; Settings over the paused race and ESC back; Restart; Quit; Return to Lobby (direct launch → race lobby); key reminder |
| HUD | GET READY → STARTING → RACING chip; position + CP; empty item slot + use key (`[Q] USE ITEM`); held item shows; prompt/hint follow rebinding; speed and timer |
| Layout | every menu page (full 5-player lobby included) fits 1280×720; canvas_items/expand scaling |
| Net: lobby data | peer ids as player ids; duplicate names numbered; duplicate id refused; client mirror matches the host; own seat marked; AI seats sync |
| Net: snapshots | real snapshot valid; 7 kinds of malformed/impossible data rejected; across a respawn the proxy snaps |
| Net: jitter buffer | jittery 30 Hz data plays back smoothly at 60 fps; late packets dropped; extrapolation capped |
| Net: proxies | frozen kinematic, ignores input; rider proxy runs EJECTED → … → RIDING with the model leaving/returning to the seat; snapshot moves the trike and its visuals |
| Net: collisions | driving into a remote trike stops you with an impact (16.3); it doesn't move; a moving remote trike knocks you 8 m |
| Net: ENet hosting | real server; status shows the port; port really in use; host owns its racer; leaving shuts down; port reusable |
| Net: online menus | pause doesn't freeze the race; clients get Leave Game, no Restart; Race Again "Host decides…" |
| Items: roll | all four items come out of boxes; 4,000 rolls: last place gets 4.6× the leader's turbos, the leader 4× the bananas; consecutive rolls vary |
| Items: pickup | driving through a box at 23 m/s collects it with no slowdown (lowest speed in the next 0.5 s = pickup speed); one event; HUD shows the item; pickup sound; "+ ITEM" message; hint is `[Q]` |
| Items: inventory, respawn | standing in a box collects it; a second box doesn't overwrite the item and stays active ("HANDS FULL" shown); no respawn while a trike sits on the spot; respawn after the delay once clear (one event); an empty trike collects nothing |
| Items: turbo | no use inside the 0.35 s use delay; Q starts a 2.2 s boost; it ends after 2.20 s; speed up to 34 m/s; empty hands do nothing; no use while thrown off |
| Items: mud bomb | thrown as a projectile; hits the racer 18 m ahead (0.6 s); victim slips, is immune, stays on; puddle left; a trike in the puddle slips; puddle there until shortly before its time, then gone, slipperiness ends; a miss splats on the road ahead; the thrower is spared by its own fresh puddle, others aren't |
| Items: banana | dropped 2.6 m behind on the road; dropper safe while unarmed; another racer driving over it spins out (6.7 rad/s, 19.3 → 7.4 m/s), peel gone, stays on; spin-out over within 1.5 s; peels capped at 8 |
| Items: spring punch | hits the racer beside; knocks sideways 3.3 m (7.4 m/s), no ejection, moderate; point-blank throws the rider off; out of range = miss, item gone, nobody moves, "MISSED!"; an immune racer can't be hit |
| Items: host validation | simultaneous pickup of one box: first wins, one event; repeated request id ignored; can't use an item you don't hold; malformed and NaN requests rejected; far pickup and unknown box refused; an item is used once; no pickups after the race |
| Polish: riders | 5 racers with 5 helmet colors, jackets and helmet styles; each rider has its own materials; every look keeps gloves on the grips and boots on the footrests (IK error 0.000 m); 5 different silhouettes (helmet shape + accessory); 5 trike accent colors; re-applying a look adds no duplicate parts |
| Polish: faces, celebration | shocked → dizzy → own face through a fall; the mouth really changes; celebrating lifts a hand 0.61 m above the grip with a cheer, then the hands return to the grips (IK 0.000 m); crossing the finish starts it; finish fanfare + confetti for the local player |
| Polish: trike sounds/effects | engine pitch 0.55 → 1.51 with speed; wheel dust at speed; drift: skid sound (1.0) + skid marks; snow powder vs heavy dark mud; boost trail; landing thump + puff; crash sound + impact burst |
| Polish: rider sounds | yelp, thud, get-up boing, mount hop; footsteps while running (18) |
| Polish: race sounds | 3 countdown beeps + GO; results chord without podium, victory jingle on the podium; items share the bank |
| Polish: camera | small bumps don't shake; a big crash shakes ≤ 0.16 m (capped); gone within 0.5 s; landing dip 0.12 m and back; the player's crashes shake it |
| Polish: remote players | a remote drifting, boosting trike shows spray, skid marks, boost trail and sounds like it; a remote landing thumps and puffs |
| Polish: UI audio | UI bus with its own saved volume; buttons click |
| Items: event sync | events recorded on a host race applied to a client-mode race give identical items, boxes, peels, puddles; repeats and junk ignored; a client driving into a box only sends one request |
| Race flow: race again | 3 consecutive races: each reaches results; Race Again puts everyone back on the grid, riding, progress/checkpoints/finish cleared, locked, AI off, timer 0, results hidden, knocked crate restored, countdown restarts; Return to Lobby waits locked with the lobby screen; Start Race begins the countdown |

| Map: Forest Rush build | in the catalog as READY, 6.5–8 km, builds < 3 s headless (stage timings printed), 60 render/collision chunks, grid lookup = full scan on 400 probes |
| Map: route layout | tightest corner ≥ 18 m (21 m by data, 18.6 m measured), longest straight ≤ 160 m, downhill all the way (≤ 20 %), parts > 250 m apart along the route ≥ 90 m apart (147 m), hairpin legs ≥ 40 m (57 m) |
| Map: sections | 2 bridges, 6 mud stretches, boulders/road trees/falling logs, 12 m gap + kicker + 6 ramps, 9.5 m narrows, 3 overlooks, > 3,000 pines (10,602) |
| Map: spawns, checkpoints, items, recovery | 5 grid slots on solid road, ≥ 3.6 m apart, 5 racers settle upright; 30 ordered checkpoints ≤ 250 m apart on solid road; 45 item box points on road (the race places an active box on each, ≥ 400 m from the grid), ≥ 8 m from obstacles, none near the jump; 2,019 recovery points on solid road with no obstacle within 5 m; falling in the gap returns you before the run-up |
| Map: collision | 17,815 downward probes: no holes, the surface (dirt/mud/planks) matches the map; barriers on both sides everywhere except the gap (1,424 probes); 5,982 scenery/structure colliders, none in the road corridor |
| Map: driving | mud slows the trike (24 → 12.7 m/s, cap 13) and the road gives speed back; grass slope off-road top 15.5 m/s (cap 16.9); falling off the mountain respawns on the road; full-speed jump clears the ravine (take-off 24.5 m/s, landing hit 2.2, no eject); rolling off slowly drops in and respawns before the run-up; both bridges crossed on their planks with no bump > 4 |
| Map: falling logs | waits off the road, rolls across the center, pose depends only on race time, a parked trike gets hit (impact 7.5, pushed 5 m) |
| Map: AI | a hard AI drives the whole 7.45 km through all 30 checkpoints in order: 5:25.5, no resets |
| All maps (milestone 08) | every generic map check runs on Forest Rush, Rocky Canyon and Snow Slide: READY in the catalog, length, build < 3 s, chunks, route layout (radius, kinks, straights, grade, clearances), own sky, 5 grid slots, 30 checkpoints on solid road, item box points + boxes in the race, recovery points, no collision holes, surfaces match (road/snow, mud, ice, bridge decks), barriers everywhere, scenery off the road, off-road and falling off, every big jump cleared and landed, slow roll into the gap respawns before the run-up, every bridge crossed on its deck, every timed hazard kind (waits off road, crosses, race-time only, hits a parked trike), hard AI full route 5–10 min with no resets |
| Map: Rocky Canyon | 5 cliff stretches (2.5 km of rock wall), wall 20 m above the road and solid 1.7 m behind the barrier, a whole cliff road driven cleanly; 10 falling + 4 rolling rocks; 2 jumps + 6 ramps; 9.5 m narrows; 14 hairpins (tightest 19.1 m); 596+ rock spires, no pines; hard AI 5:11.6 |
| Map: Snow Slide | 5 ice bands each ≤ 55 % of the width, ice + frozen bridges ≈ 6 % of the route; snow road, ice band and ice bridge bodies; on ice the travel direction turns 6° vs 19° on snow (same steering), trike stays upright; snow descent driven cleanly at 23.7 m/s; 2 wind stretches, gusts up to 6 m/s² only inside them, a function of race time, push a rolling trike 0.8 m in 1.5 s; 29 snowmen, 5 snowbanks, 8 large ramps; 4,500+ snowy pines; hard AI 5:24.3 |

Last result (final-demo milestone 10, 2026-11-11): **682 passed, 0 failed**,
normal and strict (675 earlier + finish run-off on 3 maps + quick-race).
Final reports with error/warning counts: `docs/FINAL_DEMO_REPORT.md` §3.
Milestone 09: **675 passed, 0 failed**,
normal and strict (640 earlier + 35 polish checks). Milestone 08: **640 passed, 0 failed**,
normal and strict (all three maps' checks included). Previous, milestone 07: **514 passed, 0 failed**
(448 earlier checks with 2 key texts updated from F to Q, 64 item checks,
1 Forest Rush box check, `use_item` in the input-map check), zero GDScript
warnings in strict mode.

### Timed races on every map (~4 min)

Since milestone 08 `map_test_runner` races all three maps (`-- --map=ID`
for one). Actual completion times (2026-11-09, Godot 4.7.2, M4, items on in
the player race with seed 7):

| Map | mixed (H, M, M, E, H) | easy ×5 | hard ×5 | player race (simple driver + mixed AI) |
|---|---|---|---|---|
| Forest Rush | 5:24.8 / 5:25.1 · 5:36.0 / 5:36.4 · 6:41.7 | 6:40.5–6:47.7 | 5:24.4–5:28.9 | You 5:50.9 (4 wipeouts, 2 respawns) · H 5:23.0 · M 5:38.6 / 5:44.6 · E 6:45.2 |
| Rocky Canyon | 5:12.2 / 5:15.5 · 5:29.2 / 5:38.9 · 6:34.7 | 6:34.0–6:46.7 | 5:18.6–5:32.8 (1–3 wipeouts each) | You 5:19.4 (2 wipeouts, 1 respawn) · H 5:22.1 · M 5:27.6 / 5:30.3 · E 6:38.6 |
| Snow Slide | 5:24.3 / 5:26.2 · 5:36.4 / 5:36.9 · 6:34.2 | 6:33.7–6:41.0 | 5:24.3–5:28.4 | You 5:24.2 (1 wipeout) · H 5:27.0 · M 5:34.2 / 5:36.0 · E 6:34.2 |

All 42 checks passed (every racer finished through all 30 checkpoints, no AI
reset, every run 5–10 min), normal and strict. Rocky Canyon is the most
demanding (hard AIs wipe out 1–3 times on rocks and switchbacks). Not
measured: **human** times on any map.

### Forest Rush races (timed, ~80 s, milestone 06–07 detail)

```sh
$GODOT --headless --path . --fixed-fps 60 --scene res://tests/map_test_runner.tscn
```

Whole races on the full map, simulated (much faster than real time). Each
racer must finish through all 30 checkpoints without the AI getting stuck,
and every run must take 5–10 minutes. Report:
`user://map_tests/forest_rush_report.json`.

Actual completion times (2026-11-08, Godot 4.7.2, M4):

| Race | Racers and times |
|---|---|
| mixed (5 AI) | Hard 5:24.8 / 5:25.1 · Medium 5:36.0 / 5:36.4 · Easy 6:41.7 |
| easy (5 AI) | 6:40.5 – 6:47.7 (one wipeout) |
| hard (5 AI, dense pack) | 5:24.4 – 5:28.9 |
| player (real race scene) | simple player driver 5:22.7 (no drifting or boosts, steers around obstacles, one wipeout) · Hard 5:25.3 · Medium 5:36.2 / 5:38.5 · Easy 6:41.3 |

No AI needed a reset or emergency recovery in any race. Last result:
**14 passed, 0 failed** (normal and strict).

**Since milestone 07 the player race has items** (the AI-only races build
their own racers without the race scene, so they have none and their times
are unchanged). Its item rolls use a fixed seed (7; `-- --item-seed=N` tries
another, `--verbose` prints every item event). Over 16 seeds (2026-11-09):
every racer finished through all 30 checkpoints, no AI reset, times 5:22–6:41.
Per race about 33 pickups and 33 uses; hits are rare because the field
spreads out (0–2 banana slips, 0–2 mud bomb hits, 0–2 punch hits). Items
sometimes cost an AI 10–15 s through a crash after a slip. One earlier
*unseeded* run had a Medium AI press reset once (lost ~23 s); it could not be
reproduced with any of the 16 seeds. The suite's own run (seed 7, after the
mud bomb aim fix): You 5:50.9 (5 wipeouts in the field), Hard 5:23.0, Medium
5:38.6 / 5:44.6, Easy 6:45.2; 32 pickups, 3 banana slips, 1 bomb hit, 1 punch
hit; 14 passed, 0 failed (normal and strict).

Not measured: a **human** driving the whole map. A skilled player who
chains drift boosts may be somewhat faster than the simple driver (5:22.7).
A casual player with wipeouts will be slower. Please time a few real runs.

### Network suite (separate processes, ~4.5 minutes)

```sh
$GODOT --headless --path . --scene res://tests/net/net_test_runner.tscn          # all scenarios
$GODOT --headless --path . --scene res://tests/net/net_test_runner.tscn -- duo   # duo | rules | drop | five | forest | items | maps
```

It launches real game instances (`tests/net/net_peer.tscn`, headless, real
time, ENet on 127.0.0.1) as host and clients. They play through the real
code paths (GameSession, Net, RaceSession) with the autopilot, perform
scripted actions (wipeout, spoofed packets, checkpoint cheat, quitting,
host shutdown + re-host) and write JSON reports to `user://net_tests/`.

Scenarios:
- `duo`: 2 instances
- `rules`: capacity, timeout, invalid IP, duplicate id, mid-race join, host shutdown, rejoin
- `drop`: 3 players, one quits
- `five`: 5 players
- `forest`: 2 instances race on Forest Rush (the real map) for a minute
- `maps`: the host picks Rocky Canyon (2 instances), then Snow Slide (3):
  everyone loads the host's map with the same boxes and sky and races
- `e2e5` (not in the default run, ~6 min): **five real, independent
  instances** (no AI) play one whole race on Snow Slide: lobby + ready,
  the host's map choice, countdown, driving with obstacle avoidance,
  collisions, a forced wipeout + recovery, items, finishing order and times
  on every screen, then the host presses Race Again and everyone races
  again. The scripted driver presses R after 15 s on foot or 2 s stuck,
  like a player.
- `items`: 2 instances race through 30 shared item boxes for 40 s, using
  every item they get; the client also forges a request for the host's
  racer and replays an old request id

`duo`, `rules`, `drop` and `five` use the short test track (fast). `forest`
passes `--real-map`, so the peers load the scene the lobby's map asks for.

Last result (milestone 10, 2026-11-11): **50 passed, 0 failed**, normal and
strict, 0 ENet errors; `e2e5` (five real players): **9/9** (runs 2–4).
Milestone 09: **50 passed, 0 failed**, normal and strict, with
the new audio/effects running on every instance. Milestone 08: **50 passed, 0 failed** (44 earlier + 6 map-choice checks). Strict mode:
48/50 on the full run (the `drop` "remaining client finished" and the `five`
smoothness check missed on real-time timing); re-running those two scenarios
in strict mode: 11/11. These scenarios run in real time and are sensitive to
machine load. Details and what
is *not* tested: `docs/NETWORKING.md`.

Windowed two-instance run (screenshots in `docs/screenshots/milestone_online/`):

```sh
$GODOT --path . --scene res://tests/net/net_peer.tscn -- --role=host --name=Host --port=47990 --expect=2 --out=/tmp/h.json --shots=/tmp
$GODOT --path . --scene res://tests/net/net_peer.tscn -- --role=client --name=Guest --port=47990 --out=/tmp/c.json --shots=/tmp
``` Driving numbers are still identical
to milestone 1 (autopilot run 49.2 s, 0 respawns, top 88 km/h, 3.8 s
airtime). Mixed 4-AI race in the suite: hard 49.0 s, medium 51.7/51.9 s,
easy 61.8 s.

### Five-racer race (play it)

```sh
$GODOT --path . res://scenes/main/race_five.tscn            # 1 you + 4 AI (hard, medium, medium, easy)
$GODOT --path . -- --ai=4 --difficulty=hard                 # main scene, 4 hard AI (easy|medium|hard|mixed, --ai=0..4)
```

A second after loading, the countdown runs (3 · 2 · 1 · GO!); nobody moves
before GO. After the race: results screen → Race Again or Return to Lobby
(then Start Race). In the editor: open `scenes/main/race_five.tscn` and press
F6 (Run Current Scene), or set `ai_racer_count`/`ai_difficulty`/`auto_start`
on the Main node; finish timeout and countdown timing are on the
RaceController node.

## 2. Visual capture (renders the real game)

Needs a visible window (not headless). Captures inspection screenshots:

```sh
$GODOT --path . --fixed-fps 60 --always-on-top --resolution 1280x720 \
  --scene res://tests/visual_capture.tscn -- /some/output/dir [modes...]
# milestone 08 modes: canyon snow (screenshots, docs/screenshots/milestone_08/); perfcanyon perfsnow (no --fixed-fps).
# Measured on M4, 5 racers: all three maps 120 fps (vsync cap), worst frame 11–27 ms; Snow Slide ~1 M primitives.
```

Modes (default: all except `perf`/`perf5`):

| Mode | Output |
|---|---|
| `closeup` | trike front 3/4, side, rear 3/4, top; rider face; hands on grips |
| `overview` | aerial of the whole track (fog thinned for this shot only), start area, mid section |
| `drive` | 8 shots of an autopilot run with HUD, including a forced drift and boost |
| `pause` | pause menu |
| `eject` | wipeout sequence (thrown, flying, tumble, push-up, head shake, confused, running, prompt, mounting, riding again, dizzy close-up) plus a real corner crash on the track |
| `race5` | 5-racer race through the whole flow: lobby screen, countdown "3" on the grid, GO!, player view + chase view behind the last AI at 2.5/8/16/30 s, results screen, back in the lobby (part of the default set) |
| `menu` | every main-menu screen over the live background: title, map select, solo and hosted lobby, host, join (invalid + unavailable), all four settings tabs |
| `perf` | real-time frame rate, physics time, draw calls, primitives, nodes (run **without** `--fixed-fps`) |
| `perf5` | the same with 4 AI racers (not in the default set) |
| `forest` | Forest Rush, every section: aerial views, start grid with 5 racers, overlook, fast descent, hairpins, narrow rocks, bridge from the side and on the deck, mud, boulders, falling log mid-roll, BIG AIR arch, mid-air over the ravine, overlook view, final descent, finish arch, spectator stands |
| `perfmap` | 5 racers on Forest Rush: frame rate at 7 spots (start, hairpins, bridges, mud/logs, jump, final descent, finish), plus the map build time (run **without** `--fixed-fps`) |

Keep the window visible. On macOS a covered window may stop drawing, which
delays shots or returns stale frames (`--always-on-top` prevents this).

Forest Rush performance (final-demo milestone 06, M4, 1280×720, `perfmap`,
5 racers):

| Spot | fps | worst frame | physics | draw calls | primitives |
|---|---|---|---|---|---|
| start (5 together) | 119 | 29 ms (one hitch) | 1.34 ms | 800 | 726k |
| hairpins | 120 | 12 ms | 1.57 ms | 421 | 545k |
| bridges | 120 | 12 ms | 1.68 ms | 681 | 617k |
| mud and logs | 120 | 14 ms | 1.54 ms | 598 | 630k |
| jump | 120 | 12 ms | 1.42 ms | 551 | 648k |
| final descent | 120 | 12 ms | 1.77 ms | 517 | 640k |
| finish | 120 | 12 ms | 1.59 ms | 337 | 282k |

Before distant trees faded out, the start spot drew 1.36M primitives.
Windowed map build: about 1.6 s. Not measured: weaker GPUs and Windows.

Reference screenshots: `docs/screenshots/milestone_forest_rush/` (Forest
Rush, every section), `docs/screenshots/milestone_02/` (1280×720),
`docs/screenshots/milestone_02/1080p/` (UI scaling check),
`docs/screenshots/milestone_03/` (wipeout sequence) and
`docs/screenshots/milestone_ai/` (five-racer race).

Performance with five racers (final-demo milestone 02, M4, 1280×720, 18 s,
`perf` vs `perf5`): both locked at the 120 fps display cap; worst frame 11 →
12 ms; physics 0.68 → 1.24 ms per frame; draw calls 480 → 704; primitives
728k → 832k; nodes 992 → 1,760. Milestone 03 (checkpoints + positions every
tick): `perf5` still 120 fps, worst frame 12 ms, physics 1.40 ms. Headless, the slowest frame of the full
5-racer race in the test suite was 1.8 ms.

Performance (milestone 2, MacBook Air M4 16 GB, Mobile renderer, 18 s of
driving): locked at the display's 120 fps at both 1280×720 and 1920×1080, worst
frame 11–12 ms, about 477 draw calls and 725k primitives per frame (shadow
passes included). Godot reports no GPU timings on Metal, so the true GPU
headroom is unmeasured.

## 3. Manual playtest checklist (needs a human)

### Audio, animation and polish (final demo milestone 09)

**Remaining visual/audio defects (found while testing, not fixed):**
- Performance hitch: in 2 of 4 windowed Snow Slide perf runs one frame took
  ~1 s, at a different spot each time (jump / frozen lake); the other runs
  were clean (worst 21 ms). That run also jumped between 60 and 145 fps,
  so macOS window throttling is likely, but a one-time shader compile the
  first time an effect appears can't be ruled out. Needs a check while
  really playing (and on Windows).
- Snow Slide renders ~1 M primitives (snow-cap layers): fine on the M4
  (120 fps), unmeasured on weaker GPUs.
- The rider is still a procedural model (no skinned mesh); there is no
  item-throw or hit-flinch animation, and the run cycle is the milestone 3
  one.
- Remote players' crashes make no hit sound or impact burst on other
  screens (proxies don't report impacts; landings, skids, engine and
  boost do play).
- The drift dust from milestone 2 is large when it passes close to the
  camera during a sharp drift.
- Grass tufts are subtle (fade out beyond 110 m); the environment pass was
  deliberately light to keep the road readable.
- No music. Sounds are simple synth tones: they need a listening test.
- Capture tool: running the `forest` mode and then `canyon` in one session
  hangs (each mode works on its own); run modes in separate processes.

Measured (windowed, M4, 5 racers): Forest Rush, Rocky Canyon and Snow Slide
120 fps at every spot except the hitch above; worst frames otherwise 11–31 ms.

Screenshots: `docs/screenshots/milestone_09/` (riders, faces, expressions,
celebration, effects, the three maps, menus, a two-player online session).

- [ ] Listen with headphones: engine, skid/drift, brake, crashes, landings feel right and aren't annoying over 6 minutes
- [ ] Rider sounds: the "whoa!", thud, dizzy boing, footsteps (crunch on snow), mount hop
- [ ] Countdown beeps + GO, finish fanfare, victory jingle, results chord, menu clicks
- [ ] Volume sliders (Master, Music, Sound effects, Menu sounds) each work and are saved
- [ ] The five riders are easy to tell apart in a pack (also from behind)
- [ ] Faces: shocked when thrown, dizzy getting up, the cheer at the finish
- [ ] Celebration after finishing looks fun and the hands go back to the bars
- [ ] Wheel spray/snow powder/mud splash, skid marks and boost trail never hide the road ahead
- [ ] Camera shake on crashes feels punchy but never nauseating; landings dip nicely
- [ ] Online: the other players' riders look right and their effects/sounds play

### Rocky Canyon and Snow Slide (final demo milestone 08)

Play them: PLAY → pick the map → Start Race, or
`$GODOT --path . res://scenes/main/rocky_canyon.tscn` / `snow_slide.tscn`.
Screenshots of every section: `docs/screenshots/milestone_08/`.

Rocky Canyon:
- [ ] Time a full run (target 5–10 min); it should feel harder than Forest Rush, not unfair
- [ ] The cliff walls read clearly; the barrier on the cliff side never feels like a trap
- [ ] Falling rocks: you notice the shadow in time and can steer around it
- [ ] Rolling rocks are visible early enough; getting hit feels fair
- [ ] Switchbacks are tight but drivable at your speed (14 hairpins)
- [ ] Both canyon bridges, the rock narrows and both big jumps feel good
- [ ] The red-rock look, spires and warm sky look good; nothing floats or clips

Snow Slide:
- [ ] Time a full run (target 5–10 min)
- [ ] The snow road feels a little looser than dirt but fully controllable
- [ ] Ice patches are easy to see; there is always a grippy line beside them
- [ ] Frozen bridges are slippery but straight enough to cross calmly
- [ ] Wind: windsocks and blowing snow warn you; gusts push but never feel cheap
- [ ] Snowmen and snowbanks are fun to dodge (and to plow through)
- [ ] Large ramps and the big jump feel good
- [ ] The snow scene isn't too bright/washed out on your screen
- [ ] Both maps: frame rate smooth with 5 racers (also on Windows / a weaker PC if possible)

### Items (final demo milestone 07)

Play Forest Rush (you + 4 AI). Screenshots of every item:
`docs/screenshots/milestone_07/`.

- [ ] Item boxes are easy to spot ahead and you can aim for one at speed
- [ ] Driving through a box never slows you; the pop, sound and HUD item feel rewarding
- [ ] The HUD shows what you hold; Q uses it; a second box while holding says HANDS FULL
- [ ] Mud bomb: the throw arc is readable; you can hit someone ~15 m ahead; the puddle is visible and avoidable; driving through it feels slippery but short
- [ ] Spring punch: hitting someone beside you is satisfying; the knock isn't too far; a point-blank punch throwing them off feels fair
- [ ] Turbo bottle: a clear speed burst; 2.2 s feels right
- [ ] Banana peel: visible on the road; slipping on one spins you but you recover in about a second
- [ ] Being hit never feels like a long stun; right after a hit you can't be hit again at once
- [ ] Leaders vs. the back: does the back of the field get enough turbos/punches to catch up without it feeling unfair?
- [ ] AI use their items sensibly (bananas when someone is behind, bombs when someone is ahead)
- [ ] Online (two computers): pickups, items and hits look the same on both screens; nobody gets an item twice from one box
- [ ] Sounds: pickup chime, throw whoosh, splat, boing, slip, turbo — not too loud or annoying (SFX volume slider)


### Forest Rush (final demo milestone 06)

Play it: main menu → PLAY → Forest Rush → Start Race, or
`$GODOT --path . res://scenes/main/forest_rush.tscn` (you + 4 mixed AI).

- [ ] Time a full run with the timer (target 5–10 minutes). Write down your
      time, wipeouts and resets; try once with drift boosts, once casually
- [ ] The start plaza is wide enough for 5 at GO; the field spreads out without a pile-up
- [ ] The fast forest descent feels fast; the pines make it feel like a forest
- [ ] Hairpins are tight but fair at your speed; chevrons warn you in time
- [ ] The 9.5 m rock passage and the road pines are visible early enough to steer around
- [ ] Bridges: planks look and feel solid, no bump on and off
- [ ] Mud clearly slows you (and feels slippery) and the dark patches read as mud
- [ ] Falling logs: you can see one coming, time your pass, and getting hit feels fair
- [ ] Boulders: the narrow middle gap is passable
- [ ] BIG AIR: the warning boards and arch tell you to go fast; the jump feels great; rolling in too slowly drops you in and puts you back with a run-up
- [ ] Overlooks: the view over the valley is nice and doesn't distract from the road
- [ ] Final descent: fast and fun; the finish area with stands feels like an arrival
- [ ] No spot where you get stuck, fall through the road, or can cut across to another part of the route
- [ ] Settings → Graphics quality Low: trees fade nearer; still looks OK
- [ ] Frame rate stays smooth everywhere (also on a weaker PC / Windows if possible)

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

**Five racers** (`$GODOT --path . res://scenes/main/race_five.tscn`):

- [ ] Five trikes on the grid, all different colors; you're the orange #7 on the pole
- [ ] AI wait for GO, then launch without crashing into each other
- [ ] AI follow the road, dodge rocks and crate stacks, jump the ramps
- [ ] Hard AI is clearly quicker than easy; medium/hard sometimes drift (dust/sparks)
- [ ] Bumping into an AI at low speed doesn't throw anyone off; ramming one hard does
- [ ] A thrown-off AI tumbles, gets up, runs to its own trike and hops back on
- [ ] Finished AI pull over past the line and stop; your FINISH shows your real position (e.g. "3rd")
- [ ] Frame rate stays smooth with all five on screen

**Race flow** (`$GODOT --path . res://scenes/main/race_five.tscn`):

- [ ] Countdown 3 · 2 · 1 · GO! is big and readable; holding W during it does nothing; the timer starts at GO
- [ ] HUD position ("2nd / 5") and "CP x/12" change sensibly as you pass and get passed; no flickering side by side
- [ ] Crash near an AI and watch your position drop, then recover
- [ ] Drive backwards for a bit: your position never improves from it
- [ ] Finish first: "FINISH! 1st" and "ENDS nn" counts down while the AI keep racing; then RACE OVER and results
- [ ] Finish last (wait at the start for a while): results show your time, or DNF if the timeout ends the race first
- [ ] Results: 1st–5th, names, times, race duration; Race Again and Return to Lobby work with mouse and keyboard (arrows + Enter)
- [ ] Race Again 2–3 times in a row: everyone back on the grid, crates/cones back in place, countdown each time
- [ ] Return to Lobby shows the racer list; Start Race begins the countdown

**Menus** (`$GODOT --path .`):

- [ ] Title over the live AI race; buttons grow on hover, squish on click; arrow keys + Enter work
- [ ] PLAY → each of the three maps → lobby → Start Race → countdown on that map
- [ ] Lobby: Add/Remove AI, click an AI's difficulty, Ready, Change Map, Leave Lobby
- [ ] HOST GAME: wrong port shows an error; − / + limit; Host Game opens the hosted lobby
- [ ] JOIN GAME: bad IP/port show errors; a valid address says online play isn't in this build yet
- [ ] SETTINGS: volumes, resolution (window resizes), fullscreen, quality (Low drops shadows), rebind a key and see it on the HUD/pause menu; restart the game: everything is kept
- [ ] In a race: ESC → Settings works over the pause; Return to Lobby goes back to the same lobby; results → Race Again / Return to Lobby
- [ ] Try 1920×1080 and fullscreen: everything scales, nothing is cut off

**Online** (two computers on the same network; NOT yet done):

- [ ] Computer A: HOST GAME → note the address shown (e.g. 192.168.1.20:7777); allow the firewall prompt (UDP)
- [ ] Computer B: JOIN GAME → enter that address → lobby shows both players with HOST/READY
- [ ] B presses Ready, A presses Start Race → both load, countdown together
- [ ] Each sees the other's trike driving smoothly, wipeouts, running back, remounting
- [ ] Bump into each other: both bounce; hard hits throw riders off
- [ ] Finish order and times are identical on both results screens
- [ ] B quits mid-race → A sees "B left the race", race still ends; A quits → B is back on the title with "Lost connection to the host."
- [ ] Repeat with 3 and 5 computers; then a Mac ↔ Windows pair
- [ ] Internet only with UDP port forwarding on the host's router (or a virtual LAN tool, needs approval)

