class_name MapCatalog
extends RefCounted
## The game's maps, in menu order (resources in res://resources/maps/).

const MAPS: Array[MapInfo] = [
	preload("res://resources/maps/forest_rush.tres"),
	preload("res://resources/maps/rocky_canyon.tres"),
	preload("res://resources/maps/snow_slide.tres"),
]
const DEFAULT_MAP := "forest_rush"


static func get_maps() -> Array[MapInfo]:
	return MAPS


static func get_map(id: String) -> MapInfo:
	for map in MAPS:
		if map.id == id:
			return map
	return null
