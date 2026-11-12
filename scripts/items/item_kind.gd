class_name ItemKind
extends RefCounted
## The items a racer can hold. Plain ids so they travel over the network as ints.

enum Kind { NONE, MUD_BOMB, SPRING_PUNCH, TURBO_BOTTLE, BANANA_PEEL }

## Every real item, in roll-table order (ItemConfig weights use this order).
const ALL: Array[Kind] = [Kind.MUD_BOMB, Kind.SPRING_PUNCH, Kind.TURBO_BOTTLE, Kind.BANANA_PEEL]
const NAMES: Array[String] = ["", "MUD BOMB", "SPRING PUNCH", "TURBO BOTTLE", "BANANA PEEL"]
const COLORS: Array[Color] = [
	Color.WHITE, Color(0.62, 0.42, 0.24), Color(1.0, 0.32, 0.3), Color(0.3, 0.85, 1.0), Color(1.0, 0.86, 0.2),
]


static func display_name(kind: int) -> String:
	return NAMES[kind] if kind >= 0 and kind < NAMES.size() else ""


static func color_of(kind: int) -> Color:
	return COLORS[kind] if kind >= 0 and kind < COLORS.size() else Color.WHITE


static func is_valid(kind: int) -> bool:
	return kind > Kind.NONE and kind < NAMES.size()
