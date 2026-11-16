class_name RaceStats
extends RefCounted
## What actually happened to each racer during one race, and the funny
## awards made from it for the results screen.
##
## Counters come from SkillManager and ItemManager events (applied
## identically on every computer) and from host-side sampling (surface
## under each racer, positions). Awards are computed by the host only and
## sent with an AWARDS event, so everyone sees the same list. Nothing here
## is invented: an award is only given when its number passes a floor.

## [stat key, title, floor, format of the detail line].
const AWARDS: Array[Array] = [
	["pranks", "PRANK MASTER", 2.0, "%d pranks landed"],
	["biggest_bonk", "BIGGEST BONK", 5.0, "a %.1f m/s shove"],
	["wipeouts", "MOST WIPEOUTS", 2.0, "fell off %d times"],
	["tricks", "TRICKSTER", 2.0, "%d air tricks"],
	["near_misses", "CLOSE CALL KING", 2.0, "%d near misses"],
	["perfect_drifts", "DRIFT KING", 3.0, "%d perfect drifts"],
	["mud_time", "MUD MAGNET", 6.0, "%.0f s in the mud"],
	["ice_time", "ICE SKATER", 8.0, "%.0f s on the ice"],
	["draft_time", "SLIPSTREAMER", 8.0, "%.0f s in a tow"],
	["comeback", "COMEBACK", 2.0, "climbed %d places"],
	["blocks", "PILLOW FORT", 1.0, "%d hits blocked"],
	["perfect_landings", "SMOOTH OPERATOR", 2.0, "%d perfect landings"],
	["hits_taken", "PUNCHING BAG", 3.0, "hit %d times"],
]
const INT_STATS: Array[String] = ["pranks", "wipeouts", "tricks", "near_misses", "perfect_drifts", "comeback", "blocks",
		"perfect_landings", "hits_taken"]

## racer id -> {stat key: float}
var racers := {}
## [[racer id, title, detail], ...] once the race is over.
var awards: Array = []


func reset() -> void:
	racers.clear()
	awards.clear()


func add(racer_id: int, key: String, amount := 1.0) -> void:
	var row: Dictionary = racers.get_or_add(racer_id, {})
	row[key] = float(row.get(key, 0.0)) + amount


func raise(racer_id: int, key: String, value: float) -> void:
	var row: Dictionary = racers.get_or_add(racer_id, {})
	row[key] = maxf(float(row.get(key, 0.0)), value)


func get_stat(racer_id: int, key: String) -> float:
	return float((racers.get(racer_id, {}) as Dictionary).get(key, 0.0))


## Host: the awards for this race. Each award goes to the racer with the
## highest number that passes the floor and has no award yet (so up to five
## different racers get one); ties go to the better finisher (`order`).
func build_awards(order: Array[int]) -> Array:
	var result: Array = []
	var taken := {}
	for award: Array in AWARDS:
		var key: String = award[0]
		var best_id := -1
		var best := float(award[2])
		for racer_id: int in order:
			if taken.has(racer_id):
				continue
			var value := get_stat(racer_id, key)
			if value > best or (best_id < 0 and value >= best):
				best = value
				best_id = racer_id
		if best_id < 0:
			continue
		taken[best_id] = true
		var detail: String = (award[3] as String) % (int(best) if INT_STATS.has(key) else best)
		result.append([best_id, award[1], detail])
		if taken.size() >= order.size():
			break
	return result


## Well-formed awards list from the network?
static func valid_awards(list: Variant) -> bool:
	if not list is Array or (list as Array).size() > 8:
		return false
	for entry: Variant in list:
		if not entry is Array or (entry as Array).size() != 3 or not entry[0] is int or not entry[1] is String \
				or not entry[2] is String or (entry[1] as String).length() > 40 or (entry[2] as String).length() > 60:
			return false
	return true
