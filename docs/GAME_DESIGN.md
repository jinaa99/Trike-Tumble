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
- Controls: accelerate, brake/reverse, steer, drift/handbrake, reset, pause.
- **Drift:** hold Drift while steering above ~29 km/h. The trike hops,
  slides at a 25–45° angle and charges a boost. Steering into the drift
  tightens it and charges faster. Release to boost:
  - tier 1 (blue sparks) after ~0.9 s: short boost
  - tier 2 (orange sparks) after ~2.0 s: long boost
- **Handbrake:** Drift with no steering brakes and loosens grip.
- **Recovery:** R resets onto the road. Automatic recovery after 1.5 s upside
  down, 3 s stuck, or falling off the course.

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

## Tracks (3 planned)

Downhill mountain roads with turns, jumps, obstacles (crates, cones, rocks),
shortcuts and hazards. One prototype test track exists (~1.2 km, ~114 m drop).
Final maps will be longer or multi-lap to reach 5–10 minutes.

## Planned features (not in the first milestone)

- Players falling off the trike (ragdoll-ish tumble) and climbing back on.
- Item boxes and throwable items with knockback.
- Racer-vs-racer bumping and knockback.
- Online/LAN multiplayer for up to 5 players.
- 3 finished maps, character/trike customization, audio, menus.

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
