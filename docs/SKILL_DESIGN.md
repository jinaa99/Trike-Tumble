# Signature skills

One skill per rider on **F** (`use_skill`), separate from the items on Q.
Code: `scripts/skills/`. Values: `resources/skills/default_skill_config.tres`
(`SkillConfig`). Tests: `tests/fun_tests.gd` (`-- --only=fun`), network
scenario `skills` in `tests/net/net_test_runner.gd`.

## Who has what

The rider decides the skill (`Racer.character`, `SkillKind.for_character`).
Pick a rider in the lobby (the Rider button on your row cycles; the host
can change the bots' riders) or in Settings › Player › Rider (remembered
as your preference for the next lobby). Every seat rides a different
rider: a bot riding the one you want swaps with you and is renamed; a rider
another human rides can't be taken. Online, clients ask the host
(`Net._c_set_character`), and the race setup carries each racer's rider.

| # | Rider | Personality | Skill | Cooldown |
|---|---|---|---|---|
| 0 | Zip | Cheerful slipstream ace | Slingshot | 12 s |
| 1 | Pip | Hot-headed bruiser | Spring Bonk | 14 s (6 s on a whiff) |
| 2 | Bramble | Quiet trapper | Root Snare | 15 s |
| 3 | Nutmeg | Giggling prankster | Fake Box | 16 s |
| 4 | Rusty | Sleepy old hand | Pillow Shield | 18 s |

Cooldowns scale with race position: ×1.15 for the leader, ×0.75 for last,
blended in between. No skill works in the first 4 s after GO, off the
trike, before GO or after the racer finished.

## The skills

### Zip — Slingshot
- Needs a riding rival 2.5–20 m ahead, within 3.5 m of Zip's heading line,
  roughly level (±4 m height).
- Gives 1.3 s of boost plus a full tow; nothing happens to the rival.
- No target: refused before anything is spent ("NO ONE TO SLINGSHOT"), and
  the host refuses it too. It can't be used as a free turbo.
- Zip's slipstream meter also fills 1.4× faster.
- Counterplay: don't give Zip a tow (change lanes).

### Pip — Spring Bonk
- Range 5 m, cone ±100° around Pip's heading (beside and ahead, never
  behind). The item Spring Punch reaches 9 m.
- Shove 4.5–7.5 m/s sideways (weaker than the punch's 5–10), a hop of
  1.6 m/s, a spin and 0.55 s of loose grip.
- Closer than 1.8 m it may throw the rider off — unless the target is
  guarded (see Fairness).
- A whiff costs 6 s instead of 14 s and shows the empty spring.
- Counterplay: keep 5 m away from Pip, or stay behind Pip.

### Bramble — Root Snare
- A ring of roots 3 m behind the trike, 2.5 m across, for 14 s. One per
  Bramble: a new one replaces the old.
- Arms after 0.8 s (it twitches fast while arming); Bramble can't trip on it
  for another second.
- Crossing it: speed ×0.6, a 3.5 m/s sideways tug, a small spin, 0.9 s of
  loose steering. Only at boost speeds (29 m/s+) does it throw the rider off.
- Tell: brown roots, green leaves and a glowing green disc.
- Counterplay: steer around it; it covers 2.5 m of a 13–14 m road.

### Nutmeg — Fake Box
- A box 3.5 m behind, the size and float of a real item box, for 25 s.
  One per Nutmeg.
- Hitting it: confetti, a party horn, a 3 m/s hop, a spin, speed ×0.8,
  0.7 s of loose grip. It **never** touches the held item.
- Tells: hot orange-red (no real box has that colour), spins the other way,
  bobs faster, and its "?" hangs upside down.
- The victim looks confused; Nutmeg laughs.

### Rusty — Pillow Shield
- A soft bubble for 6 s.
- Blocks the next item or skill hit (punch, bonk, banana, mud bomb, snare,
  fake box). The attacker's item is still used up.
- Soaks up one crash between 1× and 1.4× the eject threshold. A bigger
  crash or turning over still throws Rusty off: not invulnerable.
- Pops with confetti and a boing; Rusty looks smug.

## Fairness rules

- **Shared hit immunity.** Items and skills use one table
  (`ItemManager._immune`, 2.5 s). A victim can't be hit again straight
  away by either.
- **Eject guard.** A racer who was off the trike can't be thrown off by an
  item or skill for 6 s after getting back on (`SkillConfig.eject_guard`,
  enforced by the host for the Spring Punch item too). Crashes still count.
- **Range, cone and arm time** on everything; traps glow from the start.
- **No duplicates.** Requests carry an id; the host ignores repeats and a
  pending request is not re-sent.

## Network

Same shape as items (docs/NETWORKING.md):
owner sends `Request.USE` (or `TRAP_TOUCH`, `STYLE`, `EMOTE`, `ABSORB`) →
host validates → numbered `Event` (`SLINGSHOT`, `BONK`, `TRAP_PLACED`,
`TRAP_HIT`, `SHIELD_UP`, `SHIELD_POP`, `STYLE`, `EMOTE`, `SEED`, `AWARDS`)
→ applied once everywhere → only the victim's owner applies physics
(`Trike.apply_item_hit`, `set_slippery`).

## AI

`AISkillTactics.wants_use` reads only what a player could see: a slingshot
target on a calm stretch, a bonk target in reach, a rival close behind for
traps, a rival close behind or beside for the shield. The chance per half
second is `AIDriverConfig.skill_use_chance` (easy 0.25, medium 0.5, hard
0.8).

## Not verified yet

Whether the skills are fun, readable and balanced against each other in a
real five-player race needs people. See `docs/FUN_FIRST_PLAYTEST.md`.
