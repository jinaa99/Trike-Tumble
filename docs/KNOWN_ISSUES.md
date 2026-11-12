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
  hit-flinch animation.
- **No music** yet (sound effects only; all synthesized in code).
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
