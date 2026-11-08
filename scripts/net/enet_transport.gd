class_name ENetTransport
extends NetworkTransport
## NetworkTransport over the Net autoload (ENet/UDP). Hosting opens a real
## server; joining connects, says hello and waits for the host's lobby.

var _net: Node


func _init() -> void:
	_net = (Engine.get_main_loop() as SceneTree).root.get_node(^"Net")
	_net.connected_to_lobby.connect(_on_joined)
	_net.connection_failed.connect(_on_failed)
	_net.connection_lost.connect(func(reason: String) -> void: _set_status(Status.FAILED, reason))


func host(new_port: int, new_max_players: int) -> Error:
	var error: Error = _net.host(new_port)
	if error != OK:
		_set_status(Status.FAILED, "Couldn't open port %d: %s (is another game using it?)" % [new_port, error_string(error)])
		return error
	port = new_port
	max_players = new_max_players
	_set_status(Status.HOSTING, "Hosting on port %d. Friends join with your address and this port." % port)
	return OK


func join(address: String, new_port: int) -> Error:
	var error: Error = _net.join(address, new_port, GameSettings.player_name)
	if error != OK:
		var reason := "Couldn't start connecting: %s" % error_string(error)
		_set_status(Status.FAILED, reason)
		connection_failed.emit(reason)
		return error
	port = new_port
	_set_status(Status.CONNECTING, "Connecting to %s:%d…" % [address, new_port])
	return OK


func close() -> void:
	_net.close()
	super()


func is_online() -> bool:
	return true


func _on_joined() -> void:
	_set_status(Status.CONNECTED, "Connected.")
	connected.emit()


func _on_failed(reason: String) -> void:
	if status == Status.CONNECTING:
		_set_status(Status.FAILED, reason)
		connection_failed.emit(reason)
