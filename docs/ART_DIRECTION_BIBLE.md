# TRIKE TUMBLE — Art Direction Bible (Visual Overhaul V2)

Written 2026-11-12, before the overhaul started. This is the reference every
visual, UI and audio change is checked against. The "before" baseline is
`docs/screenshots/milestone_10/`.

## 1. Overall direction

**Premium stylized 3D cartoon downhill racing.** A polished indie party
racer: chunky, friendly shapes, real material response (you can tell rubber
from paint from wood from snow), warm directional light, deep but coloured
shadows, and a world with a foreground, a midground and a background.

Not photorealistic. Not a flat-colour primitive demo either. The rule:

> Low-poly **structure**, smooth **forms** where a hand would touch them,
> **PBR materials** with real texture detail, and **controlled colour**.

What was wrong in the baseline (and is the checklist for "done"):

| Baseline problem | Target |
|---|---|
| Flat vertex colour everywhere, one noise texture | Tiled CC0 PBR texture sets (albedo + normal + roughness), world-space mapped, tinted by vertex colour |
| Cone trees, sphere bushes, one boulder shape | Several silhouettes per kind, bent and layered, with bark and foliage tones |
| Pyramid mountains floating on a flat plate | Layered ridgelines with eroded faces, haze between layers |
| Snow Slide blown out to white | Snow albedo capped at ~0.86, blue shadows, lower exposure, visible grain and sparkle |
| Riders and trikes read as glued primitives | Smooth bevelled forms, distinct materials per part, faces with iris/pupil/highlight |
| Flat lighting | Warm key, cool fill, ambient occlusion, soft shadows, mild grade |
| Prototype UI, huge HUD | Display + body typeface, small glanceable HUD, map cards with identity |
| Beepy synth audio, no music | Recorded CC0 engine/surface/impact layers, two music loops |

## 2. Shape language

- **Rounded-chunky.** Primary shapes are capsules, bevelled boxes and tori.
  No knife edges on anything a character touches. Bevel radius is about 15 %
  of the smallest dimension.
- **Big–medium–small.** Every asset has one dominant mass, two or three
  medium forms and a handful of small details (bolts, stitches, caps).
- **Tapers and leans.** Trunks taper, rocks lean, posts are slightly off
  vertical. Nothing natural is perfectly straight or symmetrical.
- **Hard = angular, soft = round.** Rock and ice keep faceted planes
  (flat-shaded). Foliage, snow, characters and vehicle bodywork are smooth.
- Silhouette first: an asset must be identifiable as a black shape.

## 3. Character proportions

- About **2.6 heads tall**. Head (with helmet) is the largest mass.
- Compact bean torso, short thick limbs, oversized gloves and boots
  (hands ≈ 60 % of head height wide — they must read at race distance).
- Face: large oval eyes set low, coloured iris, dark pupil, two highlights,
  separate brows, small nose, simple mouth shapes (smile, open, wobbly),
  cheek blush. Expressions: neutral, cheer, shocked, dizzy.
- Five racers, five silhouettes (helmet + accessory + kit + eye colour
  differ, not only paint). These are the looks in
  `resources/characters/looks/` (kept from the earlier milestone, extended
  in V2 with eye colours and kit pieces):

| Racer | Identity colours | Helmet | Accessory / kit | Eyes | Personality |
|---|---|---|---|---|---|
| **Pip** | royal blue + red, orange accent | spiky mohawk fin, orange goggles | backpack, knee pads, no stripes | brown | hot-headed show-off |
| **Rusty** | cream + navy, red accent | knitted-hat helmet with pompom and stripes | scarf, plain boots | green | laid-back veteran |
| **Bramble** | leaf green + violet, pink accent | two horns, no goggles, smaller head | bandana, elbow pads, thigh stripes | hazel | calm outdoors type |
| **Nutmeg** | yellow + orange, magenta accent | antenna with a ball, big head | bell collar, knee pads | violet | cosy and mischievous |
| **Zip** | hot pink + cyan, yellow accent | bear ears and crest, cyan goggles | scarf, full pads and stripes | teal | cheerful rookie |

## 4. Vehicle proportions

- Drift trike: one large front wheel (spoked, knobby tyre), two small fat
  rear wheels (slick plastic sleeves), low seat between the rear wheels.
- The trike is about as long as the rider is tall; wheels are oversized
  (toy proportions). The frame is a clear triangle from head tube to axle.
- Visual wheel positions are **locked** to the physics wheel mounts.
- Read order: body colour (tank, fenders, deck) → accent colour (stripes,
  flag, hub caps) → dark frame → bright metal details.

## 5. Environment style

- Three depth layers in every view: **foreground** (verge detail: grass,
  stones, flowers, stumps), **midground** (tree lines, rock formations,
  structures), **background** (ridgelines, peaks, sky).
- Vegetation comes in clusters with gaps, not a uniform sprinkle.
- Each map section has a **landmark** (waterfall, arch, cabin, mesa, frozen
  fall, lake) so players know where they are.
- The road is always the lightest, most saturated-warm (or cleanest) band
  in the frame; scenery values stay darker or cooler next to it.
- Collision never changes for looks: the render pass may add detail on top
  of the collision surface only.

## 6. Material rules

| Material | Roughness | Metallic | Notes |
|---|---|---|---|
| Painted body panels | 0.25–0.35 | 0.0–0.1 | clearcoat on; believable highlight |
| Powder-coated frame | 0.5–0.6 | 0.3 | dark, slightly satin |
| Chrome / polished metal | 0.12–0.2 | 1.0 | bars, hub caps, bolts |
| Brushed metal | 0.35–0.45 | 0.9 | axle, fork lowers |
| Tyre rubber | 0.85–0.95 | 0.0 | near-black (never pure black), tread geometry |
| Plastic trim | 0.4–0.5 | 0.0 | rear wheel sleeves, plates |
| Seat vinyl | 0.6–0.7 | 0.0 | stitched trim |
| Skin | 0.55 | 0.0 | warm rim |
| Fabric | 0.8–0.9 | 0.0 | |
| Helmet shell | 0.2–0.3 | 0.0 | clearcoat |
| Dirt / rock / bark / planks | from texture | 0.0 | CC0 PBR sets, world-space mapped |
| Packed snow | 0.75–0.9 | 0.0 | albedo ≤ 0.86 |
| Ice | 0.08–0.2 | 0.0 | high specular, cyan-teal |
| Water | 0.05–0.15 | 0.0 | animated normal, fresnel edge |

Rules: no two adjacent parts share the same material. No pure white, no
pure black. Texture sizes: terrain and hero 1K, props 512, details 256.
Terrain textures are tinted by vertex colour so one texture set serves
several maps.

## 7. Colour palettes

Values are sRGB hex. "Key" colours cover large areas; accents stay under
~10 % of the frame.

### Forest Rush — golden afternoon in a mountain forest
| Role | Colours |
|---|---|
| Foliage (pine) | `#1F5A3F` `#2C7350` `#17493D` |
| Foliage (broadleaf) | `#4F9A3A` `#7DB548` `#3C7F36` |
| Grass / moss | `#6FB04A` `#4E9440` `#35703A` · moss `#5C7D2E` |
| Dirt | `#B9824F` `#8E5F38` · wet `#5E4127` |
| Wood | `#8A5C36` `#6B4528` · planks `#D9C39A` |
| Rock | `#7C7F84` `#63666D` |
| Shadow tint | `#2B4A45` (deep green) |
| Sun | `#FFE2A8` (golden) |
| Accents | curb red `#E23A3A`, flowers `#FFD84A` `#FF8FB3` `#B79CFF`, autumn tree `#F29B38` |

### Rocky Canyon — late-afternoon desert
| Role | Colours |
|---|---|
| Sandstone light | `#E0A070` `#D48A5A` |
| Terracotta / burnt orange | `#C2603A` `#A8482C` |
| Deep red rock | `#7E2F24` `#5E231F` |
| Dust road | `#D9A878` `#B98458` |
| Vegetation | sage `#8A9A5B`, dry grass `#C9B06A`, cactus `#4E7D4B` |
| Water | turquoise `#2FB8B0` `#1C8E96` |
| Shadow tint | `#5A3550` (cool plum) |
| Sun | `#FFD9A0` |
| Accents | curb yellow `#F2C230`, sign teal `#2AA6A0` |

### Snow Slide — clear cold morning
| Role | Colours |
|---|---|
| Snow lit | `#DCE8F2` `#C9DAEA` (never above 0.86 value) |
| Snow shadow | `#7FA3D1` `#5E82B8` |
| Ice | `#7FD6E6` `#4FB6D0` · deep `#2C7FA6` |
| Pine | teal `#1F6B66` `#2A8078` |
| Exposed rock | `#4A5463` `#39414F` |
| Wood | warm `#A66A3C` `#7E4C2A` |
| Sun | `#FFF1D6` · sky `#3F7FD0` → `#BFD9F2` |
| Accents | curb red `#E23A3A` + blue `#2E62D9`, flags orange `#FF8A2A` |

### Shared UI palette
Ink navy `#1B1F3B`, panel `#252A52`, cream `#FFF7E6`, sunshine `#FFC83D`,
orange `#FF8A2A`, mint `#5EE0A0`, sky `#49C6F2`, pink `#FF6FA5`.

## 8. Lighting direction

- One warm key sun, 35–45° above the horizon, coming across the road so
  shapes get a lit and a shaded side. Soft-edged shadows.
- Shadows are never grey: ambient and fill are tinted with the map's shadow
  colour (green, plum, blue).
- Ambient occlusion and contact darkening under trikes, in wheel wells and
  where scenery meets the ground.
- Filmic tone mapping; exposure set so the brightest diffuse surface (snow,
  cream planks) lands below clipping. Bloom only on emissive/specular
  highlights (boost flame, ice glints), threshold > 1.
- Mild grade: saturation ≤ 1.12, slight contrast. No vignette blur, no
  depth of field or motion blur while racing.

## 9. Weather and atmosphere

| Map | Atmosphere |
|---|---|
| Forest Rush | light golden haze, distance fog tinted warm-green, drifting pollen/leaf motes, soft clouds |
| Rocky Canyon | dry heat haze toward the horizon (warm peach), dust motes, long shadows, thin high clouds |
| Snow Slide | cold blue distance fog, falling snow, wind-blown snow streaks in wind zones, low sun glints on ice |

Fog always reveals the ridgeline layers (aerial perspective), never hides
the next 250 m of road.

## 10. Camera style

- Third-person chase, slightly above the rider, looking **ahead of** the
  trike so the next corner is visible.
- Speed reads through FOV (+ up to ~10°), a little pull-back and wind
  streak particles, not through blur.
- Small, short responses: landing dip, impact shake (capped), drift
  look-into-the-turn, boost kick. All configurable, none larger than what
  keeps the road readable.
- After an ejection the camera eases to the rider; on remount it eases back.

## 11. UI design language

- **Typefaces (SIL OFL):** *Lilita One* for titles, numbers and buttons
  (chunky, friendly), *Nunito* (bold/extra-bold) for body text and labels.
- Hierarchy: title → section header → label → hint; max three sizes per
  screen.
- Rounded panels (16–24 px radius), ink-navy glass at ~80 % opacity with a
  thin lighter top edge; cream cards for selectable things; one accent
  colour per screen.
- Buttons: pill-shaped, drop "lip" shadow, scale-up on hover, squash on
  press, visible focus ring (sky blue).
- HUD: small, at the corners, no panel bigger than it needs to be. Speed
  bottom-right, position and time top-left, item bottom-left, prompts
  centre-bottom. Total HUD coverage under ~8 % of the screen.
- Every map has a colour identity (forest green, canyon orange, snow blue)
  used on its card, lobby banner and results header.

## 12. Audio identity

- **Engine:** a small, slightly raspy single-cylinder motor (go-kart /
  minibike): recorded loops crossfaded by RPM, with load (throttle) changing
  loudness and brightness. It should sound eager, not angry.
- **Surfaces:** gravel roll on dirt, wet slop in mud, hollow rumble on
  planks, crunch on snow, airy hiss on ice. Wind builds with speed.
- **Impacts:** wood/plastic knocks and thuds, not explosions.
- **Characters:** short, funny, non-verbal; soft body thuds; cloth and boot
  footsteps.
- **Items:** each has its own timbre (pop, squelch, spring boing, whoosh,
  slip).
- **Music:** two instrumental loops (CC0): a playful, adventurous menu
  theme and an upbeat, driving race track. Music sits ~8–10 dB under the
  engine and effects and ducks slightly on results.
- UI sounds stay light and short (the existing synthesized clicks are kept).
- Mix: nothing clips; the Master bus has a limiter.
