class_name HostScreen
extends MenuScreen
## Host a game: port, player limit, this computer's LAN addresses and the
## connection status. Host Game opens the lobby through GameSession (the
## ENet transport plugs in behind it next milestone).

var port_edit: LineEdit
var limit_label: Label
var limit_minus: Button
var limit_plus: Button
var host_button: Button
var status_label: Label
var address_label: Label
var player_limit := Lobby.ABSOLUTE_MAX_PLAYERS


func build() -> void:
	var column := make_page("HOST GAME", "Open a lobby that friends on your network can join.")
	var form := UiKit.panel(30)
	form.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(form)
	var form_box := UiKit.vbox(18)
	form.add_child(form_box)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 28)
	grid.add_theme_constant_override(&"v_separation", 18)
	form_box.add_child(grid)

	grid.add_child(UiKit.label("Port", UiKit.SIZE_BODY, UiKit.TEXT))
	port_edit = UiKit.line_edit(str(NetAddress.DEFAULT_PORT), 200)
	port_edit.text = str(NetAddress.DEFAULT_PORT)
	port_edit.max_length = 5
	port_edit.text_changed.connect(func(_t: String) -> void: _validate())
	grid.add_child(port_edit)

	grid.add_child(UiKit.label("Player limit", UiKit.SIZE_BODY, UiKit.TEXT))
	var stepper := UiKit.hbox(10)
	limit_minus = UiKit.button("–", "normal", 56)
	limit_plus = UiKit.button("+", "normal", 56)
	limit_label = UiKit.title("", UiKit.SIZE_HEADING)
	limit_label.custom_minimum_size = Vector2(56, 0)
	limit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	limit_minus.pressed.connect(set_player_limit.bind(-1, true))
	limit_plus.pressed.connect(set_player_limit.bind(1, true))
	stepper.add_child(limit_minus)
	stepper.add_child(limit_label)
	stepper.add_child(limit_plus)
	grid.add_child(stepper)

	grid.add_child(UiKit.label("Your address", UiKit.SIZE_BODY, UiKit.TEXT))
	address_label = UiKit.label("", UiKit.SIZE_BODY, UiKit.SUN)
	grid.add_child(address_label)

	status_label = UiKit.label("", UiKit.SIZE_BODY, UiKit.TEXT_DIM)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(560, 0)
	form_box.add_child(status_label)

	var footer := UiKit.hbox(16)
	column.add_child(footer)
	make_back_button(footer)
	host_button = UiKit.button("Host Game", "primary", 260)
	host_button.pressed.connect(host)
	footer.add_child(host_button)
	set_player_limit(player_limit)


func on_enter() -> void:
	var addresses := NetAddress.local_addresses()
	address_label.text = ", ".join(addresses) if not addresses.is_empty() else "No local network found"
	status_label.text = "Status: not hosting."
	status_label.add_theme_color_override(&"font_color", UiKit.TEXT_DIM)
	_validate()


## Sets the limit (2–5) or, with `relative`, changes it by `value`.
func set_player_limit(value: int, relative := false) -> void:
	player_limit = clampi(player_limit + value if relative else value, 2, Lobby.ABSOLUTE_MAX_PLAYERS)
	limit_label.text = str(player_limit)
	limit_minus.disabled = player_limit <= 2
	limit_plus.disabled = player_limit >= Lobby.ABSOLUTE_MAX_PLAYERS


func host() -> void:
	var problem := _validate()
	if problem != "":
		return
	var error := GameSession.host_lobby(GameSettings.player_name, port_edit.text.to_int(), player_limit)
	if error != OK:
		_show_status(GameSession.transport.status_message, UiKit.BERRY)
		return
	_show_status("Status: " + GameSession.transport.status_message, UiKit.MINT)
	menu.show_screen(&"lobby")


func _validate() -> String:
	var problem := NetAddress.validate_port(port_edit.text)
	host_button.disabled = problem != ""
	if problem != "":
		_show_status(problem, UiKit.BERRY)
	elif status_label.text.begins_with("The port") or status_label.text.begins_with("Enter a port"):
		_show_status("Status: not hosting.", UiKit.TEXT_DIM)
	return problem


func _show_status(text: String, color: Color) -> void:
	status_label.text = text
	status_label.add_theme_color_override(&"font_color", color)


func get_default_focus() -> Control:
	return host_button if not host_button.disabled else port_edit
