class_name JoinScreen
extends MenuScreen
## Join a game: host IP and port (validated), Connect, status and errors.

var address_edit: LineEdit
var port_edit: LineEdit
var connect_button: Button
var status_label: Label


func build() -> void:
	var column := make_page("JOIN GAME", "Enter the address shown on the host's screen.")
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
	grid.add_child(UiKit.label("Host IP address", UiKit.SIZE_BODY, UiKit.TEXT))
	address_edit = UiKit.line_edit("192.168.1.20", 320)
	address_edit.max_length = 64
	grid.add_child(address_edit)
	grid.add_child(UiKit.label("Port", UiKit.SIZE_BODY, UiKit.TEXT))
	port_edit = UiKit.line_edit(str(NetAddress.DEFAULT_PORT), 200)
	port_edit.text = str(NetAddress.DEFAULT_PORT)
	port_edit.max_length = 5
	grid.add_child(port_edit)
	address_edit.text_submitted.connect(func(_t: String) -> void: try_connect())
	port_edit.text_submitted.connect(func(_t: String) -> void: try_connect())

	status_label = UiKit.label("", UiKit.SIZE_BODY, UiKit.TEXT_DIM)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(560, 0)
	form_box.add_child(status_label)

	var footer := UiKit.hbox(16)
	column.add_child(footer)
	make_back_button(footer)
	connect_button = UiKit.button("Connect", "primary", 260)
	connect_button.pressed.connect(try_connect)
	footer.add_child(connect_button)
	GameSession.transport.connection_failed.connect(_on_failed)
	GameSession.transport.connected.connect(_on_connected)


func on_enter() -> void:
	connect_button.disabled = false
	_show_status("Status: not connected.", UiKit.TEXT_DIM)


## Validates both fields; on success asks GameSession to connect.
## Returns "" when the attempt was started, else the problem shown.
func try_connect() -> String:
	var problem := NetAddress.validate_address(address_edit.text)
	if problem == "":
		problem = NetAddress.validate_port(port_edit.text)
	if problem != "":
		_show_status(problem, UiKit.BERRY)
		return problem
	_show_status("Connecting to %s:%s…" % [address_edit.text.strip_edges(), port_edit.text.strip_edges()], UiKit.SKY)
	connect_button.disabled = true
	var error := GameSession.join_game(address_edit.text.strip_edges(), port_edit.text.strip_edges().to_int())
	if error == OK:
		return ""
	connect_button.disabled = false
	# The transport already reported why (connection_failed).
	return status_label.text


func _on_failed(reason: String) -> void:
	connect_button.disabled = false
	if is_inside_tree():
		_show_status("Couldn't connect: " + reason, UiKit.BERRY)


func _on_connected() -> void:
	connect_button.disabled = false
	if is_inside_tree() and GameSession.has_lobby():
		_show_status("Connected!", UiKit.MINT)
		menu.show_screen(&"lobby")


func _show_status(text: String, color: Color) -> void:
	status_label.text = text
	status_label.add_theme_color_override(&"font_color", color)


func get_default_focus() -> Control:
	return address_edit
