class_name TrackSurface
extends RefCounted
## Ground surface kinds. A track collision body carries its kind as the
## `surface` metadata; `Trike` reads it from its wheel raycast hits and
## applies that surface's handling (TrikeConfig, "Surfaces" group).
## Anything without the metadata is ROAD (props, ramps, test arenas).

## SNOW: packed snow road (Snow Slide, slightly less grip). ICE: ice patches
## and frozen bridges (low grip, no slowdown).
enum Kind { ROAD, GRASS, MUD, WOOD, SNOW, ICE }

const META := &"surface"


static func of(collider: Object) -> Kind:
	if collider == null or not collider.has_meta(META):
		return Kind.ROAD
	return collider.get_meta(META) as Kind


static func tag(body: Object, kind: Kind) -> void:
	body.set_meta(META, kind)


static func name_of(kind: Kind) -> String:
	return ["road", "grass", "mud", "wood", "snow", "ice"][kind]
