extends Node
## Autoload "GameSession": what the player is doing across scenes.
##
## Holds the current lobby (solo or hosted), the network transport, and the
## race request that the race scene reads when it loads. Survives scene
## changes, so Return to Lobby comes back to the same lobby.

signal lobby_changed
## Online: the host started a race; load this scene.
signal race_scene_requested(scene_path: String)
## Online: the connection ended unexpectedly (reason for the player).
signal disconnected(reason: String)
## Online: the host sent everyone back to the lobby.
signal lobby_return_requested

enum Mode { NONE, SOLO, HOST, CLIENT }

const MENU_SCENE := "res://scenes/menu/main_menu.tscn"

var mode := Mode.NONE
var lobby: Lobby
var transport: NetworkTransport
## Why the last online session ended (shown on the title screen once).
var last_error := ""
## True while a race scene started from the lobby is running (restart and
## Return to Lobby keep the same lobby).
var race_active := false
## Set when leaving a race for the lobby: the menu opens on the lobby screen.
var open_lobby_on_menu := false


func _ready() -> void:
	# Our handlers first: the transport's `connected` must see the lobby set.
	Net.connected_to_lobby.connect(_on_joined)
	Net.race_requested.connect(_on_race_requested)
	Net.connection_lost.connect(_on_connection_lost)
	Net.lobby_return_requested.connect(func() -> void:
		end_race_for_lobby()
		lobby_return_requested.emit())
	transport = ENetTransport.new()


func is_online() -> bool:
	return mode == Mode.HOST or mode == Mode.CLIENT


func is_host() -> bool:
	return mode != Mode.CLIENT


## This computer's player id in the lobby.
func local_player_id() -> int:
	return Net.my_id() if is_online() else 1


## Ready toggle for the local player (clients ask the host).
func set_local_ready(ready: bool) -> void:
	if lobby == null:
		return
	if mode == Mode.CLIENT:
		Net.request_set_ready(ready)
	else:
		var me := lobby.get_local_player()
		if me:
			lobby.set_ready(me.id, ready)


## Solo race: you plus AI, nothing networked.
func create_solo_lobby(player_name: String) -> Lobby:
	_new_lobby(Mode.SOLO, Lobby.ABSOLUTE_MAX_PLAYERS, player_name)
	lobby.get_local_player().is_ready = true
	for i in 3:
		lobby.add_ai()
	return lobby


## Hosting: opens the transport, then a lobby with you as host.
func host_lobby(player_name: String, port: int, max_players: int) -> Error:
	leave_lobby()
	var error := transport.host(port, max_players)
	if error != OK:
		return error
	_new_lobby(Mode.HOST, max_players, player_name)
	Net.set_lobby(lobby)
	return OK


## Joining: validated by the caller; the transport reports the outcome.
func join_game(address: String, port: int) -> Error:
	leave_lobby()
	return transport.join(address, port)


func leave_lobby() -> void:
	if transport.status != NetworkTransport.Status.IDLE or Net.is_online():
		transport.close()
	lobby = null
	mode = Mode.NONE
	race_active = false
	open_lobby_on_menu = false
	lobby_changed.emit()


func has_lobby() -> bool:
	return lobby != null


## Everything the race scene needs: {"player_name", "map_id",
## "ai": [{"name", "difficulty"}], "online", "racers"} (lobby order).
## "racers" (grid order): [{"id", "owner", "name", "ai", "difficulty"}];
## online the host sends this list to everyone.
func get_race_setup() -> Dictionary:
	var ai: Array[Dictionary] = []
	var player_name := GameSettings.player_name
	for player in lobby.players:
		if player.is_ai:
			ai.append({"name": player.display_name, "difficulty": player.ai_difficulty})
		elif player.is_local:
			player_name = player.display_name
	var racers: Array = Net.race_setup if mode == Mode.CLIENT else build_racer_list()
	return {"player_name": player_name, "map_id": lobby.map_id, "ai": ai, "online": is_online(), "racers": racers}


## Grid order: lobby order. Humans own their racer (peer id), the host owns AI.
func build_racer_list() -> Array:
	var list: Array = []
	for player in lobby.players:
		list.append({"id": player.id, "owner": 1 if player.is_ai else player.id, "name": player.display_name,
				"ai": player.is_ai, "difficulty": int(player.ai_difficulty)})
	return list


## Marks the race as started from this lobby and returns the scene to load
## ("" if the lobby can't start).
func begin_race() -> String:
	if lobby == null or lobby.start_blocker() != "" or mode == Mode.CLIENT:
		return ""
	race_active = true
	var scene := MapCatalog.get_map(lobby.map_id).race_scene
	if mode == Mode.HOST:
		Net.start_race(build_racer_list(), scene)
	return scene


## Leaving a race for the lobby screen.
func end_race_for_lobby() -> void:
	race_active = false
	open_lobby_on_menu = lobby != null
	if lobby and mode == Mode.HOST:
		for player in lobby.players:
			if not player.is_ai:
				player.is_ready = false
	lobby_changed.emit()


func _on_joined() -> void:
	mode = Mode.CLIENT
	lobby = Net.lobby
	lobby.changed.connect(func() -> void: lobby_changed.emit())
	lobby_changed.emit()


func _on_race_requested(scene_path: String) -> void:
	race_active = true
	race_scene_requested.emit(scene_path)


func _on_connection_lost(reason: String) -> void:
	last_error = reason
	lobby = null
	mode = Mode.NONE
	race_active = false
	open_lobby_on_menu = false
	lobby_changed.emit()
	disconnected.emit(reason)


func _new_lobby(new_mode: Mode, max_players: int, player_name: String) -> void:
	mode = new_mode
	lobby = Lobby.new()
	lobby.max_players = max_players
	lobby.map_id = MapCatalog.DEFAULT_MAP
	lobby.add_human(player_name, true, true)
	lobby.changed.connect(func() -> void: lobby_changed.emit())
	lobby_changed.emit()
