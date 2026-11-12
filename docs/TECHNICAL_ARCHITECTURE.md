# TRIKE TUMBLE — Technical Architecture

Godot 4.7.2 · GDScript · Mobile renderer · Jolt Physics · 60 Hz physics with
physics interpolation enabled.

## Game flow and autoloads (final demo milestone 04)

The game starts in `scenes/menu/main_menu.tscn` (project main scene):

```
MainMenu (main_menu.gd)          one MenuScreen at a time + back history, fade/slide transitions
├─ Background (menu_background)  test track + RacerManager with 4 AI racing + TV-style camera (loops)
└─ UI (CanvasLayer)
   ├─ Shade                      left-side gradient so text reads over the 3D scene
   └─ Root                       TitleScreen, MapSelectScreen, HostScreen, JoinScreen,
                                 LobbyMenuScreen, SettingsPanel (all built in code)
```

- **Flow:** PLAY → map select → solo lobby → Start Race →
  `change_scene_to_file(map.race_scene)`. HOST GAME → host screen → hosted
  lobby. JOIN GAME → join screen. In the race, Return to Lobby (pause or
  results) goes back to the menu, which opens on the same lobby.
- **Autoloads** (`project.godot`):
  - `GameSettings` (`scripts/core/game_settings.gd`): settings in
    `user://settings.cfg`, applied at launch and on every change.
    - Audio: Master/Music/SFX bus volumes, using the `default_bus_layout.tres` buses.
    - Video: window size (skipped headless or with `--resolution`) and
      fullscreen. Quality applies to a viewport and its lights via
      `apply_graphics(node)`: Low = no MSAA, 0.75 3D scale, sun shadows off;
      Medium = 2× MSAA; High = 4× MSAA.
    - Controls: primary key of each rebindable action, conflicts refused,
      Reset Controls.
    - Player name.
    - Tests and the capture tool call `use_test_profile(path)`: default
      controls and a separate file.
  - `GameSession` (`scripts/core/game_session.gd`): mode (SOLO/HOST/CLIENT),
    the current `Lobby`, the `NetworkTransport`, `race_active`, and
    `get_race_setup()` (player name, map, AI names and difficulties) which
    `RaceSession` reads when `race_active`.
- **Networking** (`scripts/net/`, details in `docs/NETWORKING.md`):
  - `NetworkTransport` interface, implemented by `ENetTransport` over the
    `Net` autoload (ENet host/join, lobby authority, race relay).
  - Remote racers are proxies (`Trike`/`RiderController.network_proxy`)
    moved by `NetRaceSync` from `SnapshotBuffer`.
  - The milestone 04 `OfflineTransport` placeholder was removed when ENet
    replaced it.
  - `Lobby` (seats, ready flags, host, map, `start_blocker()`, `changed`
    signal for syncing) and `LobbyPlayer`.
  - `NetAddress`: IPv4/localhost and port 1024–65535 validation; LAN
    addresses.
- **Maps:** `MapInfo` resources in `resources/maps/`, listed by `MapCatalog`.
  Forest Rush, Rocky Canyon and Snow Slide are READY (`race_scene` =
  `scenes/main/<map>.tscn`, `track_scene` = `scenes/tracks/<map>.tscn`).
  `MapPreview` draws a route map from the track scene's saved data
  (`SceneState`, no instancing): course shaded by height, start/finish,
  bridges, jumps, ice, mud, cliffs, wind, length and drop. A map without a
  track still gets the labelled placeholder; no fake screenshots.
- **Design system:** `UiKit` (`scripts/ui/kit/ui_kit.gd`).
  - Palette, type scale, display font.
  - Factories: buttons (primary/normal/quiet) with hover/focus grow and
    press squish, panels, chips, inputs, fade-in.
  - Key names from the live InputMap, so the HUD hint, mount prompt, item
    hint and pause controls follow rebinding.
  - Base theme: `trike_theme.tres`.
- **UI scaling:** 1280×720 base, `canvas_items` stretch with `expand` aspect.
  A test checks every menu page's minimum size fits 1280×720.
- **Race UI additions:**
  - HUD race-state chip (GET READY / STARTING / RACING / FINISHED · WAITING / RACE OVER / RESULTS).
  - Item slot: held item in its color (pops in on pickup), EMPTY otherwise, `[Q] USE ITEM`.
  - Pause menu: Resume, Restart (scene reload), Settings (overlay), Return
    to Lobby, Quit Game, live key reminder.
  - `RaceSession.scene_changer`, `MainMenu.quit_handler/scene_changer` and
    `PauseMenu.quit_handler` are replaceable for tests.

## Scene graph (main.tscn)

```
Main (RaceSession, main.gd)          local player + race flow ↔ camera/HUD/screens, AI count/difficulty
├─ WorldEnvironment, Sun, FillLight
├─ <track> (Track)                  instanced from `track_scene` at the start of _ready (TestTrack or ForestRush)
│  ├─ Road_NN, Walls_NN, Slopes_NN   render chunks (60 samples = 120 m each)
│  ├─ TrackBody / MudBody / BridgeBody / SlopeBody   collision per surface (chunked shapes)
│  ├─ Props (track_props.gd)         crates, cones, rocks, ramps, boulders, road trees, falling logs, big kicker
│  ├─ Decor (track_decorator.gd)     trees, bushes, boulders, flowers (+ trunk/boulder collision)
│  ├─ Landmarks (track_landmarks.gd) turn signs, hay bales, cabin, logs, bunting (+ box collision)
│  ├─ Backdrop (track_backdrop.gd)   terrain, far forest, mountains, hills, clouds, valley, lake (no collision)
│  └─ Structures (track_structures.gd) bridges, streams, jump arch, overlooks, rock gates, stands (Forest Rush)
├─ Trike (Trike, RigidBody3D)        vehicle physics + gameplay state
│  ├─ ChassisShape, RiderShape
│  ├─ PlayerInputSource              keyboard/gamepad → TrikeInput
│  └─ Visuals (TrikeVisuals)         frame, wheels, fork, handlebar, flag, Rider (IK), particles
├─ RiderCharacter (RiderController)  rider state machine (ejection → recovery)
│  ├─ PlayerInputSource              on-foot input (WASD, E, R)
│  ├─ Ragdoll (RiderRagdoll)         tumbling body while thrown (disabled otherwise)
│  ├─ OnFoot (RiderOnFoot)           CharacterBody3D while on foot (disabled otherwise)
│  └─ DizzyStars
├─ FollowCamera (Camera3D)
├─ HUD (CanvasLayer)
├─ PauseMenu (CanvasLayer, process_mode Always)
├─ RacerManager (racer_manager.gd)   racer registry, AI spawning, progress/checkpoints/positions, respawns, race clock, FinishTracker
   └─ Racer2..Racer5 (Node3D)        one per AI racer, spawned at runtime
      ├─ AIDriver (TrikeInputSource) AI brain: polled by both the trike and the rider
      ├─ Trike (trike.tscn)          same scene as the player's; PlayerInputSource removed
      └─ RiderCharacter              same scene as the player's; PlayerInputSource removed
├─ Items (ItemManager)               item boxes, held items, bombs/puddles/peels, host authority (see "Items")
│  └─ Sounds (ItemSounds)            synthesized item sounds
├─ RaceController (race_controller.gd) race flow: RaceStateMachine, countdown, finish timeout, results, race again
├─ ResultsScreen (CanvasLayer)       results table + Race Again / Return to Lobby
└─ LobbyScreen (CanvasLayer)         racer list + Start Race
```

The race scene doesn't contain its track: `RaceSession.track_scene` is
instanced first thing in `_ready` (it keeps its root name, so tests still
find `TestTrack`). `main.tscn` uses the test track; `scenes/main/forest_rush.tscn`
inherits it with `track_scene = forest_rush.tscn` and 4 mixed AI. The map
catalog points Forest Rush at that scene, so menu races and online races
load it. `RaceSession` also hands the track's `finish_timeout` (45 s test
track, 120 s Forest Rush) to `RaceController`.

`scenes/main/race_five.tscn` inherits `main.tscn` with `ai_racer_count = 4`
and mixed difficulty. `main.tscn` alone is the 1-racer game (and what the
older tests load); `-- --ai=N --difficulty=easy|medium|hard|mixed` on the
command line adds AI to it.

## Vehicle movement model: decision record

Options evaluated:

| Option | Verdict |
|---|---|
| `VehicleBody3D` | Simulation tire model. Hard to tune for arcade drifting; unpredictable at speed. Rejected. |
| `CharacterBody3D` (kinematic) | Very predictable, but tumbling, flips and physical knockback must all be faked. Rejected: tumbling is a core pillar. |
| Arcade sphere controller | Stable and simple, but cannot flip or tumble. Rejected. |
| **`RigidBody3D` + raycast suspension + arcade forces** | **Chosen.** Real collisions, flips and impulses from Jolt; handling is a small set of tunable velocity changes. |

How `Trike._integrate_forces` works each physics tick:

1. **Suspension:** 3 rays (front, rear-left, rear-right) cast down from wheel
   mounts. Spring + damper force at each mount (capped). Contact count gives
   `grounded_wheel_count`; hit normals give the ground normal.
2. **Drive** (rear wheels grounded): throttle acceleration fading to 0 at
   `max_speed`, brakes, reverse, boost, rolling resistance, handbrake. Idle
   hold stops creeping on slopes. Resistances never flip the direction of travel.
3. **Grip:** removes sideways velocity at a rate (`grip`) up to a cap
   (`max_lateral_accel`). Drifting uses lower values. Part of the scrubbed
   speed is redirected forward (`*_speed_retention`) so turning and drifting
   don't feel draggy. Applied at the center of mass, so cornering never tips
   the trike over.
4. **Yaw:** angular velocity around the trike's up axis chases a target yaw
   rate from steering or drift state. Acceleration is capped, so collisions
   can still spin the trike.
5. **Upright stabilizer:** damped spring toward the ground normal (grounded)
   or world up (airborne, weaker). Air steering is limited.
6. **Drag:** quadratic.

`_physics_process` (runs before the physics step) polls input, smooths
steering, runs the drift state machine (start → charge → release boost) and
the recovery timers.

All numbers live in `TrikeConfig` (`resources/vehicles/default_trike_config.tres`).

## Rider ejection and recovery (milestone 3)

**State machine** (`RiderController`, one per player). All transitions go
through `_change_state()`, which emits `state_changed(old, new)`:

| State | Rider model | Physics body | Input goes to | Camera follows | Exit |
|---|---|---|---|---|---|
| RIDING | seated (child of trike, IK to grips) | trike | trike (`Trike.input_source`) | trike | impact ≥ `eject_impact_strength`, or tilted past `eject_tilt_up` for `eject_tilt_time` (not during `eject_grace_time`) |
| EJECTED | top_level, flail pose | `RiderRagdoll` launched with ¾ of the pre-impact velocity + up + forward somersault | nobody (R = emergency) | ragdoll | first ground contact |
| RAGDOLL | flail pose | ragdoll, ground damping | — | ragdoll | settled after `min_fall_time`, or `max_fall_time`, or lost |
| GETTING_UP | blends from fallen pose to standing; push-up, head shake, scratch | `RiderOnFoot` placed on the ground (back on the road if thrown off it) | — | on-foot body | `get_up_duration` |
| ON_FOOT | stand/run pose | `RiderOnFoot`, camera-relative WASD | RiderController | on-foot body | E within `mount_distance` of a slow trike |
| MOUNTING | hop arc to the seat, IK reaching for the grips | none | — | trike | `mount_duration` → RIDING |

**Separation of rider and vehicle:** the trike knows only `has_rider`. When
it's false (`set_rider_aboard(false)`) the trike ignores input, applies
`riderless_brake_deceleration`, skips air control and self-righting, and
disables its rider collision capsule. Flip auto-recovery is off whenever a
rider system is attached (`auto_recover_when_flipped`). Stuck auto-recovery
only runs with a rider aboard. Mounting an overturned trike calls
`Trike.set_upright()` in place (no respawn signal).

**Impact detection** (`Trike._measure_impact`): each tick, the actual velocity
is compared with the expected one (velocity we left the body with, plus our
suspension forces, plus gravity). The difference comes from contacts. It's
reported as `impact(strength, velocity_before)` above
`impact_report_threshold`. Calibration (flat arena): head-on wall
hits ≈ 1.1 × hit speed; glancing scrapes ≈ 1.3; crate at speed ≈ 1.8;
3 m drop ≈ 0; full track autopilot run peaks at 1.75. Missing a corner into
the barrier reads 1.6–5.2 at 8 of the 9 corners and 12.3 at the
sharpest-angled one.

**The thrown rider** is one rounded RigidBody (layer 4 "riders", mask world +
vehicles + props) with procedural limb flailing. It ignores its own trike until
1.6 m clear, then bounces off it. The spin wobble uses a seeded RNG
(`fling_seed`), so replays and netcode can reproduce a tumble.

**Race wiring** (`RaceSession`): `focus_changed` → `FollowCamera.set_target`
(blended over 0.9 s, positions continuous); `mount_prompt_changed` → HUD
prompt; `ejected` → "WIPEOUT!"-style message;
`emergency_recovery_requested` (R while off) → trike to the last safe road
point and `force_mount()`. The race clock keeps running. Finishing requires
being on the trike.

**Multiplayer readiness:** rider input is the same `TrikeInput` data
(+`interact_pressed`). `get_sync_state()` returns state, state time, ragdoll
transform/velocity and on-foot position/facing. Visuals are derived from that
state only.

## Input abstraction (multiplayer-ready)

`TrikeInput` is plain data (`throttle`, `brake`, `steer`, `drift`,
`reset_pressed`, `interact_pressed`, `move_direction`). The trike reads it
while ridden; the `RiderController` reads its own copy while the rider is off
the trike (throttle/brake/steer become camera-relative on-foot movement,
`interact_pressed` mounts). `move_direction` is an optional **world-space**
on-foot direction for AI and network sources; when non-zero it replaces the
camera-relative movement (the camera belongs to the local player only).

`Trike.input_source` and `RiderController.input_source` are typed
`TrikeInputSource` (base class with `poll(into)`). Implementations:
`PlayerInputSource` (keyboard/gamepad) and `AIDriver`.

Input map (project.godot, all `device = -1`, keys use physical keycodes):

| Action | Keys | Gamepad |
|---|---|---|
| `accelerate` | W, ↑ | right trigger (axis 5) |
| `brake` | S, ↓ | left trigger (axis 4) |
| `steer_left` / `steer_right` | A, ← / D, → | left stick X (axis 0) |
| `drift` | Space | RB (button 10), B (button 1) |
| `reset` | R | Y (button 3) |
| `interact` | E | X (button 2) |
| `pause` | Esc | Start (button 6) |

Sources:

- `PlayerInputSource`: local keyboard/gamepad (polled each physics tick)
- `AIDriver`: AI racers (see below)
- `TrackAutopilot`: tests and screenshots only (drives a trike directly)
- future: network peer inputs

For multiplayer, the server simulates with each client's `TrikeInput` and
replicates the transform and velocities. `TrikeVisuals` holds no gameplay
state, so remote trikes render unchanged.

## Racers and RacerManager (final demo milestone 02)

`Racer` (RefCounted, `scripts/race/racer.gd`) is one racer's record: `id`,
`display_name`, `type` (HUMAN/AI), `trike`, `rider`, `input_source`,
`progress` (own `VehicleProgress`), `spawn_slot`, `spawn_transform`, `color`,
`lane_offset`, `root` (spawned node, null for the scene-placed player),
`finished`/`finish_position`/`finish_time`, `respawn_count`.

`RacerManager` (Node3D in `main.tscn`):

- `setup(track)` creates the `FinishTracker`, listens to `finish_crossed`
  and collects AI obstacles from the track's `Props` (crates, cones, rocks by
  scene name; ramps by class).
- `add_human_racer(trike, rider, id, name, slot)` registers the
  scene-placed local player; `add_ai_racer(difficulty, name, id, slot)`
  instantiates `trike.tscn` + `rider_character.tscn`, **removes their
  `PlayerInputSource` nodes** (AI can never read the keyboard), creates an
  `AIDriver` and sets it as both input sources, and `attach_to()`s the rider.
  Both return null when the race is full (`max_racers` = 5) or the id is
  taken. Ids default to the lowest free id (local player = 1), slots to the
  lowest free grid slot.
- Registration teleports the trike to `Track.get_start_transform(slot)`
  (`notify=false`), gives it its own `VehicleProgress`, connects
  `respawn_requested` and `emergency_recovery_requested` **bound to that
  racer**, registers it with `FinishTracker` and applies the livery
  (`TrikeVisuals.body_color`, number decals) from `racer_colors` /
  `racer_numbers`.
- `_physics_process`: advances `race_time` between start and
  `stop_race()`. Updates every racer's progress, checkpoints and
  out-of-bounds respawn, then `finish_tracker.update()` and positions.
- `start_race()` activates every `AIDriver` and starts the clock.
  `RaceController` calls it at GO.
- Queries: `get_racers()`, `get_racer(id)`, `get_racer_for_body(body)`,
  `get_obstacles()`, `get_ramps()`, `is_everyone_finished()`.
- Signals: `racer_added`, `racer_respawned`, `racer_finished`, `race_started`.

`RaceSession` keeps the old public API (`trike`, `rider`, `get_progress()`,
`get_race_time()`, `is_race_finished()`, `get_finish_tracker()`) for the
local racer, plus `racers` and `get_local_racer()`.

`Track.get_start_transform(slot)` now places rows at their exact distance
(it used to round to 2 m path samples, which put slots 1 and 3 only 2.1 m
apart). Slot 0 is unchanged.

## AI driver (final demo milestone 02)

`AIDriver` (`scripts/ai/ai_driver.gd`) extends `TrikeInputSource`. The trike
polls it while ridden and the `RiderController` polls it while off the
trike, so one brain covers both. It only writes `TrikeInput`: the AI drives
the real `Trike` physics with the same `TrikeConfig` as the player, and falls
off, gets up and remounts through the normal rider state machine. It never
moves a trike or rider itself.

Riding, every tick:

1. **Track following:** nearest path sample (windowed search), then a
   look-ahead point `max(lookahead_min, speed × lookahead_time)` ahead on the
   centerline, shifted by the planned lateral offset. Steering = heading
   error × `steer_gain`, rate-limited by `steer_rate`, plus a smooth
   two-sine wobble of `steer_noise`.
2. **Planned lateral:** the racer's lane (`RacerManager.lane_offsets` by
   grid slot), pulled toward the inside of the coming corner by `corner_cut`,
   then obstacle avoidance (below). It slews at `lane_change_speed`.
3. **Speed planning:** per-sample signed curvature is precomputed. Target
   speed = `top_speed_ratio × max_speed`, lowered so that for every sample
   within braking range `v ≤ sqrt(v_corner² + 2·a·d)` with
   `v_corner = sqrt(corner_lateral_accel / curvature)`. Throttle below
   target, `cruise_throttle` near it, brake above `target + brake_margin`.
   Pointing the wrong way (> 1.1 rad off) caps speed while turning round.
4. **Obstacles:** props within `avoid_distance` ahead and racers we close in
   on (or that are < 4 m ahead) become blocked lateral intervals
   (radius + trike half-width + `avoid_margin`). An obstacle only counts
   after it has been in view for `reaction_time`. The AI picks the free
   lateral closest to its desired line. Crates and cones are **soft**: when
   no clean gap exists the AI pushes through them. Only when rocks or racers
   wall off the road is it `blocked`, and then it follows the slowest blocker.
5. **Ramps / jumps:** a ramp the planned line would clip takes over the
   lateral target (taken straight and centered, no dodging or drifting).
   Airborne, the AI steers to align the nose with the road (air control) and
   doesn't brake or drift.
6. **Drifting:** once per sharp-enough corner (`drift_min_curvature`) it
   rolls `drift_chance`. It drifts only when steering into the corner above
   the drift threshold, fast enough and with nothing in the avoidance window.
   It bails out on counter-steer, a big heading error or near the barrier.
   Releasing gives the normal drift boost: no hidden boosts.
7. **Recovery:** stuck (trying to drive, < 1 m/s, grounded for `stuck_time`)
   → reverse with opposite steer for `reverse_time`. After
   `max_unstick_attempts`, or no new ground for `no_progress_time`, it
   presses R: the same respawn a human has.
8. **Finish:** once its finish is confirmed it pulls to the side of the road
   and brakes with `finish_brake`.

Off the trike: nothing during EJECTED/RAGDOLL/GETTING_UP/MOUNTING. ON_FOOT:
writes `move_direction` toward its own trike (slowing within
`on_foot_slow_radius`) and presses E `mount_delay` after the GET ON prompt
appears. If it moves < 0.1 m in 0.4 s it side-steps (80°) for 0.9 s,
alternating sides. Last resort after `on_foot_give_up_time` (15 s): R, the
same emergency recovery a human has (never reached in the tested races).

**Difficulty** = `AIDriverConfig` resource (`resources/ai/ai_easy.tres`,
`ai_medium.tres`, `ai_hard.tres`; assigned in `main.tscn` →
`RacerManager.ai_configs`):

| Value | Easy | Medium | Hard |
|---|---|---|---|
| top_speed_ratio | 0.74 | 0.9 | 1.0 |
| corner_lateral_accel (m/s²) | 10 | 15 | 19 |
| planning_deceleration (m/s²) | 9 | 14 | 18 |
| steer_gain / steer_rate | 2.0 / 3.5 | 2.6 / 6 | 3.0 / 9 |
| steer_noise | 0.16 | 0.06 | 0.02 |
| corner_cut | 0 | 0.25 | 0.5 |
| drift_chance (min curvature) | 0 | 0.35 (0.01) | 0.75 (0.008) |
| avoid_distance / reaction_time | 30 m / 0.45 s | 40 m / 0.25 s | 50 m / 0.08 s |
| lane_change_speed | 4 | 6 | 8 m/s |
| avoids cones | no | yes | yes |
| start / mount delay | 0.7 / 0.8 s | 0.2 / 0.2 s | 0.05 / 0.05 s |

## Race flow (final demo milestone 03)

**States** (`RaceStateMachine`, pure logic, `scripts/race/race_state_machine.gd`):
`LOBBY → COUNTDOWN → RACING → FINISHED → RESULTS → LOBBY`, plus aborts back to
LOBBY from COUNTDOWN, RACING and FINISHED. `transition()` refuses anything else
(returns false), emits `state_changed`, and records `history`.

**`RaceController`** (node in `main.tscn`) drives it on top of `RacerManager`:

| State | What happens | Leaves when |
|---|---|---|
| LOBBY | racers on their grid slots, `set_controls_locked(true)` | `auto_start` and `lobby_delay` (1 s) passed, or `begin_countdown()` (Start Race) |
| COUNTDOWN | `countdown_step` "3", "2", "1" every `countdown_step_time` (1 s); still locked | after 3 steps → `_go()` |
| RACING | "GO!", controls unlocked, `RacerManager.start_race()` (AI on, clock runs). First finisher starts `finish_timeout` (45 s, 0 = none) | everyone finished, or the timeout runs out |
| FINISHED | `stop_race()`: clock stops, finish line ignored, unfinished = DNF, AI off, locked. `results` built | `results_delay` (2.5 s) |
| RESULTS | `ResultsScreen` | `race_again()` or `return_to_lobby()` |

- `race_again()` = RESULTS → LOBBY (reset) → COUNTDOWN.
- `return_to_lobby()` = RESULTS → LOBBY (reset) and wait for Start Race.
- `start_immediately()` = LOBBY → COUNTDOWN → RACING in one tick (tools and
  tests; `RaceSession.skip_countdown`).
- `race_duration` = the last finisher's time when everyone finished, else
  the clock at the timeout.
- Results entries: `{position, id, name, is_ai, finished, time}`, in final
  race order.

**Controls lock:** `Trike.input_locked` clears input and brakes gently like a
riderless trike. It is applied in `_physics_process` and again in
`_integrate_forces`: physics callbacks run *before* `_physics_process`
each tick, so input written between ticks would otherwise reach the motor
once.

**Reset** (`RacerManager.reset_for_new_race()`, no scene reload):
- riders off their trikes are `force_mount()`ed
- trikes teleported to their `spawn_transform` (`notify=false`)
- inputs cleared and locked
- `VehicleProgress`, `CheckpointProgress`, finish fields, DNF and respawn
  counts reset
- `FinishTracker.reset()`, `AIDriver.reset_for_race()` (inactive, unhinted
  path search)
- `TrackProps.reset_props()` puts crates and cones back at their spawn
  transforms
- clock zeroed

Ids, slots, colors and AI difficulty stay. `ItemManager.reset_for_new_race()`
runs on the same `race_reset` signal: empty hands, every box back, no bombs,
puddles or peels. The pause menu's Restart still reloads
the whole scene.

## Checkpoints and positions (final demo milestone 03)

`Track.get_checkpoints()`: path indices every `checkpoint_spacing` (100 m)
after the start, none within `checkpoint_finish_gap` (20 m) of the finish,
then the finish index as the last one. The test track has 12. A test checks
every track scene in `scenes/tracks/`.

`CheckpointProgress` (one per racer, `racer.checkpoints`), updated by
`RacerManager` every tick from the trike's `VehicleProgress.current_index`:
- **Ordered:** only `next_checkpoint` can be passed, and only while the trike
  is within `pass_window` (15 samples = 30 m) after it. Jumping further
  (teleport, shortcut) sets `missed_checkpoint`, and nothing after it can
  count. The skip is never repaired automatically.
- **Once:** passing increments `next_checkpoint`; reversing back over it and
  through again changes nothing. `checkpoint_passed(i)` fires once per
  checkpoint.
- **Valid distance** (`distance`, m) = path index × spacing + the offset
  along the path, capped at the next unpassed checkpoint. Reversing lowers
  it; skipping gains nothing beyond the skipped checkpoint.
- Based on the trike, so a wipeout changes nothing (the empty trike keeps
  its state).
- `segment_distance`, `get_overall_progress()` (0..1),
  `force_passed_through(index)` (tests/tools after a teleport), `complete()`
  on finish.

**Finish gate:** `FinishTracker.can_finish` (new optional Callable) is
`RacerManager._can_finish`: a crossing only counts once every checkpoint
before the line was passed. Ids the manager doesn't own aren't gated. The
pending-finish logic is unchanged; `FinishTracker.reset()` was added for new
races.

**Positions** (`RacePositions.rank`, every tick, into `racer.position` and
`RacerManager.get_ranking()`):
1. finished racers, by finishing order
2. then more checkpoints passed
3. then more valid distance along the path (not straight-line distance)

Two racers on the same checkpoint within `position_swap_margin` (1 m) keep
their previous order (no flicker). The HUD shows "2nd / 5", "CP 3/12" and,
while it runs, the finish timeout.

## Items (final demo milestone 07)

Four original items, one carried at a time, collected from floating "?"
boxes on the road. Everything lives in `scripts/items/`; the only hooks into
older code are two `Trike` methods, `TrikeInput.use_item_pressed`,
`Racer.held_item`/`item_hold_time` and one line in `AIDriver`.

| Item | Use (Q) | Effect |
|---|---|---|
| Mud bomb | thrown forward in a visible arc | direct hit: victim slips 1.4 s + small wobble; always leaves a mud puddle (r 3.8 m, 8 s) where trikes lose grip and top speed |
| Spring punch | boxing glove on a spring | nearest riding opponent within 9 m and a 110° cone: knocked sideways 5–10 m/s (stronger closer) + short slide; ≥ 8.5 m/s (about ≤ 2.7 m away) throws the rider off; nobody in range = a miss |
| Turbo bottle | instant | `boost_time` = 2.2 s (the drift-boost acceleration and top speed) |
| Banana peel | dropped 2.6 m behind | first racer over it (the dropper only after 1 s) spins out: yaw spin, 55 % speed kept, 1 s low grip; max 8 peels, 45 s life |

**Authority.** One model offline and online (offline = the local machine is
the host):

1. Each computer watches only the racers it simulates (its player; the host
   also its AI). Driving through a box (swept segment test, no collision,
   no slowdown), over an armed peel, or pressing Q creates a **request**
   `(racer id, request id, kind, data)`. A pending flag stops repeats while
   waiting for the answer.
2. The host validates in `ItemManager.handle_request()`:
   - racer exists, is riding, racing, not finished;
   - well-formed data (finite vectors, believable speed);
   - request id newer than the last one from that racer (replays ignored);
   - pickup: box active, empty hands, no post-use cooldown, racer within
     `plausible_distance` of the box (host view);
   - use: the item is really held (and was held ≥ half the use delay);
     the reported position is used only if it matches the host's view;
   - banana hit: peel exists and is armed for that racer, racer not immune.
   Online, `Net` first checks that the sender owns the racer.
3. Granted requests become **events** `[seq, type, ...]` (`ItemManager.Event`):
   `BOX_TAKEN`, `BOX_RESPAWNED`, `TURBO_USED`, `BANANA_DROPPED`, `BANANA_HIT`,
   `BOMB_THROWN`, `BOMB_LANDED`, `PUNCH`. The host applies each one and
   broadcasts it; clients apply events in order and ignore repeated or
   malformed ones. Item rolls, peel spots, bomb landings, punch targets,
   knock velocity and ejection are all decided on the host and carried in
   the event.
4. Physical effects are applied only by the victim's owner (`_owns()`), via
   `Trike.apply_item_hit()` / `set_slippery()` / `RiderController.eject()`;
   proxies just move with the next snapshots.

Bombs fly as plain ballistics (`MudBomb.step`) on every computer; the host
alone tests them against trikes and the ground and announces the landing.
Puddles are areas: each owner makes its own trikes slippery inside one.
Puddles and peels age locally with the same lifetimes.

**Trike hooks.**
- `apply_item_hit(velocity_change, spin, speed_keep)`: queued and applied
  inside `_integrate_forces` after the impact measurement, so the impact
  rule never also counts it as a crash. Whether an item ejects is the
  host's decision.
- `set_slippery(duration, grip_factor, speed_factor)` / `slip_time`: scales
  surface grip and top speed (mud drag applies) on top of the ground's own
  surface. Cleared by `teleport()`.

**Balance rules** (all values in `ItemConfig`,
`resources/items/default_item_config.tres`):
- one item; a box never overwrites it (it stays for others, the player sees
  "HANDS FULL")
- use delay 0.35 s after pickup, 0.6 s pickup cooldown after use
- no use or pickup while off the trike, before GO or after the race
- 2.5 s immunity after any item hit (no chain-stuns); immune racers don't
  trigger peels and aren't punch targets
- every slowdown lasts ≤ 1.4 s (puddles: only while inside)
- position-weighted roll (`ItemRoll`): leader mostly bananas and mud,
  last place mostly turbos and punches
- boxes respawn after 6 s, but only when no trike or rider is within 3.5 m

**AI.** `AIItemTactics.wants_use()` (called from `AIDriver._poll_riding`)
presses use through `TrikeInput`: turbo on straight road, banana with a racer
behind, mud bomb with a racer ahead, punch with a racer close beside; any
item after `item_max_hold` (punch: twice that). Values per difficulty in
`AIDriverConfig` ("Items").

**Maps.** `ItemManager.setup()` places a box on every
`Track.get_item_box_transforms()` point (`item_box_rows` × `item_box_columns`).
Forest Rush: 15 rows × 3 = 45 boxes. A new map only fills `item_box_rows`
(distances along the built path, on safe road); the test track has none, so
the older tests run without items. Tests and tools add boxes with `add_box()`
and give items with `grant_item()` (host only).

**Feedback.** Box pop burst in the item's color, HUD slot pop + "+ ITEM"
message, "SPLAT!/SLIPPED!/PUNCHED!/POW!/MISSED!/TURBO!" messages, punch
glove effect, splat/turbo bursts. Sounds are synthesized in code at startup
(`ItemSounds`, SFX bus): flat for the local player, positional otherwise.

## Audio, looks, effects and camera feedback (final demo milestone 09)

**Audio.** All sounds are synthesized in code, no files:
- `SoundSynth`: tones/melodies, pitch sweeps (with vibrato for cartoon
  voices), filtered noise bursts, seamless loops (whole wave cycles +
  cross-faded noise), mixing; 16-bit 22 kHz mono `AudioStreamWAV`.
- `SoundBank`: every sound by name, built once and cached; `played` logs
  one-shot requests (tests check triggers headless).
- `SoundPlayer`: positional (`play_at`) and flat (`play_flat`) one-shots,
  freed on a timer (headless audio never emits `finished`).
- Buses (`default_bus_layout.tres`): Master, Music (empty for now), SFX,
  UI, each with a saved volume slider (`GameSettings`, Settings → Audio).

| Component | Created by | Plays |
|---|---|---|
| `TrikeAudio` | `TrikeVisuals` | engine loop (pitch by speed/throttle, boost), skid loop (real tyre slip or drifting; softer on snow, hiss on ice), brake squeal, soft/hard hits (`Trike.impact`), landing thumps (`TrikeVisuals.landed`) |
| `RiderAudio` | `RiderController` | yelp on EJECTED, thud on RAGDOLL, boing + chime on GETTING_UP, footsteps by distance on foot (crunch on snow maps), hop on MOUNTING |
| `RaceAudio` | `RaceSession` | countdown beeps, GO, the local finish fanfare + confetti, victory jingle (podium) or results chord |
| `ItemSounds` | `ItemManager` | item sounds, from the same bank |
| `UiKit.play_ui` | every `UiKit` button | hover tick, press click (UI bus) |

Trike and rider audio read only synced state (speed, slip, wheel contact,
boost, rider state), so network proxies sound like the real racer.

**Rider looks.** `RiderLook` (`resources/characters/looks/*.tres`: Zip, Pip,
Bramble, Nutmeg, Rusty) = colors, `HelmetStyle` (bear ears, mohawk, horns,
antenna, pompom), `Accessory` (scarf, backpack, bandana, bell, none),
goggles, head size and resting `Face`. `RiderStyle.apply()` gives the rider
its own copies of the shared materials (by role), adds the style/accessory
meshes (`Look_*` nodes, replaced on re-apply) and sets the face. The rig
(bones, IK targets, limb lengths) never changes. `RacerManager.rider_looks`
and `racer_accents` pick the look and the trike's second color by racer
order (the same on every computer).

**Faces and celebration.** `Rider.Face`: the five resting faces plus
SHOCKED (thrown off), DIZZY (getting up) and CHEER. `set_expression()` poses
brows, eyes, pupils and mouth relative to their rest transforms; pose-mode
changes pick the face, so proxies show it too. `Rider.celebrate()` (called
by `RacerManager` on `racer_finished` for every finisher that is riding):
while seated the arms leave the grips (free IK targets: fist pump + wave),
then return to them.

**Effects** (`TrikeEffects`, created by `TrikeVisuals`, state-driven so
proxies show them): wheel spray styled per ground (`SPRAY`: dirt, grass,
mud, planks none, snow, ice), skid marks while drifting (world-space flat
particles), a boost trail, a landing puff and an impact burst; plus the
existing drift dust/sparks and boost flame, item effects and the finish
confetti (`RaceAudio.fire_confetti`). All low and behind the trike, or
above the finish arch.

**Camera feedback** (`FollowCamera`): `add_impact_shake(strength)` adds
trauma (ignored below 3 m/s, full at 14); the shake is trauma² × 0.16 m /
1.4° and decays in under 0.5 s. `add_landing(airtime)` dips the camera
(≤ 0.4 m) on a critically damped spring. `turn_look_shift` aims up to 1.6 m
into a turn at speed. `RaceSession` wires the local trike's `impact` and
`TrikeVisuals.landed` to it.

## Desktop export (final demo milestone 10)

`export_presets.cfg`:
- **macOS**: universal (x86_64 + arm64), bundle id
  `io.github.triketumble.demo`, ad-hoc code signature (built-in signing,
  hardened runtime, no Apple account), not notarized, no sandbox →
  `release/TrikeTumble-macOS/TrikeTumble.zip` containing "Trike Tumble.app".
  Needs `textures/vram_compression/import_etc2_astc=true` (set).
- **Windows**: x86_64, pck embedded in the exe, no code signing, no rcedit
  resource changes → `release/TrikeTumble-Windows/TrikeTumble.exe`.
- Both exclude `tests/`, `docs/`, `release/` and `override.cfg`. The pack is
  ~0.6 MB (everything is procedural).
- Templates: official Godot 4.7.2 stable **standard** templates
  (`Godot_v4.7.2-stable_export_templates.tpz`, SHA-512 checked against the
  release's `SHA512-SUMS.txt`) in
  `~/Library/Application Support/Godot/export_templates/4.7.2.stable/`.
- Export with the strict-mode `override.cfg` removed (project settings are
  baked into the export).
- Release builds can't open a scene from the command line; for QA,
  `-- --quick-race=<map_id>` starts a solo race (you + 4 AI) from the menu.

## Signals and APIs

- `Trike`:
  - **Signals:** `respawn_requested(trike)`, `respawned`,
    `drift_started(dir)`, `drift_ended(tier)`,
    `impact(strength, velocity_before)`.
  - **Methods:** `request_respawn()`, `teleport(xf, notify := true)`,
    `set_rider_aboard(bool)`, `set_upright()`,
    `apply_knockback(impulse, spin)`, `apply_item_hit(dv, spin, speed_keep)`,
    `set_slippery(duration, grip, speed)`, `get_drift_tier()`, `is_grounded()`.
  - **State:** `has_rider`, `auto_recover_when_flipped` (true only for a
    standalone trike without a rider system).
  - With no `respawn_requested` listener, a reset rights the trike in place,
    which keeps it usable in isolation and in tests.
- `RiderController`:
  - **Signals:** `state_changed`, `ejected`, `mounted`,
    `mount_prompt_changed`, `focus_changed`, `emergency_recovery_requested`.
  - **Methods:** `attach_to(trike) -> bool`, `detach()`, `is_attached()`,
    `eject()`, `force_mount()`, `is_riding()`, `get_sync_state()`.
  - **`attach_to()` lifecycle:**
    - Safe at any time. Before `_ready` it only stores the trike, and
      `_ready` binds it once the child bodies exist.
    - Calling it again with the same trike is a no-op, and the `impact`
      signal is never connected twice.
    - A different trike first detaches the old one (disconnects `impact`,
      restores its flip recovery).
    - null or freed returns false and keeps the current binding.
    - A trike freed while bound is released on the next tick: the rider stops
      falling or walking and returns to the RIDING state, unattached.
- `FinishTracker` (see below): `register_racer(id, trike, rider, progress)`,
  `on_body_crossed(body, time)`, `update(time)`, `has_finished(id)`,
  `is_pending(id)`, `get_result(id)`; signals `racer_finished(id, position,
  time)`, `finish_pending(id, time)`.
- `Track`: signal `finish_crossed(body)`. Methods `get_start_transform(slot)`
  (5 grid slots), `get_respawn_transform(index)`, `is_on_road()`,
  `is_out_of_bounds()`, `path: TrackPath`.
- `VehicleProgress` (one per racer): nearest track sample plus last safe
  on-road sample (the respawn point). Windowed search, so it never jumps to a
  nearby section of road.
- `RaceSession` (main.gd): binds the local racer (`LOCAL_PLAYER_ID` = 1) to
  camera and HUD and starts the race; racer rules live in `RacerManager`.
- `RacerManager`, `Racer`, `AIDriver`, `AIDriverConfig`: see the sections above.

## Finish detection

The finish `Area3D` (mask: vehicles) emits `Track.finish_crossed(body)` for
any vehicle. `RacerManager` forwards it to `FinishTracker` (once the race
has started), which resolves the body to the **owning player** through the
racer registry. Unknown bodies are ignored, so one player's vehicle can never
finish for another.

- Crossed with the rider aboard: finish confirmed immediately.
- Crossed **empty**: recorded as *pending*. `update()` (every physics tick)
  confirms it on the first tick the owner is riding that trike again (E mount
  or R emergency recovery) while its progress is still at or past the line.
  If the trike ends up back before the line, the pending finish is dropped
  and the line counts again on the next crossing.
- Each player finishes once. Position = confirmation order. Official time =
  race time at confirmation (`crossed_time` is kept too).
- Pure logic with no nodes, keyed by player id: a future host can run it
  authoritatively and broadcast `racer_finished`. No results screen yet.

## Track generation (rewritten in final demo milestone 06)

**Data → path.**
- A map is a `Track` scene with data only.
  - `route_segments`: each segment is `Vector3(length m, turn °, grade %
    downhill)` and is turned into control points by `TrackRoute`. A segment
    is a constant-radius arc, so the tightest corner is simply
    `min(length / turn)` (`TrackRoute.min_radius`).
  - The old `control_points` still work (the test track uses them).
- `width_profile` holds `(distance, width)` keys, eased between keys.
- `zones` holds `[start, end, kind, ...]` entries: `bridge`, `gap`,
  `mud u0 u1`, `overlook side`, `clearing` and `rocks`.
- `TrackPath` samples every 2 m. Each sample has a frame (forward, a level
  right vector, up) and a road width (`widths`). Read the width through
  `Track.half_width_at(i)`; never use `road_width` directly.

**Lookup.**
- `TrackPath` keeps a 40 m spatial grid. An unhinted `find_nearest()`
  searches ring by ring and gives the same answer as a full scan (tested on
  400 random probes).
- `samples_near()` serves scenery placement.
- Hinted lookups (per-frame racer tracking) stay windowed.

**Geometry (`TrackMeshBuilder`).**
- Every sample has a kind: NORMAL (road, walls, slopes), BRIDGE (plank deck
  and parapets; no slopes, an open gorge below) or GAP (nothing).
- At every bridge and gap end the full cross-section drops as a rocky cliff
  face (rendered and solid).
- The road and the collision cross-section are cached per sample, so each
  slope point and noise color is computed once.
- Quads go into `MeshBatch` (packed arrays, no SurfaceTool calls per vertex).
- The track is built in chunks of 60 samples (120 m). Each chunk gets its own
  meshes (frustum culling) and its own collision shapes.

**Collision by surface.** One `StaticBody3D` per surface:
- `TrackBody`: road, walls, cliffs and end blockers
- `MudBody`: mud strips
- `BridgeBody`: plank deck
- `SlopeBody`: grass

The non-road bodies carry `TrackSurface` metadata. `Trike` reads the
surface from each wheel's raycast hit (`wheel_surface`, `surface`) and
averages the TrikeConfig "Surfaces" factors over the grounded wheels:
- top speed factor
- drag above that speed
- grip factor

Untagged ground (props, ramps, test arenas) is ROAD, so road handling is
exactly what it was before.

**Safety and race data (`Track`).**
- `is_safe_index()` / `mark_unsafe()`: jump gaps (45 m before, 12 m after)
  and props (ramps, boulders, road trees and logs, ±10 m) are not respawn
  points.
- `VehicleProgress` only records a safe index as `last_safe_index`, and
  `reset()` falls back to `get_recovery_index()`.
- `get_item_box_transforms()` gives the item box spawn points (rows ×
  columns).
- `surface_at()` gives the expected surface at a point.
- `hazard_time` is the race clock for timed hazards. `RacerManager` advances
  it from GO.
- `build_timings` records milliseconds per build stage.

**Themes (milestone 08).** `Track.theme` (`TrackTheme`,
`resources/maps/themes/*.tres`) holds a map's look: road, curb, barrier,
bridge, slope and cliff paint (copied into `TrackMeshBuilder`), the scenery
style and palettes (`TrackDecorator`), backdrop colors (`TrackBackdrop`),
set-dressing colors (`TrackLandmarks`, `TrackStructures`) and, with
`apply_environment`, the sky, fog, ambient light and sun
(`RaceSession._load_track` → `TrackTheme.apply_to_world`, on a duplicated
Environment). The defaults are the forest values, so a track without a
theme (Forest Rush, test track) looks exactly as before; the map tests
confirm Forest Rush's scenery counts are unchanged.

Scenery styles (`TrackTheme.SceneryStyle`): FOREST (pines, round trees,
bushes, boulders, flowers); CANYON (solid striped rock spires instead of
pines, dry trees, shrubs, desert flowers); SNOW (the forest meshes plus
white snow-cap batches on the same transforms, snow mounds instead of
bushes, snow on boulders, no flowers). MultiMesh instances are tinted per
instance, which is why snow caps are separate batches.

**Per-map ground (milestone 08).**
- `Track.road_surface` tags `TrackBody` (Snow Slide: SNOW). Forest Rush
  and the test track keep ROAD, so their road handling is unchanged.
- `Track.bridge_surface` tags `BridgeBody` (Snow Slide: ICE, frozen bridges).
- Zone `"ice", u0, u1` is a surface band like mud (`TrackMeshBuilder.band_kinds`)
  with its own `IceBody` (ICE). Same collision quads, different body.
- `TrackSurface.Kind` gained SNOW and ICE; `TrikeConfig.snow_*` / `ice_*`.

**Cliff roads (milestone 08).** Zone `"cliff", side`: on that side the slope
uses `TrackMeshBuilder.cliff_profile` (a sheer 20 m rock face rising 1–2 m
behind the barrier, a ridge, then back down to the terrain) instead of
`slope_profile`. `cliff_weights` blend the two over `Track.zone_blend` (16 m)
so there are no seams. Render and collision use the same points; the face is
colored from `cliff_colors` with horizontal `cliff_band_colors`. Gorge faces
at bridges/gaps pick it up automatically. The decorator keeps cliff faces
clear (no trees, bushes, boulders or flowers).

**Crosswind (milestone 08).** Zone `"wind", side, strength`:
`Track.wind_at(index)` is a pure function of `hazard_time` (gusts between
35 % and 100 % of `strength`, `wind_gust_period` 5 s, faded in/out over
`zone_blend`). `RacerManager` sets `Trike.wind` each tick for the trikes this
computer simulates; `Trike._integrate_forces` adds it to the velocity after
the impact measurement (never an impact). Proxies ignore it. Windsocks and
blowing-snow particles (`TrackStructures._build_wind`) make it visible.

**New props (milestone 08).** `falling_rock` and `rolling_rock`
(`RollingRock`, an `AnimatableBody3D` like `FallingLog`: pose = function of
`hazard_time`; FALL drops from the cliff with a landing shadow, ROLL crosses
diagonally downhill; `is_active()` for the AI, `mid_crossing_time()` for
tests), `snowman` / `snowman_group` (knockable, props layer, reset with the
crates), and `ramp` with `{"length", "height", "width"}`. Boulders take the
theme's `road_boulder_color` (Snow Slide: snowbanks). All mark respawn-unsafe
stretches; AI avoidance radii are in `RacerManager.obstacle_radii`.

**Children.** Each child with `build_for_track(track)` runs in scene order:
1. Props (layout table, including `boulder`, `road_tree`, `falling_log` and
   `big_ramp`)
2. Decor (chunked MultiMesh batches with fade distances, grid-based
   road-clearance checks; nothing on bridges, gaps, clearings or open
   overlook sides)
3. Landmarks
4. Backdrop (terrain heightfield in tiles, nearest track sample per vertex by
   a two-pass grid sweep instead of vertices × samples; edges eased into the
   valley; a noise-warped section choice away from the road so cliffs
   between levels wind; far-forest pines on the terrain)
5. Structures (needs Backdrop's `terrain_height()`)

**Falling logs (`FallingLog`).**
- An `AnimatableBody3D` whose pose is a pure function of
  `Track.hazard_time`, so online peers see the same log at the same time
  with no extra sync.
- The AI ignores it while it's off the road (`is_active()`).

**Level of detail.**
- Trees, bushes, flowers, boulders and the far forest fade out by distance
  (`visibility_range_end`). Each batch node sits at the center of its
  instances, so the distance is measured from there.
- `GameSettings.apply_graphics` scales those distances by quality: Low 0.55,
  Medium 0.85, High 1.0 (group `scenery_lod`).

**Build profile.** Measured on a MacBook Air M4:

| Map | Before (old code) | After | Main stages after the rewrite |
|---|---|---|---|
| Test track, 1.2 km, headless | 330 ms | ~250 ms | geometry 99, backdrop 50 |
| Forest Rush, 7.45 km, headless | — | 1.1–1.4 s | geometry ~600, backdrop ~300–450, decor ~250 |
| Forest Rush, windowed | — | ~1.6 s | mesh uploads make the decorative parts slower |
| Rocky Canyon, 7.34 km | — | ~1.1 s headless, ~1.6 s windowed | geometry ~530, backdrop ~390 |
| Snow Slide, 7.49 km | — | ~1.4 s headless, ~2.0 s windowed | geometry ~590, backdrop ~500, decor ~210 (snow caps) |

The old code's cost grew with the square of the map size (terrain vertices
× track samples, and scenery × samples). For Forest Rush it would have taken
several seconds.

## Camera

`FollowCamera` is separate from the trike, so it never inherits roll or pitch.
It updates in `_process` from `get_global_transform_interpolated()`. Two
modes, picked from the target type:

- **Vehicle** (target is a `Trike`):
  - yaw blends heading and velocity direction (steady in drifts)
  - aims down the slope
  - with speed it pulls back, drops, looks further ahead and widens FOV
  - boost adds an FOV kick
- **Character** (falling or on-foot rider): a "dragged" follow camera at fixed
  distance that never auto-turns, so camera-relative walking stays stable.

`set_target(node)` blends over `transition_time` (0.9 s) with softened
following and position smoothing; tested max 0.27 m per frame, no cuts. A
sphere cast keeps it out of walls and terrain, with a minimum ground
clearance. It snaps on respawn (`respawned`).

## Physics layers

| Layer | Bit value | Used by | Collides with (mask) |
|---|---|---|---|
| 1 world | 1 | track (road, mud, bridge, slope, walls, cliffs), gates, rocks, ramps, boulders, road trees, falling logs (kinematic), scenery and structure colliders | — (static) |
| 2 vehicles | 2 | trikes (chassis + rider capsule; the capsule is disabled while the rider is off) | world, vehicles, props (1+2+4) |
| 3 props | 4 | crates, cones | world, vehicles, props (1+2+4) |
| 4 riders | 8 | thrown rider (`RiderRagdoll`), rider on foot (`RiderOnFoot`) | ragdoll: world, vehicles, props (1+2+4), own trike ignored until 1.6 m clear · on foot: 1+2+4 |

Other queries: wheel rays mask 1+4 (world + props). Camera sphere cast and
ground check mask 1. Rider ground probe mask 1. Finish trigger mask 2
(vehicles only; riders on foot can't finish). Items have no collision: box/peel/puddle contact is a distance test in `ItemManager`; the host's mud bomb ray masks 1 (world).

## Rendering and visual architecture (milestone 2)

**Renderer: Mobile, unchanged.** It runs at the display-locked 120 fps on the
target-class MacBook Air M4 at 1280×720 and 1920×1080. Forward+ would add
SSAO/SSIL and better shadow filtering, but at a real GPU cost on a fanless
laptop. The cartoon look comes from color, shape and lighting, which Mobile
handles well, so switching wasn't justified.

**Lighting:** a warm side-lit sun (PSSM 2 splits, 110 m, soft blur), a cool
shadowless fill light from the opposite side (keeps faces and shaded sides
readable), warm sky-based ambient, light fog with aerial perspective,
Filmic tonemapping, and +18% saturation / +6% contrast grading.

**Materials:** characters and trike use lambert-wrap diffuse with rim light,
glossy plastic and chrome parts. The track uses sRGB vertex colors for the
large-scale paint, multiplied by a runtime `NoiseTexture2D` mapped in world
space for fine grain (`TrackMaterials`). There are no image assets.

**Procedural mesh toolkit** (`scripts/visuals/`):
- `RoundedBoxMesh`, `ArcMesh`: `@tool` PrimitiveMesh scripts (soft boxes,
  fenders, smile), visible in the editor.
- `MeshKit.combine`: merges primitives into one flat-shaded, vertex-colored
  surface. `MeshKit.batch` makes a MultiMesh. A whole forest is one draw call
  per tree type.

**Trike visuals:** only the `Visuals` subtree changed. `TrikeVisuals` places
wheel nodes at `mount - up * suspension_length`, exactly where the physics
rays put the wheels (tested). The handlebar pivots on the steering axis.
Body-color parts are in the `body_paint` group.

**Rider:** `Rider` is a bone-style node hierarchy (`BONE_MAP`: hips, spine,
chest, neck, head, upper arm/forearm/hand, thigh/shin/foot per side). Limbs
are placed every frame by an analytic two-bone IK solver toward targets on
the trike: grips on the handlebar, foot targets above the footrests. The chest
twists to follow the bars, so both hands stay in reach at full lock (tested:
under 2 cm error). For skeletal animation later, swap the meshes for a
skinned mesh and drive `Skeleton3D` bones with the same pose roles and IK
targets (Godot's `SkeletonIK3D`/`TwoBoneIK3D` or this solver).

**Track rendering vs. collision:** `TrackMeshBuilder` builds collision and
rendering in separate passes. The render pass adds curbs, verge, ruts,
plank/post/rail barriers and finely banded slopes on exactly the same surfaces.
Collision triangles are identical to milestone 1 (verified: 19,008 of 19,008
match).

**Scenery collision:** solid-looking scenery gets colliders on its own
StaticBody (layer 1): tree trunks (cylinders), boulders (convex hulls built
from the same mesh as the visual), signs, hay bales, cabin and logs (boxes).
Foliage, bushes, flowers, bunting and backdrop have none. The terrain starts
below the out-of-bounds depth, so a falling trike respawns before reaching it.

## File map

| Path | Purpose |
|---|---|
| `scripts/vehicles/trike_controller.gd` | `Trike`: physics, gameplay state, impact reporting, riderless mode |
| `scripts/vehicles/trike_config.gd` | `TrikeConfig`: tuning resource |
| `scripts/vehicles/trike_input.gd` | `TrikeInput`: control data |
| `scripts/vehicles/player_input_source.gd` | Local input → `TrikeInput` |
| `scripts/vehicles/trike_visuals.gd` | Cosmetic wheel/fork/rider/effects |
| `scripts/characters/rider.gd` | Rider pose: ride (lean, chest twist, IK to bars) and off-trike modes (flail, get-up, stand/run) |
| `scripts/rider/rider_controller.gd` | `RiderController`: ejection/recovery state machine |
| `scripts/rider/rider_config.gd` | `RiderConfig`: all ejection/fall/on-foot/mount values |
| `scripts/rider/rider_ragdoll.gd`, `rider_on_foot.gd` | Falling body and walking body |
| `scripts/camera/follow_camera.gd` | Chase camera |
| `scripts/track/*.gd` | Track path (+ grid lookup), route builder (`TrackRoute`), mesh builder (chunks, surfaces), `MeshBatch`, `TrackSurface`, track node (zones, safety, item boxes), gate, props, decor, structures |
| `scenes/tracks/forest_rush.tscn`, `scenes/main/forest_rush.tscn` | Forest Rush map data and its race scene |
| `scenes/tracks/rocky_canyon.tscn`, `snow_slide.tscn` (+ `scenes/main/` race scenes) | Rocky Canyon and Snow Slide map data and race scenes |
| `scripts/track/track_theme.gd`, `resources/maps/themes/*.tres` | `TrackTheme`: a map's paint, scenery style and sky |
| `scripts/props/rolling_rock.gd` (+ `scenes/props/falling_rock.tscn`, `rolling_rock.tscn`), `scenes/props/snowman.tscn` | Canyon rock hazards, snowmen |
| `scripts/ui/map_preview.gd` | Route-map previews drawn from track data |
| `scripts/audio/sound_synth.gd`, `sound_bank.gd`, `sound_player.gd` | Synthesized sounds, the named sound bank, one-shot players |
| `scripts/vehicles/trike_audio.gd`, `trike_effects.gd` | Trike sounds and particles |
| `scripts/rider/rider_audio.gd`, `scripts/race/race_audio.gd` | Rider sounds; race sounds and finish confetti |
| `scripts/characters/rider_look.gd`, `rider_style.gd`, `resources/characters/looks/*.tres` | Rider looks and how they are applied |
| `tests/polish_tests.gd` | Milestone 09 tests (`--only=polish`) |
| `scripts/props/road_boulder.gd`, `road_tree.gd`, `falling_log.gd` (+ `scenes/props/*.tscn`) | Road obstacles and the timed log hazard |
| `tests/map_tests.gd`, `tests/map_test_runner.*` | Forest Rush checks (main suite); long timed races |
| `scripts/race/vehicle_progress.gd` | Per-racer progress and respawn point |
| `scripts/race/finish_tracker.gd` | `FinishTracker`: player-specific finish and pending finish |
| `scripts/race/racer.gd` | `Racer`: one racer's record |
| `scripts/race/racer_manager.gd` | `RacerManager`: registry, AI spawning, progress, respawns, race clock |
| `scripts/ai/ai_driver.gd` | `AIDriver`: AI racer brain (`TrikeInputSource`) |
| `scripts/ai/ai_driver_config.gd` | `AIDriverConfig`: difficulty resource |
| `resources/ai/ai_*.tres` | Easy / Medium / Hard presets |
| `scripts/vehicles/trike_input_source.gd` | `TrikeInputSource`: base for keyboard/AI/network input |
| `scenes/main/race_five.tscn` | 5-racer race (1 human + 4 mixed AI) |
| `tests/racer_tests.gd` | Racer registry and AI tests (run by `test_runner.gd`) |
| `scripts/race/race_state_machine.gd` | `RaceStateMachine`: states and allowed transitions |
| `scripts/race/race_controller.gd` | `RaceController`: countdown, racing, finish timeout, results, race again |
| `scripts/race/checkpoint_progress.gd` | `CheckpointProgress`: ordered checkpoints, valid distance |
| `scripts/race/race_positions.gd` | `RacePositions`: ranking with hysteresis |
| `scripts/ui/race_menu_base.gd`, `results_screen.gd`, `lobby_screen.gd` | Results and lobby screens (built in code from the UI theme) |
| `tests/race_flow_tests.gd` | Race flow tests (run by `test_runner.gd`) |
| `scripts/core/game_settings.gd`, `game_session.gd` | Autoloads `GameSettings`, `GameSession` |
| `scripts/net/*.gd` | `Net` (autoload), `NetworkTransport`, `ENetTransport`, `NetSnapshot`, `SnapshotBuffer`, `NetRaceSync`, `Lobby`, `LobbyPlayer`, `NetAddress` |
| `tests/net_unit_tests.gd`, `tests/net/*` | In-process network tests; multi-process network suite |
| `scripts/items/item_manager.gd` | `ItemManager`: boxes, held items, requests/validation/events, bombs, puddles, peels |
| `scripts/items/item_config.gd`, `resources/items/default_item_config.tres` | `ItemConfig`: every item value |
| `scripts/items/item_kind.gd`, `item_roll.gd`, `item_rules.gd` | Item ids/names/colors, position-weighted roll, punch targeting and strength |
| `scripts/items/item_box.gd`, `mud_bomb.gd`, `mud_patch.gd`, `banana_peel.gd` | In-world item objects (no collision) |
| `scripts/items/item_visuals.gd`, `item_sounds.gd` | Procedural item meshes and effects; synthesized item sounds |
| `scripts/ai/ai_item_tactics.gd` | When an AI racer uses its item |
| `tests/item_tests.gd` | Item tests (run by `test_runner.gd`, `--only=items`) |
| `scripts/maps/*.gd`, `resources/maps/*.tres` | `MapInfo`, `MapCatalog`, the three maps |
| `scripts/menu/*.gd`, `scenes/menu/*.tscn` | Main menu, its screens and 3D background |
| `scripts/ui/kit/ui_kit.gd` | `UiKit` design system |
| `scripts/ui/settings_panel.gd`, `map_card.gd`, `map_preview.gd` | Shared settings page, map card, preview placeholder |
| `default_bus_layout.tres` | Audio buses Master, Music, SFX |
| `tests/ui_tests.gd` | Menu/lobby/settings/pause/HUD tests (run by `test_runner.gd`) |
| `scripts/ui/hud.gd`, `pause_menu.gd` | UI |
| `scripts/main/main.gd` | `RaceSession` |
| `scripts/props/ramp.gd` | Tool script: wedge ramp mesh (striped planks) + collision |
| `scripts/visuals/*.gd` | `RoundedBoxMesh`, `ArcMesh`, `MeshKit` procedural mesh helpers |
| `scripts/track/track_materials.gd` | Shared track materials + noise detail texture |
| `scripts/track/track_landmarks.gd`, `track_backdrop.gd` | Built set dressing; distant scenery and terrain |
| `scripts/ui/speed_gauge.gd` | Arc speedometer control |
| `resources/ui/trike_theme.tres` | UI theme: system rounded font with fallbacks, buttons, panels |
