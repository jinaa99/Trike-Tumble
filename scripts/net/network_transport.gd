class_name NetworkTransport
extends RefCounted
## Interface between the lobby/race and the network. The next milestone adds
## an ENet implementation; until then OfflineTransport is used.
##
## Contract:
## - host(port, max_players) opens a session this machine owns; the local
##   player is peer 1. Returns OK or an error (port in use, ...).
## - join(address, port) starts connecting; the outcome arrives as
##   `connected` or `connection_failed(reason)`. Returns OK if the attempt
##   started, or an error right away.
## - close() leaves/closes the session.
## - peer_joined/peer_left report remote players (host side).

signal status_changed(status: Status, message: String)
signal connected
signal connection_failed(reason: String)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)

enum Status { IDLE, HOSTING, CONNECTING, CONNECTED, FAILED }

var status := Status.IDLE
var status_message := "Not connected"
var port := 0
var max_players := 5


func host(_port: int, _max_players: int) -> Error:
	return ERR_UNAVAILABLE


func join(_address: String, _port: int) -> Error:
	return ERR_UNAVAILABLE


func close() -> void:
	_set_status(Status.IDLE, "Not connected")


## Whether other computers can actually reach this session.
func is_online() -> bool:
	return false


func _set_status(new_status: Status, message: String) -> void:
	status = new_status
	status_message = message
	status_changed.emit(new_status, message)
