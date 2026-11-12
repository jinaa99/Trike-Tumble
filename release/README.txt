TRIKE TUMBLE — desktop demo (v0.10)
====================================

A cartoon downhill party racer for 1–5 players on three-wheeled drift
trikes. Three maps, races of about 5–7 minutes, items, wipeouts, online
play over your own network. No Steam, no accounts, no paid services.

Folders
-------
  TrikeTumble-macOS/    TrikeTumble.zip -> "Trike Tumble.app" (Apple Silicon and Intel Macs, macOS 11+)
  TrikeTumble-Windows/  TrikeTumble.exe (64-bit Windows, x86_64; everything is inside the exe)

SHA-256 (to check a download is complete):
  TrikeTumble.zip  1a7d8c3e7d45b88ee93a7a8b9b9cbdf998ba77b1ef1608bb0aa24a675d5a9d5b
  TrikeTumble.exe  3faa8dc70f8616e8451de7da27cbd20b0f1c4443ba8431681b9f71d8d597617c


1. Launch
---------
macOS
  1. Unzip TrikeTumble.zip and move "Trike Tumble.app" anywhere (e.g. Applications).
  2. The app is not notarized by Apple (no paid developer account), so the
     first launch is blocked by Gatekeeper ("Apple could not verify ...").
     On macOS 15 (Sequoia): try to open it once, then open
     System Settings > Privacy & Security, scroll down and click
     "Open Anyway" next to TrikeTumble, and confirm.
     On macOS 13–14: Control-click the app > Open > Open.
     (Alternative, Terminal: xattr -dr com.apple.quarantine "/path/to/Trike Tumble.app")
  3. When you HOST a game macOS may ask to allow incoming connections: Allow.

Windows
  1. Keep TrikeTumble.exe in its folder and double-click it.
  2. SmartScreen may say "Windows protected your PC" (the exe is not
     code-signed): click "More info" > "Run anyway".
  3. When you HOST a game, Windows Firewall asks for network access:
     allow it on Private networks.

The game starts at the main menu. Settings (volume, resolution, fullscreen,
graphics quality, controls, your name) are saved automatically.


2. Play alone
-------------
PLAY > choose a map > in the lobby add up to 4 AI riders (Easy/Medium/Hard)
> Ready > Start Race.


3. Play together (up to 5 players)
----------------------------------
Everybody needs the same version of the game.

HOST (one player)
  1. HOST GAME. Keep the port 7777 (or choose 1024–65535) and the player limit.
  2. Press Host Game. The screen shows your LAN address, e.g. 192.168.1.23.
  3. Tell your friends that address and the port.
  4. In the lobby: choose the map (Change Map), add AI riders for empty
     seats if you like, press Ready and Start Race when everyone is ready.

JOIN (everyone else)
  1. JOIN GAME. Enter the host's address (e.g. 192.168.1.23) and port (7777).
  2. Connect. In the lobby press Ready and wait for the host.

Network requirements
  - Same home network (LAN / same Wi-Fi): nothing else needed.
  - Over the internet: the HOST must forward UDP port 7777 (or the port
    they chose) on their router to their computer, and give friends their
    PUBLIC address (search "what is my IP"). Some internet providers use
    carrier-grade NAT, which makes port forwarding impossible. A free
    virtual-LAN tool (e.g. ZeroTier or Tailscale) is an alternative, but it
    is third-party software and is not required.
  - The host's computer runs the race (positions, finish, items): if the
    host quits, the race ends for everyone. You can't join a race that is
    already running; join in the lobby.


4. Controls (keyboard; change them in Settings > Controls)
------------------------------------------------------------
  W / Up        accelerate            S / Down     brake, then reverse
  A D / Left Right  steer             SPACE + steer  drift (release = BOOST)
  SPACE alone   handbrake             Q            use item
  R             back on the road      ESC          pause / menu
  After a wipeout: W A S D / arrows run, E get back on your trike.
  Basic gamepad support (triggers, left stick, buttons).

Items: drive through the floating "?" boxes. You hold one item at a time.
  Mud Bomb (throw ahead), Spring Punch (knock a rider beside you),
  Turbo Bottle (boost), Banana Peel (drop behind you).


5. Maps
-------
  Forest Rush   7.4 km   fast pine forest, wooden bridges, mud, falling logs, a ravine jump
  Rocky Canyon  7.3 km   cliff roads, falling rocks, tight switchbacks, two big jumps
  Snow Slide    7.5 km   snow and ice, frozen bridges, crosswinds, snowmen


6. Known limitations (honest)
-----------------------------
  - Tested on one MacBook Air M4 only. Online play was tested with up to
    five copies of the game on ONE computer; two real computers on a LAN,
    Windows, and the internet are NOT tested yet.
  - The Windows build has never been run on a Windows PC (it was built on a Mac).
  - The Mac build was tested on that MacBook (menu and a race on each map);
    the Gatekeeper "Open Anyway" steps above are what macOS normally asks
    for an app that isn't notarized, but were not clicked through on a
    freshly downloaded copy.
  - The new recorded sounds and the music have not had a proper listening
    pass yet; tell us if something is too loud or annoying.
  - Full list: docs/KNOWN_ISSUES.md in the project.

7. Licenses
-----------
  Made with the Godot Engine (MIT license, see GODOT_LICENSE.txt).
  Models are original (built in code). Music, recorded sound effects,
  textures and fonts are free-licensed (CC0 / SIL OFL): see CREDITS.txt.

Credits and licenses for the music, sounds, textures and fonts: CREDITS.txt
