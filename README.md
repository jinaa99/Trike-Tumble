# Trike Tumble

Colorful 3D cartoon downhill party racing on three-wheeled drift trikes.
Godot 4.7.2 · GDScript · Mobile renderer.

**Run:** open the folder in Godot 4.7.2 and press Play (F5), or
`<godot-binary> --path .` (starts at the main menu: Play / Host / Join / Settings).

**Forest Rush** (the first finished map, 7.4 km, about 5½–7 minutes): PLAY →
Forest Rush → Start Race, or `<godot-binary> --path . res://scenes/main/forest_rush.tscn`.
A mountain start, a fast pine-forest descent, hairpins, two wooden bridges,
mud and falling logs, a ravine jump and a fast run to the finish.

**Race 4 AI riders on the short test track:** straight from the command line:
`<godot-binary> --path . res://scenes/main/race_five.tscn`
(or `res://scenes/main/main.tscn -- --ai=4 --difficulty=easy|medium|hard|mixed`).
The countdown starts by itself; results, Race Again and Return to Lobby follow the race.

**Play online (LAN):** one player picks HOST GAME and shares the address
shown; others pick JOIN GAME and enter it. Up to 5 players. Over the
internet the host must forward UDP port 7777 on their router. See
[Networking](docs/NETWORKING.md) (so far only tested with several instances
on one computer).

**Controls** (rebindable in Settings): W/↑ accelerate · S/↓ brake/reverse ·
A/D/←/→ steer · SPACE + steer drift (release for boost) · F use item (items
coming) · R reset · ESC pause · after a wipeout: WASD/arrows run, E get back
on the trike

Screenshots: [milestone 02](docs/screenshots/milestone_02) ·
[milestone 03 (wipeouts)](docs/screenshots/milestone_03) ·
[five-racer race](docs/screenshots/milestone_ai) ·
[menus](docs/screenshots/milestone_menu) ·
[online](docs/screenshots/milestone_online) ·
[Forest Rush](docs/screenshots/milestone_forest_rush)

Docs: [CLAUDE.md](CLAUDE.md) · [Game design](docs/GAME_DESIGN.md) ·
[Roadmap](docs/ROADMAP.md) · [Architecture](docs/TECHNICAL_ARCHITECTURE.md) ·
[Networking](docs/NETWORKING.md) · [Testing](docs/TESTING.md)
