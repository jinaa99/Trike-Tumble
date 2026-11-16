# TRIKE TUMBLE — Fun-First Gameplay V2 ("Chaos on the Mountain")

Design for the gameplay overhaul started 2026-11-13. Written from the real
source (file references are to the tree at that date) and from three
read-only specialist reviews (party-game design, level design,
character/audio). Implementation status lives in
`docs/DEVELOPMENT_PROGRESS.md`; this file is the intent.

Baseline before any change: 740 automated checks passing; hard-AI race
times 5:12–5:25 on the three maps.

## 1. Vision

The game worked but played as "hold W, steer, grab an item, finish". The
target is a party racer where something worth reacting to happens every
15–30 seconds, where a player in last place is still laughing, and where
getting better at the game is visible.

Identity: **chaos + skill + pranks + personality**. Fun beats simulation,
but controls stay simple and every bad thing that happens to a player was
avoidable.

## 2. Pillars

| Pillar | What it means in the code |
|---|---|
| Skillful racing | Perfect drift release, slipstream, near misses, air tricks and graded landings: all in `Trike` / `SkillManager`, all optional, all rewarding a modest boost. |
| Chaotic environments | Timed, telegraphed hazards that are pure functions of the race clock and a shared seed: falling trees (Forest), rockslides and resting rubble (Canyon), ice and wind (Snow). |
| Mischief | One signature skill per character on **F**, next to the four items on **Q**. |
| Personality | Faces, reactions, barks, a taunt on **C**, per-character voices. |
| Fast recovery | Unchanged loop (fall, get up, run, mount), plus protection against being knocked off twice in a row by skills or items. |

## 3. Player interaction

What existed: trike-to-trike bumps (physical), four items, an impact rule
that throws riders off at 11 m/s of unexplained velocity change.

What is added:

- **Slipstream** for everyone (section 5) — the first reason to sit behind
  someone on purpose.
- **Signature skills** (section 4) — two attacks at close range, two traps
  dropped behind, one defence.
- **Near-miss rewards** for passing a rival closely at speed.
- **Reactions**: the attacker laughs, the victim yelps; both are visible
  and audible to everyone.
- **Awards** on the results screen from recorded events (section 10).

Fairness rules shared by items and skills:

- One hit immunity table (`ItemManager._immune`, 2.5 s) for both systems:
  no chain-stuns.
- A racer thrown off by an item or skill cannot be thrown off by another
  item or skill for 6 s after remounting (`SkillConfig.eject_guard`).
- Every trap has a visible tell and an arm time; every attack has a range
  and a cone the target can leave.
- No skill works off the trike, before GO or after the finish.

## 4. Signature skills

Separate from items. `SkillManager` (node `Skills` in the race scene)
mirrors `ItemManager`'s authority model: the owner of a racer sends a
request, the host validates and emits a numbered event, every computer
applies it once, and only the victim's owner applies physics. Values are
in `SkillConfig` (`resources/skills/default_skill_config.tres`). Details
and tuning notes: `docs/SKILL_DESIGN.md`.

| Rider | Skill | Needs | Effect | Counterplay | Cooldown |
|---|---|---|---|---|---|
| Zip | **Slingshot** | A riding rival 3–20 m ahead, roughly in line | 1.3 s boost and a wind streak. Nothing happens to the rival. | Don't give Zip a tow: change lane. | 12 s (no cooldown when refused) |
| Pip | **Spring Bonk** | — (can whiff) | Rival within 5 m and a 75° cone gets a sideways shove (4.5–7.5 m/s), a wobble and a short slide. Ejects only point-blank (< 1.8 m) and only if the target is not guarded. | Keep 5 m away or be behind Pip. | 14 s, 6 s on a whiff |
| Bramble | **Root Snare** | — | A patch of roots 3 m behind the trike for 14 s (one at a time). Crossing it: speed cut to 60 %, a sideways tug, 0.9 s of loose steering. Glows and twitches; arms after 0.8 s. | Steer around: it is 2.2 m wide on a 13 m road. | 15 s |
| Nutmeg | **Fake Box** | — | A box that looks like an item box for 25 s (one at a time). Hitting it: confetti, a hop, a wobble. Never touches the held item. | The tell: it is tinted orange-red, spins the wrong way and its "?" is upside down. | 16 s |
| Rusty | **Pillow Shield** | — | 6 s bubble. Blocks one item or skill hit; absorbs one crash up to 1.4× the eject threshold. Pops with a bounce. | Wait it out, or hit Rusty hard: big crashes still throw him. | 18 s |

Comeback tilt: cooldowns are ×0.75 for the last racer and ×1.15 for the
leader (blended in between), like the item roll.

Characters are assigned by grid order as before (`Racer.character`), with
one change: the local player can pick a rider in the lobby / Settings and
swaps slots with whoever had it (section 13).

AI use: `AISkillTactics` presses F under the same conditions a player
would see (rival in range, rival behind, incoming threat).

## 5. Drift mastery, slipstream, near misses

**Drift** (existing: charge 0.9 s → tier 1, 2.0 s → tier 2; boost 0.5 / 1.0 s).
Unchanged for beginners. New: releasing within 0.35 s of charge after a
tier is reached is a **PERFECT** release and adds 0.4 s of boost. Holding
past the window still pays the normal tier. The HUD drift bar shows the
two windows as bright bands; sparks turn white inside a window; the
release sound is pitched up; the camera kicks its FOV.

**Slipstream.** Tucked in 3–16 m behind a riding rival, within 1.7 m of
its line, above 12 m/s: a draft meter fills in 1.1 s. A full draft gives
+5 m/s² and +3 m/s top speed, shows wind streaks and a HUD meter, and
drains in 0.6 s when the tow is lost. It cannot stack: one meter, one
target, capped.

**Near miss.** Passing within 1.3 m (surface to surface) of a rival, a
boulder, a road tree or an active hazard at 14 m/s or more, without
touching it: "NEAR MISS!", a chime, 0.35 s of boost and a style point. Each
obstacle pays once per 25 s and there is a 2 s global re-arm, so circling a
boulder pays nothing.

## 6. Air tricks and landings

- **Shift** in the air starts a trick: a 360° spin (direction from A/D) or
  a backflip (with S held). One rotation takes 0.72 s and always completes
  if there is air left; holding Shift chains another.
- **W / S** in the air lean the nose down / up by 9°, to match the landing.
- Landings after 0.6 s or more of air are graded when the first wheel
  touches, from body tilt against the ground and slide angle (heading
  against direction of travel):

| Grade | Condition | Result |
|---|---|---|
| PERFECT | Clean (< 17° / 17°) with at least one landed trick, or a very clean (< 9° / 9°) big-air landing | 0.55 s boost (+0.25 s per extra trick), style, sparkle, cheer |
| GOOD | Clean | Nothing lost |
| POOR | In between | 10 % speed lost, a hop, 0.45 s of loose grip |
| BAD | > 38° tilt or > 42° slide | 28 % speed lost, a bigger hop, a spin, 0.9 s of loose grip. The rider only comes off if the normal impact or overturn rule says so. |

A trick cut short by the ground is simply a crooked landing: its grade
comes from the same two angles.

Jump sizes on the maps: small kickers (≈ 1 s of air, one trick), big
kickers (Snow Slide's 1.7–2.0 m ramps) and gap jumps (two tricks for the
brave). Every graded jump has a clear, straight landing zone.

## 7. Dynamic hazards

All timed hazards are pure functions of `Track.hazard_time` (advanced
from GO by `RacerManager` on every computer) plus `Track.hazard_seed`, a
per-race number the host picks and sends before the countdown. Seed 0
keeps the authored phases (tests, tools). No hazard owns a timer or an RNG.

- **Falling tree** (`FallingTree`, Forest): stands beside the road. Cycle:
  birds scatter and the crown shakes (1.2 s) → a crack and a red landing
  strip on the road while the trunk leans (1.0 s) → falls (0.7 s) → lies
  across 55–80 % of the road (5–7 s) → sinks away → regrows. The free side
  is always at least 3.2 m wide.
- **Rockslide** (Canyon): several `RollingRock`s with staggered phases and
  different landing lanes, dust and a crack from the cliff first, landing
  shadows as before. Some rocks **rest** on the road for a few seconds
  before rolling off.
- **Falling log** (Forest) and **rolling boulder** (Canyon): unchanged
  motion, now with a warning rumble and shake.
- **Wind** (Snow): unchanged, also blows across the frozen bridges.

AI sees hazards through the same obstacle list as before; wide hazards
publish several avoidance points.

## 8. Three map identities

Details per map, with distances: `docs/MAP_GAMEPLAY_V2.md`.

- **Forest Rush — Wild Forest Chaos.** S-bends cut into the two long fast
  stretches, a second hairpin pair late in the race, seven tree-falls,
  mud raised from 4 % to about 10 % of the route with a clean line beside
  most of it and two full-width bogs.
- **Rocky Canyon — Rockslide Chaos.** Tighter cliff corners, three
  rockslides, resting rubble, a second narrows, more rolling boulders.
- **Snow Slide — Frozen Mountain.** Ice that slides (section 9 of the map
  doc), raised from about 6 % to about 13 % of the drivable surface: a
  widened frozen lake, a full-width ice descent, an icy run-in to the
  first hairpin, ice on both sides of fast bends, windy frozen
  bridges.

Race length stays in the 5–10 minute window; changes slow the maps a
little, never shorten them.

## 9. Items

Unchanged in number and rules. Changes around them:

- The Pillow Shield can block any item hit (the item is still spent).
- Item and skill hits share one immunity.
- Item ejection (point-blank Spring Punch) respects the 6 s guard.

## 10. Comebacks and results

- Slipstream (the back of a pack is faster than the front).
- Position-scaled skill cooldowns.
- The existing position-weighted item roll.
- **Awards** on the results screen, at most one per racer, computed by the
  host from recorded events only (`RaceStats`): MOST WIPEOUTS, BIGGEST
  BONK, PRANK MASTER, MUD MAGNET, ICE SKATER, TRICKSTER, CLOSE CALL KING,
  DRIFT KING, SLIPSTREAMER, COMEBACK, SMOOTH OPERATOR. An award is only
  given when its number is above a floor; no award is invented.

## 11. Reactions and personality

`Rider.react(kind)` plays a short gesture (face + arms + head) on top of
the riding pose; feet stay on the pegs and hands return to the grips.
Kinds: laugh, yelp, cheer, taunt, smug, dizzy, focus, trick, skill.
Triggers: skill and item events (attacker laughs, victim yelps), perfect
landings and drifts, near misses, overtakes, the C key. Each rider has a
voice pitch and a preferred taunt. Barks have per-kind cooldowns and a
scene-wide cap so five riders never talk at once.

## 12. Audio identity

No engine. `TrikeAudio` becomes a wheel model: a hub whirr and a freewheel
tick that follow wheel speed, the surface roll loop as the main bed
(dirt, mud, wood, snow, ice recordings that already exist), the sleeve
slide while drifting, frame rattle, wind by speed and airtime. Silent at
standstill. Details: `docs/AUDIO_DESIGN_V2.md`.

## 13. Controls

| Key | Action |
|---|---|
| W / S | Accelerate (push) / brake; nose down / up in the air |
| A / D | Steer; spin direction in the air |
| Space | Drift |
| **F** | Signature skill (new, `use_skill`) |
| Q | Use item |
| **Shift** | Air trick (new, `trick`) |
| E | Get back on |
| R | Reset |
| **C** | Taunt (new, `emote`) |
| Esc | Pause |

All three new actions are rebindable in Settings and listed in the pause
menu. Gamepad: LB skill, left-stick click trick, D-pad up taunt.

## 14. Multiplayer

- `Net.PROTOCOL_VERSION` 2 → 3.
- New RPC pair `_c_skill_request` / `_h_skill_event` (reliable), same
  ownership check as items.
- `NetSnapshot` gains field 20, `fx`: surface under the trike, trick in
  progress, slipstream active — cosmetic state proxies need.
- Host decides: skill use, targets, trap hits, shield pops, style rewards
  (rate-limited), taunts, the hazard seed, awards.
- Owner decides (as before): its own physics, so drift release and landing
  grade are measured by the owner and reported; the host rate-limits them.
- Hazards need no messages beyond the seed.

## 15. Testing

New test group `fun` (skills, drift, tricks, landings, slipstream, near
misses, stats) and additions to `map` (tree-falls, mud share, ice share,
per-wheel ice behaviour) and `overhaul` (wheel audio). The network suite
gains skill and seed checks. What automated tests cannot judge (is it
fun, are the tells readable, do the sounds fit) is listed for the owner in
`docs/FUN_FIRST_PLAYTEST.md`.
