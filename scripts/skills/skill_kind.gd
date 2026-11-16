class_name SkillKind
extends RefCounted
## The five signature skills, one per character. Plain ids so they travel
## over the network as ints. A racer's character is its index in
## CHARACTER_NAMES (Racer.character); its skill is for_character().

enum Kind { NONE, SLINGSHOT, BONK, SNARE, FAKE_BOX, SHIELD }

const CHARACTER_NAMES: Array[String] = ["Zip", "Pip", "Bramble", "Nutmeg", "Rusty"]
const CHARACTER_TAGLINES: Array[String] = [
	"Cheerful slipstream ace", "Hot-headed bruiser", "Quiet trapper", "Giggling prankster", "Sleepy old hand",
]
const BY_CHARACTER: Array[Kind] = [Kind.SLINGSHOT, Kind.BONK, Kind.SNARE, Kind.FAKE_BOX, Kind.SHIELD]
const NAMES: Array[String] = ["", "SLINGSHOT", "SPRING BONK", "ROOT SNARE", "FAKE BOX", "PILLOW SHIELD"]
## One-line help shown in the lobby and the HUD hint.
const HELP: Array[String] = [
	"", "Tuck in behind a rival, then fire past them.", "Spring-loaded shove at anyone right beside you.",
	"Drop grabbing roots behind you.", "Leave a fake item box behind you.", "A pillow bubble that eats one hit.",
]
## Short glyph for the HUD skill slot.
const GLYPHS: Array[String] = ["", ">>", "POW", "~~", "?!", "()"]
const COLORS: Array[Color] = [
	Color.WHITE, Color(0.35, 0.85, 1.0), Color(1.0, 0.35, 0.3), Color(0.45, 0.8, 0.35), Color(1.0, 0.62, 0.2),
	Color(0.95, 0.9, 0.98),
]


static func for_character(character: int) -> Kind:
	return BY_CHARACTER[posmod(character, BY_CHARACTER.size())]


static func character_name(character: int) -> String:
	return CHARACTER_NAMES[posmod(character, CHARACTER_NAMES.size())]


static func display_name(kind: int) -> String:
	return NAMES[kind] if kind >= 0 and kind < NAMES.size() else ""


static func color_of(kind: int) -> Color:
	return COLORS[kind] if kind >= 0 and kind < COLORS.size() else Color.WHITE


static func is_valid(kind: int) -> bool:
	return kind > Kind.NONE and kind < NAMES.size()
