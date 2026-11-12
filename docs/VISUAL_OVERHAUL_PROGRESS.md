# TRIKE TUMBLE — Visual Overhaul V2: progress and results

Work done on 2026-11-12 on one MacBook Air (Apple M4, 16 GB, macOS 15).
Engine: Godot 4.7.2 stable, Mobile renderer, Jolt. Direction:
`docs/ART_DIRECTION_BIBLE.md`. Audio: `docs/AUDIO_DESIGN.md`. Credits:
`docs/ASSET_CREDITS.md`.

Before/after screenshots: `docs/screenshots/visual_overhaul_v2/`
(`before/` = the milestone 10 baseline, `after/` = same views now,
`renderer_ab/` = Mobile vs Forward+).

## Status by phase

| Phase | Status | Notes |
|---|---|---|
| A. Inspect, art bible, baseline | Done | Baseline = existing milestone 10 screenshots (the repository was unchanged since they were taken) |
| B. Asset pipeline and materials | Done | CC0 texture sets, two shaders, `MaterialLibrary`, sculpting kit. No Blender on this machine, so no Blender/glTF models |
| C. Trike and characters | Done as a detail pass | Detail and materials added on top of the existing models; the base shapes are the same |
| D. Three maps | Done | New scenery models, textured ground, ridgelines, waterfalls, ledges, arches, palettes |
| E. Lighting, renderer, camera | Done | Mobile kept after an A/B; shadows, exposure and grade retuned; drift roll and speed streaks added |
| F. UI | Partly done | Bundled fonts, compact HUD, theme polish. Screen layouts, map cards and portraits are **not** redesigned |
| G. Audio and music | Done, **not listened to** | Recorded CC0 audio, layered engine, music |
| H. Optimise, test, screenshots | Done | See "Performance" and "Tests" |

## What changed

### Materials and textures (B)

- Nine CC0 PBR texture sets from Poly Haven at 1K (albedo, normal,
  roughness): dirt, grass, mud, rock face, sandstone, boulder,
  packed snow, planks, bark. Albedos are stored near-neutral; each map's
  theme supplies the colour through vertex colour.
- `assets/materials/terrain.gdshader`: slopes, cliffs, barriers and the
  backdrop terrain. Flat ground and steep faces get different texture sets
  by slope angle (grass → rock, dust → sandstone, snow → dark rock), mapped
  in world space, with low-frequency variation against tiling and snow
  glints.
- `assets/materials/road.gdshader`: the driving surface. Dirt texture with
  gravel speckle, damp patches and puddles; glossy churned mud; wood grain
  on bridge decks; clear ice with frost and cracks; painted curbs. The
  surface kind comes from vertex colour alpha set in the render pass.
- `MaterialLibrary`: every textured material is built once and shared.
- Collision was not touched. `TrackMeshBuilder._build_collision` is
  unchanged; only render-pass colours gained an alpha value.

### Models (B, C, D)

No model files were imported. Everything is sculpted in code by a new kit
(`Sculpt`: lathes with jagged/drooping rings, noise-displaced blobs,
tapered limbs; smooth or faceted output):

- Trees: 3 pine variants (5–6 drooping tiers, root flare, separate bark
  trunk, matching snow load), 3 broadleaf variants (lumpy layered canopy,
  branches), 2 canyon dry trees, a cheap far-forest pine.
- Ground cover: bushes, ferns, stumps, mushrooms, pebbles, cacti, ice shards.
- Rock: faceted boulders, snow caps, 3 hoodoo variants, cliff ledges, rock
  arches.
- Backdrop: ridged mountains with uneven snow lines, terraced mesas, two
  far horizon ranges, lobed clouds.
- Waterfalls (frozen on Snow Slide) at every bridge.

### Trike (C)

`TrikeDetail` adds, without renaming or moving any existing node: knobby
front tread, 16 wire spokes, hub flanges, valve stem, brake disc and
caliper, fork brace and gaiters, axle nuts, headlight bezel, plate bolts,
brake levers, bar ends, crossbar pad, a finned engine with air filter and
pull-start cover, twin exhausts ending where the boost flames appear, chain
guard and sprocket, bearing blocks, side pods, belly pan, seat trim,
footpeg treads, mud flaps, rear tyre grooves, lug nuts and frame bolts.

Materials retuned in `trike.tscn`: chrome (metallic 1.0, roughness 0.14),
powder-coated frame (0.52 / 0.35), clear-coated paint, matte rubber with a
moulded-grain normal map, satin plastic sleeves, vinyl seat, plus brushed
metal for the engine and disc.

Wheel positions, collision shapes and every node path are unchanged (tests
check the first two).

### Riders (C)

`RiderDetail` adds: coloured irises and a second eye highlight, helmet
racing stripe, side vents and bolts, collar, chest pocket, shoulder
stripes, elbow and knee pads, trouser stripes, boot toe caps, laces, heel
tabs and treads; rounder primitives; clear-coated helmets; woven-fabric
normal maps on jackets and trousers. Looks gained an eye colour and
per-racer kit switches, so the five racers differ in more than paint.

**Not done:** new character models. The riders are still the scene-built
primitive rig (no skinned mesh). Proportions, the animation set (run cycle,
get-up, mount, celebration) and the expressions are the earlier ones.

### Maps (D)

- **Forest Rush:** new palette (deep greens, earthy dirt, golden sun, green
  shadows), textured dirt road with puddles and gravel, grass slopes that
  turn to rock where steep, sculpted pines and broadleaf trees with bark
  trunks, ferns, stumps, mushrooms and pebbles in clustered patches,
  waterfalls beside both bridges, textured timber, layered ridgelines.
- **Rocky Canyon:** sandstone cliffs with strata texture and jutting
  ledges, eroded hoodoos, cacti, rock arches as landmarks, terraced mesas
  all around, turquoise water, plum-tinted shadows.
- **Snow Slide:** no longer blown out. Snow paint capped at 0.86, exposure
  0.86, blue ambient and fill, textured packed snow with glints, dark rock
  on steep faces, snow-loaded pines, ice shards, frozen waterfalls, clear
  ice with frost and cracks.

Not done from the brief: valleys and streams beyond the existing ones,
frozen lake rework (it only got the new water material), tyre-track decals
and footprints, bridge rope/metal fittings (bridges got wood textures
only), wind-swept snow beyond the existing wind zones.

### Lighting, renderer and camera (E)

- Per-map light in the theme: sun colour/energy, tinted ambient, cool fill
  light, exposure, saturation. Forest now has its own theme too.
- Sun shadows: 4096 map, soft filter, blended cascades; two cascades on
  Medium, four on High (`GameSettings.SHADOW_DISTANCE`).
- 8× anisotropic filtering; glow limited to real highlights.
- Camera: the existing chase camera already had look-ahead, speed FOV,
  shake, landing dip and transitions. Added a small roll into drifts and
  faint wind streaks at top speed and during boosts.

### UI (F)

- Bundled OFL fonts: Lilita One (titles, buttons, numbers, number plates,
  gate banners) and Nunito 800 (body). No system fonts any more, so the
  game looks the same on every computer.
- HUD about 30 % smaller: timer, position, item slot, speed gauge and hint.
- Panels: navy glass with a thin edge; lighter text outlines.

**Not done:** redesigned menu layouts, map cards with rendered previews,
racer portraits, item icons, new transitions. The screens keep their
earlier structure with the new type and colours.

### Audio (G)

See `docs/AUDIO_DESIGN.md`. In short: 37 CC0 recordings cut into 46 sound
files, a four-layer engine crossfaded by simulated revs with overrun and
throttle blip, a rolling loop per surface, wind, recorded impacts, rider
voices and item sounds, two CC0 music loops with crossfades and ducking,
and a limiter on the Master bus. **Nobody has listened to it yet.**

## Renderer A/B (Mobile vs Forward+)

Same scene (Forest Rush, 5 racers), same cameras, 1280×720, High quality,
on the M4. Screenshots: `docs/screenshots/visual_overhaul_v2/renderer_ab/`.
For the test the environment had SSAO enabled and the sun a 0.9° angular
size (soft penumbrae); both only work in Forward+.

| | Mobile | Forward+ |
|---|---|---|
| Shadows | soft-filtered, uniform edge | contact-hardening penumbrae |
| Ambient occlusion | none | SSAO: slightly darker wheel wells and tree bases |
| Glow | highlights only | same, a little smoother |
| Materials, fog, sky, reflections | same | same |
| Frame rate (7 spots) | 114–120 fps, at the 120 Hz cap everywhere after the start | 106–120 fps, below the cap at 4 of 7 spots |
| Draw calls | 414–994 | 689–1466 (depth pre-pass) |
| Video memory | 374 MB | 460 MB |
| Compatibility | same graphics APIs (Metal / D3D12 / Vulkan) | same, heavier on integrated GPUs |

**Decision: stay on Mobile.** The visible difference is small (side by
side you have to look for it), while Forward+ already loses frame-time
headroom at 720p on the fastest machine we have and would be worse on the
integrated GPUs the game also targets. The SSAO and angular-size settings
were removed again (Mobile prints a warning for them on every load).

## Performance

Windowed 1280×720, Medium quality (the default), 5 racers, Apple M4, Mobile
renderer, `visual_capture` modes `perfmap` / `perfcanyon` / `perfsnow`
(real time, no fixed frame rate). The display caps at 120 fps.

| Map | Frame rate (all spots) | Worst frame | Draw calls | Primitives per frame | Video memory |
|---|---|---|---|---|---|
| Forest Rush (7 spots) | 120 fps | 11–25 ms | 591–1333 | 0.68–2.02 M | 303 MB |
| Rocky Canyon (8 spots) | 119–120 fps | 10–36 ms | 511–1629 | 0.59–1.60 M | 301 MB |
| Snow Slide (8 spots) | 120 fps | 11–22 ms | 548–1679 | 0.62–2.46 M | 303 MB |

Compared with the milestone 10 numbers (Forest Rush 337–800 draw calls,
0.28–0.73 M primitives; Snow Slide about 1 M primitives): draw calls
roughly ×1.7 and triangles ×2.5–3, from the sculpted trees (separate trunk
and snow batches), ground cover and the horizon ranges. The M4 still holds
the display cap everywhere; the long 0.4–0.9 s first-frame hitch seen in
earlier measurements did not occur in these three runs (it did once in an
earlier run today, 0.9 s at the Forest Rush start, before the shadow
cascades were reduced).

Map build time (windowed): Forest 1.9 s, Canyon 1.6 s, Snow 2.0 s
(milestone 10: about 1.6 s for Forest).

Quality presets (`Settings → Video`):

| | Low | Medium | High |
|---|---|---|---|
| MSAA | off | 2× | 4× |
| 3D render scale | 75 % | 100 % | 100 % |
| Sun shadows | off | 2 cascades, 120 m | 4 cascades, 170 m |
| Scenery range | 55 % | 85 % | 100 % |

**Not measured:** High and Low presets separately, any resolution above
720p, integrated GPUs, Windows. The triangle counts are the main risk on
weaker GPUs; Low is the intended answer and has not been timed.

## Tests

All runs headless on the M4, on the final code unless noted.

| Suite | Result | Notes |
|---|---|---|
| Main suite (`test_runner.tscn`) | **740 passed, 0 failed** | 682 earlier checks, none removed or weakened, plus 58 new `overhaul` checks |
| Timed AI races, Forest Rush (`map_test_runner`) | **14 / 14** | hard AI 5:21.8–5:26.4, player driver race 5:20.5 |
| Timed AI races, Rocky Canyon | **14 / 14** after a fix (below) | hard AI 5:13.3–5:23.3 |
| Timed AI races, Snow Slide | **14 / 14** | hard AI 5:21.7–5:29.4 |
| Network, separate processes (`net_test_runner`) | **50 passed, 0 failed** | run before the last two small changes (prop placement, cactus colliders); not re-run after them |
| Five real players, whole race (`e2e5`) | **not run** in this milestone | |
| macOS export | built, 0 errors, 0 warnings (88 MB zip) | the exported app was launched with `--quick-race=snow_slide` for 25 s: no errors or warnings printed. Nobody looked at or listened to it |
| Windows export | built, 0 errors, 0 warnings (142 MB exe) | never run (no Windows PC) |

**One gameplay regression was found and fixed.** The first two full
timed-race runs failed one check: in the Rocky Canyon player race a Medium
AI needed one reset. The same test passes on the last commit, and passes
with the new cactus colliders turned off, so the cause was a thin cactus
collider on the canyon slopes trapping a trike. Cacti are now soft props
without colliders (like bushes); stumps and arch legs keep theirs.

Log messages in the final main-suite run: the intended ENet error and
quick-race warning (as before), the usual leaked-instances warning, and one
new shutdown line, "resources still in use at exit" (a recorded sound still
playing when the process quits; also printed by each network test process).
No script errors or GDScript warnings. Strict mode (warnings as errors) was
not run.

One existing test needed the layout to change, not the test: the new fonts
are taller, so three menu pages overflowed 720 px until the font line
spacing and the hero title size were reduced.

## Remaining limitations

- No Blender on this machine and no imported models: characters and trike
  are the earlier models with added detail, not new sculpts.
- UI redesign is typographic only (see above).
- Audio is unheard; expect a tuning pass.
- Not measured on Windows, on an integrated GPU or on a second computer
  (unchanged from the final demo report).
- Scenery pop: small ground cover fades out at 120 m; visible if you look
  for it on long straights.
- Waterfalls are static meshes (no flowing animation).
