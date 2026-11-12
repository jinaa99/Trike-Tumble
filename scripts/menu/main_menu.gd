class_name MainMenu
extends Node
## Main menu scene: 3D background plus one MenuScreen at a time (title, map
## select, host, join, lobby, settings) with fade/slide transitions and a
## back history. Opens on the lobby when returning from a race.

const RACE_LOADING_TEXT := "Loading race…"

## Replaced by tests: how the game quits and changes scenes.
var quit_handler := func() -> void: get_tree().quit()
var scene_changer := func(path: String) -> void: get_tree().change_scene_to_file(path)

var screens := {}
var current: MenuScreen
var current_name := &""
var history: Array[StringName] = []

@onready var ui_root: Control = $UI/Root


func _ready() -> void:
	GameSettings.apply_graphics(self)
	MusicPlayer.duck(false)
	MusicPlayer.play(&"menu")
	_add_screen(&"title", TitleScreen.new())
	_add_screen(&"maps", MapSelectScreen.new())
	_add_screen(&"host", HostScreen.new())
	_add_screen(&"join", JoinScreen.new())
	_add_screen(&"lobby", LobbyMenuScreen.new())
	_add_screen(&"settings", SettingsPanel.new())
	GameSession.race_scene_requested.connect(func(path: String) -> void: scene_changer.call(path))
	GameSession.disconnected.connect(_on_disconnected)
	if GameSession.open_lobby_on_menu and GameSession.has_lobby():
		GameSession.open_lobby_on_menu = false
		show_screen(&"title")
		show_screen(&"lobby")
	else:
		show_screen(&"title")
	_quick_race_from_command_line.call_deferred()


## QA/launch option for exported builds (which can't open a scene from the
## command line): `-- --quick-race=snow_slide` starts a solo race on that map
## through the normal solo lobby (you + 4 AI). Used once per launch.
static var _quick_race_used := false


func _quick_race_from_command_line() -> void:
	if _quick_race_used:
		return
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--quick-race="):
			continue
		_quick_race_used = true
		quick_race(arg.trim_prefix("--quick-race="))
		return


## Solo race on `map_id` with 4 AI, straight from the menu. False if the map
## isn't playable.
func quick_race(map_id: String) -> bool:
	var map := MapCatalog.get_map(map_id)
	if map == null or not map.is_playable():
		push_warning("--quick-race: unknown or unplayable map %s" % map_id)
		return false
	GameSession.create_solo_lobby(GameSettings.player_name)
	GameSession.lobby.add_ai()
	GameSession.lobby.set_map(map.id)
	start_race()
	return true


func _add_screen(screen_name: StringName, screen: MenuScreen) -> void:
	screen.name = String(screen_name).capitalize()
	screen.menu = self
	screen.visible = false
	ui_root.add_child(screen)
	screen.build()
	screen.back_requested.connect(_on_back.bind(screen_name))
	screens[screen_name] = screen


func get_screen(screen_name: StringName) -> MenuScreen:
	return screens[screen_name]


## Shows a screen. `remember` puts the current one on the back history.
func show_screen(screen_name: StringName, remember := true) -> void:
	if current_name == screen_name:
		return
	if current:
		if remember:
			history.append(current_name)
		current.visible = false
	current = screens[screen_name]
	current_name = screen_name
	current.visible = true
	current.on_enter()
	UiKit.fade_in(current)
	var focus := current.get_default_focus()
	if focus:
		focus.grab_focus.call_deferred()


func go_back() -> void:
	if history.is_empty():
		return
	var previous: StringName = history.pop_back()
	show_screen(previous, false)


func _on_back(screen_name: StringName) -> void:
	if screen_name == &"lobby":
		leave_lobby()
	else:
		go_back()


# --- Actions used by the screens ----------------------------------------------

## PLAY: pick a map, then a solo lobby (you + AI).
func start_solo() -> void:
	open_map_select(MapCatalog.DEFAULT_MAP, func(map_id: String) -> void:
		GameSession.create_solo_lobby(GameSettings.player_name)
		GameSession.lobby.set_map(map_id)
		show_screen(&"lobby", false))


func open_map_select(selected: String, on_chosen: Callable) -> void:
	var maps: MapSelectScreen = screens[&"maps"]
	maps.selected_id = selected
	maps.on_chosen = on_chosen
	show_screen(&"maps")


func leave_lobby() -> void:
	GameSession.leave_lobby()
	history.clear()
	show_screen(&"title", false)


func start_race() -> void:
	var scene_path := GameSession.begin_race()
	if scene_path.is_empty():
		return
	scene_changer.call(scene_path)


func quit_game() -> void:
	quit_handler.call()


## Online session ended (host left, connection lost): back to the title
## with the reason.
func _on_disconnected(_reason: String) -> void:
	history.clear()
	current_name = &""
	if current:
		current.visible = false
		current = null
	show_screen(&"title", false)
