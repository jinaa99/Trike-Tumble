class_name LobbyMenuScreen
extends MenuScreen
## The lobby before a race: players (name, host badge, ready, AI difficulty),
## player count, selected map with preview, and actions: Add/Remove AI,
## Ready, Change Map, Start Race, Leave Lobby. Reads and edits
## GameSession.lobby, which is what networking will sync.

var header_label: Label
var count_label: Label
var player_list: VBoxContainer
var map_slot: Control
var add_ai_button: Button
var remove_ai_button: Button
var ready_button: Button
var change_map_button: Button
var start_button: Button
var leave_button: Button
var blocker_label: Label
var map_card: MapCard


func build() -> void:
	var column := make_page("LOBBY")
	header_label = column.get_child(0) as Label
	var info := UiKit.hbox(14)
	count_label = UiKit.label("", UiKit.SIZE_BODY, UiKit.TEXT, 8)
	count_label.add_theme_color_override(&"font_outline_color", UiKit.INK)
	info.add_child(count_label)
	column.add_child(info)

	var body := UiKit.hbox(28)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	var players_panel := UiKit.panel(22)
	players_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(players_panel)
	var players_box := UiKit.vbox(10)
	players_panel.add_child(players_box)
	players_box.add_child(UiKit.label("PLAYERS", UiKit.SIZE_SMALL, UiKit.SUN))
	player_list = UiKit.vbox(8)
	players_box.add_child(player_list)
	var ai_row := UiKit.hbox(10)
	add_ai_button = UiKit.button("+ Add AI", "normal", 170)
	remove_ai_button = UiKit.button("– Remove AI", "normal", 190)
	add_ai_button.pressed.connect(add_ai)
	remove_ai_button.pressed.connect(remove_ai)
	ai_row.add_child(add_ai_button)
	ai_row.add_child(remove_ai_button)
	players_box.add_child(ai_row)

	var map_box := UiKit.vbox(10)
	body.add_child(map_box)
	map_slot = UiKit.vbox(0)
	map_box.add_child(map_slot)
	change_map_button = UiKit.button("Change Map", "normal", 340)
	change_map_button.pressed.connect(change_map)
	map_box.add_child(change_map_button)

	blocker_label = UiKit.label("", UiKit.SIZE_SMALL + 2, UiKit.TEXT, 6)
	blocker_label.add_theme_color_override(&"font_outline_color", UiKit.INK)
	column.add_child(blocker_label)
	var footer := UiKit.hbox(16)
	column.add_child(footer)
	leave_button = make_back_button(footer, "Leave Lobby")
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(fill)
	ready_button = UiKit.button("Ready", "normal", 220)
	ready_button.toggle_mode = true
	ready_button.toggled.connect(set_ready)
	footer.add_child(ready_button)
	start_button = UiKit.button("Start Race", "primary", 260)
	start_button.pressed.connect(start_race)
	footer.add_child(start_button)
	GameSession.lobby_changed.connect(refresh)


func on_enter() -> void:
	refresh()


func refresh() -> void:
	var lobby := GameSession.lobby
	if lobby == null or not is_inside_tree():
		return
	var hosted := GameSession.mode == GameSession.Mode.HOST
	var client := GameSession.mode == GameSession.Mode.CLIENT
	header_label.text = "HOSTED LOBBY" if hosted else ("ONLINE LOBBY" if client else "SOLO RACE")
	var port_text := ""
	if hosted:
		var addresses := NetAddress.local_addresses()
		port_text = "  ·  join at %s:%d" % [addresses[0] if not addresses.is_empty() else "this computer", GameSession.transport.port]
	count_label.text = "%d / %d players%s" % [lobby.count(), lobby.max_players, port_text]
	for child in player_list.get_children():
		player_list.remove_child(child)
		child.queue_free()
	for player in lobby.players:
		player_list.add_child(_player_row(player))
	var me := lobby.get_local_player()
	var is_host := me != null and me.is_host
	add_ai_button.disabled = not is_host or lobby.is_full()
	remove_ai_button.disabled = not is_host or lobby.ai_count() == 0
	change_map_button.disabled = not is_host
	ready_button.set_pressed_no_signal(me != null and me.is_ready)
	ready_button.text = "Ready ✓" if ready_button.button_pressed else "Ready"
	var blocker := lobby.start_blocker()
	start_button.disabled = not is_host or blocker != ""
	if not is_host:
		blocker_label.text = "Waiting for the host to start the race." if blocker == "" else blocker
	else:
		blocker_label.text = blocker if blocker != "" else "Everyone's ready. Start when you like!"
	_show_map(lobby.map_id)


func _player_row(player: LobbyPlayer) -> Control:
	var row := UiKit.hbox(12)
	var swatch := ColorRect.new()
	swatch.color = player.color
	swatch.custom_minimum_size = Vector2(18, 18)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(swatch)
	var player_name := UiKit.label(player.display_name + ("  (you)" if player.is_local else ""), UiKit.SIZE_BODY + 2, UiKit.TEXT)
	player_name.custom_minimum_size = Vector2(190, 0)
	row.add_child(player_name)
	if player.is_host:
		row.add_child(UiKit.chip("HOST", UiKit.SUN))
	if player.is_ai:
		var difficulty := Button.new()
		difficulty.text = "AI · " + ["Easy", "Medium", "Hard"][player.ai_difficulty]
		difficulty.tooltip_text = "Click to change difficulty"
		difficulty.add_theme_font_size_override(&"font_size", UiKit.SIZE_SMALL)
		difficulty.custom_minimum_size = Vector2(130, 34)
		var me := GameSession.lobby.get_local_player()
		difficulty.disabled = me == null or not me.is_host
		difficulty.pressed.connect(func() -> void: GameSession.lobby.cycle_ai_difficulty(player.id))
		difficulty.name = "Difficulty%d" % player.id
		row.add_child(difficulty)
	row.add_child(UiKit.chip("READY" if player.is_ready else "NOT READY", UiKit.MINT if player.is_ready else UiKit.BERRY))
	return row


func _show_map(map_id: String) -> void:
	if map_card and map_card.map and map_card.map.id == map_id:
		return
	if map_card:
		map_slot.remove_child(map_card)
		map_card.queue_free()
	var map := MapCatalog.get_map(map_id)
	if map == null:
		map_card = null
		return
	map_card = MapCard.new()
	map_card.setup(map, true)
	map_card.selected = true
	map_card.focus_mode = Control.FOCUS_NONE
	map_slot.add_child(map_card)


func add_ai() -> void:
	GameSession.lobby.add_ai()


func remove_ai() -> void:
	GameSession.lobby.remove_last_ai()


func set_ready(ready: bool) -> void:
	GameSession.set_local_ready(ready)


func change_map() -> void:
	menu.open_map_select(GameSession.lobby.map_id, func(map_id: String) -> void:
		GameSession.lobby.set_map(map_id)
		menu.show_screen(&"lobby", false))


func start_race() -> void:
	menu.start_race()


func get_default_focus() -> Control:
	return start_button if not start_button.disabled else ready_button
