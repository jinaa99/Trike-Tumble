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
- **External assets:** only SIL OFL fonts, CC0 sound effects and original
  procedural assets. No paid assets, plugins or services; no copyrighted
  commercial music. Download only when the milestone needs them, verify the
  license at the source, and record every external asset in
  `docs/ASSET_CREDITS.md` before use.
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
$GODOT --path .                                            # play the game
```

Details, the visual capture tool and the manual checklist: `docs/TESTING.md`.

## Project layout

```
scenes/   main/ vehicles/ characters/ camera/ ui/ tracks/ props/
scripts/  main/ vehicles/ characters/ camera/ ui/ track/ race/ props/ visuals/ rider/
resources/vehicles/default_trike_config.tres   # all handling values
resources/rider/default_rider_config.tres      # ejection / fall / on-foot / mount values
resources/ui/trike_theme.tres                  # shared UI theme (fonts, buttons, panels)
tests/    test_runner (automated), visual_capture (screenshots/perf), track_autopilot
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
- Teleporting the trike far in the race scene: also `RaceSession.get_progress().reset(index)`,
  or the out-of-bounds check sends it back.
- If the Godot editor is open while files change on disk, let it reload. Saving
  stale editor state can overwrite `project.godot` (input map, renderer).
