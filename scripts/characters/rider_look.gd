class_name RiderLook
extends Resource
## One rider's look: colors, helmet style, accessory and face. Applied to a
## Rider model by RiderStyle; purely cosmetic (the rig and its IK are the
## same for everyone). Presets: res://resources/characters/looks/*.tres, one
## per racer slot (RacerManager.rider_looks).

enum HelmetStyle {
	BEAR_EARS,  ## round ears and a crest (the original rider)
	MOHAWK,  ## a row of spikes front to back
	HORNS,  ## two curved horns
	ANTENNA,  ## a springy antenna with a ball on top
	POMPOM,  ## knitted-hat look: stripes and a big pompom
}
enum Accessory { SCARF, BACKPACK, BANDANA, BELL, NONE }
enum Face { CHEERFUL, DETERMINED, GRINNING, SLEEPY, CHEEKY }

@export var look_name := "Rider"
@export var helmet_style := HelmetStyle.BEAR_EARS
@export var accessory := Accessory.SCARF
@export var face := Face.CHEERFUL
@export var goggles := true
## Head size (silhouette): 0.92 small .. 1.12 big.
@export_range(0.85, 1.2) var head_scale := 1.0

@export_group("Colors")
@export var helmet_color := Color(0.97, 0.28, 0.48)
@export var accent_color := Color(1, 0.82, 0.18)
@export var jacket_color := Color(0.25, 0.75, 0.85)
@export var jacket_dark_color := Color(0.15, 0.45, 0.65)
@export var pants_color := Color(0.25, 0.3, 0.55)
@export var glove_color := Color(0.98, 0.98, 0.96)
@export var boot_color := Color(0.85, 0.3, 0.25)
@export var skin_color := Color(1.0, 0.82, 0.68)
@export var lens_color := Color(0.4, 0.85, 1.0)
