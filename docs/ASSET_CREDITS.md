# TRIKE TUMBLE — Asset Credits

Every external asset in the project must be listed here **before** it is
committed: source, author, license and where it's used. Verify the license on
the original source page (not a mirror) when adding an entry.

## Allowed licenses (owner decisions, 2026-11-08 and 2026-11-12)

| Type | Allowed | Notes |
|---|---|---|
| Fonts | SIL Open Font License (OFL) only | Keep the font's `OFL.txt` next to the font file |
| Sound effects | CC0 only | Record the original page URL |
| Music | Original or CC0 only | No copyrighted commercial music |
| Textures, 3D models | Original, or CC0 / compatible free commercial-use licenses with attribution (Visual Overhaul V2 brief, 2026-11-12) | Kenney, Quaternius, Poly Haven and ambientCG were named as acceptable sources |

Never allowed: paid assets, paid plugins, paid services, ripped or
unlicensed assets, anything with unclear commercial-use terms.

## External assets

All added for Visual Overhaul V2 on 2026-11-12. Every license was read on
the source page that day. CC0 needs no attribution; authors are credited
anyway.

### Fonts

| Asset | File(s) in project | Author / source (URL) | License | License verified on | Used for |
|---|---|---|---|---|---|
| Lilita One | `assets/fonts/lilita_one/LilitaOne-Regular.ttf` (+ `OFL.txt`) | Juan Montoreano — <https://github.com/google/fonts/tree/main/ofl/lilitaone> | SIL OFL 1.1 | 2026-11-12 | Titles, buttons, HUD numbers, trike number plates, gate banners |
| Nunito (variable) | `assets/fonts/nunito/Nunito-Variable.ttf` (+ `OFL.txt`) | The Nunito Project Authors — <https://github.com/google/fonts/tree/main/ofl/nunito> | SIL OFL 1.1 | 2026-11-12 | Body text and labels (weight 800) |

### Textures (Poly Haven)

Downloaded at 1K through the Poly Haven API. The albedo maps were processed
(`tools/asset_pipeline/proc_tex.py`: softened, mostly desaturated, brightness
normalised) so vertex colour supplies each map's palette; normal and
roughness maps are unchanged apart from JPEG re-encoding.

| Asset | File(s) in project | Author / source (URL) | License | License verified on | Used for |
|---|---|---|---|---|---|
| dirt (1K) | `assets/textures/terrain/dirt_albedo.jpg`, `_normal.jpg`, `_rough.jpg` | Charlotte Baglioni — <https://polyhaven.com/a/dirt> | CC0 1.0 | 2026-11-12 | Road dirt (forest, canyon), canyon ground |
| leafy_grass (1K) | `assets/textures/terrain/grass_albedo.jpg`, `_normal.jpg`, `_rough.jpg` | Charlotte Baglioni — <https://polyhaven.com/a/leafy_grass> | CC0 1.0 | 2026-11-12 | Forest slopes and backdrop terrain |
| brown_mud_02 (1K) | `assets/textures/terrain/mud_albedo.jpg`, `_normal.jpg`, `_rough.jpg` | Rob Tuytel — <https://polyhaven.com/a/brown_mud_02> | CC0 1.0 | 2026-11-12 | Mud patches (normal map) |
| rock_face (1K) | `assets/textures/stone/rock_face_albedo.jpg`, `_normal.jpg`, `_rough.jpg` | Greg Zaal, Dario Barresi — <https://polyhaven.com/a/rock_face> | CC0 1.0 | 2026-11-12 | Forest and snow cliffs, ledges |
| sandstone_cracks (1K) | `assets/textures/stone/sandstone_albedo.jpg`, `_normal.jpg`, `_rough.jpg` | Rob Tuytel — <https://polyhaven.com/a/sandstone_cracks> | CC0 1.0 | 2026-11-12 | Canyon cliffs, hoodoos, arches, boulders |
| rock_boulder_dry (1K) | `assets/textures/stone/boulder_albedo.jpg`, `_normal.jpg`, `_rough.jpg` | Dimitrios Savva, Rico Cilliers — <https://polyhaven.com/a/rock_boulder_dry> | CC0 1.0 | 2026-11-12 | Boulders and pebbles |
| snow_02 (1K) | `assets/textures/snow/snow_packed_albedo.jpg`, `_normal.jpg`, `_rough.jpg` | Rob Tuytel — <https://polyhaven.com/a/snow_02> | CC0 1.0 | 2026-11-12 | Snow road, slopes, snow loads |
| weathered_planks (1K) | `assets/textures/wood/planks_albedo.jpg`, `_normal.jpg`, `_rough.jpg` | Dario Barresi, Dimitrios Savva — <https://polyhaven.com/a/weathered_planks> | CC0 1.0 | 2026-11-12 | Barriers, bridge decks, timber structures |
| bark_brown_02 (1K) | `assets/textures/wood/bark_albedo.jpg`, `_normal.jpg`, `_rough.jpg` | Rob Tuytel — <https://polyhaven.com/a/bark_brown_02> | CC0 1.0 | 2026-11-12 | Tree trunks, stumps |

### Music (OpenGameArt)

| Asset | File(s) in project | Author / source (URL) | License | License verified on | Used for |
|---|---|---|---|---|---|
| Flowerbed Fields [Loop] | `assets/audio/music/menu_flowerbed_fields.ogg` | Dylan_B — <https://opengameart.org/content/flowerbed-fields-loop> | CC0 1.0 | 2026-11-12 | Menu and lobby music |
| Sky Blue Street (165 bpm, loopable) | `assets/audio/music/race_sky_blue_street.ogg` | submitted by Titanio Verde, from the "For Racing Game (MintoDog's music)" collection — <https://opengameart.org/content/sky-blue-street> | CC0 1.0 | 2026-11-12 | Race music |

### Sound effects (Freesound, all CC0)

Each source is the sound's high-quality preview from its Freesound page
(the page showed the Creative Commons 0 license when it was fetched; the
check is automated in `tools/asset_pipeline/fs_get.py`). The recordings were
cut, looped, layered and level-matched by
`tools/asset_pipeline/build_audio.py`; nothing is used unedited.

| Asset | File(s) in project | Author / source (URL) | License | License verified on | Used for |
|---|---|---|---|---|---|
| Motorcycle_Yamaha_Tenere_250CC_Enduro_Idle.wav | `assets/audio/engine/engine_idle.wav` | Singular_Estudio — <https://freesound.org/people/Singular_Estudio/sounds/510231/> | CC0 1.0 | 2026-11-12 | Engine idle layer |
| Quad Bike_ATV Engine.wav | `assets/audio/engine/engine_low.wav` | Alex_hears_things — <https://freesound.org/people/Alex_hears_things/sounds/379915/> | CC0 1.0 | 2026-11-12 | Engine low-RPM layer |
| mower1.wav | `assets/audio/engine/engine_mid.wav` | Pagey1969 — <https://freesound.org/people/Pagey1969/sounds/566047/> | CC0 1.0 | 2026-11-12 | Engine mid-RPM layer |
| [Loopable] Generator or Lawn Mower Running | `assets/audio/engine/engine_high.wav`, `assets/audio/items/turbo_boost.wav` | sketchy.dog — <https://freesound.org/people/sketchy.dog/sounds/680119/> | CC0 1.0 | 2026-11-12 | Engine high-RPM layer; turbo rise |
| Gilera Runner 2007 revs backfire cold idle | `assets/audio/engine/engine_blip.wav`, `assets/audio/engine/engine_overrun.wav` | lovretta — <https://freesound.org/people/lovretta/sounds/140384/> | CC0 1.0 | 2026-11-12 | Throttle blip, lift-off overrun |
| bicycle tires on dirt road or gravel | `assets/audio/vehicles/roll_dirt.wav` | Garuda1982 — <https://freesound.org/people/Garuda1982/sounds/524115/> | CC0 1.0 | 2026-11-12 | Tyres rolling on gravel/dirt |
| tire_rolling_1.wav | `assets/audio/vehicles/roll_rattle.wav` | mhad — <https://freesound.org/people/mhad/sounds/390798/> | CC0 1.0 | 2026-11-12 | Chassis rattle / rolling |
| Skateboard rolling down wooden bridge.wav | `assets/audio/vehicles/roll_wood.wav` | Bruno_Garcez — <https://freesound.org/people/Bruno_Garcez/sounds/243762/> | CC0 1.0 | 2026-11-12 | Wheels on bridge planks |
| Footsteps on snow (clean) | `assets/audio/vehicles/roll_snow.wav` | xkeril — <https://freesound.org/people/xkeril/sounds/611277/> | CC0 1.0 | 2026-11-12 | Snow crunch rolling loop |
| 180530 Ice scrapes like skating foley.flac | `assets/audio/vehicles/roll_ice.wav` | TRP — <https://freesound.org/people/TRP/sounds/570990/> | CC0 1.0 | 2026-11-12 | Ice sliding loop |
| MudSquelch.wav | `assets/audio/vehicles/roll_mud.wav` | ahill86 — <https://freesound.org/people/ahill86/sounds/207142/> | CC0 1.0 | 2026-11-12 | Mud squelch grains (mud rolling loop) |
| Muddy Boots | `assets/audio/vehicles/roll_mud.wav`, `assets/audio/items/mud_bomb_splat.wav` | Breviceps — <https://freesound.org/people/Breviceps/sounds/447928/> | CC0 1.0 | 2026-11-12 | Mud grains, mud bomb splat |
| Kid bike drift - 250609_10h20 Albi Skatepark Madeleine - OKM | `assets/audio/vehicles/skid_loop.wav` | Sadiquecat — <https://freesound.org/people/Sadiquecat/sounds/811620/> | CC0 1.0 | 2026-11-12 | Skid/drift loop grains |
| auto car or van stop brake skid gravel short.flac | `assets/audio/vehicles/skid_loop.wav`, `assets/audio/vehicles/brake_skid.wav` | kyles — <https://freesound.org/people/kyles/sounds/637161/> | CC0 1.0 | 2026-11-12 | Skid grains, brake skid |
| loop smooth muffled rushing air tone skyline traffic distant | `assets/audio/environment/wind_loop.wav` | kyles — <https://freesound.org/people/kyles/sounds/454072/> | CC0 1.0 | 2026-11-12 | Wind rush at speed |
| Dull_Thud_01.flac | `assets/audio/vehicles/landing.wav`, `assets/audio/vehicles/hit_hard.wav` | wwstudioswastaken — <https://freesound.org/people/wwstudioswastaken/sounds/616295/> | CC0 1.0 | 2026-11-12 | Landing thump, crash body |
| Wood Smack.mp3 | `assets/audio/vehicles/hit_soft.wav`, `assets/audio/items/item_denied.wav` | Pancakebees — <https://freesound.org/people/Pancakebees/sounds/680108/> | CC0 1.0 | 2026-11-12 | Soft hit, item denied knock |
| Impact: Wood - Hitting Blocks | `assets/audio/vehicles/hit_wood_1.wav`, `assets/audio/vehicles/hit_wood_2.wav` | Sheyvan — <https://freesound.org/people/Sheyvan/sounds/521010/> | CC0 1.0 | 2026-11-12 | Soft hit variations |
| plastic_boxes_fall_01.wav | `assets/audio/vehicles/hit_hard.wav` | goldendiaphragm — <https://freesound.org/people/goldendiaphragm/sounds/321294/> | CC0 1.0 | 2026-11-12 | Hard crash |
| Mud Splash | `assets/audio/vehicles/mud_splash.wav`, `assets/audio/items/mud_bomb_splat.wav` | adiantheman — <https://freesound.org/people/adiantheman/sounds/841538/> | CC0 1.0 | 2026-11-12 | Mud splash, mud bomb |
| Cartoony Scream - Character Knocked Out (3 of 3) | `assets/audio/character/yelp_1.wav` | el_boss — <https://freesound.org/people/el_boss/sounds/751702/> | CC0 1.0 | 2026-11-12 | Rider thrown off (take 1) |
| wow/whoa | `assets/audio/character/yelp_2.wav` | Alivvie — <https://freesound.org/people/Alivvie/sounds/323438/> | CC0 1.0 | 2026-11-12 | Rider thrown off (take 2) |
| Oof (original) | `assets/audio/character/oof.wav` | unfa — <https://freesound.org/people/unfa/sounds/719053/> | CC0 1.0 | 2026-11-12 | Rider landing grunt |
| Short Ouch | `assets/audio/character/ouch.wav` | qubodup — <https://freesound.org/people/qubodup/sounds/743350/> | CC0 1.0 | 2026-11-12 | Rider landing grunt (take 2) |
| BODY FALL - V HVY - DIRT | `assets/audio/character/body_fall.wav` | leonelmail — <https://freesound.org/people/leonelmail/sounds/504626/> | CC0 1.0 | 2026-11-12 | Rider hits the ground |
| classic dizzy take slide whistle.wav | `assets/audio/character/dizzy.wav` | martian — <https://freesound.org/people/martian/sounds/403002/> | CC0 1.0 | 2026-11-12 | Getting up, dizzy slide whistle |
| woohoo | `assets/audio/character/woohoo.wav` | unfa — <https://freesound.org/people/unfa/sounds/468898/> | CC0 1.0 | 2026-11-12 | Podium celebration |
| Joyful - Wouhouh | `assets/audio/character/cheer.wav` | Sadiquecat — <https://freesound.org/people/Sadiquecat/sounds/801291/> | CC0 1.0 | 2026-11-12 | Podium celebration (take 2) |
| Cartoon Quick Zip 02 | `assets/audio/character/mount.wav` | se2001 — <https://freesound.org/people/se2001/sounds/541507/> | CC0 1.0 | 2026-11-12 | Hopping back on the trike |
| Running on gravel forest road.wav | `assets/audio/character/step_dirt_1-4.wav` | Vendarro — <https://freesound.org/people/Vendarro/sounds/584321/> | CC0 1.0 | 2026-11-12 | Footsteps on dirt |
| Footsteps Snow 2 - Walk & run | `assets/audio/character/step_snow_1-4.wav` | Vrymaa — <https://freesound.org/people/Vrymaa/sounds/773740/> | CC0 1.0 | 2026-11-12 | Footsteps on snow |
| Wine cork | `assets/audio/items/item_pickup.wav` | HenKonen — <https://freesound.org/people/HenKonen/sounds/757257/> | CC0 1.0 | 2026-11-12 | Item box pickup (pop) |
| Popping Cork | `assets/audio/items/item_pickup.wav` | milcahrawr — <https://freesound.org/people/milcahrawr/sounds/622150/> | CC0 1.0 | 2026-11-12 | Item box pickup (second pop) |
| Swoosh sound 2 | `assets/audio/items/item_throw.wav`, `assets/audio/items/turbo_boost.wav` | Masgame — <https://freesound.org/people/Masgame/sounds/347550/> | CC0 1.0 | 2026-11-12 | Item throw whoosh, turbo start |
| boing.wav | `assets/audio/items/spring_punch.wav` | suzenako — <https://freesound.org/people/suzenako/sounds/537060/> | CC0 1.0 | 2026-11-12 | Spring punch boing |
| Cartoon_Spring_Bouncing 01.wav | `assets/audio/items/spring_bounce.wav` | Denis Chapon — <https://freesound.org/people/Denis%20Chapon/sounds/109435/> | CC0 1.0 | 2026-11-12 | Spring punch (take 2) |
| Awawawaw - cartoon-like slip vocal sfx | `assets/audio/items/banana_slip.wav` | A_kn — <https://freesound.org/people/A_kn/sounds/711794/> | CC0 1.0 | 2026-11-12 | Banana peel slip |

### Considered and not used

Blender is not installed on the build machine, so no Blender-made models
exist. Kenney and Quaternius model packs were considered; the project keeps
its own sculpted-in-code models instead (see "Original assets"), so **no
external 3D models are in the project**. Downloaded but unused candidate
recordings and music were not added to the repository.

## Tools and runtime (not shipped as game content)

| Item | Source | License | Notes |
|---|---|---|---|
| Godot Engine 4.7.2 stable | godotengine.org | MIT | Engine. The exported game includes the Godot runtime, so the Godot MIT notice must ship with releases |
| Godot 4.7.2 standard export templates | official GitHub release `godotengine/godot` 4.7.2-stable, `Godot_v4.7.2-stable_export_templates.tpz` | MIT | Approved 2026-11-08; installed 2026-11-09 after checking its SHA-512 against the release's `SHA512-SUMS.txt`. Standard (non-.NET). Used for the macOS and Windows builds; their runtime ships inside the builds, so the Godot MIT notice applies |

## Original assets

Everything else is original and built in code or scenes:

- **Models (Visual Overhaul V2):** all scenery is sculpted procedurally by
  `scripts/visuals/sculpt.gd` + `scenery_kit.gd` (pines, broadleaf trees,
  bushes, boulders, hoodoos, mesas and mountains, rock arches, cliff ledges,
  cacti, stumps, ferns, mushrooms, ice shards, clouds, waterfalls); trike
  detail by `scripts/vehicles/trike_detail.gd`; rider detail by
  `scripts/characters/rider_detail.gd`. The trike and rider base models are
  the original scene-built ones from earlier milestones.
- **Shaders and materials:** `assets/materials/terrain.gdshader`,
  `road.gdshader`, and `scripts/visuals/material_library.gd` (original).
- **Synthesized audio (kept):** countdown beeps, GO, finish fanfare,
  victory jingle, results chord and UI clicks (`scripts/audio/sound_synth.gd`).
- Track geometry, props, items, effects, UI, route-map previews, rider
  looks and trike liveries: original, as before.
