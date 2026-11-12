# Trike Tumble

Colorful 3D cartoon downhill party racing on three-wheeled drift trikes, for
1–5 players. Godot 4.7.2 · GDScript · Mobile renderer · Jolt physics.
No Steam, no accounts, no paid services.

**Status (final demo, milestone 10):** three maps, AI riders, items,
wipeouts and recovery, online play over LAN/direct IP, sound and effects.
The honest test report is [docs/FINAL_DEMO_REPORT.md](docs/FINAL_DEMO_REPORT.md);
open issues are in [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md). Exported
builds need the official Godot 4.7.2 export templates (see the report).

## Run from source

Open the folder in Godot 4.7.2 and press Play (F5), or
`<godot-binary> --path .` (main menu: Play / Host / Join / Settings / Quit).

Straight into a race (you + 4 AI):

```sh
<godot-binary> --path . res://scenes/main/forest_rush.tscn
<godot-binary> --path . res://scenes/main/rocky_canyon.tscn
<godot-binary> --path . res://scenes/main/snow_slide.tscn
```

## Maps

| Map | Length | What makes it special |
|---|---|---|
| Forest Rush | 7.4 km | fast pine forest, wooden bridges, mud, falling logs, a ravine jump |
| Rocky Canyon | 7.3 km | cliff roads, falling and rolling rocks, three switchback descents, two big jumps |
| Snow Slide | 7.5 km | snow road, ice patches, frozen bridges, crosswinds, snowmen |

Races take about 5½–7 minutes.

## Play together

One player picks **HOST GAME** (port 7777 by default) and shares the address
shown; the others pick **JOIN GAME** and enter it. Up to 5 players; AI can
fill free seats. Over the internet the host must forward **UDP port 7777**.
Only tested with several game instances on one computer so far (see the
report). Details: [Networking](docs/NETWORKING.md).

## Controls (rebindable in Settings)

W/↑ accelerate · S/↓ brake/reverse · A/D/←/→ steer · SPACE + steer drift
(release for boost) · Q use item · R back on the road · ESC pause · after a
wipeout: WASD/arrows run, E get back on the trike.

## Tests

```sh
$GODOT --headless --path . --fixed-fps 60 --scene res://tests/test_runner.tscn        # main suite
$GODOT --headless --path . --fixed-fps 60 --scene res://tests/map_test_runner.tscn     # timed races, all maps
$GODOT --headless --path . --scene res://tests/net/net_test_runner.tscn                # multi-process network
$GODOT --headless --path . --scene res://tests/net/net_test_runner.tscn -- e2e5        # 5 real players, one whole race
```

See [Testing](docs/TESTING.md).

## Docs

[CLAUDE.md](CLAUDE.md) · [Final demo report](docs/FINAL_DEMO_REPORT.md) ·
[Known issues](docs/KNOWN_ISSUES.md) · [Game design](docs/GAME_DESIGN.md) ·
[Roadmap](docs/ROADMAP.md) · [Architecture](docs/TECHNICAL_ARCHITECTURE.md) ·
[Networking](docs/NETWORKING.md) · [Testing](docs/TESTING.md) ·
[Asset credits](docs/ASSET_CREDITS.md) · [Art direction](docs/ART_DIRECTION_BIBLE.md) · [Audio design](docs/AUDIO_DESIGN.md) · [Visual overhaul results](docs/VISUAL_OVERHAUL_PROGRESS.md)

Screenshots: `docs/screenshots/` (milestone folders; the latest are
`visual_overhaul_v2/` with `before/`, `after/` and a comparison sheet).
