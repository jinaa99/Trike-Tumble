# TRIKE TUMBLE — Game Design

## Pitch

A colorful, low-poly cartoon party racer. Up to 5 friends ride small
three-wheeled drift trikes down winding mountain dirt roads. They bump into
each other, tumble off, scramble back on and throw silly items. Races last
5–10 minutes. Readable chaos beats simulation accuracy.

## Pillars

1. **Funny physics.** Collisions, knockbacks and wipeouts are part of the fun.
2. **Easy to drive, fun to master.** Predictable arcade handling. Drifting
   rewards skill with boosts.
3. **Always back in the race.** Fast recovery after falls. Nobody sits out.
4. **Premium indie look.** Bright, readable, polished low-poly with
   exaggerated animation and clear effects.

## Core loop

Ride downhill → dodge obstacles, take jumps → drift through corners for
boost → grab item boxes → throw items at rivals → crash / fall off →
recover → finish.

## Vehicle: the trike

- One big front wheel (steers), two small rear wheels (drive).
- Controls (keyboard / gamepad):

  | Action | Keyboard | Gamepad |
  |---|---|---|
  | Accelerate | W / ↑ | RT |
  | Brake / reverse | S / ↓ | LT |
  | Steer | A D / ← → | Left stick |
  | Drift / handbrake | Space | RB / B |
  | Reset (emergency recovery) | R | Y |
  | Interact (get back on the trike) | E | X |
  | Pause | Esc | Start |

  On foot after a wipeout, the same W/A/S/D (arrows) move the rider relative to the camera.
- **Drift:** hold Drift while steering above ~29 km/h. The trike hops,
  slides at a 25–45° angle and charges a boost. Steering into the drift
  tightens it and charges faster. Release to boost:
  - tier 1 (blue sparks) after ~0.9 s: short boost
  - tier 2 (orange sparks) after ~2.0 s: long boost
- **Handbrake:** Drift with no steering brakes and loosens grip.
- **Recovery:**
  - Overturning or a big crash **throws the rider off** (see Wipeouts). The
    trike stays where it is. Getting back on with E rights an overturned
    trike in place. An empty trike never rights itself or teleports.
  - Falling off the course puts the trike back on the road at its last safe
    point.
  - Stuck on top of something (wheels off the ground for 3 s while riding and
    giving throttle) respawns on the road.
  - **R** is the emergency button: trike and rider back on the road, rider
    seated.

## Wipeouts (milestone 3) — the signature mechanic

Hit something hard enough (roughly a head-on crash at 37+ km/h) or flip the
trike, and the rider is **thrown off**: they somersault through the air,
bounce, roll and flop to a stop (about 1–2 s). Then a quick, silly **get-up**
(about 1 s): push up, head shake with dizzy stars, a confused head scratch.

Now **on foot**, the player runs back (WASD, relative to the camera) to their
trike, which has rolled to a stop wherever it ended up. Within reach an
**[E] GET ON** prompt appears. E plays a hop onto the seat, hands grab the bars,
and the race continues. A typical wipeout costs about 4–7 seconds. The race
clock keeps running.

- Scrapes, glancing barrier hits, crates, cones and ramp landings never eject.
- No ejection for 1.5 s after getting back on (no chain wipeouts).
- Thrown over a barrier? The rider climbs back onto the road within 8 m of the trike.
- The trike never comes to you, and you're never put back on automatically.
  **R** is the emergency button (trike and rider back on the road).
- **Finishing needs the rider aboard.** If your empty trike rolls over the
  finish line after a wipeout, the finish is *pending*. It counts the moment
  you're back on that trike past the line. Your finish time and position are
  taken at that moment. Every player finishes once, and only their own trike
  can finish for them.

## Visual identity (milestone 2)

- **Palette:** saturated but soft. Coral-orange trike body, sunny yellow
  accents, deep navy frame, mint/teal jacket, magenta helmet, warm dirt road,
  fresh greens, lavender-blue distant mountains, white clouds.
- **Shapes:** rounded toy-like parts (capsules, spheres, rounded boxes) mixed
  with faceted low-poly scenery (flat-shaded trees, rocks, terrain).
- **Readability first:** red/white curbs and cream plank barriers with a red
  rail mark the road edge. Chevron signs on the outside of sharp corners.
  Scenery stays outside the barriers.
- **Signature silhouettes:** the trike's tall yellow whip flag and big white
  drift sleeves; the rider's oversized head, round helmet ears and crest.
- **UI:** chunky rounded type, slanted "racing" numerals, dark-indigo panels
  with yellow accents, arc speedometer.
- Inspiration is only the broad playful energy of cartoon party games. All
  designs are original procedural geometry.

## Characters

Original cute riders: round heads, big helmets with ear bumps, goggles,
scarves. Milestone 2 has one procedural rider: big expressive eyes and
brows, blush, smile, magenta helmet with crest/visor/goggles, jacket with
zipper and badge, scarf that flutters with speed, gloves, chunky boots. Final
characters will be original low-poly models. No copyrighted designs.

## Racers and AI opponents (final demo milestone 02)

A race has 1–5 racers. Offline it's you plus up to 4 AI riders (Pip,
Bramble, Nutmeg, Rusty), each with its own trike color and number. The AI
play by the player's rules:

- same trike and handling values, driven through the same controls: no
  speed bonus, no rubber-banding, no teleporting along the track
- they wait on the grid until GO
- they follow the road, slow down for sharp corners, dodge rocks, crate
  stacks and slower racers, line up with ramps and jump them
- when they wipe out they tumble, get up, run back to their own trike and
  hop on, exactly like you; the R-style recovery is only a last resort
- once finished they pull over past the line and stop

Difficulties (`resources/ai/ai_easy|medium|hard.tres`):

- **Easy:** ~74 % of top speed, cautious corners, wobbly steering, late
  reactions, ignores cones, never drifts. Finishes the test track in ~62 s.
- **Medium:** ~90 % of top speed, cuts corners a little, drifts sometimes.
  ~52 s.
- **Hard:** full speed, quick and accurate steering, cuts corners, early
  avoidance, drifts often for boosts. ~49–50 s, about as fast as a clean
  full-throttle run.

`race_five.tscn` uses one hard, two medium and one easy.

## Menus (final demo milestone 04)

- **Title:**
  - big bouncing TRIKE TUMBLE logo over a live race of four AI riders
  - PLAY, HOST GAME, JOIN GAME, SETTINGS, QUIT
- **PLAY:** choose a map → solo lobby (you + 3 AI). Add/remove AI (up to 5
  racers), click an AI's difficulty to change it, Change Map, Start Race.
- **HOST GAME:** port (default 7777), player limit 2–5, your LAN address,
  status → hosted lobby that friends join over the network (AI can fill
  free seats).
- **JOIN GAME:** IP + port with validation, Connect, clear errors (timeout,
  full, race in progress…), then the host's lobby.
- **Online races:** everyone drives their own trike with no input lag. You
  see the others' trikes, riders, wipeouts and remounts. Bumping works. The
  host decides positions and finish order. Details: `docs/NETWORKING.md`.
- **Lobby:** players with color, name, HOST badge, READY/NOT READY, AI
  difficulty; "3 / 5 players"; selected map card with preview; Ready; Start
  Race (enabled when everyone's ready); Leave Lobby.
- **Maps:** Forest Rush (READY: the full 7.4 km map), Rocky
  Canyon and Snow Slide (coming soon). Previews are labelled placeholders
  until the maps exist.
- **Settings** (saved): master/music/SFX volume, resolution, fullscreen,
  graphics quality, key rebinding, player name.
- **In race:**
  - race-state chip and item slot on the HUD
  - pause menu: Resume, Restart, Settings, Return to Lobby, Quit Game
  - results: Race Again, Return to Lobby

## Race structure (final demo milestone 03)

1. **Lobby:** everyone on the starting grid. The first race starts by itself
   after a second; after "Return to Lobby" a lobby panel lists the racers and
   waits for **Start Race**.
2. **Countdown:** big 3 · 2 · 1 · GO!. Nobody can move until GO (throttle
   does nothing); the clock starts at GO.
3. **Racing:** 12 ordered checkpoints on the test track (every 100 m) plus
   the finish line. Skip one and the finish line won't count; reversing
   never gains ground. The HUD shows your position ("2nd / 5") and
   checkpoints ("CP 3/12"), ranked by real progress along the track.
4. **Finishing:** when the first racer finishes, everyone else keeps racing
   for up to 45 s (shown as "ENDS 12" on the HUD), then the race ends and
   anyone still out there is DNF. The finish rules are unchanged: you must
   be riding, and an empty trike over the line finishes when you get back on.
5. **Results:** places 1st–5th with names and times (or DNF), race duration,
   **Race Again** (same racers, straight into a new countdown, props reset)
   and **Return to Lobby**.

## Tracks (3 planned)

Downhill mountain roads with turns, jumps, obstacles and hazards, one long
run from a mountain start to a finish far below (no laps). Forest Rush is
finished (final demo milestone 06); Rocky Canyon and Snow Slide are still
"coming soon". The ~1.2 km test track stays in the project for the fast
automated tests and the menu background; it is not in the map list.

### Forest Rush (final demo milestone 06)

A colorful cartoon mountain forest. **7,454 m long, 630 m drop, 30
checkpoints**, about 5½ to 7 minutes per racer (measured, see TESTING.md).
Built from data in `scenes/tracks/forest_rush.tscn` (route segments, road
width keys, zones, props).

| # | Section | Where (m) | What happens |
|---|---|---|---|
| 1 | Mountain start | 0–360 | 18 m wide start plaza with banners and hay bales, a cabin, a viewing deck (overlook) on the left, gentle bends while the field spreads out |
| 2 | Fast forest descent | 360–1,510 | 10–12 % grade, long sweeping bends (radius 200–370 m) through dense, tall pines; small jump ramps, crate stacks, rocks |
| 3 | Tight winding forest turns | 1,510–2,430 | Eight hairpins and S-bends (radius 21–29 m), 13 m road, a narrow 9.5 m passage between rock pillars, a pine growing in the middle of the road |
| 4 | Wooden bridges | 2,430–3,000 | Two plank bridges (85 m and 60 m, 9.5–10 m wide) on timber trestles over mountain streams, a viewing deck between them |
| 5 | Mud and obstacles | 3,000–4,240 | Six mud stretches (full width or one side), big boulders on the road (one pair leaves a narrow gap in the middle), two more road pines, two falling-log hazards, crates |
| 6 | Large jump | 4,240–5,240 | Fast run-up under a "BIG AIR!" arch with warning boards, a full-width kicker and a 12 m ravine gap with a creek below, then a second ramp |
| 7 | Final fast downhill | 5,240–7,220 | 11–14 % grade, fast bends, small ramps, a third viewing deck over the valley |
| 8 | Finish area | 7,220–7,454 | Road widens to 18 m, spectator stands on both sides, bunting, checkered finish arch (finish line 30 m before the end) |

**Surfaces.** Road and bridge planks handle normally. **Mud** caps speed at
half (13 m/s), drags the trike down to it and cuts grip to 55 %. **Grass**
(the slopes beyond the barriers, only reachable by flying over them) caps
speed at 65 % with 80 % grip. Values: `TrikeConfig` "Surfaces" group.

**Hazards.**
- **Falling logs:** a log drops off the bank, rolls across the road (about
  2 s) and tumbles away down the other side, every 6.5–7 s. A hit shoves you
  aside and can throw you off. Its timing comes from the race clock, so every
  player sees the same log at the same moment.
- **The ravine jump:** at full speed you clear it easily (take-off ~24 m/s,
  landing hit 2.2 of the 11 that ejects). Roll in too slowly and you drop
  into the ravine and are put back 45 m before the lip, so you get a proper
  run-up.

**Fairness.**
- No shortcuts: parts of the route more than 250 m apart (along the road)
  are at least 147 m apart on the map, and the checkpoints and
  out-of-bounds checks make leaving the road useless.
- Respawns only happen on "safe" road: never in the jump run-up, the gap or
  its landing, and never within 10 m of a ramp, boulder, road tree or log
  hazard.
- Five grid slots on the wide start plaza, and 14 item box rows (3 boxes
  each) ready for the items milestone.

## Planned features (not in the first milestone)

- Item boxes and throwable items with knockback.
- Dedicated racer-vs-racer bump tuning and knockback (racers already collide
  physically, and hard hits eject through the normal impact rule).
- Rocky Canyon and Snow Slide, character/trike customization, audio.

## Current tuning targets (milestone 1)

| Value | Target |
|---|---|
| Top speed on flat ground (throttle) | ~83 km/h (max 94 km/h cap before drag) |
| Downhill cruising speed | ~85–90 km/h |
| 0 → 43 km/h | ~1 s |
| Full stop from 78 km/h | < 1 s |
| Turn at speed | ~70° per second |
| Drift angle | 25–45° |
| Test track run (autopilot) | ~49 s |
