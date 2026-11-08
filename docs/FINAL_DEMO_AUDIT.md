# TRIKE TUMBLE — Final Demo Audit

Audit date: 2026-11-08 · Godot 4.7.2 stable · macOS (MacBook Air M4, 16 GB)
Scope: everything in the repository at the end of milestone 3. No features were
added, and no project files were changed during the audit (the only new files
are this document and one evidence screenshot). All probes ran from scratch
scripts outside the project.

---

## 0. Summary

The project is a **polished single-player vertical slice**:
- one procedurally built downhill track (~1.2 km, ~49 s run)
- one trike with arcade physics, drifting and boosts
- an expressive procedural rider with the full wipeout → get-up → run →
  remount loop
- a styled HUD and pause menu

Everything that exists is covered by 112 automated checks, which all pass.

For the planned *demo*, most of the game around that slice is still
**missing**:
- multiplayer (no networking code at all)
- the race structure: countdown, checkpoints, positions, results
- items
- the three named maps
- menus and lobby
- audio
- exports

One **broken** edge case was found (the race never finishes if the trike
crosses the line riderless), plus one latent robustness bug in
`RiderController.attach_to()` that multiplayer spawning would hit.

Status counts (24 systems): **COMPLETE 4 · PARTIAL 8 · BROKEN 1 · MISSING 11 · UNVERIFIED 0**.

---

## 1. Current project architecture

```
RaceSession (scripts/main/main.gd, scenes/main/main.tscn) — single-player race glue
├─ WorldEnvironment, Sun, FillLight              Mobile renderer, Jolt physics, 60 Hz + interpolation
├─ TestTrack (Track)                             procedural: TrackPath → TrackMeshBuilder (render + collision passes)
│  ├─ Props (track_props.gd)                     crates, cones, rocks, ramps from a data table
│  ├─ Decor (track_decorator.gd)                 trees/bushes/boulders/flowers (MultiMesh) + trunk/boulder colliders
│  ├─ Landmarks (track_landmarks.gd)             chevron signs, hay bales, cabin, logs, bunting + box colliders
│  └─ Backdrop (track_backdrop.gd)               terrain heightfield, mountains, hills, clouds, valley, lake
├─ Trike (Trike: RigidBody3D)                    raycast suspension + arcade forces; impact reporting; riderless mode
│  ├─ PlayerInputSource → TrikeInput             input abstraction (keyboard, tests, AI and network all write TrikeInput)
│  └─ Visuals (TrikeVisuals) → Rider (IK)        cosmetic only; wheels placed exactly at physics wheels
├─ RiderCharacter (RiderController)              state machine RIDING/EJECTED/RAGDOLL/GETTING_UP/ON_FOOT/MOUNTING
│  ├─ Ragdoll (RigidBody3D) · OnFoot (CharacterBody3D) · DizzyStars
├─ FollowCamera                                  vehicle chase mode + character mode, blended target switching
├─ HUD (CanvasLayer)                             timer, speed gauge, drift meter, boost, messages, [E] prompt
└─ PauseMenu (CanvasLayer, always processing)
```

| Metric | Value |
|---|---|
| Scripts | 32 (5,234 lines). Largest: `test_runner.gd` 881, `trike_controller.gd` 478, `rider_controller.gd` 409 |
| Scenes | 14 · Resources: 3 (`.tres` configs and theme) |
| Imported assets | **none**: no images, audio, models or fonts. Everything is procedural or a system font |
| Input actions | accelerate, brake, steer_left, steer_right, drift, reset, pause, interact (keyboard + gamepad) |
| Physics layers | 1 world · 2 vehicles · 3 props · 4 riders |
| Per player | trike 96 nodes (69 meshes) + rider model 81 nodes (58 meshes) + rider character 12 nodes |

**Strengths:**
- Clean separation: vehicle vs. rider state, visuals vs. physics, collision
  pass vs. render pass.
- All tuning lives in resources (`TrikeConfig`, `RiderConfig`).
- Input is abstracted through `TrikeInput`.
- Strong automated and visual test tooling.

**Structural limitation:** `RaceSession` is hard-wired to exactly one
`$Trike`, one `$RiderCharacter`, one camera and one HUD. Every multiplayer,
AI and race-structure feature needs a **racer registry** first.

---

## 2. Actual test results (run during this audit)

| Check | Command / method | Result |
|---|---|---|
| Godot discovery | PATH (none), Spotlight `org.godotengine.godot` | One install: `/Users/sharu/Downloads/Godot.app` → `4.7.2.stable.official.ed1daf0bf`. Has the macOS quarantine flag (runs via App Translocation) |
| Export templates | `~/Library/Application Support/Godot/export_templates/` | **Folder exists, empty**: no templates installed |
| Import | `--headless --import` | exit 0, no errors or warnings |
| Automated suite | `--headless --fixed-fps 60 --scene res://tests/test_runner.tscn` | **112 passed, 0 failed**, exit 0, 5 s |
| Strict mode (warnings = errors) | same suite on a scratch copy with `override.cfg` (project untouched) | **112 passed, 0 failed**, exit 0, zero warnings |
| Script parsing | `--check-only --script` on all 32 `.gd` files | 0 failures |
| Scene/resource loading | scratch script: `load()` every `.tscn/.tres/.gd`, instantiate every scene | 14 scenes, 3 resources, 32 scripts, **0 errors** |
| Main scene startup (headless) | `--headless --quit-after 600` | exit 0, no errors |
| Main scene startup (real renderer) | windowed, `--quit-after 900`, Metal "Forward Mobile" | exit 0, no errors |
| Visual capture (all modes) | `tests/visual_capture.tscn` | 32 screenshots, no errors; real corner-crash ejection reproduced |
| Performance, 1 racer | `visual_capture perf`, 18 s real time | 120 fps (display cap), worst frame 12 ms, 480 draw calls, 728k primitives |
| Performance, 5 racers (probe) | main scene + 4 extra trike/rider rigs, all autopiloted, 20 s | **120 fps**, worst frame 12 ms, **811 draw calls**, 823k primitives, physics 0.96 ms/frame (1 racer: 547 / 0.67 ms), 1,758 nodes |
| Vehicle-vs-vehicle (probe) | two ridden trikes in an arena | Head-on 15+15 m/s: impact 18.9, **both ejected** · rear-end 20 m/s into a stopped trike: 11.7, **both ejected** · T-bone 15 m/s: 9.6, nobody ejected · side-swipe: inconclusive (probe spawned overlapping) |
| Finish edge case (probe) | eject just before the line; empty trike rolls past; remount after the line | **Race never finishes** (`is_race_finished() == false`). BROKEN |
| `attach_to()` before `_ready` (probe) | instantiate rider, call `attach_to()` before ready | Null crash (`on_foot` not ready), then `_ready` calls `attach_to()` again → "Signal 'impact' is already connected" |

Not testable here: Windows (no machine), export builds (no templates or
presets), audio (none exists), networking (none exists), human feel.

---

## 3. System-by-system status

| # | System | Status | Evidence / notes |
|---|---|---|---|
| 1 | Vehicle physics | **COMPLETE** | 40+ automated checks (accel, top speed, brakes, reverse, steering, drift, boost, handbrake, collisions, recovery), identical numbers since milestone 1. Not yet tuned by a human player |
| 2 | Rider character & animation | **PARTIAL** | Procedural rider with IK riding pose (tested < 2 cm), flail/get-up/run/mount poses, verified in screenshots. Missing: skinned/skeletal model, per-player look (all 5 riders identical), victory/idle/throw/hit animations |
| 3 | Rider ejection & recovery | **COMPLETE** | 44 rider checks plus a real-track corner crash. The threshold (11) makes wipeouts rare (glancing barrier hits read 1.6–5.2); needs playtest tuning |
| 4 | On-foot movement & mounting | **COMPLETE** | Camera-relative WASD, mount distance, mounting, righting a flipped trike all tested. Gaps: the real **E key** isn't covered by a key-event test (only `interact_pressed`); gamepad X unverified; no jump |
| 5 | Camera | **COMPLETE** | Chase framing, slope aim, collision, blended transitions (max 0.27 m/frame) tested. Local single view only |
| 6 | Race countdown & management | **PARTIAL** | Timer starts on first throttle; out-of-bounds/emergency respawn work. **No countdown**, no race states (pre-race, racing, finished, results), single racer only |
| 7 | Checkpoints & progress | **PARTIAL** | `VehicleProgress` tracks the nearest sample and the last safe sample (respawn point). No checkpoints, no ordered validation, no positions/ranking |
| 8 | Finish line & results | **BROKEN** | Finish is an `Area3D` entry event that's ignored while riderless → verified: the race never finishes if the trike crosses riderless. No results screen; the race just continues after "FINISH!" |
| 9 | Item boxes | **MISSING** | — |
| 10 | Item usage & projectiles | **MISSING** | — (no input action reserved) |
| 11 | Vehicle-to-vehicle collisions | **PARTIAL** | Physical collisions work (layer 2 masks layer 2) and feed the ejection system (probe). No dedicated bump/knockback tuning or design; a stopped victim of a rear-end is also ejected; no automated test |
| 12 | Multiplayer architecture | **MISSING** | Groundwork only: `TrikeInput` abstraction, `RiderController.get_sync_state()`, seeded fling RNG. No networking code; `RaceSession` is single-player |
| 13 | Five-player synchronization | **MISSING** | — (5 local racers render at 120 fps on M4, see §6) |
| 14 | Forest Rush map | **PARTIAL** | The test track is forest-themed and production quality, but ~1.2 km / ~49 s (target 5–10 min races), not named or data-driven |
| 15 | Rocky Canyon map | **MISSING** | — |
| 16 | Snow Slide map | **MISSING** | — |
| 17 | Main menu | **MISSING** | Game boots straight into the race |
| 18 | Host / Join lobby | **MISSING** | — |
| 19 | Map selection | **MISSING** | — |
| 20 | HUD & pause menu | **PARTIAL** | Timer, speed gauge, drift meter, boost, messages, [E] prompt, pause (Resume/Restart/Quit) verified at 720p/1080p. Missing for the demo: countdown, position, item slot, racer list/name tags, results, "leave race" |
| 21 | Audio & SFX | **MISSING** | No audio files, no AudioStreamPlayers, no bus layout |
| 22 | Graphics & performance | **PARTIAL** | Verified 120 fps on M4 with 1 and 5 racers. Unverified on Windows and weaker GPUs; draw calls grow ~66 per racer; no quality settings; Metal reports no GPU timings |
| 23 | Mac export | **MISSING** | No `export_presets.cfg`, no export templates installed, no signing/notarization plan, default Godot icon |
| 24 | Windows export | **MISSING** | Same as Mac; `rendering_device/driver.windows="d3d12"` is set but never run on Windows |

### Completed systems
Vehicle physics, rider ejection & recovery, on-foot movement & mounting,
camera. All are backed by automated tests and screenshots, and all still need
human feel-tuning.

### Incomplete systems (PARTIAL)
Rider character & animation, race management, checkpoints/progress, vehicle-
to-vehicle collisions, Forest Rush, HUD & pause, graphics & performance.

### Broken systems
- **Finish line** (verified): crossing while riderless is ignored forever.
- **Latent bug** (verified with a probe, not reachable in the current game):
  `RiderController.attach_to()` is not idempotent and crashes if called
  before `_ready`. Multiplayer spawning will call it.

### Missing systems
Items (boxes, usage, projectiles), multiplayer (architecture, 5-player sync,
lobby), Rocky Canyon, Snow Slide, main menu, map selection, audio, Mac
export, Windows export.

### Documentation drift (found while reading)
- `GAME_DESIGN.md` still says overturned trikes auto-recover after 1.5 s, and
  lists "falling off the trike" as a planned feature. Both are superseded by
  milestone 3.
- `TECHNICAL_ARCHITECTURE.md`: the camera section describes a ray (it's now a
  sphere cast with a character mode), the physics-layer table lacks layer 4
  "riders", and the signals list lacks `impact`/`set_rider_aboard`.
- `CLAUDE.md` physics-layer line lacks "riders".
- `TESTING.md` says the input map test covers "all 7 actions". There are 8,
  and the test's `REQUIRED_ACTIONS` omits `interact`.

---

## 4. Performance problems

| Problem | Measured | Risk | Fix |
|---|---|---|---|
| Draw calls per racer | +66 per racer (547 → 811 for 5) | Fine on M4; risky on Windows laptops with integrated GPUs (Intel UHD) | Merge each trike's static parts per material at spawn (MeshKit already does this for scenery); merge rider parts per bone; lower rider sphere segments (28×16 today) |
| Primitives | 728k (1 racer) → 823k (5), shadow passes included | Moderate | Fewer shadow casters (flowers, bushes, small props off); visibility ranges on scenery |
| Track build time | ~425 ms for 1.2 km; the terrain heightfield is O(cells × samples) in GDScript | 5–10 min maps are 5–10× longer → multi-second loads and big single meshes | Spatial hashing for nearest-sample lookups; build in chunks per ~200 m with visibility ranges; optionally a loading screen |
| One giant mesh + collider per track part | 19,008 collision triangles for 1.2 km | Long maps → very large meshes, no culling | Chunk render meshes and collision per segment |
| GPU headroom unknown | Metal reports 0.00 ms GPU time | Can't predict weaker hardware | Test on real Windows hardware; add a frame-time overlay and quality presets |
| Display cap hides headroom | Always 120 fps (macOS compositor) | — | Measure on Windows with vsync off |

No current performance *problem* on the development machine. The risks are
longer maps and weaker hardware.

---

## 5. Visual problems

1. **All riders look identical.** Only the trike body recolors
   (`body_paint`). Five players need distinct helmet/jacket colors (and
   ideally name tags) to be readable.
2. No in-world racer labels or position indicators.
3. Rider is rigid rounded shapes; thighs clip slightly into the tank; limbs
   can poke into the ground while tumbling.
4. Off-road recovery is a cut, not a climb animation. Righting a flipped trike
   on mount is instant.
5. Shaded barrier planks and curbs pick up a bluish tint.
6. The aerial view of the terrain is plain, with cliff seams where two track
   sections meet.
7. Forced (non-crash) ejection at speed lets the rider tumble over the
   still-rolling trike for a moment. Not reachable in play today; items will
   make it reachable.
8. The app icon is the default Godot icon; there's no splash or branding.
9. HUD fonts are system fonts (Arial Rounded on macOS); the Windows fallback
   (Segoe UI Black / Arial Black) has never been seen.

---

## 6. Multiplayer risks

| Risk | Why it matters | Mitigation |
|---|---|---|
| **Physics is not deterministic** (Jolt, floats, different machines) | Lockstep is impossible; naive server-authoritative rigid bodies feel laggy for the driver | Owner-authoritative: each peer simulates its own trike + rider; host relays state at 20–30 Hz; remote racers are kinematic proxies with interpolation. Acceptable for a friends-only demo (no anti-cheat need) |
| Trike has no "proxy" mode | Remote trikes must not run suspension/drive physics, but visuals read `wheel_suspension_length`, `steer_angle`, `forward_speed`, drift/boost | Add a proxy mode (frozen kinematic body + synced visual state) |
| Racer-vs-racer contacts between proxies | Two owners each see the other as kinematic → one-sided, inconsistent bumps | Victim-side resolution: the owner applies knockback when its body is hit, and contact RPCs carry impulses. Tune generously (party game) |
| Rider ejection across the network | Only the owner detects impacts; ragdoll physics differs per machine | Sync `RiderController` state + ragdoll transform (`get_sync_state()` exists); remote ragdolls are interpolated, not simulated |
| Single-player assumptions everywhere | `RaceSession` (`$Trike`), HUD, camera, input polling assume one local player | Racer registry and a `local_racer` concept before any networking |
| `attach_to()` not idempotent | Spawn code will hit the verified double-connect/null crash | Fix first (guard + defer until ready) |
| Connectivity without Steam | ENet needs a reachable host: LAN works, internet needs port forwarding; relays/signaling servers are services | Demo: LAN + direct IP (host forwards one UDP port), documented. Optional later: free self-hosted relay (needs owner approval) |
| Items authority | Item rolls and hits must agree for everyone | Host-authoritative item boxes, rolls and projectile spawns; owners report hits |
| Race state | Countdown, checkpoints, finish order must be identical | Host-authoritative race state machine, broadcast to clients |
| Testing 5 players | One developer, one Mac | Launch several Godot instances locally (host + 4 clients via command-line args) plus automated headless network tests |

---

## 7. Missing assets and animations

**Audio (all missing):**
- engine/pedal loop with pitch by speed
- tire skid/drift loop, boost whoosh, impacts (soft/hard), "boing" ejection
- rider vocal blips, footsteps, mount hop
- item pickup/use/hit sounds
- countdown beeps, finish fanfare, UI clicks
- music: menu plus one track per map

Sourcing options: original sounds generated in code (`AudioStreamGenerator`,
no files) or CC0 libraries. Downloads need owner approval.

**Animations (missing):**
- start-grid idle/anticipation, countdown lean-in, victory/finish pose,
  results poses
- item throw/use, hit flinch, stunned-by-item tumble
- climbing back over a barrier, pushing a flipped trike upright
- camera shake on big impacts, squash/stretch on landings
- racer name tags/emotes

**Art/content (missing):**
- per-player rider palettes (5 distinct sets)
- item box mesh and item meshes (projectile, trap, boost, shield)
- Rocky Canyon kit: canyon walls, red rock palette, arches, rock slides
- Snow Slide kit: snow/ice palette, snow pines, snowmen, ice patches, snow
  particles
- app icon and logo, menu backgrounds, results podium

**Fonts:** system fonts only. Bundling an OFL font would guarantee the same
look on Windows (download needs approval).

---

## 8. Prioritized remaining work

Priorities: **P0** blocks the demo · **P1** expected in the demo · **P2** polish.
Sizes: S ≈ ≤1 session, M ≈ 1–2 sessions, L ≈ 3+ sessions.

| ID | Item | Priority | Size |
|---|---|---|---|
| A1 | Fix finish-line edge case + `attach_to()` robustness + missing interact tests + doc drift | P0 | S |
| A2 | Racer registry (N racers), per-racer progress/respawn/finish, rider palettes, AI bots | P0 | M |
| B1 | Race state machine: countdown, racing, finished, results; checkpoints, positions, results screen | P0 | M |
| F1 | Main menu + host/join lobby (ENet, direct IP/LAN) + map selection | P0 | M |
| F2 | Networked racers: proxy trikes, owner-authoritative state sync, rider state sync, host race state | P0 | L |
| F3 | Racer-vs-racer bumping/knockback over the network | P1 | M |
| D1 | Item boxes + item roll + HUD slot + use input | P1 | M |
| D2 | 3–4 original items with projectiles/traps, knockback, ejection on hit (host-authoritative) | P1 | L |
| C1 | Map data resource + theme hooks; turn the test track into **Forest Rush** (long version) + chunked building | P0 | M |
| C2 | **Rocky Canyon** map | P1 | M |
| C3 | **Snow Slide** map | P1 | M |
| G1 | Audio: bus layout, procedural or CC0 SFX, music | P1 | M |
| H1 | Export: templates, presets (macOS universal, Windows x86_64), icon, packaging and friend install notes | P0 | S–M |
| I1 | Performance: mesh merging per racer, scenery visibility ranges, quality settings | P1 | M |
| I2 | Visual polish: name tags, camera shake, victory pose, barrier tint | P2 | M |

---

## 9. Recommended implementation order

1. **A1 → A2** (fixes, then the racer registry with AI bots). Everything else
   needs N racers. Bots also give 5-racer testing offline.
2. **B1** (race structure). Built host-authoritative-ready on the registry.
3. **F1 → F2** (menus/lobby, then networked racers). Highest risk; it shapes
   how items and race state are written. Done before items so items are
   network-aware from day one.
4. **C1** (map data + Forest Rush long version + chunking). Needed before
   C2/C3 and for real race lengths.
5. **D1 → D2** (items) and **F3** (bumping), on the networked base.
6. **C2, C3** (Rocky Canyon, Snow Slide). Mostly data and theme work on C1.
7. **G1** (audio).
8. **H1** (exports). A first test export early (right after F1) to surface
   platform problems, a final one at the end.
9. **I1, I2** (performance and polish), then owner playtests and Windows
   hardware testing.

---

## 10. Feature plans

### A1 — Fixes and test gaps
- **Exists:** finish `Area3D` (`track.gd`), finish handling
  (`main.gd::_on_finish_crossed`), `RiderController.attach_to()`, input-map
  test.
- **Add:**
  - Finish by **progress** (racer's progress index passes the finish index,
    or the finish area is entered) while riding, re-checked every tick. A
    racer who crossed riderless finishes the moment they're back on the
    trike past the line.
  - `attach_to()` guarded: no-op if already attached to the same trike;
    deferred until ready.
  - `interact` added to `REQUIRED_ACTIONS`; an E key-event test.
  - Doc drift corrected.
- **Files:** `scripts/main/main.gd` (later the race manager),
  `scripts/rider/rider_controller.gd`, `tests/test_runner.gd`,
  `docs/*.md`, `CLAUDE.md`.
- **Tests:**
  - riderless-cross-then-remount finishes
  - `attach_to()` before ready and twice → no errors
  - E key event → `interact_pressed`
  - full suite in strict mode

### A2 — Racer registry, AI bots, rider palettes
- **Exists:** single `Trike` + `RiderCharacter` in `main.tscn`;
  `VehicleProgress`; `Track.get_start_transform(slot)` (5 grid slots);
  `TrackAutopilot` (test AI); `TrikeVisuals.body_color`.
- **Add:**
  - `Racer` (node or scene): trike + rider controller + progress + player
    info (id, name, palette, is_local, is_bot).
  - `RaceManager` spawning N racers at grid slots, with per-racer
    out-of-bounds, emergency recovery and finish.
  - Camera and HUD bound to the local racer.
  - `BotInputSource` built from `TrackAutopilot`: drifts, avoids, recovers on
    foot.
  - `Rider.palette` (helmet, jacket, accent) applied like `body_paint`.
- **Files:**
  - new `scenes/race/racer.tscn`, `scripts/race/racer.gd`,
    `scripts/race/race_manager.gd`, `scripts/race/bot_input_source.gd`
  - modified `scripts/main/main.gd` (thin), `scenes/main/main.tscn`,
    `scripts/characters/rider.gd`, `scenes/characters/rider.tscn` (paint
    groups), `scripts/vehicles/trike_visuals.gd`
- **Tests:**
  - 5 racers spawn on distinct slots
  - each racer's respawn and recovery affects only itself
  - bots finish the track
  - local camera and HUD follow only the local racer
  - palettes distinct
  - 5-racer perf capture
  - all existing tests

### B1 — Race state machine, countdown, checkpoints, positions, results
- **Exists:** race timer, finish trigger, `VehicleProgress` (distance along
  the path).
- **Add:**
  - States: PRE_RACE, COUNTDOWN (3-2-1-GO, inputs locked, trikes held),
    RACING, FINISHING (timeout after the first finisher), RESULTS.
  - Checkpoints as ordered path-index gates (no skipping).
  - Positions = (finished, checkpoint, distance) per racer.
  - HUD: countdown, position "2nd/5", finish order.
  - Results screen: order, times, back to lobby/menu.
- **Files:**
  - new `scripts/race/race_state.gd`, `scripts/race/checkpoint_tracker.gd`,
    `scenes/ui/countdown.tscn`, `scenes/ui/results_screen.tscn` (+ scripts)
  - modified `scripts/race/race_manager.gd`,
    `scripts/race/vehicle_progress.gd`, `scripts/track/track.gd`
    (checkpoint list), `scripts/ui/hud.gd` / `hud.tscn`
- **Tests:**
  - inputs ignored during the countdown, GO releases them
  - checkpoint order enforced
  - positions update when passing
  - first finisher starts the timeout
  - results list matches finish order
  - pause during the countdown

### C1 — Map data + Forest Rush
- **Exists:** `Track` (control points), mesh builder (palette fields), props
  table, decorator/landmarks/backdrop with exported settings. Builds in ~425 ms.
- **Add:**
  - `MapData` resource: name, control points, road width, palette, prop
    layout, decor densities, environment (sky, fog, light), music,
    checkpoint spacing.
  - The builder/decor/backdrop read the theme.
  - Chunked meshes/collision (~200 m) with visibility ranges; spatial grid
    for terrain sampling.
  - Forest Rush as a long point-to-point course (~5–6 km for a ~5 min race
    including wipeouts).
- **Files:**
  - new `scripts/track/map_data.gd`, `resources/maps/forest_rush.tres`
  - modified `scripts/track/track.gd`, `track_mesh_builder.gd`,
    `track_decorator.gd`, `track_landmarks.gd`, `track_backdrop.gd`,
    `track_props.gd`; `scenes/tracks/test_track.tscn` kept for tests
- **Tests:**
  - map loads under a time budget
  - collision identical between chunked and unchanged sections
  - autopilot completes the full map
  - scenery stays clear of the road
  - perf capture
  - screenshots

### C2 / C3 — Rocky Canyon, Snow Slide
- **Exists after C1:** theme-able map pipeline.
- **Add:**
  - **Rocky Canyon:** red/orange palette, tall canyon walls (collision),
    arches, rock slides, dust.
  - **Snow Slide:** snow/ice palette, snow pines, snowmen, falling-snow
    particles, ice patches with lower grip (surface type → `TrikeConfig`
    multiplier).
- **Files:**
  - new `resources/maps/rocky_canyon.tres`, `snow_slide.tres`
  - new theme-specific prop scenes in `scenes/props/`
  - small surface-grip hook in `trike_controller.gd` (config-driven)
- **Tests:** per map: load time, autopilot completion, scenery clearance,
  screenshots; ice grip unit test.

### D1 / D2 — Items
- **Exists:** `Trike.apply_knockback()`, `RiderController.eject()`, physics
  layers, HUD framework.
- **Add:**
  - Item boxes (respawning pickups on the track) and a position-weighted roll.
  - One held item, HUD slot, new `use_item` input action (project.godot
    input map change at implementation time).
  - Original items, e.g.:
    - **Bouncy Ball:** forward projectile; knockback, ejects on direct hit.
    - **Grease Puddle:** dropped trap; spin and drift loss.
    - **Turbo Pepper:** boost.
    - **Bumper Bubble:** short shield.
  - Host-authoritative spawn and hit resolution.
- **Files:** new `scripts/items/` (item_box, item_roll, item_data resources,
  projectile, trap), `scenes/items/*.tscn`, `resources/items/*.tres`;
  modified `hud.gd`/`hud.tscn`, `race_manager.gd`, `project.godot` (input).
- **Tests:**
  - box pickup gives an item and respawns
  - roll respects position weights
  - each item's effect on a target trike
  - ejection on direct hit
  - no item use while on foot
  - network authority test in F2's harness

### F1 / F2 / F3 — Menus, lobby, networking, bumping
- **Exists:** `TrikeInput` abstraction, `get_sync_state()`, seeded fling,
  pause menu and theme.
- **Add:**
  - **F1 (menus):** main menu (Play solo vs bots, Host, Join by IP,
    Settings, Quit). Lobby: names, colors, ready-up, host picks the map.
    ENet peer.
  - **F2 (networking):**
    - player spawning (`MultiplayerSpawner` or manual)
    - owner-authoritative trike + rider state at 20–30 Hz
    - trike proxy mode, remote rider/ragdoll interpolation
    - host-authoritative race state, items and results
    - disconnect handling
  - **F3 (bumping):** contact detection between racers, knockback RPC,
    tuned so rear-end victims aren't always ejected.
- **Files:**
  - new `scenes/ui/main_menu.tscn`, `lobby.tscn`, `settings.tscn` (+
    scripts)
  - new `scripts/net/network_session.gd`, `net_racer_sync.gd`,
    `lobby_state.gd`
  - modified `trike_controller.gd` (proxy mode), `rider_controller.gd`
    (apply sync state), `race_manager.gd`, `project.godot` (main scene →
    main menu, at implementation time)
- **Tests:**
  - headless host + clients launched by the test harness: join, lobby
    sync, start, positions agree, items agree, finish order agrees,
    disconnect mid-race
  - manual multi-window test on one Mac
  - LAN test between Mac and Windows when available

### G1 — Audio
- **Exists:** nothing.
- **Add:**
  - Bus layout (Master, Music, SFX, UI).
  - `AudioDirector` for UI/music; `TrikeAudio`/`RiderAudio` components
    listening to existing signals (`impact`, drift/boost,
    `state_changed`, `ejected`, mount).
  - Procedural or approved CC0 sounds.
  - Volume settings.
- **Files:** new `scripts/audio/*.gd`, `default_bus_layout.tres`, audio
  assets (if approved); small hooks in `trike_visuals.gd` or a new
  component.
- **Tests:**
  - players exist and trigger on signals (headless with the dummy driver)
  - volume settings persist
  - manual listening pass

### H1 — Exports
- **Exists:** nothing (no presets, no templates).
- **Add:**
  - Install the official 4.7.2 export templates (download from
    godotengine.org; needs approval).
  - `export_presets.cfg`: macOS universal `.app`/`.dmg` with ad-hoc
    signing; Windows x86_64 `.exe` + `.pck` or embedded pck.
  - Custom icon (`.icns`/`.ico` generated from an original SVG).
  - A README for friends: macOS "right-click → Open" / Gatekeeper,
    Windows SmartScreen.
  - Optional notarization later (requires a paid Apple Developer account:
    out of scope).
- **Files:** new `export_presets.cfg`, `icon` assets, `docs/RELEASE.md`;
  modified `project.godot` (icon) at implementation time.
- **Tests:**
  - headless export succeeds for both presets
  - the exported Mac app launches and passes a scripted smoke test
  - the Windows build smoke-tested on a real Windows PC (owner)

### I1 / I2 — Performance and polish
- **Exists:** `MeshKit.combine`, perf capture mode, 5-racer probe (this
  audit).
- **Add:**
  - Per-racer static mesh merging, rider sphere LOD.
  - Shadow-caster pruning, scenery visibility ranges.
  - Quality presets (shadows, MSAA, render scale).
  - Name tags, camera shake, landing squash, victory pose, barrier tint fix.
- **Files:** `trike_visuals.gd`, `rider.gd`, `track_decorator.gd`,
  `track_landmarks.gd`, `follow_camera.gd`, new `scripts/ui/settings.gd`.
- **Tests:**
  - draw calls per racer below a budget (assert in the perf capture)
  - visual-wheel and IK tests still pass
  - screenshots
  - Windows frame-time measurement

---

## 11. Audit artifacts

- Evidence screenshot: `docs/screenshots/final_audit/five_racers_probe.jpg`
  (5 autopiloted racers, 120 fps)
- Probe scripts and logs lived in the session scratchpad only, so the
  project is unchanged. They can be recreated from the descriptions in §2.
