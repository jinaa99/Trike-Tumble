# TRIKE TUMBLE — Final demo report (milestone 10)

Date: 2026-11-11. Hardware: **one** MacBook Air (Apple M4, 16 GB, macOS
15.7.9, built-in 2560×1664 display). Engine: Godot 4.7.2 stable (official),
Mobile renderer, Jolt physics. Every number below was measured during this
milestone unless marked otherwise. Nothing was tested on a second computer
or on Windows.

## 1. Verdict

The five core experiences work end to end **in automated tests and in a
real five-instance online race on one computer**: launch, host/join a
lobby, pick one of three maps, race 5–7 minutes, collide, fall off, recover
and remount, collect and use items, finish, see identical results, Race
Again. The exported macOS build launches and races on all three maps.

**Not verified:** two real computers on a LAN, internet play, the Windows
build on Windows, the Gatekeeper prompt on a freshly downloaded copy, and
any human playtest. Treat the demo as **ready for a first friends playtest
on Macs over a LAN**, with Windows and internet play still unproven.

## 2. Completed features

- **Racing:** custom arcade trike physics (steering, drift + boost tiers,
  handbrake, air control, surfaces: dirt, grass, mud, planks, snow, ice),
  rider ejection/ragdoll/get-up/run/mount, out-of-bounds and emergency
  recovery.
- **Races:** lobby → 3-2-1-GO → racing → finish (with a 90 m cool-down run-off
  and automatic braking) → results → Race Again / Return to Lobby; ordered
  checkpoints, live positions, finish timeout and DNF.
- **AI:** Easy/Medium/Hard drivers that race, avoid obstacles, drift, use
  items, recover from crashes and finish every map.
- **Maps:** Forest Rush (7.45 km), Rocky Canyon (7.34 km), Snow Slide
  (7.49 km), each with 5 grid slots, 30 checkpoints, item boxes, hazards,
  bridges and big jumps.
- **Items:** Mud Bomb, Spring Punch, Turbo Bottle, Banana Peel; host-
  authoritative pickups, uses and hits.
- **Online:** ENet over UDP (default port 7777), 2–5 players, AI fills
  seats, host authority for race state, results and items; disconnect,
  host shutdown and rejoin handling.
- **Presentation:** five distinct riders with reactive faces and a finish
  celebration, effects, camera feedback, all sounds synthesized in code,
  menus, settings (volumes, resolution, fullscreen, quality, key rebinding,
  name), route-map previews.
- **Release:** macOS universal and Windows x86_64 exports, `release/`
  folder with README and the Godot license.

## 3. Test totals

Final runs on the shipped code (2026-11-11), headless on the M4:

| Suite | Normal | Strict (warnings = errors) | Failed |
|---|---|---|---|
| Main suite (`test_runner.tscn`: vehicles, riders, races, AI, items, polish, UI, network unit, all three maps) | **682 passed** | **682 passed** | 0 |
| Timed AI races (`map_test_runner.tscn`, 3 maps × 14) | **42 passed** (2026-11-09) | **42 passed** | 0 |
| Network, separate processes (`net_test_runner.tscn`: duo, rules, drop, five, forest, items, maps) | **50 passed** | **50 passed** | 0 |
| Five real players, one whole race (`e2e5`) | **9 passed** (final run) | **9 passed** (run 3) | 0 in the final runs (run 1: 1 failure, see §4) |

No assertion was removed or weakened in this milestone; 7 new checks were
added (finish run-off on 3 maps × 2, quick-race launch).

**Errors and warnings in the final logs:**
- Errors: **1** per main-suite run, and it is intentional: "Couldn't create
  an ENet host" from the test that hosts on a port already in use. Network
  suite and five-player run: **0 errors** (they had 9 "Unable to send
  packet" errors before the fix in §8).
- Warnings: **2** per main-suite run (the intended "unknown map" warning
  from the quick-race test, and "ObjectDB instances leaked at exit" at
  shutdown); network runs: only "ObjectDB instances leaked at exit" when
  each test process quits (15–17 per network run). No GDScript warnings
  (strict mode passes).
- Exports: 0 errors, 0 warnings. Exported Mac app: 0 errors, 0 warnings in
  the menu and in a race on each map.

## 4. Real five-player end-to-end (five independent game instances)

Five separate Godot processes (one host, four clients) on the M4 over
127.0.0.1, real time, driven by the scripted test driver (obstacle
avoidance, items used after 1 s, R after 2 s stuck or 15 s on foot), no AI
racers. Map chosen by the host: Snow Slide. Scenario `e2e5`.

| Run | Result | Finish (host's results, identical on all 5 screens) | Notes |
|---|---|---|---|
| 1 (2026-11-09) | **8/9** | Hana 5:21.80 · Milo 5:26.67 · Noor 5:28.43 · Kai 5:29.72 · **Lumi DNF** | Lumi got stuck twice; the driver then had no "R when stuck on foot", and she missed the 120 s finish timeout. Also 4 wipeouts right after the finish line (see §8, fixed) and 3 ENet shutdown errors (fixed) |
| 2 (2026-11-09) | **9/9** | Hana 5:21.87 · Kai 5:23.03 · Lumi 5:26.60 · Milo 5:26.75 · Noor 5:27.18 | 11 collisions (hardest 15.5), wipeout + recovery seen by the host, 40 item pickups/uses, 2 item hits, Race Again |
| 3 (strict mode) | **9/9** | Kai 5:17.90 · Hana 5:18.97 · Lumi 5:22.75 · Milo 5:23.58 · Noor 5:27.02 | after the finish fix: 2 wipeouts in total, none after the line; 46 pickups/uses, 2 hits, Race Again |
| 4 (final, 2026-11-11) | **9/9** | Milo 5:21.05 · Kai 5:21.07 · Noor 5:24.08 · Lumi 5:26.08 · Hana 5:26.80 | 10 collisions (hardest 15.0), 2 wipeouts (none after the line), 41 pickups/uses, 4 item hits, Race Again |

Checked in every run: 5 human players in the lobby, all ready, the host's
map, everyone loaded it and saw 3-2-1-GO, everyone finished through every
checkpoint (runs 2–4), identical finishing order and times on every screen,
collisions, a wipeout and full recovery seen remotely, items, Race Again.

AI is tested separately: the timed races (§5) and the in-suite AI tests.

## 5. AI races (separate from the player test)

`tests/map_test_runner.tscn`, 14 races per map, simulated time (headless,
`--fixed-fps 60`): **42/42 passed, normal and strict.** Every racer finished
through all 30 checkpoints with no AI reset.

| Map | Hard AI | Medium AI | Easy AI | Simple player driver |
|---|---|---|---|---|
| Forest Rush | 5:24–5:29 | 5:36–5:45 | 6:40–6:48 | 5:51 (4 wipeouts, 2 respawns) |
| Rocky Canyon | 5:12–5:33 (1–3 wipeouts each) | 5:27–5:39 | 6:34–6:47 | 5:19 |
| Snow Slide | 5:24–5:28 | 5:34–5:37 | 6:34–6:41 | 5:24 |

(Measured before the 90 m finish run-off was added; the finish line now sits
60 m earlier, so real times are ~2–3 s shorter. The map tests' hard-AI runs
after the change: Forest 5:22.9, Canyon 5:09.1, Snow 5:21.7.)

## 6. LAN and internet

| | Status |
|---|---|
| Several instances on one computer (127.0.0.1) | **Tested**: 2, 3 and 5 instances; all network checks pass |
| **Two separate computers on a LAN** | **NOT TESTED** — only one computer was available. No real latency, packet loss or NAT behaviour has been observed |
| **Internet** | **UNVERIFIED** — never tested across independent networks |

What a LAN test needs: both computers on the same network; the host allows
the game through its firewall (macOS asks on first host; Windows: allow on
Private networks); clients join the LAN address the lobby shows (e.g.
192.168.1.18:7777). Internet: the host forwards **UDP 7777** (or the chosen
port) on the router to their computer and shares their public IP;
carrier-grade NAT can make this impossible; a virtual LAN (ZeroTier,
Tailscale) is optional third-party software. One-computer observations:
smooth proxies (max ~0.65 m per tick, no unexplained jumps), host
validation drops spoofed/replayed packets, disconnect = DNF for that
player, host shutdown returns clients to the menu with a message.

## 7. Performance (windowed 1280×720, 5 racers, Apple M4)

Measured 2026-11-11 with the Mac left untouched (an earlier, interrupted
session gave erratic 60/145 fps readings and was discarded).

| Map | Load (scene + track build + 5 racers) | Average FPS (frame time) | Worst frame | Physics | Draw calls | Memory (static / video) |
|---|---|---|---|---|---|---|
| Test track (`perf5`) | — | 79 fps | **610 ms** (one spike) | 1.8 ms | 779 | — |
| Forest Rush | 1.93 s | 136–145 fps (6.9–7.3 ms) | **417 ms** (one spike at the start), otherwise 9–24 ms | 1.8–4.2 ms | 347–926 | 215 MB / 328 MB |
| Rocky Canyon | 1.71 s | 109–145 fps (6.9–9.2 ms) | **398 ms** (one spike), otherwise 11–20 ms | 1.8–4.9 ms | 286–937 | 206 MB / 375 MB |
| Snow Slide | 2.09 s | 120 fps (8.3 ms) at every spot | 11–28 ms | 1.3–4.6 ms | 432–965 | 215 MB / 345 MB |

- Far above the 60 fps target on this machine; averages are capped by the
  display/vsync (120–145).
- **One isolated 0.4–0.6 s hitch per run** in three of four runs, at a
  different place each time. Ruled out: sound synthesis (all 29 sounds
  build in 56 ms in total). Likely a one-time GPU pipeline compile when an
  effect or material first appears. Unfixed (see KNOWN_ISSUES.md).
- Snow Slide draws ~0.75–1.15 M primitives; weaker GPUs are untested.
- Pack size 0.6 MB (everything is procedural).

## 8. Bugs found and fixed in this milestone

- **Finish wall:** the road ended 30 m after the finish line, so finishers
  who didn't brake hit the end wall and were thrown off (seen in the
  five-player run). Now 90 m of run-off on every map, and a finished local
  trike brakes to a stop automatically. New test on all three maps:
  23 m/s over the line → stops with 54–58 m to spare, rider aboard.
- **ENet send errors** when players leave ("Unable to send packet on
  channel 0"): clients check the connection before sending, the host only
  sends to connected peers, and peer-notice relaying (unused) is off. The
  network suite went from 9 such errors to 0.
- **macOS export configuration:** universal/arm64 exports need ETC2/ASTC
  texture import — enabled.
- **Release builds can't open scenes from the command line**, so a QA launch
  option was added: `-- --quick-race=<map>` (solo race with 4 AI via the
  normal lobby); tested in the UI suite and used on the exported app.
- Forest Rush card text said "7 km" next to a "7.4 km" route map — fixed.

## 9. Mac export

- Templates: official **Godot 4.7.2 stable standard** export templates
  (`Godot_v4.7.2-stable_export_templates.tpz`, 1.28 GB, from the
  godotengine/godot GitHub release; SHA-512 verified against the release's
  `SHA512-SUMS.txt`). Installed 2026-11-09 with the owner's approval.
- Build: `release/TrikeTumble-macOS/TrikeTumble.zip` (61 MB) →
  "Trike Tumble.app", **universal (x86_64 + arm64)**, ad-hoc signed
  (hardened runtime), signature verifies; not notarized (no paid Apple
  account). SHA-256 `1a7d8c3e7d45b88ee93a7a8b9b9cbdf998ba77b1ef1608bb0aa24a675d5a9d5b`.
- **Tested on the M4 (arm64 slice only):** main menu, and a race on each of
  the three maps (~35 s each, via `--quick-race`), 0 errors, 0 warnings.
  The x86_64 slice was **not run** (no Intel Mac).
- **Gatekeeper:** with a download quarantine flag set, `spctl --assess`
  **rejects** the app (expected for a non-notarized app). Friends must
  allow it once (System Settings → Privacy & Security → Open Anyway on
  macOS 15; Control-click → Open on 13–14). This flow was **not clicked
  through** on a freshly downloaded copy.
- Online play from the exported build was not automated (no UI scripting);
  it runs the same code that the network tests cover.

## 10. Windows export

- Build: `release/TrikeTumble-Windows/TrikeTumble.exe` (110 MB, x86_64,
  PE32+ GUI, game data embedded), exported with 0 errors/0 warnings.
  SHA-256 `3faa8dc70f8616e8451de7da27cbd20b0f1c4443ba8431681b9f71d8d597617c`.
- Same resources as the Mac build (one shared ~0.6 MB pack; no tests or
  docs). Input map, audio buses, UI and network settings come from the same
  project settings.
- **Execution on Windows: UNVERIFIED.** No Windows PC was available. D3D12
  is the configured Windows driver (Godot falls back to Vulkan); not
  code-signed (SmartScreen will warn).

## 11. Known limitations

See `docs/KNOWN_ISSUES.md`. In short: no LAN/internet/Windows testing, one
unexplained 0.4–0.6 s hitch per session, remote crashes are silent on other
screens, no music, procedural rider (no throw/flinch animation), AI don't
avoid item traps, no reconnect/host migration, Gatekeeper/SmartScreen
prompts.

## 12. Exact instructions for friends

Give them the `release/` folder (or the one build they need plus
`README.txt`). Short version:

1. **Mac:** unzip `TrikeTumble.zip`, open "Trike Tumble.app"; when macOS
   blocks it: System Settings → Privacy & Security → **Open Anyway**.
   **Windows:** run `TrikeTumble.exe`; SmartScreen → More info → Run
   anyway; allow the firewall prompt on Private networks when hosting.
2. **Host:** HOST GAME → keep port 7777 → Host Game → tell everyone the
   address shown at the top of the lobby (e.g. 192.168.1.18:7777) → Change
   Map → Ready → Start Race when everyone is ready.
3. **Join:** JOIN GAME → type the host's address and port → Connect → Ready.
4. **Internet:** the host forwards UDP 7777 to their computer and shares
   their public IP (untested).
5. **Controls:** W/↑ throttle, S/↓ brake/reverse, A/D steer, SPACE + steer
   drift (release for boost), Q item, R back on the road, ESC pause; after a
   wipeout WASD to run and E to get back on.
6. Everyone must run the same build. If the host quits, the race ends for
   all; join again from the lobby.
