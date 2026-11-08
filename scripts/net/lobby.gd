class_name Lobby
extends RefCounted
## Lobby state: up to five seats (humans and AI), ready flags, the host and
## the selected map. Pure data + rules, so a host can sync it to clients
## once networking exists (`changed` fires on every edit).

signal changed

const ABSOLUTE_MAX_PLAYERS := 5
const AI_NAMES: Array[String] = ["Pip", "Bramble", "Nutmeg", "Rusty"]
const COLORS: Array[Color] = [
	Color(1.0, 0.4, 0.2), Color(0.2, 0.55, 1.0), Color(0.3, 0.78, 0.32),
	Color(0.68, 0.4, 0.95), Color(1.0, 0.42, 0.68),
]

var max_players := ABSOLUTE_MAX_PLAYERS:
	set(value):
		max_players = clampi(value, 1, ABSOLUTE_MAX_PLAYERS)
var map_id := ""
var players: Array[LobbyPlayer] = []
var _next_id := 1


## `id` = network peer id for online players (-1 = next free id).
func add_human(player_name: String, is_local: bool, is_host: bool, id := -1) -> LobbyPlayer:
	if is_full() or (id >= 0 and get_player(id) != null):
		return null
	var player := _new_player(_unique_name(player_name), id)
	player.is_local = is_local
	player.is_host = is_host
	players.append(player)
	changed.emit()
	return player


func add_ai(difficulty := AIDriverConfig.Difficulty.MEDIUM) -> LobbyPlayer:
	if is_full():
		return null
	var player := _new_player(_free_ai_name())
	player.is_ai = true
	player.is_ready = true
	player.ai_difficulty = difficulty
	players.append(player)
	changed.emit()
	return player


func remove_player(id: int) -> bool:
	for player in players:
		if player.id == id and not player.is_host:
			players.erase(player)
			_recolor()
			changed.emit()
			return true
	return false


## Removes the most recently added AI. False if there is none.
func remove_last_ai() -> bool:
	for i in range(players.size() - 1, -1, -1):
		if players[i].is_ai:
			return remove_player(players[i].id)
	return false


func set_ready(id: int, ready: bool) -> void:
	var player := get_player(id)
	if player and player.is_ready != ready:
		player.is_ready = ready
		changed.emit()


func cycle_ai_difficulty(id: int) -> void:
	var player := get_player(id)
	if player and player.is_ai:
		player.ai_difficulty = ((player.ai_difficulty + 1) % 3) as AIDriverConfig.Difficulty
		changed.emit()


func set_map(new_map_id: String) -> void:
	if map_id != new_map_id:
		map_id = new_map_id
		changed.emit()


func get_player(id: int) -> LobbyPlayer:
	for player in players:
		if player.id == id:
			return player
	return null


func get_local_player() -> LobbyPlayer:
	for player in players:
		if player.is_local:
			return player
	return null


func get_host() -> LobbyPlayer:
	for player in players:
		if player.is_host:
			return player
	return null


func count() -> int:
	return players.size()


func ai_count() -> int:
	var n := 0
	for player in players:
		n += 1 if player.is_ai else 0
	return n


func is_full() -> bool:
	return players.size() >= max_players


func all_ready() -> bool:
	for player in players:
		if not player.is_ready:
			return false
	return not players.is_empty()


## Why the race can't start yet ("" = it can).
func start_blocker() -> String:
	if players.is_empty():
		return "Nobody is in the lobby."
	var map := MapCatalog.get_map(map_id)
	if map == null or not map.is_playable():
		return "Pick a playable map."
	if not all_ready():
		return "Waiting for everyone to be ready."
	return ""


func _new_player(player_name: String, id := -1) -> LobbyPlayer:
	var player := LobbyPlayer.new()
	if id < 0:
		while get_player(_next_id) != null:
			_next_id += 1
		id = _next_id
		_next_id += 1
	player.id = id
	player.display_name = player_name
	player.color = COLORS[players.size() % COLORS.size()]
	return player


## Network form of the lobby (host → clients).
func to_dict() -> Dictionary:
	var list: Array[Dictionary] = []
	for player in players:
		list.append({"id": player.id, "name": player.display_name, "host": player.is_host, "ai": player.is_ai,
				"ready": player.is_ready, "difficulty": int(player.ai_difficulty)})
	return {"max": max_players, "map": map_id, "players": list}


## Replaces this lobby's contents with `data` (client mirror). `local_id`
## marks which player is this computer.
func apply_dict(data: Dictionary, local_id: int) -> void:
	max_players = int(data.get("max", ABSOLUTE_MAX_PLAYERS))
	map_id = str(data.get("map", ""))
	players.clear()
	for entry: Dictionary in data.get("players", []):
		var player := LobbyPlayer.new()
		player.id = int(entry["id"])
		player.display_name = str(entry["name"])
		player.is_host = bool(entry["host"])
		player.is_ai = bool(entry["ai"])
		player.is_ready = bool(entry["ready"])
		player.ai_difficulty = clampi(int(entry["difficulty"]), 0, 2) as AIDriverConfig.Difficulty
		player.is_local = player.id == local_id and not player.is_ai
		players.append(player)
	_recolor()
	changed.emit()


## Adds " 2", " 3"... to a name already used in the lobby.
func _unique_name(wanted: String) -> String:
	var candidate := wanted
	var n := 2
	while _name_taken(candidate):
		candidate = "%s %d" % [wanted, n]
		n += 1
	return candidate


func _name_taken(candidate: String) -> bool:
	for player in players:
		if player.display_name == candidate:
			return true
	return false


func _free_ai_name() -> String:
	for candidate in AI_NAMES:
		var taken := false
		for player in players:
			taken = taken or player.display_name == candidate
		if not taken:
			return candidate
	return "Bot %d" % _next_id


func _recolor() -> void:
	for i in players.size():
		players[i].color = COLORS[i % COLORS.size()]
