# TRIKE TUMBLE — Known issues and untested areas

Honest list for the final demo (milestone 10, 2026-11-09). "Untested" means
nobody has tried it, not that it is broken.

## Not tested (needs hardware or people we don't have)

| Area | Status |
|---|---|
| **Two real computers on a LAN** | **NOT TESTED.** Only one computer (MacBook Air M4) was available. Every online test ran several game instances on that one Mac over 127.0.0.1. |
| **Internet play** | **UNVERIFIED.** Never tested across independent networks. Needs the host's UDP port (default 7777) forwarded; carrier-grade NAT can make that impossible. |
| **Windows** | **UNVERIFIED.** The Windows x86_64 preset exists, but no Windows PC was available; the game has never run on Windows. The project uses D3D12 on Windows (`rendering_device/driver.windows`), with Godot's Vulkan fallback. |
| **Exported builds** | Built (official 4.7.2 standard templates). The Mac build ran on the M4 (arm64 slice): menu + a race on each map, 0 errors. Its x86_64 slice was not run (no Intel Mac). The Windows exe was never run. |
| **Gatekeeper on a downloaded copy** | `spctl` rejects the non-notarized app (expected); the "Open Anyway" steps were not clicked through on a freshly downloaded copy. |
| **Human playtests** | No human has timed or judged the three maps, the items balance, the sounds or the controls on a real keyboard/gamepad. |
| **Weaker GPUs** | Only measured on an Apple M4 (120 fps). Snow Slide draws ~1 M primitives. |

## Fun-First Gameplay V2 (2026-11-13/14): unverified or unfinished

Everything listed as built in `docs/DEVELOPMENT_PROGRESS.md` has automated
tests. What those tests cannot show:

- **Fun is unverified.** No human has played the skills, tricks, slipstream,
  tree-falls, the new mud and ice, or read the awards. Checklist:
  `docs/FUN_FIRST_PLAYTEST.md`.
- **The new sounds have not been listened to.** Hub whirr, freewheel tick,
  sleeve hiss, hazard, skill and voice sounds are synthesized and only
  checked for timing, level and clipping in headless tests.
- **Characters are the same code-sculpted rigs.** Blender is not installed
  on this Mac; no new models or rigs were made. Added instead: reaction
  faces and gestures (laugh, yelp, cheer, smug, confused, grumble, focus,
  trick pose), a blink, one taunt per rider, a voice pitch per rider, and a
  riding posture per rider (`Rider.RIDING_STYLE`: Pip hunched and glaring,
  Rusty laid back with a lolling head, Nutmeg fidgety, Zip bouncy, Bramble
  calm and upright).
  Silhouettes and accessories are unchanged from Visual Overhaul V2.
- **Rider choice in the lobby** works offline and online (each seat picks a
  rider; bots swap, another human's rider can't be taken). Tested with
  unit tests and the multi-process network suite, not by people on two
  machines.
- **Per-map music** is the same race track played at a different speed and
  level per map, not separate tracks.
- **Unused audio files:** the engine recordings and `turbo_boost.wav` stay
  in `assets/audio` (credited) but are no longer used. Safe to delete if
  nothing else wants them.
- **Hazards and AI:** the hard AI finishes every map with no resets at the
  authored hazard phases (seed 0) and with the seeds tried in
  `tests/tools/ai_probe.tscn`; a random seed can still line up a tree-fall
  with an AI badly (it then falls off and recovers, which is allowed, not a
  reset).
- **Performance** (re-measured 2026-11-14, Apple M4, 5 racers): 120 fps
  average on every measured section of all three maps; worst single frame
  34 ms (Forest start, all five racers together). Primitive counts are
  higher than the Visual Overhaul note (Snow Slide start 2.8 M, Forest
  2.0 M); weaker GPUs are still untested.

## Visual Overhaul V2 (2026-11-12): what is unverified or unfinished

- **Audio has not been listened to.** The recorded engine, surface, rider
  and item sounds and both music tracks were chosen and mixed by
  measurement and tests only. Levels, takes and engine crossover points
  need a human pass (checklist in `docs/AUDIO_DESIGN.md`).
- **Characters and trike are detail passes, not new models.** Blender is
  not installed on the build machine; no models were imported. The rider
  is still a procedural primitive rig.
- **UI redesign is partial:** new fonts, colours and a smaller HUD; menu
  layouts, map cards, portraits and icons are as before.
- **Renderer:** Mobile kept after an A/B (no SSAO, no contact-hardening
  shadows). See `docs/VISUAL_OVERHAUL_PROGRESS.md`.
- **Heavier scenes:** the new scenery roughly triples the triangle count
  (see the performance table in VISUAL_OVERHAUL_PROGRESS). Fine on the M4;
  unmeasured on integrated GPUs and Windows. Low quality shortens scenery
  range and turns sun shadows off.
- **Shutdown message:** quitting while a recorded sound plays can print
  "resources still in use at exit" (seen in headless test runs and when
  the capture tools quit). Harmless.
- **Cacti have no collision** (Rocky Canyon): with colliders one trapped an
  AI trike in the timed races, so they are soft like bushes. A trike can
  pass through one.
- The network suite passed (50/50) before the last two small scenery
  changes and was not re-run after them; the five-player end-to-end race
  and strict mode were not run in this milestone.
- Waterfalls are static; small ground cover fades out at 120 m; bridges
  have wood textures but no new rope/metal fittings; no tyre-track decals.

## Known problems

- **One isolated 0.4–0.6 s frame hitch per session (unresolved).** In the
  final undisturbed measurements, three of four runs had a single spike
  (610, 417, 398 ms), each at a different spot near the start; all other
  frames were 9–28 ms. Sound synthesis is ruled out (56 ms for all sounds).
  Most likely a one-time GPU pipeline compile when an effect/material first
  appears (warming effects up during the countdown would be the fix).
- **Remote crashes are silent.** On other players' screens a remote
  racer's crash makes no hit sound or impact burst (proxies don't report
  impacts). Landings, skids, engine, boost and rider sounds do play.
- **Finish times of remote players** are measured on the host from
  interpolated positions (≈0.1–0.2 s late on a LAN); the host's own racer
  has no such delay.
- **Collisions between players** are resolved on each victim's computer, so
  a close bump can look slightly different on two screens.
- **No reconnect into a running race, no host migration**: if the host
  quits, the race ends for everyone; join again from the menu.
- **Items vs AI:** AI racers don't steer around banana peels or mud
  puddles. Item hits are rare in AI races because the field spreads out.
- **Rider model** is procedural (no skinned character); no item-throw or
  hit-flinch animation (unchanged by Visual Overhaul V2).
- Music: two CC0 loops since Visual Overhaul V2 (menu, race); no per-map
  tracks.
- **macOS Gatekeeper:** the app is not notarized (no paid Apple developer
  account), so friends must allow it once (README.txt explains how).
- **Windows SmartScreen:** the exe is not code-signed ("More info → Run
  anyway").
- The large milestone-2 drift dust can look big when it passes the camera
  in a sharp drift.
- **Test tooling:** the screenshot tool hangs when the `forest` mode is
  followed by `canyon` in one session (each mode works alone).
- The simple scripted test driver (not the game) sometimes needs a reset on
  Rocky Canyon; AI racers finish every map without resets.
