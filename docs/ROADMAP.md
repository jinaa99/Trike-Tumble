# TRIKE TUMBLE — Roadmap

## Final demo milestones (plan: `docs/FINAL_DEMO_AUDIT.md`)

- [x] **01 — fixes:** finish while riderless (pending finish), `attach_to()`
      lifecycle, E-key tests, doc drift. 143/143 checks.
- [x] **02 — AI racers and five-racer offline race:** `RacerManager` +
      `Racer` registry (1–5 racers, unique ids, slots, own progress/respawn/
      finish), `AIDriver` through `TrikeInput` (track following, corner speed
      planning, obstacle/racer avoidance, ramps, drifting, unsticking, finish
      pull-over, on-foot recovery and mounting), Easy/Medium/Hard,
      `race_five.tscn` and `--ai=N --difficulty=…`. 217/217 checks.
      Owner playtest of AI feel still open.
- [x] **03 — race management:** `RaceStateMachine` (LOBBY → COUNTDOWN →
      RACING → FINISHED → RESULTS), `RaceController` (3-2-1-GO with locked
      controls, finish timeout, DNF, results, Race Again / Return to Lobby
      without a reload), ordered checkpoints (`CheckpointProgress`, finish
      gate), live positions (`RacePositions`), HUD position/CP, results and
      lobby screens. 281/281 checks. Owner playtest still open.
- [x] **04 — main menu, lobby and UI:** menu scene with 3D background,
      Play/Host/Join/Settings/Quit, map selection (placeholder previews),
      lobby (players, ready, host, AI fill, map), saved settings (audio buses,
      resolution, fullscreen, quality, key rebinding, name), HUD race state +
      item slot, pause Settings/Return to Lobby, `UiKit` design system,
      `NetworkTransport` interface with an offline implementation. 366/366 checks.
- [x] **05 — online multiplayer (ENet):** owner-simulated trikes +
      host authority, kinematic proxies with jitter-buffer interpolation,
      host-validated snapshots, host-decided checkpoints/positions/finish,
      lobby sync, connection handling (timeout, full, version, duplicate,
      mid-race join, disconnect, host shutdown, rejoin). 395/395 checks +
      32/32 multi-process network checks (2, 3 and 5 instances on one Mac).
      **Not yet tested: two real computers on a LAN, Windows, internet.**
- [x] **06 — Forest Rush complete racing map:** 7.45 km downhill (630 m
      drop, 30 checkpoints) in 8 sections: mountain start, fast forest
      descent, hairpins with a rock narrows, two wooden trestle bridges, mud
      and obstacles (boulders, road pines, falling logs), ravine jump, final
      descent with overlooks, finish with stands.
      - Map system: route segments, width profile, zones, chunked meshes and
        collision, road surfaces (mud/grass/planks), safe recovery points,
        item box points.
      - Faster track build (grid lookups, linear terrain sweep, packed mesh
        arrays): the test track went from 330 to 250 ms, and Forest Rush
        builds in 1.1–1.4 s.
      - Tests: 448/448 checks (52 map checks), 14/14 timed map races, 36/36
        network checks (Forest Rush online included).
      - Measured times: Hard AI about 5:25, Medium about 5:37, Easy about
        6:42, a simple player driver 5:23.
      - **Human playtest of the map and real human times still open.**
- [ ] Next (only when the owner starts it): see `docs/FINAL_DEMO_AUDIT.md` §9.

## Milestone 1: single-player trike prototype ✅ (implemented, automated tests pass)

- [x] Main game scene (track, trike, camera, HUD, pause menu)
- [x] Procedural downhill test track (~1.2 km) with walls, slopes, gates,
      ramps, crates, cones, rocks, trees and mountains
- [x] Placeholder three-wheel trike (1 front, 2 rear wheels; visible steering)
- [x] Placeholder rider that leans into turns
- [x] Custom arcade vehicle controller (raycast suspension, drive, brake,
      reverse, steer, drift + boost, handbrake, air control, self-righting)
- [x] Third-person follow camera (smoothed, speed FOV, wall collision)
- [x] Keyboard + basic gamepad input map
- [x] Environment collision and knockable props
- [x] Reset (R) and auto-recovery (overturned, stuck, out of bounds)
- [x] Speed HUD, race timer, drift meter, boost indicator, finish message
- [x] Automated test suite (64 checks) and screenshot capture tool
- [ ] **Hands-on playtest by the owner with a real keyboard** (feel tuning)

## Milestone 2: visual polish ✅ (implemented; 68/68 automated checks pass)

- [x] Trike redesign: rounded toy look, tubular frame, tank with number decals,
      bucket seat, footrests, fenders, BMX-style front wheel and white drift
      sleeves, handlebar on the steering axis, whip flag. Physics untouched.
- [x] Rider redesign: big expressive head, helmet with ears, crest, visor and
      goggles, jacket, scarf, gloves, boots. Bone-style hierarchy plus two-bone
      IK (hands on grips, boots on footrests, chest twists with the bars).
- [x] Track redesign: dirt road with curbs, verge and grain; plank barriers
      with posts and rail; multi-tone grass slopes; pines, round trees, bushes,
      boulders, flowers; chevron turn signs, hay bales, cabin, log pile,
      bunting; titled gates; terrain, layered mountains, hills, clouds, lake.
- [x] Lighting: side-lit warm sun, cool fill light, warm ambient, soft
      shadows, lighter fog, saturation/contrast grading (Mobile renderer kept).
- [x] Camera: closer framing, aims down the slope, speed-based pull-back,
      look-ahead and FOV, boost FOV kick, sphere-cast collision, ground clearance.
- [x] HUD + pause menu: theme, speed gauge, timer panel, drift meter with tier
      marker, pulsing BOOST, pop-in messages, fading control hints, styled menu.
- [x] Drift effects: soft fading dust, tier-colored sparks.
- [x] Screenshots in `docs/screenshots/milestone_02/`.
- [ ] Owner review of the look and a hands-on playtest.

## Milestone 3: rider ejection and recovery ✅ (implemented; 112/112 automated checks pass)

- [x] Rider state machine: RIDING → EJECTED → RAGDOLL → GETTING_UP → ON_FOOT → MOUNTING → RIDING
- [x] Ejection on big impacts (configurable threshold) and on overturning;
      grace period after mounting; small bumps, scrapes, crates and ramps don't eject
- [x] Cartoon "ragdoll": one tumbling rigid body + procedural limb flailing
- [x] Get-up animation (push up, head shake, dizzy stars, confused head scratch)
- [x] Camera-relative running on foot (WASD), run cycle
- [x] [E] GET ON prompt within 2.6 m; mount hop with hands reaching for the bars
- [x] Riderless trike brakes to a stop, never teleports; R = emergency recovery
- [x] Camera blends trike → falling rider → rider on foot → trike, without cuts
- [x] Thrown over a barrier → rider climbs back onto the road near the trike
- [ ] Owner playtest: tune eject threshold, fling and recovery timings

## Milestone 4: make the trike feel great (next)

- Owner playtest. Tune `default_trike_config.tres` from feedback.
- Hard-impact detection (`hard_impact` signal): camera shake, squash/stretch,
  rider flinch.
- Sound: engine/pedal loop, skid, impacts, boost (original or CC0 only,
  after approval).
- Camera polish: tighter at low speed, drift framing, airborne framing.
- Track surface types (dirt vs grass grip) via physics material metadata.
- Performance for 5 racers: merge each trike's static visual parts into a few
  meshes (each trike + rider is ~130 mesh nodes today).

## Milestone 5: race structure

- [x] Countdown, checkpoints, positions, results screen (final demo milestone 03).
- Laps or long single runs: decided with the map work.
- [x] AI opponents (done in final demo milestone 02, `AIDriver`).
- Racer-vs-racer bumping and knockback (`Trike.apply_knockback`).

## Milestone 6: items

- Item boxes, random item roll, held-item HUD.
- Throwables with knockback; big hits call `RiderController.eject()`.

## Milestone 7: multiplayer (up to 5)

- Choose transport (ENet LAN/direct IP first; no Steam).
- Server-authoritative simulation, clients send `TrikeInput`; state sync and
  interpolation for remote trikes; rider state via `RiderController.get_sync_state()`.
- Lobby, player colors, ready-up.

## Milestone 8: content and polish

- 3 final maps (5–10 minute races), original character models, menus,
  settings, export presets for macOS and Windows.
