# TRIKE TUMBLE — Technical Architecture

Godot 4.7.2 · GDScript · Mobile renderer · Jolt Physics · 60 Hz physics with
physics interpolation enabled.

## Scene graph (main.tscn)

```
Main (RaceSession, main.gd)          race rules: spawn, respawn, timer; finish via FinishTracker
├─ WorldEnvironment, Sun, FillLight
├─ TestTrack (Track)                 builds road/barriers/slopes/collision on _ready
│  ├─ Props (track_props.gd)         crates, cones, rocks, ramps from a data table
│  ├─ Decor (track_decorator.gd)     trees, bushes, boulders, flowers (+ trunk/boulder collision)
│  ├─ Landmarks (track_landmarks.gd) turn signs, hay bales, cabin, logs, bunting (+ box collision)
│  └─ Backdrop (track_backdrop.gd)   terrain, mountains, hills, clouds, valley, lake (no collision)
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
└─ PauseMenu (CanvasLayer, process_mode Always)
```

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
`reset_pressed`, `interact_pressed`). The trike reads it while ridden; the
`RiderController` reads its own copy while the rider is off the trike
(throttle/brake/steer become on-foot movement, `interact_pressed` mounts).

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
- `TrackAutopilot`: tests and screenshots; template for future AI
- future: network peer inputs

For multiplayer, the server simulates with each client's `TrikeInput` and
replicates the transform and velocities. `TrikeVisuals` holds no gameplay
state, so remote trikes render unchanged.

## Signals and APIs

- `Trike`:
  - **Signals:** `respawn_requested(trike)`, `respawned`,
    `drift_started(dir)`, `drift_ended(tier)`,
    `impact(strength, velocity_before)`.
  - **Methods:** `request_respawn()`, `teleport(xf, notify := true)`,
    `set_rider_aboard(bool)`, `set_upright()`,
    `apply_knockback(impulse, spin)`, `get_drift_tier()`, `is_grounded()`.
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
- `RaceSession` (main.gd): connects everything and owns race rules. The local
  racer is `LOCAL_PLAYER_ID` (1).

## Finish detection

The finish `Area3D` (mask: vehicles) emits `Track.finish_crossed(body)` for
any vehicle. `RaceSession` forwards it to `FinishTracker` (once the race
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

## Track generation

`TrackPath` smooths control points (Catmull-Rom → Curve3D) and samples every
2 m with a frame per sample (forward along slope, level right vector).
`TrackMeshBuilder` emits flat-shaded quads with vertex colors: road (4 strips),
striped walls (inner/top/outer), and a multi-segment slope falling away on
each side. Collision is three `ConcavePolygonShape3D`s (backface collision
on) on one `StaticBody3D`. The track also adds end blockers, start/finish
gates (`track_gate.gd`) and a finish `Area3D`. Children with
`build_for_track(track)` (props, decor) run after the track is built.

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
| 1 world | 1 | track, barriers, slopes, gates, rocks, ramps, scenery colliders | — (static) |
| 2 vehicles | 2 | trikes (chassis + rider capsule; the capsule is disabled while the rider is off) | world, vehicles, props (1+2+4) |
| 3 props | 4 | crates, cones | world, vehicles, props (1+2+4) |
| 4 riders | 8 | thrown rider (`RiderRagdoll`), rider on foot (`RiderOnFoot`) | ragdoll: world, vehicles, props (1+2+4), own trike ignored until 1.6 m clear · on foot: 1+2+4 |

Other queries: wheel rays mask 1+4 (world + props). Camera sphere cast and
ground check mask 1. Rider ground probe mask 1. Finish trigger mask 2
(vehicles only; riders on foot can't finish).

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
| `scripts/track/*.gd` | Track path, mesh builder, track node, gate, props, decor |
| `scripts/race/vehicle_progress.gd` | Per-racer progress and respawn point |
| `scripts/ui/hud.gd`, `pause_menu.gd` | UI |
| `scripts/main/main.gd` | `RaceSession` |
| `scripts/props/ramp.gd` | Tool script: wedge ramp mesh (striped planks) + collision |
| `scripts/visuals/*.gd` | `RoundedBoxMesh`, `ArcMesh`, `MeshKit` procedural mesh helpers |
| `scripts/track/track_materials.gd` | Shared track materials + noise detail texture |
| `scripts/track/track_landmarks.gd`, `track_backdrop.gd` | Built set dressing; distant scenery and terrain |
| `scripts/ui/speed_gauge.gd` | Arc speedometer control |
| `resources/ui/trike_theme.tres` | UI theme: system rounded font with fallbacks, buttons, panels |
