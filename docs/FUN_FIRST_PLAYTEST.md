# Fun-First playtest checklist

For the owner and friends. The automated tests check that things happen,
are fair by the numbers and stay in sync. They cannot tell whether it is
fun. That part is yours.

## Before you start

- **Rider**: the Rider button on your lobby row (or Settings › Player ›
  Rider). Each rider has a different skill on **F**.
- Settings › Player › **Show wheel surfaces and grip**: a small readout of
  what each wheel stands on. Turn it on for the ice test, off otherwise.
- New keys: **F** skill, **Shift** air trick, **C** taunt. All rebindable
  in Settings › Controls.

## Sessions

1. **Solo, Forest Rush, no items in mind** (5 AI, `forest_rush.tscn` or the
   menu). Just race.
2. **Each rider once** on any map, using the skill as often as you can.
3. **Snow Slide** with the surface readout on.
4. **Online, 2–5 people**, all three maps. Use everything.

## Questions (score 1–5, plus a sentence)

| # | Question | What to look for |
|---|---|---|
| 1 | Is the game fun **without** items? | Drifting, slipstream, jumps and hazards alone |
| 2 | Are collisions funny? | Bumps, bonks, falling off, getting back on |
| 3 | Are the character skills exciting? | Would you pick a rider for their skill? |
| 4 | Are attacks fair? | Did you ever feel hit with no chance to avoid it? |
| 5 | Are jumps skillful? | Do tricks feel earned; can you land them on purpose? |
| 6 | Does landing require control? | Do you notice PERFECT vs ROUGH and know why? |
| 7 | Is mud noticeable? | Do you choose the clean line on purpose? |
| 8 | Is ice noticeably slippery? | Does the frozen lake feel different from snow? |
| 9 | Are the falling trees surprising, but avoidable? | Did you see the warning in time? |
| 10 | Is each map different? | Could you tell them apart with your eyes closed (sound)? |
| 11 | Are the characters charming? | Laughs, taunts, reactions: cute or annoying? |
| 12 | Do the sounds match a drift trike? | Wheels and gravel, not a motorbike? |
| 13 | Is there enough player interaction? | How often did you affect someone else? |
| 14 | Did a five-player race create funny moments? | Write down the best one |

## Specific things to try

- **Perfect drift:** hold Space + steer, watch the drift bar; let go while
  a white band is lit ("RELEASE NOW!"). Longer boost than a normal release?
- **Slipstream:** sit 3–16 m behind someone at speed. The SLIPSTREAM bar
  fills; you should gain on them.
- **Near miss:** skim past a boulder or a rival at speed. "NEAR MISS!"
- **Tricks:** off a big kicker, tap Shift (spin, A/D for direction) or hold
  S + Shift (backflip). Land level. Try landing crooked too.
- **Zip:** F behind someone (works), F with nobody ahead (refused, no
  cooldown spent).
- **Pip:** F right beside someone. From 1 m it can throw them off; right
  after they get back on it can't.
- **Bramble / Nutmeg:** drop a snare or fake box in front of a chaser. Can
  you see it in time when it is dropped in front of *you*?
- **Rusty:** shield up, let someone punch you. Then crash hard into a
  wall: you should still fall off.
- **Ice:** on Snow Slide watch the readout: one wheel on ice already shows
  lower grip; all three ≈ 0.22. Brake on the frozen lake.
- **Taunt:** press C after overtaking. Is it funny or annoying after the
  tenth time?
- **Awards:** after a race, do the awards match what happened?

## Known rough edges to report on

See `docs/KNOWN_ISSUES.md` ("Fun-First V2"). In short: the riders' bodies
are still the code-sculpted rigs (no new models), and per-map music is one
track played at different speeds.
