# TRIKE TUMBLE — Claude Code project guide

Colorful 3D cartoon downhill party racer: up to 5 players on three-wheeled
drift trikes. Funny physics, collisions, falling off, items. See
`docs/GAME_DESIGN.md` for the vision.

## Locked requirements (do not change without the owner's approval)

- Engine **Godot 4.7.2 stable**, **GDScript** only, **Mobile** renderer, **Jolt** physics.
- Targets: macOS + Windows desktop. Shared directly with friends; **no Steam**.
- Up to 5 players, 3 maps, 5–10 minute races, low-poly cartoon style.

## Permanent rules

1. Inspect the existing project before coding. Keep the architecture modular:
   separate scenes/scripts per system, no monolithic scripts.
2. Typed GDScript where practical. Gameplay values must be configurable
   (`TrikeConfig` resource, `@export` vars), never magic numbers in logic.
3. No paid assets/plugins/services. No downloaded assets without approval.
   No unnecessary dependencies. Never copy copyrighted characters or assets.
4. Don't implement unrelated features or skip ahead on the roadmap
   (multiplayer and map production come later, see `docs/ROADMAP.md`).
5. **Never run `git commit`, `git push`, `git reset` or `git clean`.** The owner handles git.
6. Never delete existing work without explaining why.
7. Never claim something works without testing it. Run the test suite
   (below) after every gameplay change and add tests for new systems.
8. Keep these docs current: `CLAUDE.md`, `docs/GAME_DESIGN.md`,
   `docs/ROADMAP.md`, `docs/TECHNICAL_ARCHITECTURE.md`, `docs/TESTING.md`.

## Owner decisions (2026-11-08, final demo stage)

- **Work milestone by milestone, only when the owner says to start one.**
  Never rebuild working systems unnecessarily. Never claim a feature is
  complete without testing it.
- **Export templates:** official Godot 4.7.2 stable **standard** templates
  are approved. Never the .NET templates.
- **External assets:** only SIL OFL fonts, CC0 sound effects and music, CC0
  textures/models (allowed since Visual Overhaul V2, 2026-11-12) and
  original procedural assets. No paid assets, plugins or services; no
  copyrighted commercial music. Download only when the milestone needs
  them, verify the license at the source, and record every external asset
  in `docs/ASSET_CREDITS.md` before use.
- **Collision design:** a strong rear-end hit **can** eject a stationary
  rider. Small bumps never eject. High-speed impacts can. Judge impacts by
  relative impact speed and collision impulse. Weak impacts give only a small
  knockback or vehicle shake. All thresholds configurable.
- **Windows:** prepare an x86_64 export, but never call Windows compatibility
  verified until the game has run on a real Windows PC.
- Final demo plan and priorities: `docs/FINAL_DEMO_AUDIT.md`.

## Running and testing

Godot is not on PATH on the owner's Mac. Binary:
`~/Downloads/Godot.app/Contents/MacOS/Godot` (referred to as `$GODOT`).

```sh
$GODOT --headless --path . --import                       # refresh class cache after adding class_name scripts
$GODOT --headless --path . --fixed-fps 60 --scene res://tests/test_runner.tscn   # full suite, exit 0 = pass
$GODOT --path .                                            # play the game (main menu)
$GODOT --path . res://scenes/main/main.tscn                # straight into a 1-racer race
$GODOT --path . res://scenes/main/race_five.tscn           # you + 4 AI (or: -- --ai=4 --difficulty=hard)
$GODOT --path . res://scenes/main/forest_rush.tscn          # Forest Rush, you + 4 AI
$GODOT --path . res://scenes/main/rocky_canyon.tscn         # Rocky Canyon, you + 4 AI
$GODOT --path . res://scenes/main/snow_slide.tscn           # Snow Slide, you + 4 AI
$GODOT --headless --path . --fixed-fps 60 --scene res://tests/test_runner.tscn -- --only=map   # one test group (core|racers|flow|ui|net|items|polish|overhaul|map)
$GODOT --path . --fixed-fps 60 --always-on-top --resolution 1280x720 --scene res://tests/tools/quick_shot.tscn -- <out_dir> forest chase:name:300:3   # look-dev screenshots (see the script header)
$GODOT --headless --path . --fixed-fps 60 --scene res://tests/map_test_runner.tscn             # timed Forest Rush races (~80 s)
```

Details, the visual capture tool and the manual checklist: `docs/TESTING.md`.

## Project layout

```
assets/   textures/ (CC0 PBR sets) materials/ (terrain + road shaders) audio/ (CC0 recordings, music) fonts/ (OFL)
scenes/   menu/ main/ vehicles/ characters/ camera/ ui/ tracks/ (test_track, forest_rush) props/
scripts/  core/ menu/ net/ maps/ main/ vehicles/ characters/ camera/ ui/ track/ race/ props/ visuals/ rider/ ai/ items/ audio/
tools/    asset_pipeline/ (texture + audio build scripts; .gdignore, not part of the game)
resources/vehicles/default_trike_config.tres   # all handling values
resources/rider/default_rider_config.tres      # ejection / fall / on-foot / mount values
resources/ai/ai_easy|medium|hard.tres           # AI difficulty presets (AIDriverConfig)
resources/items/default_item_config.tres        # every item value (ItemConfig)
resources/ui/trike_theme.tres                  # shared UI theme (fonts, buttons, panels)
resources/ui/font_display.tres, font_body.tres # Lilita One / Nunito (bundled OFL fonts)
resources/maps/themes/*.tres                    # per-map palette, sky, light, exposure (forest too since V2)
tests/    test_runner (automated) + racer/race_flow/ui/net_unit/item/map tests, map_test_runner (timed races), net/ (multi-process), visual_capture (screenshots/perf), track_autopilot
docs/     design, roadmap, architecture, testing, screenshots/
```

## Things that bite

- **Vehicle movement is custom** (raycast suspension + arcade forces in
  `Trike._integrate_forces`). Do not swap in `VehicleBody3D`. Tune feel in
  `default_trike_config.tres`, not in code.
- Drive the trike only through `Trike.input` (`TrikeInput`). Keyboard, tests,
  AI and future networking all use this path.
- Teleport a trike only with `Trike.teleport()`. It resets velocity, drift state
  and physics interpolation.
- Physics interpolation is on. Code that moves things in `_process` should read
  `get_global_transform_interpolated()`, as `FollowCamera` does.
- In hand-edited `.tscn` files: `Transform3D(...)` lists basis **rows**. A
  node-typed `@export` needs `node_paths=PackedStringArray("prop")` in the node
  header, or it silently stays null.
- Child `_ready` runs before parent `_ready`. `Trike` sets up its wheels in
  `_enter_tree` so `TrikeVisuals` can query them.
- Vertex-colored materials need `vertex_color_is_srgb = true`, or colors wash out.
- Physics layers: 1 world, 2 vehicles, 3 props (bit value 4), 4 riders (bit value 8).
- **Visuals never drive physics.** The trike's `Visuals` subtree is cosmetic:
  wheel nodes are placed from `Trike.wheel_suspension_length`, the rider is
  posed by IK. Never add collision shapes or change the `Trike` body/shapes when
  restyling. Tests check that visual wheels match the physics wheels and that
  gloves and boots stay on their IK targets.
- Track collision and track rendering are separate passes in
  `TrackMeshBuilder`. Restyle the render pass freely. Changing
  `_build_collision` changes how the track drives.
- **Maps** (read "Track generation" in TECHNICAL_ARCHITECTURE first):
  - A race scene doesn't contain its track. `RaceSession.track_scene` is
    instanced at the start of `_ready`. `main.tscn` uses the 1.2 km test
    track, which the fast tests and the menu background rely on.
    `scenes/main/<map>.tscn` (forest_rush, rocky_canyon, snow_slide) are what
    the menu/online maps load (`MapInfo.race_scene`).
  - Every map is pure data in `scenes/tracks/<map>.tscn`, no per-map code:
    - `route_segments` (length, turn, grade)
    - `width_profile`
    - `zones` (bridge, gap, mud, ice, cliff, wind, overlook, clearing, rocks)
    - the Props `layout`
    - `theme` (`TrackTheme`: paint, scenery style, sky), `road_surface`,
      `bridge_surface`
  - Never change a `TrackTheme` default (a track without a theme falls back
    to them); give the map's theme a value instead.
  - Check a new route's layout (clearances, radius, grade) before building:
    `--only=map` checks it, and the decorator RNG order must stay as is or
    Forest Rush's scenery reshuffles.
  - Distances in zones and props are along the **built** path, which is
    about 0.5 % longer than the sum of the segment lengths. After changing
    the route, re-check where features land and run `--only=map`.
  - The road width varies: use `Track.half_width_at(i)`, never
    `road_width`.
- **Surfaces:** a collision body tagged with `TrackSurface` metadata is mud,
  grass, wood, snow or ice; anything untagged is road. `Trike` reads the tag
  from its wheel hits. Values live in `TrikeConfig` ("Surfaces"). The road
  body is tagged only through `Track.road_surface` (Snow Slide: SNOW);
  Forest Rush and the test track must stay untagged ROAD.
- **Respawn safety:** `Track.mark_unsafe()` / `is_safe_index()`. Props that
  block the road (ramps, boulders, road trees, logs) mark ±10 m, and jump
  gaps mark their run-up and landing. `VehicleProgress` only records safe
  samples. A new blocking prop kind must mark itself too, or racers can
  respawn inside it.
- **Timed hazards** (`FallingLog`, `RollingRock`) and **wind**
  (`Track.wind_at`) are pure functions of
  `Track.hazard_time`, which `RacerManager` advances from GO. Don't give
  them their own timers or physics: online peers rely on identical motion.
- Scenery batches (MultiMesh) are positioned at the center of their
  instances and fade by distance (`scenery_lod` group, scaled by graphics
  quality). Keep it that way when adding scenery to long maps.
- Scenery that looks solid (trunks, boulders, signs, bales, cabin) must get a
  matching collider. A test asserts no scenery collider enters the road corridor.
- Body-colored trike parts are in the `body_paint` group
  (`TrikeVisuals.body_color` recolors them, ready for per-player colors).
- `RoundedBoxMesh` / `ArcMesh` (scripts/visuals) are `@tool` PrimitiveMesh
  scripts. `MeshKit.combine` merges primitives into one flat-shaded,
  vertex-colored mesh for cheap batching.
- `SceneTree.physics_frame` fires *before* `_physics_process`, and
  `process_frame` before `_process`. Tests that read state right after
  awaiting need an extra tick, or must call the update themselves.
- `docs/.gdignore` keeps Godot from importing screenshots as game assets.
- The macOS capture window must stay visible (`--always-on-top`), or frames
  may be stale.
- **Rider vs. trike state are separate.** `RiderController` (scenes/characters/
  rider_character.tscn) owns the rider states (RIDING, EJECTED, RAGDOLL,
  GETTING_UP, ON_FOOT, MOUNTING). The trike only knows `has_rider`
  (`set_rider_aboard`). Change states only through `_change_state()`.
- Riderless trike: ignores input, brakes gently, no air control or
  self-righting, rider collision capsule disabled. It never moves toward the
  rider. Mounting rights an overturned trike in place (`set_upright`, not a respawn).
- `Trike.impact(strength, velocity_before)`: unexplained velocity change per
  tick (collisions). Measured head-on wall hits read ~1.1x hit speed; scrapes,
  crates and ramp landings stay under ~2.5. Eject threshold is in RiderConfig.
- The rider model (`Visuals/Rider`) leaves the trike by switching to
  `top_level` while off, and RiderController drives its transform and pose.
  TrikeVisuals only poses it while it is seated.
- `RiderController.attach_to()` is lifecycle-safe (deferred before `_ready`,
  idempotent, never double-connects). Use it for spawning riders, never
  connect `Trike.impact` by hand.
- Finishing goes through `FinishTracker` (player id → trike/rider/progress).
  Never check `body == trike` directly. An empty trike crossing the line =
  pending finish, confirmed when its owner is riding again past the line.
- `Trike.teleport(xf, notify)`: `notify=false` doesn't emit `respawned` (use
  it for setup/uprighting so it doesn't count as a respawn).
- Teleporting the trike far in the race scene: also `RaceSession.get_progress().reset(index)`
  (or `racer.progress.reset(index)` for any racer), or the out-of-bounds check sends it back.
- **Racers:** `RacerManager` (node in main.tscn) owns the racer registry
  (`Racer`: id, name, type, trike, rider, input source, progress, slot,
  finish state), per-racer progress/out-of-bounds/respawn/emergency recovery,
  the race clock and the `FinishTracker`. `RaceSession` only binds the local
  racer (id 1, the scene's `Trike`/`RiderCharacter`) to camera and HUD. Add
  racers only through `add_human_racer()` / `add_ai_racer()` (max 5).
- **AI** (`AIDriver`, a `TrikeInputSource`) is the input source of both its
  trike and its rider; it only writes `TrikeInput` (on foot: world-space
  `move_direction`). Never move AI trikes/riders directly. Difficulty values
  live in `resources/ai/ai_*.tres` (`AIDriverConfig`), not in code. AI trikes
  have their `PlayerInputSource` node removed at spawn.
- `main.tscn` defaults to 0 AI (the older tests rely on that). Five racers:
  `scenes/main/race_five.tscn` or `$GODOT --path . -- --ai=4 --difficulty=mixed`.
- **Race flow:** `RaceController` (node in main.tscn) owns the states via
  `RaceStateMachine` (LOBBY → COUNTDOWN → RACING → FINISHED → RESULTS). Change
  race state only through its methods (`begin_countdown`, `start_immediately`,
  `race_again`, `return_to_lobby`), never by calling `RacerManager.start_race()`
  in the race scene. Race Again resets in place (`RacerManager.reset_for_new_race()`);
  new per-race state must be reset there too (items reset on `race_reset`).
- Tests/tools that need to drive at once set `RaceSession.skip_countdown = true`
  before adding the scene (the old `_load_main` does); `auto_start = false`
  keeps the race in the lobby until the test starts it.
- `Trike.input_locked` (lobby/countdown/race over) is enforced in
  `_integrate_forces` too: physics callbacks run *before* `_physics_process`,
  so input written between ticks reaches the motor unless cleared there.
- **Checkpoints:** a teleport skips them, and the finish line then refuses
  the racer. After teleporting a racer forward in tests, call
  `racer.checkpoints.force_passed_through(index)`.
- Positions come from `CheckpointProgress.distance` (path distance capped at
  the next unpassed checkpoint), never straight-line distance.
- **Menus/UI:** the main scene is `scenes/menu/main_menu.tscn`. Autoloads
  `GameSettings` (saved settings, key rebinding) and `GameSession` (lobby,
  transport, race setup) are registered in project.godot. Build UI with
  `UiKit` (palette, fonts, buttons with motion). Key names in UI must come
  from `UiKit.action_keys()` / `GameSettings.primary_key()`, never literals.
- Tests and the capture tool call `GameSettings.use_test_profile()` first.
  Never let tests write `user://settings.cfg`.
- Test hooks: `MainMenu.quit_handler/scene_changer`,
  `RaceSession.scene_changer`, `PauseMenu.quit_handler`. Never let a test
  call `RaceSession.restart()` (it reloads the *current* scene, which is the
  test runner).
- Headless test windows are 1280×1280, so check layout with minimum sizes,
  not positions. `--script` mode runs without autoloads (use a scene).
- **Online:** read `docs/NETWORKING.md` first. The long five-real-player
  end-to-end race is `net_test_runner.tscn -- e2e5` (~6 min, not in the
  default run).
  - Only a racer's owner simulates it; everyone else shows a proxy
    (`network_proxy` on Trike and RiderController). Never simulate a proxy
    or feed it input.
  - Clients never decide checkpoints, positions or finishes
    (`RacerManager.authoritative` is false on clients).
  - All RPCs live on the `Net` autoload (same path on every peer). New
    synced state belongs in `NetSnapshot` (bump `FIELD_COUNT` and
    `validate()`) or in the host's status list.
  - `Trike.teleport()` increments `teleport_count`, so proxies snap
    instead of sliding.
  - Network suite: `tests/net/net_test_runner.tscn` (separate processes,
    real time, ~3.5 min).
- **Items** (read "Items" in TECHNICAL_ARCHITECTURE first):
  - `ItemManager` (node `Items` in main.tscn) owns boxes, held items
    (`Racer.held_item`), bombs, puddles and peels. Owners send requests;
    only the host (`authoritative`) decides, via numbered events applied
    once everywhere. Never change `held_item` or box state outside an event.
  - Item hits go through `Trike.apply_item_hit()` / `set_slippery()` on the
    victim's owner only. `apply_item_hit` is applied inside
    `_integrate_forces`, so it never trips the impact/eject rule; item
    ejection is the host's decision (`PUNCH` event).
  - Q (`use_item`) → `TrikeInput.use_item_pressed`; ItemManager consumes it.
  - Boxes come from `Track.item_box_rows`; the test track has none, so the
    older tests run item-free. Tests add boxes with `add_box()` and give
    items with `grant_item()`.
  - Item state resets on `RaceController.race_reset`.
  - New item RPCs or event fields: bump `Net.PROTOCOL_VERSION`.
- **Audio** (read `docs/AUDIO_DESIGN.md` first): vehicle, surface, rider and
  item sounds are CC0 recordings in `assets/audio` (`SoundBank.FILES`, random
  take per play); race jingles and UI clicks are still synthesized
  (`SoundSynth`). Never add an audio file without an ASSET_CREDITS entry.
  Play one-shots through `SoundPlayer` (timer-freed; headless never emits
  `finished`). `TrikeAudio` crossfades four engine recordings by simulated
  revs; `visuals.audio.engine` is the mid layer (tests read its pitch).
  Trike/rider audio and `TrikeEffects` read synced state only, so proxies
  get them for free; keep it that way. Music goes through the
  `MusicPlayer` autoload (`play(&"menu"|&"race")`, `duck()`).
- **Visual Overhaul V2** (read `docs/ART_DIRECTION_BIBLE.md` and
  `docs/VISUAL_OVERHAUL_PROGRESS.md` first):
  - Textured materials come from `MaterialLibrary` (cached, shared). Road
    and slopes use `assets/materials/road.gdshader` / `terrain.gdshader`:
    world-space CC0 texture sets tinted by vertex colour. On the road mesh
    the vertex colour **alpha** picks the surface look (1 ground, 0.9 curb,
    0.75 mud, 0.5 planks, 0.25 ice; `TrackMeshBuilder.*_ALPHA`). Render
    only: never use it for gameplay.
  - Texture albedos are stored near-neutral at ~0.8 brightness; the palette
    comes from the theme. New texture: process it with
    `tools/asset_pipeline/proc_tex.py` and give its `.import` mipmaps +
    VRAM compression (normal maps: `compress/normal_map=1`).
  - Scenery models are sculpted in code (`Sculpt`, `SceneryKit`). The
    decorator picks a tree variant from the sample index, never from
    `_rng`, and `_build_extras` has its own RNG, so the tree layout (and
    its colliders) is unchanged. Keep both rules.
  - New scenery colliders can trap AI: a cactus collider did (found only by
    `map_test_runner`), so cacti are soft. After adding any collider near
    the road, run the timed races, not just the main suite.
  - `TrikeDetail.build()` and `RiderDetail.build()` only **add** child
    meshes under existing nodes. Never rename or move the scene's own
    nodes; new body-coloured parts go in `body_paint`, new accent parts in
    `TrikeVisuals.ACCENT_PARTS`; rider parts named `Kit_*` are switched per
    look (`RiderLook` flags).
  - Renderer stays **Mobile** (A/B against Forward+ recorded in
    VISUAL_OVERHAUL_PROGRESS). Don't add SSAO/SSR/volumetric settings to
    the environment: Mobile warns about them on every load.
  - Snow paint must stay at or below ~0.86 and Snow Slide's exposure
    below 1 (a test checks it), or the map blows out again.
  - Every map now has a theme with `apply_environment = true`
    (`forest_rush_theme.tres` is also used by the test track).
- **Rider looks:** `RiderStyle.apply(model, look)` (per-rider material
  copies, `Look_*` nodes). Never edit the rig or IK targets for a look.
  `Rider.celebrate()` frees the arms from the grips temporarily; IK tests
  assume no celebration is running.
- **Exports:** `export_presets.cfg` has "macOS" (universal, ad-hoc signed,
  not notarized → `release/TrikeTumble-macOS/TrikeTumble.zip`) and "Windows"
  (x86_64, embedded pck → `release/TrikeTumble-Windows/TrikeTumble.exe`).
  They need the official 4.7.2 **standard** templates in
  `~/Library/Application Support/Godot/export_templates/4.7.2.stable/`
  (never .NET). Universal/arm64 Mac export needs
  `textures/vram_compression/import_etc2_astc=true` (set).
  `$GODOT --headless --path . --export-release "macOS" <path>`.
- **Finish:** the real maps keep 90 m of road after the finish line, and a
  finished local player's trike is locked and brakes to a stop (cool-down);
  `set_controls_locked`/Race Again unlock it.
- Online client sends check `Net.is_connected_to_host()` (no ENet errors when
  the host has just left).
- macOS has no `timeout`; use `perl -e 'alarm 500; exec @ARGV' $GODOT ...`.
- Autowrap labels need a `custom_minimum_size.x`, or they collapse to one
  word per line and blow up the layout.
- If the Godot editor is open while files change on disk, let it reload. Saving
  stale editor state can overwrite `project.godot` (input map, renderer).
