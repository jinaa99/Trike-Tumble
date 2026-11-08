# TRIKE TUMBLE — Roadmap

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

## Milestone 3: make the trike feel great (next)

- Owner playtest. Tune `default_trike_config.tres` from feedback.
- Hard-impact detection (`hard_impact` signal): camera shake, squash/stretch,
  rider flinch.
- **Fall-off state:** rider gets thrown on big impacts, tumbles, then a quick
  recovery puts them back on the trike.
- Sound: engine/pedal loop, skid, impacts, boost (original or CC0 only,
  after approval).
- Camera polish: tighter at low speed, drift framing, airborne framing.
- Track surface types (dirt vs grass grip) via physics material metadata.
- Performance for 5 racers: merge each trike's static visual parts into a few
  meshes (each trike + rider is ~130 mesh nodes today).

## Milestone 4: race structure

- Countdown, checkpoints, laps or long single runs, positions, results screen.
- AI opponents (reuse `TrikeInput`, as `TrackAutopilot` already does) for
  solo play and testing.
- Racer-vs-racer bumping and knockback (`Trike.apply_knockback`).

## Milestone 5: items

- Item boxes, random item roll, held-item HUD.
- Throwables with knockback and fall-off.

## Milestone 6: multiplayer (up to 5)

- Choose transport (ENet LAN/direct IP first; no Steam).
- Server-authoritative simulation, clients send `TrikeInput`; state sync and
  interpolation for remote trikes.
- Lobby, player colors, ready-up.

## Milestone 7: content and polish

- 3 final maps (5–10 minute races), original character models, menus,
  settings, export presets for macOS and Windows.
