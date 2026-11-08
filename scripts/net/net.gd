extends Node
## Autoload "Net": online play over ENet (UDP). One host + up to four clients.
##
## Authority model (see docs/NETWORKING.md):
## - The host owns the lobby, the race flow (countdown, GO, end, results),
##   checkpoints, positions and finish order. Clients never report results.
## - Every computer simulates only its own trike + rider (the host also
##   simulates the AI racers) and sends snapshots ~30×/s. The host checks
##   that the sender owns that racer and that the data is plausible, then
##   relays it. Everyone shows other racers as interpolated kinematic
##   proxies: no competing physics simulations of the same trike.
##
## Messages are RPCs on this node (same path, /root/Net, everywhere).
## Client→host methods start with _c_, host→client methods with _h_.

signal connected_to_lobby
signal connection_failed(reason: String)
signal connection_lost(reason: String)
signal race_requested(scene_path: String)
signal lobby_return_requested
signal peer_left(peer_id: int)

const PROTOCOL_VERSION := 1
const CONNECT_TIMEOUT := 6.0
## How long the host waits for every client to load the race scene.
const LOAD_TIMEOUT := 15.0
## ENet slots: 4 clients + 1 spare so a "lobby is full" reply can be delivered.
const MAX_CLIENTS := Lobby.ABSOLUTE_MAX_PLAYERS
const CHANNEL_SNAPSHOTS := 1
const CHANNEL_STATUS := 2

enum Role { NONE, HOST, CLIENT }

var role := Role.NONE
var port := 0
## Host: the authoritative lobby. Client: a mirror of the host's lobby.
var lobby: Lobby
## Racers of the current race: [{"id", "owner", "name", "ai", "difficulty"}] in grid order.
var race_setup: Array = []
var race_scene := ""
var race_in_progress := false
## The running race scene (RaceSession) and its NetRaceSync.
var race: Node
var sync: Node
var player_name := "Player"
## Host diagnostics: snapshots dropped for wrong owner / bad data.
var rejected_snapshots := 0
var relayed_snapshots := 0
var last_reason := ""
## Host diagnostics: repeated hellos from a peer already in the lobby.
var duplicate_hellos := 0

var _peer: ENetMultiplayerPeer
var _connect_elapsed := -1.0
var _load_elapsed := -1.0
var _loaded := {}
## Host: racer id -> owning peer id.
var _owners := {}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_online() -> bool:
	return role != Role.NONE


func is_host() -> bool:
	return role == Role.HOST


func my_id() -> int:
	return multiplayer.get_unique_id() if _peer else 1


# --- Hosting and joining ----------------------------------------------------

## Opens an ENet server. The lobby (with the host as player 1) is handed over
## with set_lobby().
func host(new_port: int) -> Error:
	close()
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_server(new_port, MAX_CLIENTS)
	if error != OK:
		_peer = null
		return error
	multiplayer.multiplayer_peer = _peer
	role = Role.HOST
	port = new_port
	return OK


func set_lobby(new_lobby: Lobby) -> void:
	lobby = new_lobby
	if is_host() and not lobby.changed.is_connected(_broadcast_lobby):
		lobby.changed.connect(_broadcast_lobby)


## Starts connecting; the result is connected_to_lobby or connection_failed.
func join(address: String, new_port: int, name_for_lobby: String) -> Error:
	close()
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_client(address, new_port)
	if error != OK:
		_peer = null
		return error
	multiplayer.multiplayer_peer = _peer
	role = Role.CLIENT
	port = new_port
	player_name = name_for_lobby
	_connect_elapsed = 0.0
	return OK


## Leaves/closes the session (clients disconnect, a host shuts the game down).
func close() -> void:
	if _peer:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	role = Role.NONE
	_connect_elapsed = -1.0
	_load_elapsed = -1.0
	_loaded.clear()
	_owners.clear()
	race_in_progress = false
	race_setup = []
	if lobby and lobby.changed.is_connected(_broadcast_lobby):
		lobby.changed.disconnect(_broadcast_lobby)
	lobby = null


func _process(delta: float) -> void:
	if _connect_elapsed >= 0.0:
		_connect_elapsed += delta
		if _connect_elapsed > CONNECT_TIMEOUT:
			_fail_join("Connection timed out. Check the IP address and port, and that the host is running.")
	if _load_elapsed >= 0.0:
		_load_elapsed += delta
		if _all_loaded() or _load_elapsed > LOAD_TIMEOUT:
			_load_elapsed = -1.0
			if race and race.has_method(&"net_all_loaded"):
				race.net_all_loaded()


func _fail_join(reason: String) -> void:
	last_reason = reason
	close()
	connection_failed.emit(reason)


func _on_connected_to_server() -> void:
	_c_hello.rpc_id(1, player_name, PROTOCOL_VERSION)


func _on_connection_failed() -> void:
	_fail_join("Couldn't reach the host. Check the IP address and port.")


func _on_server_disconnected() -> void:
	var was_connecting := _connect_elapsed >= 0.0
	close()
	if was_connecting:
		_fail_join(last_reason if last_reason != "" else "The host closed the connection.")
		return
	last_reason = "Lost connection to the host."
	connection_lost.emit(last_reason)


func _on_peer_connected(_peer_id: int) -> void:
	pass  # a player only counts once its hello is accepted


func _on_peer_disconnected(peer_id: int) -> void:
	if not is_host():
		return
	_loaded.erase(peer_id)
	if lobby and lobby.get_player(peer_id):
		lobby.remove_player(peer_id)
	if race_in_progress:
		_h_player_left.rpc(peer_id)
		if race and race.has_method(&"net_player_left"):
			race.net_player_left(peer_id)
	peer_left.emit(peer_id)


# --- Lobby ------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _c_hello(requested_name: String, version: int) -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	var problem := ""
	if version != PROTOCOL_VERSION:
		problem = "Version mismatch: the host runs a different build of the game."
	elif lobby == null:
		problem = "The host isn't running a lobby."
	elif lobby.get_player(sender) != null:
		duplicate_hellos += 1  # same peer id twice: keep the existing seat
		return
	elif race_in_progress:
		problem = "A race is in progress. Try again when it's over."
	elif lobby.is_full():
		problem = "The lobby is full."
	if problem != "":
		reject(sender, problem)
		return
	lobby.add_human(GameSettings.sanitize_name(requested_name), false, false, sender)
	_h_welcome.rpc_id(sender, lobby.to_dict())


## Host: tells a peer why it can't join, then disconnects it.
func reject(peer_id: int, reason: String) -> void:
	_h_reject.rpc_id(peer_id, reason)
	get_tree().create_timer(0.3).timeout.connect(func() -> void:
		if _peer and is_host():
			_peer.disconnect_peer(peer_id))


@rpc("authority", "call_remote", "reliable")
func _h_reject(reason: String) -> void:
	last_reason = reason


@rpc("authority", "call_remote", "reliable")
func _h_welcome(lobby_data: Dictionary) -> void:
	_connect_elapsed = -1.0
	lobby = Lobby.new()
	lobby.apply_dict(lobby_data, my_id())
	connected_to_lobby.emit()


func _broadcast_lobby() -> void:
	if is_host() and _peer:
		_h_lobby.rpc(lobby.to_dict())


@rpc("authority", "call_remote", "reliable")
func _h_lobby(lobby_data: Dictionary) -> void:
	if lobby:
		lobby.apply_dict(lobby_data, my_id())


## Client: asks the host to change this player's ready flag.
func request_set_ready(ready: bool) -> void:
	if role == Role.CLIENT:
		_c_set_ready.rpc_id(1, ready)


@rpc("any_peer", "call_remote", "reliable")
func _c_set_ready(ready: bool) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if is_host() and lobby and lobby.get_player(sender) and not race_in_progress:
		lobby.set_ready(sender, ready)


# --- Race -------------------------------------------------------------------

## Host: everyone loads `scene_path` with these racers.
func start_race(setup: Array, scene_path: String) -> void:
	race_setup = setup
	race_scene = scene_path
	race_in_progress = true
	_owners.clear()
	for entry: Dictionary in setup:
		_owners[int(entry["id"])] = int(entry["owner"])
	_loaded.clear()
	_h_start_race.rpc(setup, scene_path)


@rpc("authority", "call_remote", "reliable")
func _h_start_race(setup: Array, scene_path: String) -> void:
	race_setup = setup
	race_scene = scene_path
	race_in_progress = true
	race_requested.emit(scene_path)


## The race scene registers itself once its racers exist.
func attach_race(race_session: Node, race_sync: Node) -> void:
	race = race_session
	sync = race_sync
	if is_host():
		_load_elapsed = 0.0
	elif role == Role.CLIENT:
		_c_race_loaded.rpc_id(1)


func detach_race(race_session: Node) -> void:
	if race == race_session:
		race = null
		sync = null


@rpc("any_peer", "call_remote", "reliable")
func _c_race_loaded() -> void:
	if is_host():
		_loaded[multiplayer.get_remote_sender_id()] = true


func _all_loaded() -> bool:
	for owner_peer: int in _owners.values():
		if owner_peer != 1 and not _loaded.has(owner_peer) and multiplayer.get_peers().has(owner_peer):
			return false
	return true


func owner_of(racer_id: int) -> int:
	return _owners.get(racer_id, 1)


## Owner → others. Host sends its own racers straight to every client.
func send_snapshot(racer_id: int, data: Array) -> void:
	if is_host():
		_h_snapshot.rpc(racer_id, data)
	elif role == Role.CLIENT:
		_c_snapshot.rpc_id(1, racer_id, data)


@rpc("any_peer", "call_remote", "unreliable_ordered", CHANNEL_SNAPSHOTS)
func _c_snapshot(racer_id: int, data: Array) -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if owner_of(racer_id) != sender or NetSnapshot.validate(data) != "":
		rejected_snapshots += 1  # someone else's racer, or bogus data
		return
	if sync:
		sync.receive_snapshot(racer_id, data)
	for peer_id in multiplayer.get_peers():
		if peer_id != sender:
			_h_snapshot.rpc_id(peer_id, racer_id, data)
	relayed_snapshots += 1


@rpc("authority", "call_remote", "unreliable_ordered", CHANNEL_SNAPSHOTS)
func _h_snapshot(racer_id: int, data: Array) -> void:
	if sync and NetSnapshot.validate(data) == "":
		sync.receive_snapshot(racer_id, data)


## Host: race state change (+ results once known).
func send_race_state(state: int, race_time: float, results: Array, duration: float) -> void:
	if is_host():
		_h_race_state.rpc(state, race_time, results, duration)


@rpc("authority", "call_remote", "reliable")
func _h_race_state(state: int, race_time: float, results: Array, duration: float) -> void:
	if race and race.has_method(&"net_apply_race_state"):
		race.net_apply_race_state(state, race_time, results, duration)


## Host: positions, checkpoints, finish state of every racer (~10×/s).
func send_status(status: Array) -> void:
	if is_host():
		_h_status.rpc(status)


@rpc("authority", "call_remote", "unreliable_ordered", CHANNEL_STATUS)
func _h_status(status: Array) -> void:
	if race and race.has_method(&"net_apply_status"):
		race.net_apply_status(status)


@rpc("authority", "call_remote", "reliable")
func _h_player_left(peer_id: int) -> void:
	if race and race.has_method(&"net_player_left"):
		race.net_player_left(peer_id)
	peer_left.emit(peer_id)


## Host: everybody back to the lobby.
func return_all_to_lobby() -> void:
	if not is_host():
		return
	race_in_progress = false
	_h_return_to_lobby.rpc()


@rpc("authority", "call_remote", "reliable")
func _h_return_to_lobby() -> void:
	race_in_progress = false
	lobby_return_requested.emit()
