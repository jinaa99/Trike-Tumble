# TRIKE TUMBLE — Asset Credits

Every external asset in the project must be listed here **before** it is
committed: source, author, license and where it's used. Verify the license on
the original source page (not a mirror) when adding an entry.

## Allowed licenses (owner decision, 2026-11-08)

| Type | Allowed | Notes |
|---|---|---|
| Fonts | SIL Open Font License (OFL) only | Keep the font's `OFL.txt` next to the font file |
| Sound effects | CC0 only | Record the original page URL |
| Music | Original or CC0 only | No copyrighted commercial music |
| 3D models, textures, other | Original procedural assets | External ones need owner approval first |

Never allowed: paid assets, paid plugins, paid services.

## External assets

| Asset | File(s) in project | Author / source (URL) | License | License verified on | Used for |
|---|---|---|---|---|---|
| *(none yet)* | | | | | |

## Tools and runtime (not shipped as game content)

| Item | Source | License | Notes |
|---|---|---|---|
| Godot Engine 4.7.2 stable | godotengine.org | MIT | Engine. The exported game includes the Godot runtime, so the Godot MIT notice must ship with releases |
| Godot 4.7.2 standard export templates | official GitHub release `godotengine/godot` 4.7.2-stable, `Godot_v4.7.2-stable_export_templates.tpz` | MIT | Approved 2026-11-08; installed 2026-11-09 after checking its SHA-512 against the release's `SHA512-SUMS.txt`. Standard (non-.NET). Used for the macOS and Windows builds; their runtime ships inside the builds, so the Godot MIT notice applies |

## Original assets

All current game content is original and generated procedurally in code or
scenes: trike, rider, track, scenery, materials (runtime noise textures), UI,
effects, item boxes and item meshes (mud bomb, puddle, banana peel, spring
punch), and the Rocky Canyon / Snow Slide content (rock spires, cliff walls,
falling/rolling rocks, snowmen, snow-capped trees, windsocks, wind-snow
particles, route-map previews). HUD/menu text uses operating-system fonts
(not bundled).

**Audio (milestone 09): every sound is original and synthesized in code**
the first time it is needed (`scripts/audio/sound_synth.gd`: sine tones,
pitch sweeps, filtered noise bursts and seamless loops; named sounds in
`scripts/audio/sound_bank.gd`). There are **no audio files and no
downloaded sounds** in the project: engine and skid loops, brake, hits,
landing, rider yelp/thud/get-up/footsteps/mount, item sounds, countdown,
GO, finish fanfare, victory jingle, results chord and UI clicks. There is no
music yet (the Music bus and slider exist; any music must be original or
CC0 and recorded here before use).

Rider looks (helmet styles, accessories, faces), trike accent liveries,
particle effects (wheel spray, skid marks, boost trail, landing puffs,
impact bursts, confetti) and grass tufts (milestone 09) are also original
and procedural. **External assets: still none.**
