# TRIKE TUMBLE — Online Multiplayer (final demo milestone 05)

Godot `ENetMultiplayerPeer` over UDP. One host plus up to four joining
players (five racers in total, AI can fill free seats). No Steam, no relay
service.

## Architecture: owner-simulated trikes, host authority

Jolt physics isn't deterministic across computers, so nobody simulates
another player's trike:

| Who | Does what |
|---|---|
| **Each player** | Simulates only their own trike + rider with full physics and local input (no input lag). Sends a snapshot ~30×/s. |
| **Host** | Also simulates the AI racers. Owns the lobby, the race flow (countdown, GO, end, results), checkpoints, positions and the finish order. Validates every snapshot (sender owns that racer; data well-formed and plausible) and relays it. |
| **Everyone else** | Shows each remote racer as a **proxy**: same trike and rider scenes, but `Trike.network_proxy` (frozen kinematic body, no input, no forces) and `RiderController.network_proxy` (state and body transforms from the snapshots). |

**No competing simulations:** a racer's RigidBody physics runs on exactly one
computer, its owner's.

**Collisions:** local trikes collide with the kinematic proxies. When you
hit a remote trike you bounce off it and your own impact rule may throw
you off. A remote trike moving into you pushes you. Each side resolves only
its own trike ("victim-side"). Tested in-process: an impact of 16.3, and a
parked trike knocked 8 m.

**Clients never declare results.** The host runs `CheckpointProgress` and
`FinishTracker` on the proxies it sees and decides who finished, in which
order and with what time. Teleporting past checkpoints never finishes (the
network test does exactly that: the cheater ends up DNF).

## Code

| File | Role |
|---|---|
| `scripts/net/net.gd` (autoload `Net`) | ENet peer, connection timeout, hello/reject rules, lobby authority + sync, race start + load barrier, snapshot validation/relay, race state, status, disconnects |
| `scripts/net/enet_transport.gd` | `NetworkTransport` for the Host/Join screens (wraps `Net`) |
| `scripts/net/net_snapshot.gd` | Snapshot array format (20 fields), `validate()`, `blend()`, `extrapolate()` |
| `scripts/net/snapshot_buffer.gd` | Per-proxy jitter buffer: clock-offset estimate, 100 ms delay, interpolation, capped 0.2 s extrapolation |
| `scripts/net/net_race_sync.gd` | In the race scene: sends own snapshots, moves proxies, host status 10×/s |
| `scripts/core/game_session.gd` | Mode SOLO/HOST/CLIENT, `build_racer_list()`, race request, connection-lost handling |
| `Trike.set_network_proxy / get_network_state / apply_network_state` | Proxy mode and state for the trike |
| `RiderController.set_network_proxy / get_network_state / apply_network_state` | Proxy mode; state transitions reuse the real ones (model on/off the seat, poses) |
| `RacerManager.add_proxy_racer / authoritative / build_status / apply_remote_status / mark_disconnected` | Racer bookkeeping online |
| `RaceController.follower / apply_remote_state` | Clients follow the host's race states |
| `scripts/items/item_manager.gd` (`ItemManager`) | Item requests, host validation, numbered item events (see "Items") |

## Messages (RPCs on `/root/Net`)

Client → host (`_c_*`, `any_peer`):
- `hello(name, version)`, `set_ready(bool)`, `race_loaded()` (reliable)
- `item_request(racer_id, req_id, kind, data)` (reliable)
- `snapshot(racer_id, data)` (unreliable ordered, channel 1)

Host → clients (`_h_*`, `authority`):
- `welcome(lobby)`, `reject(reason)`, `lobby(lobby)`
- `start_race(racers, scene)`, `race_state(state, race_time, results, duration)`
- `player_left(id)`, `return_to_lobby()` (all reliable)
- `item_event(event)` (reliable, same channel as race state, so a Race Again
  reset never overtakes an item event)
- `snapshot(racer_id, data)` (relay, unreliable ordered, channel 1)
- `status(list)` (positions, checkpoints, finish, DNF, pending; unreliable ordered, channel 2, 10×/s)

**Snapshot** (`NetSnapshot`, ~30 Hz, 20 fields):
- owner time
- trike position, rotation, velocity
- steering, forward speed, drift direction/charge, boost
- suspension lengths, wheel contacts, has_rider
- rider state, state time, ragdoll position/rotation, on-foot position and facing
- teleport counter

**Host validation:**
- the sender must own the racer
- 20 fields with the right types
- finite values, position within 20 km, speed ≤ 80 m/s
- valid rider state and suspension data

Anything else is dropped and counted (`Net.rejected_snapshots`).

## Items (final demo milestone 07)

Host-authoritative, like results. `PROTOCOL_VERSION` is 2 (builds without
items are refused with "Version mismatch").

1. Each owner detects its own racer driving through a box, over a banana
   peel, or pressing Q, and sends `item_request` (the host calls its own
   `ItemManager.handle_request` directly).
2. `Net` drops requests for a racer the sender doesn't own
   (`Net.rejected_item_requests`). `ItemManager` validates the rest: request
   id newer than the last one from that racer (replays ignored), racer
   riding and racing, box active, hands empty, item really held, data
   well-formed, racer within 14 m (host view) of the box/peel.
3. The host decides everything with randomness or other players in it
   (item roll, peel spot, bomb flight and landing, punch target, knock
   velocity, ejection) and broadcasts a numbered `item_event`. Everyone,
   the host included, applies events in order; repeats and malformed events
   are ignored.
4. Only the victim's owner applies a hit to its trike (velocity change,
   slippery, ejection); everyone else sees it through the next snapshots.
   Mud bombs fly as plain ballistics on every computer; the host alone
   decides where they land.

Two racers reaching one box together: whichever request the host handles
first gets it; the other is refused and the box is already gone on its
screen. A client sees its own pickup and item use one round trip after the
fact (a few ms on a LAN).

## Smooth remote players

- **Jitter buffer:** proxies are shown 100 ms in the past, interpolated
  between the two snapshots around that time. Owner clocks are mapped to
  the local clock through the smallest observed offset (follows drift
  slowly).
- **Playback clock:** advances with physics ticks and is pulled gently
  toward the wall clock, so catch-up ticks after a slow frame still move
  proxies evenly. It resyncs only after a stall over 250 ms.
- **Teleports:** a teleport counter in every snapshot (respawn, reset,
  uprighting on mount). The receiver snaps instead of sliding across the
  map, and resets physics interpolation.
- **Dropouts:** extrapolation is capped at 0.2 s, then the proxy holds.
- **Rendering:** proxies are moved in `_physics_process`, so the engine's
  physics interpolation renders them smoothly at any frame rate.

## Two real computers / internet (milestone 10)

**Not tested.** Only one computer was available, so every test ran several
instances on 127.0.0.1 (no real network latency, loss or NAT). Setup for a
real test: both computers on the same network, the host's firewall allowing
the game (macOS asks on first host; Windows Firewall: allow on Private
networks), the client joins the host's LAN address shown in the lobby. Over
the internet: forward UDP 7777 (or the chosen port) to the host; carrier-
grade NAT can make this impossible. **Internet play: UNVERIFIED.**

Client sends (`_c_*`) check `Net.is_connected_to_host()`: right after the
host leaves, a client can still be "CLIENT" for a moment; sending then only
produced ENet errors ("Unable to send packet on channel 0") at shutdown.

## Connection handling

| Case | Behavior |
|---|---|
| Invalid IP / port | Rejected on the Join/Host screens before connecting (`NetAddress`) |
| Nobody answering | "Connection timed out…" after 6 s (`Net.CONNECT_TIMEOUT`) |
| ENet can't reach the host | "Couldn't reach the host…" |
| Lobby full | Host replies "The lobby is full." then disconnects the peer (ENet keeps one spare slot so this reply can arrive) |
| Version mismatch | "Version mismatch…" |
| Duplicate player id | A second hello from a peer already in the lobby is ignored (`Net.duplicate_hellos`); ENet ids are unique per connection |
| Joining during a race | "A race is in progress. Try again when it's over." |
| Client disconnects (lobby) | Removed from the lobby; everyone gets the new lobby |
| Client disconnects (race) | Their racer is DNF and removed from every screen; the race continues and still ends normally |
| Host shuts down | Clients get "Lost connection to the host.", return to the menu, and the title shows the reason |
| Restart after connection loss | Join again from the menu; tested: the host re-hosts the same port and the client rejoins |
| Reconnect into a running race | **Not supported**: rejoin after the race (lobby only) |

## Race flow online

1. Host presses Start Race. Everyone loads the race scene with the host's
   racer list (grid order = lobby order).
2. The host waits until every client reports `race_loaded` (max 15 s),
   then starts the countdown.
3. Clients' `RaceController` follows the host's states. They show 3-2-1
   locally and are released at the host's GO.
4. During the race the host sends positions, checkpoints and finishes 10×/s.
5. FINISHED and RESULTS arrive with the host's results list, so everyone
   shows identical results.
6. Results screen and pause menu:
   - Host: Race Again or Return to Lobby (everyone goes back).
   - Clients: Race Again is disabled ("Host decides…"), Leave Game is available.
   - The online pause menu doesn't freeze the game, and Restart is hidden.

## Actual tests (2026-11-08, MacBook Air M4, Godot 4.7.2)

`tests/net/net_test_runner.tscn` launches real game instances (headless, real
time, ENet on 127.0.0.1) and checks what each saw: **44/44 passed**, also in
strict mode. Since final-demo milestone 06 one scenario (`forest`) races
on Forest Rush (falling logs need no sync: their motion is a function of the
race clock).

| Order | Test | Result |
|---|---|---|
| 1 | **Two local instances** (automated `duo` + manual windowed run with screenshots) | Pass. Lobby, ids, map, countdown, race states, both see each other race (~1,000+ m), wipeout/run/remount seen by the host, 10 spoofed snapshots rejected, checkpoint-skipping cheat → DNF, identical results |
| 2 | **Two computers on the same LAN** | **NOT TESTED** (only one computer available). Needs a second machine; see the checklist in TESTING.md |
| 3 | **Three players** (automated `drop`, one quits mid-race) | Pass. Leaver removed everywhere and DNF; race finishes; identical results |
| 4 | **Five players** (automated `five`) | Pass. Everyone sees four others race; all finish; identical order and times on all five |
| — | **Forest Rush online** (`forest`, 2 instances, 60 s) | Pass. Both loaded Forest Rush, each saw the other race ~1.4 km, smooth proxies (max 0.64 m per tick), no honest snapshot rejected |
| — | **Items** (`items`, 2 instances, 40 s, 30 shared boxes) | Pass. 44 events, identical and in order on both; host 8 / client 6 pickups, 13 uses; no box taken twice; a forged request for the host's racer refused; a replayed request id ignored; no duplicate or malformed events on the client |
| — | **Five real players, one whole race** (`e2e5`, milestone 10: 5 independent instances, Snow Slide, ~6 min) | Run 1: 8/9 — one player (the one scripted to wipe out) got stuck and was DNF; the test driver then had no "press R when stuck on foot" (players and AI do). Run 2 after adding it: **9/9**: lobby + ready + host's map, 3-2-1-GO, everyone finished (5:21.9–5:27.2), identical results everywhere, 11 collisions, wipeout + recovery seen by the host, 40 item pickups/uses, Race Again. Run 3 (strict): see TESTING.md |
| — | **Host picks the map** (`maps`: Rocky Canyon with 2 instances, Snow Slide with 3) | Pass. Everyone loaded the host's map with the same item boxes (63 / 60) and sky, and raced down it |
| — | Connection rules (`rules`) | Pass. Full lobby, mid-race join refused, timeout, invalid IP, duplicate hello, host shutdown → menu with message, rejoin after re-host |

In-process unit tests in the main suite:
- lobby sync data
- snapshot validation, including the teleport snap
- jitter buffer smoothness
- proxy trike/rider state machine
- collisions with proxies
- real ENet hosting and port reuse
- online pause/results menus

## Limitations (honest)

- **Only localhost has been tested.** LAN between two computers and the
  internet are untested, and Windows ↔ Mac play is untested.
- **Playing over the internet:** the host must forward its UDP port (default
  7777) on the router to their computer, or everyone joins a virtual LAN tool
  (e.g. ZeroTier or Tailscale; third-party software, owner approval needed;
  no paid relay is used or planned). Carrier-grade NAT can make port
  forwarding impossible.
- **Proxy lag:** you see others ~100 ms + half the ping in the past.
  Collisions are resolved on each victim's side, so a close bump can look
  slightly different on the two screens.
- **Finish times** for other players are taken on the host from proxies, so
  they include that delay (about 0.1–0.2 s on a LAN). The host's own trike
  has none, a small advantage for the host in photo finishes.
- **Two instances on one Mac:** macOS may throttle the window that isn't
  focused. In the windowed test this gave a handful of hitches (a proxy
  moving up to 3 m in one tick). The headless automated runs had none.
- Effects (drift dust/sparks, boost flame, flag) come from synced state, so
  they look right but aren't frame-identical. The finish-timeout countdown
  ("ENDS nn") shows only on the host's HUD.
- No reconnect into a running race; no host migration (if the host leaves,
  the game ends for everyone).
- Online pause doesn't stop the race (by design).
