extends RefCounted
## Menu, lobby, settings, pause and HUD tests (final-demo milestone 04).
## Run as part of tests/test_runner.gd; uses its helpers.

const MENU_SCENE := preload("res://scenes/menu/main_menu.tscn")
const MAIN_SCENE := preload("res://scenes/main/main.tscn")
const SETTINGS_SCRIPT := preload("res://scripts/core/game_settings.gd")
const TEST_SETTINGS := "user://test_settings.cfg"

var runner: Node
var _quits := 0
var _scene_requests: Array[String] = []


func _init(test_runner: Node) -> void:
	runner = test_runner


func run() -> void:
	await _test_title_buttons_and_navigation()
	await _test_map_select()
	await _test_quick_race()
	await _test_host_screen()
	await _test_join_validation()
	await _test_lobby_actions()
	await _test_start_race_and_return_to_lobby()
	await _test_settings_controls_and_persistence()
	await _test_key_rebinding()
	await _test_pause_menu()
	await _test_hud()
	await _test_layout_fits()
	GameSession.leave_lobby()
	GameSettings.use_test_profile(TEST_SETTINGS)


# --- Helpers ----------------------------------------------------------------

func _check(condition: bool, test_name: String, detail := "") -> void:
	runner._check(condition, test_name, detail)


func _tree() -> SceneTree:
	return runner.get_tree()


func _frames(count := 2) -> void:
	for i in count:
		await _tree().process_frame


func _clear_arena() -> void:
	if runner._arena:
		runner._arena.queue_free()
		runner._arena = null
	await _tree().process_frame


func _load_menu() -> MainMenu:
	await _clear_arena()
	var menu: MainMenu = MENU_SCENE.instantiate()
	menu.quit_handler = func() -> void: _quits += 1
	menu.scene_changer = func(path: String) -> void: _scene_requests.append(path)
	runner.add_child(menu)
	await _frames(3)
	return menu


func _free(node: Node) -> void:
	node.queue_free()
	await _tree().process_frame


func _press_ui_cancel() -> void:
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(2)
	event = InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = false
	Input.parse_input_event(event)
	await _frames(1)


# --- Main menu --------------------------------------------------------------

func _test_title_buttons_and_navigation() -> void:
	print("\n[Menu: title buttons and navigation]")
	GameSession.leave_lobby()
	var menu := await _load_menu()
	var title: TitleScreen = menu.get_screen(&"title")
	_check(menu.current_name == &"title" and title.visible, "the game opens on the title screen")
	var labels: Array[String] = []
	for key: String in ["play", "host", "join", "settings", "quit"]:
		labels.append((title.buttons[key] as Button).text)
	_check(labels == ["PLAY", "HOST GAME", "JOIN GAME", "SETTINGS", "QUIT"], "PLAY, HOST GAME, JOIN GAME, SETTINGS, QUIT",
			"(%s)" % ", ".join(labels))
	for entry: Array in [["play", &"maps"], ["host", &"host"], ["join", &"join"], ["settings", &"settings"]]:
		(title.buttons[entry[0]] as Button).pressed.emit()
		await _frames()
		var opened: bool = menu.current_name == entry[1] and menu.get_screen(entry[1]).visible and not title.visible
		_check(opened, "%s opens the %s screen" % [String(entry[0]).to_upper(), entry[1]])
		await _press_ui_cancel()
		_check(menu.current_name == &"title" and title.visible, "ESC returns from %s to the title" % entry[1])
	(title.buttons["host"] as Button).pressed.emit()
	await _frames()
	(menu.get_screen(&"host").find_children("*", "Button", true, false).filter(
			func(b: Button) -> bool: return b.text == "Back")[0] as Button).pressed.emit()
	await _frames()
	_check(menu.current_name == &"title", "Back button returns to the title")
	var quits_before := _quits
	(title.buttons["quit"] as Button).pressed.emit()
	_check(_quits == quits_before + 1, "QUIT quits the game")
	await _free(menu)


## `-- --quick-race=MAP` (exported builds can't open a scene from the
## command line): a solo race with 4 AI on that map, via the normal lobby.
func _test_quick_race() -> void:
	print("\n[Menu: quick race launch option]")
	var menu := await _load_menu()
	var loaded: Array[String] = []
	menu.scene_changer = func(path: String) -> void: loaded.append(path)
	var bad := menu.quick_race("no_such_map")
	var ok := menu.quick_race("rocky_canyon")
	_check(not bad and ok and loaded == ["res://scenes/main/rocky_canyon.tscn"] and GameSession.lobby.count() == 5
			and GameSession.lobby.map_id == "rocky_canyon", "quick race: the map's race scene with you + 4 AI",
			"(%s, %d racers)" % [str(loaded), GameSession.lobby.count()])
	GameSession.end_race_for_lobby()
	GameSession.leave_lobby()
	await _free(menu)


func _test_map_select() -> void:
	print("\n[Menu: map selection]")
	var menu := await _load_menu()
	menu.start_solo()
	await _frames()
	var maps: MapSelectScreen = menu.get_screen(&"maps")
	var names: Array[String] = []
	for card in maps.cards:
		names.append(card.map.display_name)
	_check(names == ["Forest Rush", "Rocky Canyon", "Snow Slide"], "three map cards", "(%s)" % ", ".join(names))
	var all_routes := true
	var described := true
	for card in maps.cards:
		all_routes = all_routes and card.is_route_preview() and not card.is_placeholder_preview() and card.map.preview == null
		described = described and not card.map.description.is_empty() and not card.map.characteristic.is_empty()
	_check(all_routes, "previews are route maps drawn from each map's track data (no fake screenshots)")
	_check(described, "each card has a description and a gameplay characteristic")
	var lengths: Array[String] = []
	for card in maps.cards:
		var route: Dictionary = card._preview.get_route()
		lengths.append("%.1f km / %d m" % [float(route.get("length", 0.0)) / 1000.0, roundi(float(route.get("drop", 0.0)))])
	_check(lengths.size() == 3 and not lengths.has("0.0 km / 0 m"), "each route map shows the real length and drop",
			"(%s)" % ", ".join(lengths))
	var forest := maps.cards[0]
	var canyon := maps.cards[1]
	var snow := maps.cards[2]
	_check(forest.selectable and forest.selected and forest.map.get_status_text() == "READY",
			"Forest Rush is selectable, selected by default, marked READY")
	canyon.press()
	_check(canyon.selectable and canyon.selected and not forest.selected and maps.selected_id == "rocky_canyon"
			and canyon.map.get_status_text() == "READY", "Rocky Canyon is READY and selectable")
	maps.select("snow_slide")
	_check(snow.selectable and snow.selected and not canyon.selected and maps.selected_id == "snow_slide"
			and snow.map.get_status_text() == "READY", "Snow Slide is READY and selectable")
	maps.select("forest_rush")
	maps.continue_button.pressed.emit()
	await _frames()
	_check(menu.current_name == &"lobby" and GameSession.mode == GameSession.Mode.SOLO
			and GameSession.lobby.map_id == "forest_rush" and GameSession.lobby.count() == 4,
			"Continue opens a solo lobby on Forest Rush (you + 3 AI)")
	menu.leave_lobby()
	await _free(menu)


func _test_host_screen() -> void:
	print("\n[Menu: host screen]")
	var menu := await _load_menu()
	menu.show_screen(&"host")
	await _frames()
	var host: HostScreen = menu.get_screen(&"host")
	_check(host.port_edit.text == "7777" and not host.host_button.disabled, "default port 7777 is valid")
	_check(host.address_label.text != "" and host.status_label.text.contains("not hosting"),
			"local network info and status are shown", "(%s)" % host.address_label.text)
	var invalid_ok := true
	for bad: String in ["", "abc", "80", "0", "70000", "-5", "12.5", "7 77"]:
		host.port_edit.text = bad
		host.port_edit.text_changed.emit(bad)
		invalid_ok = invalid_ok and host.host_button.disabled and host.status_label.text != "" \
				and not host.status_label.text.begins_with("Status")
	_check(invalid_ok, "invalid ports disable Host Game with an error")
	host.port_edit.text = "7800"
	host.port_edit.text_changed.emit("7800")
	_check(not host.host_button.disabled, "a valid port enables Host Game")
	host.set_player_limit(5)
	host.limit_plus.pressed.emit()
	var at_max := host.player_limit == 5 and host.limit_plus.disabled
	for i in 5:
		host.limit_minus.pressed.emit()
	_check(at_max and host.player_limit == 2 and host.limit_minus.disabled, "player limit steps between 2 and 5")
	host.limit_plus.pressed.emit()
	host.host_button.pressed.emit()
	await _frames()
	var lobby := GameSession.lobby
	_check(menu.current_name == &"lobby" and GameSession.mode == GameSession.Mode.HOST and lobby != null
			and lobby.max_players == 3 and lobby.count() == 1 and lobby.get_host() == lobby.get_local_player(),
			"Host Game creates a lobby: you as host, limit 3")
	_check(GameSession.transport.status == NetworkTransport.Status.HOSTING and GameSession.transport.port == 7800,
			"transport reports hosting on the chosen port", "(%s)" % GameSession.transport.status_message)
	menu.get_screen(&"lobby").back_requested.emit()
	await _frames()
	_check(menu.current_name == &"title" and not GameSession.has_lobby()
			and GameSession.transport.status == NetworkTransport.Status.IDLE, "Leave Lobby closes the hosted lobby")
	await _free(menu)


func _test_join_validation() -> void:
	print("\n[Menu: join screen]")
	_check(NetAddress.validate_address("192.168.1.20") == "" and NetAddress.validate_address("localhost") == ""
			and NetAddress.validate_address(" 10.0.0.5 ") == "", "valid addresses accepted")
	var bad_ips := ["", "abc", "256.1.1.1", "1.2.3", "1.2.3.4.5", "192.168.1.", "01.2.3.4", "1.2.3.-4", "0.0.0.0", "1..2.3"]
	var rejected := true
	for ip: String in bad_ips:
		rejected = rejected and NetAddress.validate_address(ip) != ""
	_check(rejected, "invalid addresses rejected", "(%d cases)" % bad_ips.size())
	var menu := await _load_menu()
	menu.show_screen(&"join")
	await _frames()
	var join: JoinScreen = menu.get_screen(&"join")
	join.address_edit.text = "999.1.1.1"
	var attempts := [0]
	GameSession.transport.status_changed.connect(func(_s: NetworkTransport.Status, _m: String) -> void: attempts[0] += 1)
	join.connect_button.pressed.emit()
	_check(join.status_label.text.contains("0 to 255") and attempts[0] == 0, "bad IP: error shown, no connection attempt",
			"(%s)" % join.status_label.text)
	join.address_edit.text = "192.168.1.30"
	join.port_edit.text = "99999"
	join.connect_button.pressed.emit()
	_check(join.status_label.text.contains("between") and attempts[0] == 0, "bad port: error shown, no connection attempt")
	join.port_edit.text = ""
	_check(join.try_connect().contains("port"), "empty port rejected")
	# Localhost with nobody listening: a real attempt that can't fail at once,
	# whatever network this computer is on.
	join.address_edit.text = "127.0.0.1"
	join.port_edit.text = "47999"
	join.connect_button.pressed.emit()
	await _frames()
	_check(attempts[0] >= 1 and GameSession.transport.status == NetworkTransport.Status.CONNECTING
			and join.status_label.text.begins_with("Connecting") and join.connect_button.disabled,
			"valid input starts a real connection attempt", "(%s)" % join.status_label.text)
	_check(not GameSession.has_lobby() and menu.current_name == &"join", "stays on the join screen while connecting")
	GameSession.leave_lobby()
	_check(GameSession.transport.status == NetworkTransport.Status.IDLE and not Net.is_online(),
			"leaving aborts the attempt")
	await _free(menu)


# --- Lobby ------------------------------------------------------------------

func _test_lobby_actions() -> void:
	print("\n[Menu: lobby]")
	var menu := await _load_menu()
	GameSession.host_lobby("Sam", 7777, 5)
	menu.show_screen(&"lobby")
	await _frames()
	var screen: LobbyMenuScreen = menu.get_screen(&"lobby")
	var lobby := GameSession.lobby
	_check(screen.count_label.text.begins_with("1 / 5 players") and screen.player_list.get_child_count() == 1,
			"lobby lists players with a count", "(%s)" % screen.count_label.text)
	var row_text := _row_text(screen.player_list.get_child(0))
	_check(row_text.contains("Sam") and row_text.contains("HOST") and row_text.contains("NOT READY"),
			"host row: name, HOST badge, ready status", "(%s)" % row_text)
	_check(screen.start_button.disabled and screen.blocker_label.text.contains("ready"),
			"Start Race waits until everyone is ready", "(%s)" % screen.blocker_label.text)
	for i in 6:
		screen.add_ai_button.pressed.emit()
	await _frames()
	_check(lobby.count() == 5 and screen.add_ai_button.disabled and screen.player_list.get_child_count() == 5,
			"Add AI fills up to five players, then disables")
	screen.remove_ai_button.pressed.emit()
	await _frames()
	_check(lobby.count() == 4 and not screen.add_ai_button.disabled, "Remove AI frees a seat")
	var ai := lobby.players[1]
	var difficulty_button := screen.player_list.find_child("Difficulty%d" % ai.id, true, false) as Button
	var before := ai.ai_difficulty
	difficulty_button.pressed.emit()
	await _frames()
	_check(ai.ai_difficulty != before and _row_text(screen.player_list.get_child(1)).contains(["Easy", "Medium", "Hard"][ai.ai_difficulty]),
			"AI difficulty button cycles the difficulty")
	screen.ready_button.button_pressed = true
	await _frames()
	_check(lobby.get_local_player().is_ready and not screen.start_button.disabled
			and _row_text(screen.player_list.get_child(0)).contains("READY"), "Ready marks you ready and enables Start Race")
	screen.change_map_button.pressed.emit()
	await _frames()
	_check(menu.current_name == &"maps", "Change Map opens map selection")
	(menu.get_screen(&"maps") as MapSelectScreen).continue_button.pressed.emit()
	await _frames()
	_check(menu.current_name == &"lobby" and lobby.map_id == "forest_rush" and screen.map_card != null
			and screen.map_card.map.id == "forest_rush" and screen.map_card.is_route_preview(),
			"back in the lobby with the selected map and its preview")
	screen.leave_button.pressed.emit()
	await _frames()
	_check(menu.current_name == &"title" and not GameSession.has_lobby(), "Leave Lobby returns to the title")
	await _free(menu)


func _row_text(row: Node) -> String:
	var parts: Array[String] = []
	for child in row.get_children():
		if child is Label:
			parts.append((child as Label).text)
		elif child is Button:
			parts.append((child as Button).text)
	return " ".join(parts)


func _test_start_race_and_return_to_lobby() -> void:
	print("\n[Menu: lobby → race → lobby]")
	var menu := await _load_menu()
	menu.start_solo()
	(menu.get_screen(&"maps") as MapSelectScreen).confirm()
	await _frames()
	GameSession.lobby.cycle_ai_difficulty(GameSession.lobby.players[1].id)  # Pip: Medium → Hard
	var screen: LobbyMenuScreen = menu.get_screen(&"lobby")
	_scene_requests.clear()
	screen.start_button.pressed.emit()
	_check(_scene_requests == ["res://scenes/main/forest_rush.tscn"] and GameSession.race_active,
			"Start Race loads the map's race scene (Forest Rush)")
	await _free(menu)
	# What the scene change would load:
	var race: RaceSession = (load("res://scenes/main/forest_rush.tscn") as PackedScene).instantiate()
	race.scene_changer = func(path: String) -> void: _scene_requests.append(path)
	runner.add_child(race)
	await _frames(2)
	var names: Array[String] = []
	for racer in race.racers.get_racers():
		names.append(racer.display_name)
	var pip := race.racers.get_racer(2)
	_check(race.from_lobby and names == [GameSettings.player_name, "Pip", "Bramble", "Nutmeg"]
			and pip.get_ai_driver().config.difficulty == AIDriverConfig.Difficulty.HARD,
			"the race uses the lobby's players, names and AI difficulties", "(%s)" % ", ".join(names))
	_check(race.race.get_state() == RaceStateMachine.State.LOBBY and race.hud.get_race_state_text() == "GET READY",
			"race starts in its LOBBY state with the countdown coming")
	_scene_requests.clear()
	race.pause_menu.set_paused(true)
	race.pause_menu.press("lobby")
	_check(_scene_requests == [GameSession.MENU_SCENE] and not _tree().paused and GameSession.open_lobby_on_menu
			and not GameSession.race_active, "pause → Return to Lobby goes back to the menu lobby")
	await _free(race)
	var back := await _load_menu()
	_check(back.current_name == &"lobby" and GameSession.lobby.count() == 4, "the menu reopens on the same lobby")
	back.leave_lobby()
	await _free(back)


# --- Settings -----------------------------------------------------------------

func _test_settings_controls_and_persistence() -> void:
	print("\n[Settings: controls and persistence]")
	GameSettings.use_test_profile(TEST_SETTINGS)
	var menu := await _load_menu()
	menu.show_screen(&"settings")
	await _frames()
	var settings: SettingsPanel = menu.get_screen(&"settings")
	var sections_ok := true
	for section: String in ["audio", "video", "controls", "player"]:
		(settings.section_buttons[section] as Button).pressed.emit()
		sections_ok = sections_ok and settings.current_section == section and (settings.sections[section] as Control).visible
	_check(sections_ok, "Audio / Video / Controls / Player tabs switch pages")
	(settings.volume_sliders["Master"]["slider"] as HSlider).value = 50
	(settings.volume_sliders["Music"]["slider"] as HSlider).value = 30
	(settings.volume_sliders["SFX"]["slider"] as HSlider).value = 0
	var master_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master"))
	var music_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))
	_check(is_equal_approx(GameSettings.master_volume, 0.5) and absf(master_db - linear_to_db(0.5)) < 0.01
			and absf(music_db - linear_to_db(0.3)) < 0.01 and AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")),
			"volume sliders drive the Master, Music and SFX buses", "(master %.1f dB)" % master_db)
	settings.resolution_option.select(2)
	settings.resolution_option.item_selected.emit(2)
	_check(GameSettings.get_resolution() == Vector2i(1920, 1080), "resolution option sets 1920×1080")
	settings.fullscreen_check.button_pressed = true
	_check(GameSettings.fullscreen and settings.resolution_option.disabled, "fullscreen toggle (resolution locked while on)")
	settings.fullscreen_check.button_pressed = false
	settings.quality_option.select(0)
	settings.quality_option.item_selected.emit(0)
	var viewport := _tree().root
	_check(GameSettings.quality == GameSettings.Quality.LOW and viewport.msaa_3d == Viewport.MSAA_DISABLED
			and is_equal_approx(viewport.scaling_3d_scale, 0.75), "Low quality: no MSAA, 75 % 3D scale")
	var sun := menu.get_node("Background/Sun") as DirectionalLight3D
	_check(not sun.shadow_enabled, "Low quality turns sun shadows off")
	settings.quality_option.select(2)
	settings.quality_option.item_selected.emit(2)
	_check(viewport.msaa_3d == Viewport.MSAA_4X and sun.shadow_enabled, "High quality: 4× MSAA, shadows on")
	settings.name_edit.text = "Captain Zoom"
	settings.name_edit.text_changed.emit("Captain Zoom")
	_check(GameSettings.player_name == "Captain Zoom", "player name edits the saved name")
	settings.name_edit.text_changed.emit("   ")
	_check(GameSettings.player_name == "Player", "an empty name falls back to Player")
	settings.name_edit.text_changed.emit("Captain Zoom")

	var fresh: Node = SETTINGS_SCRIPT.new()
	fresh.settings_path = TEST_SETTINGS
	fresh.load_settings()
	_check(is_equal_approx(fresh.master_volume, 0.5) and is_equal_approx(fresh.music_volume, 0.3)
			and is_equal_approx(fresh.sfx_volume, 0.0) and fresh.resolution_index == 2 and not fresh.fullscreen
			and fresh.quality == GameSettings.Quality.HIGH and fresh.player_name == "Captain Zoom",
			"all settings are saved and load again (as after a relaunch)")
	fresh.free()
	settings.back_button.pressed.emit()
	await _frames()
	_check(menu.current_name == &"title", "Back leaves settings")
	GameSettings.use_test_profile(TEST_SETTINGS)
	await _free(menu)


func _test_key_rebinding() -> void:
	print("\n[Settings: keyboard controls]")
	GameSettings.use_test_profile(TEST_SETTINGS)
	var menu := await _load_menu()
	menu.show_screen(&"settings")
	var settings: SettingsPanel = menu.get_screen(&"settings")
	settings.show_section("controls")
	await _frames()
	_check((settings.key_buttons[&"accelerate"] as Button).text == "W / ↑", "Controls lists current keys", "(W / ↑)")
	(settings.key_buttons[&"accelerate"] as Button).pressed.emit()
	_check(settings.listening_action == &"accelerate" and (settings.key_buttons[&"accelerate"] as Button).text == "Press a key…",
			"clicking a key waits for the new key")
	await runner._send_key(KEY_I, true)
	await runner._send_key(KEY_I, false)
	_check(GameSettings.primary_key(&"accelerate") == KEY_I and (settings.key_buttons[&"accelerate"] as Button).text == "I / ↑",
			"pressing I rebinds Accelerate to I")
	await runner._send_key(KEY_I, true)
	await _tree().physics_frame
	var strength := Input.get_action_strength(&"accelerate")
	await runner._send_key(KEY_I, false)
	_check(strength == 1.0, "the new key drives the action")
	(settings.key_buttons[&"brake"] as Button).pressed.emit()
	await runner._send_key(KEY_I, true)
	await runner._send_key(KEY_I, false)
	_check(GameSettings.primary_key(&"brake") == KEY_S and settings.controls_message.text.contains("already used"),
			"a key already in use is refused", "(%s)" % settings.controls_message.text)
	(settings.key_buttons[&"drift"] as Button).pressed.emit()
	await runner._send_key(KEY_ESCAPE, true)
	await runner._send_key(KEY_ESCAPE, false)
	_check(settings.listening_action == &"" and GameSettings.primary_key(&"drift") == KEY_SPACE and menu.current_name == &"settings",
			"ESC cancels without leaving settings")
	var fresh: Node = SETTINGS_SCRIPT.new()
	fresh.settings_path = TEST_SETTINGS
	fresh.load_settings()
	_check(fresh.key_overrides.get(&"accelerate") == KEY_I, "rebinding is saved")
	fresh.free()
	settings.reset_controls_button.pressed.emit()
	_check(GameSettings.primary_key(&"accelerate") == KEY_W and (settings.key_buttons[&"accelerate"] as Button).text == "W / ↑",
			"Reset Controls restores the defaults")
	await _free(menu)


# --- Race UI ----------------------------------------------------------------

func _test_pause_menu() -> void:
	print("\n[Pause menu]")
	GameSession.leave_lobby()
	await _clear_arena()
	var main: RaceSession = MAIN_SCENE.instantiate()
	main.skip_countdown = true
	runner.add_child(main)
	main.pause_menu.quit_handler = func() -> void: _quits += 1
	main.pause_menu.restart_requested.disconnect(main.restart)  # a reload would reload the test runner
	var restarts := [0]
	main.pause_menu.restart_requested.connect(func() -> void: restarts[0] += 1)
	await _frames(3)
	var labels: Array[String] = []
	for button in main.pause_menu.find_children("*Button", "Button", true, false):
		if (button as Button).get_parent().name == "VBox":
			labels.append((button as Button).text)
	_check(labels == ["Resume", "Restart", "Settings", "Return to Lobby", "Quit Game"],
			"Resume, Restart, Settings, Return to Lobby, Quit Game", "(%s)" % ", ".join(labels))
	await runner._press_action(&"pause")
	_check(_tree().paused and main.pause_menu.is_open(), "ESC pauses")
	main.pause_menu.press("resume")
	_check(not _tree().paused and not main.pause_menu.is_open(), "Resume continues the race")
	main.pause_menu.set_paused(true)
	main.pause_menu.press("settings")
	await _frames()
	_check(_tree().paused and main.pause_menu.is_settings_open() and main.pause_menu.settings.visible,
			"Settings opens over the paused race")
	await runner._press_action(&"pause")
	_check(_tree().paused and not main.pause_menu.is_settings_open() and main.pause_menu.is_open(),
			"ESC closes settings back to the pause menu")
	main.pause_menu.press("restart")
	_check(restarts[0] == 1 and not _tree().paused, "Restart requests a restart and unpauses")
	main.pause_menu.set_paused(true)
	var quits_before := _quits
	main.pause_menu.press("quit")
	_check(_quits == quits_before + 1, "Quit Game quits")
	main.pause_menu.press("lobby")
	await _frames()
	_check(not _tree().paused and main.race.get_state() == RaceStateMachine.State.LOBBY and main.lobby_screen.is_open(),
			"Return to Lobby (race started directly): back to the race lobby")
	var keys_text := ""
	for child in main.pause_menu.find_child("Controls", true, false).get_children():
		keys_text += (child as Label).text + " "
	_check(keys_text.contains("W / ↑") and keys_text.contains("Q") and keys_text.contains("ESC"),
			"pause menu lists the current keys")
	_tree().paused = false
	await _free(main)


func _test_hud() -> void:
	print("\n[HUD]")
	await _clear_arena()
	var main: RaceSession = MAIN_SCENE.instantiate()
	main.ai_racer_count = 2
	runner.add_child(main)
	main.trike.input_source = null
	await _frames(2)
	var hud := main.hud
	var states: Array[String] = [hud.get_race_state_text()]
	var t := 0.0
	while main.race.get_state() != RaceStateMachine.State.RACING and t < 6.0:
		await _tree().physics_frame
		await _tree().process_frame
		t += 1.0 / Engine.physics_ticks_per_second
		var text := hud.get_race_state_text()
		if states[-1] != text:
			states.append(text)
	_check(states == ["GET READY", "STARTING", "RACING"], "race state shown: GET READY → STARTING → RACING",
			"(%s)" % " → ".join(states))
	_check(hud.get_race_position_text().contains("/ 3") and hud.position_title.text.contains("CP 0/12"),
			"position and checkpoint progress shown", "(%s, %s)" % [hud.get_race_position_text(), hud.position_title.text])
	_check(hud.get_item_text() == "EMPTY" and hud.get_item_hint_text() == "[Q] USE ITEM", "empty item slot with its use key (Q)")
	hud.set_item("Bouncy Ball")
	_check(hud.get_item_text() == "Bouncy Ball", "item slot shows a held item")
	hud.set_item("")
	_check(hud.get_prompt_key_text() == "E" and hud.get_hint_text().contains("W / ↑   Accelerate"),
			"mount prompt and controls hint use the bound keys")
	GameSettings.rebind(&"interact", KEY_G)
	_check(hud.get_prompt_key_text() == "G", "rebinding updates the HUD prompt")
	GameSettings.reset_controls()
	await runner._hold(main.trike, 2.0, 1.0)
	await _frames()
	_check(hud.get_displayed_speed() > 30 and hud.timer_label.text != "00:00.00", "speed and timer update while racing")
	await _free(main)


## Every visible button of every screen fits in the 1280×720 base layout
## (larger windows scale this layout up).
func _test_layout_fits() -> void:
	print("\n[Layout at 1280×720]")
	var menu := await _load_menu()
	GameSession.host_lobby("Sam", 7777, 5)
	for i in 4:
		GameSession.lobby.add_ai()
	# The headless test window isn't 1280×720, so compare each page's minimum
	# layout size (what it needs to show everything) with the base size.
	var problems: Array[String] = []
	var sizes: Array[String] = []
	for screen_name: StringName in [&"title", &"maps", &"host", &"join", &"lobby", &"settings"]:
		menu.show_screen(screen_name)
		await _frames(4)
		var needed := Vector2.ZERO
		for child in menu.get_screen(screen_name).get_children():
			if child is Control:
				needed = needed.max((child as Control).get_combined_minimum_size())
		sizes.append("%s %dx%d" % [screen_name, needed.x, needed.y])
		if needed.x > 1280.0 or needed.y > 720.0:
			problems.append(screen_name)
	_check(problems.is_empty(), "every menu page fits a 1280×720 screen (full lobby included)", "(%s)" % ", ".join(sizes))
	_check(ProjectSettings.get_setting("display/window/stretch/mode") == "canvas_items"
			and ProjectSettings.get_setting("display/window/stretch/aspect") == "expand",
			"UI scales with the window (canvas_items stretch, expand aspect)")
	menu.leave_lobby()
	await _free(menu)
