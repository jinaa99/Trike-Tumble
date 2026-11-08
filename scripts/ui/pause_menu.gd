class_name PauseMenu
extends CanvasLayer
## ESC toggles pause. Runs while the tree is paused (process_mode = Always).
## Resume, Restart, Settings (overlay), Return to Lobby, Quit Game, and a
## controls reminder built from the current key bindings.

signal restart_requested
signal lobby_requested

## (keycap, description) rows of the controls reminder.
const CONTROL_ROWS: Array[Array] = [
	[[&"accelerate"], "Accelerate"], [[&"brake"], "Brake / reverse"],
	[[&"steer_left", &"steer_right"], "Steer"], [[&"drift"], "Drift (hold + steer)"],
	[[&"use_item"], "Use item"], [[&"interact"], "Get back on"],
	[[&"reset"], "Reset trike"], [[&"pause"], "Pause"],
]

## Replaced by tests.
var quit_handler := func() -> void: get_tree().quit()
var settings: SettingsPanel

@onready var _root: Control = $Root
@onready var _resume_button: Button = %ResumeButton
@onready var _restart_button: Button = %RestartButton
@onready var _settings_button: Button = %SettingsButton
@onready var _lobby_button: Button = %LobbyButton
@onready var _quit_button: Button = %QuitButton
@onready var _controls: GridContainer = %Controls
var _settings_layer: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.visible = false
	_resume_button.pressed.connect(set_paused.bind(false))
	_restart_button.pressed.connect(_on_restart_pressed)
	_settings_button.pressed.connect(open_settings)
	_lobby_button.pressed.connect(_on_lobby_pressed)
	_quit_button.pressed.connect(func() -> void: quit_handler.call())
	for button in [_resume_button, _restart_button, _settings_button, _lobby_button, _quit_button]:
		UiKit.add_motion(button)
	_build_settings_overlay()
	_refresh_controls()
	GameSettings.settings_changed.connect(_refresh_controls)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pause"):
		return
	if is_settings_open():
		close_settings()
	else:
		set_paused(not _root.visible)
	get_viewport().set_input_as_handled()


func set_paused(paused: bool) -> void:
	if not online:
		get_tree().paused = paused
	_root.visible = paused
	_settings_layer.visible = false
	if paused:
		_refresh_controls()
		_resume_button.grab_focus()


func is_open() -> bool:
	return _root.visible or _settings_layer.visible


func is_settings_open() -> bool:
	return _settings_layer.visible


func open_settings() -> void:
	_root.visible = false
	_settings_layer.visible = true
	settings.on_enter()
	UiKit.fade_in(settings)
	settings.get_default_focus().grab_focus()


func close_settings() -> void:
	_settings_layer.visible = false
	_root.visible = true
	_refresh_controls()
	_settings_button.grab_focus()


## Online the race keeps running behind the menu (no tree pause), Restart
## is hidden, and clients get "Leave Game" instead of "Return to Lobby".
var online := false


func set_online(is_host: bool) -> void:
	online = true
	_restart_button.visible = false
	_lobby_button.text = "Return to Lobby" if is_host else "Leave Game"


func press(button_name: String) -> void:
	({"resume": _resume_button, "restart": _restart_button, "settings": _settings_button,
			"lobby": _lobby_button, "quit": _quit_button}[button_name] as Button).pressed.emit()


func _build_settings_overlay() -> void:
	_settings_layer = Control.new()
	_settings_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_layer.visible = false
	add_child(_settings_layer)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.06, 0.04, 0.16, 0.72)
	_settings_layer.add_child(dim)
	settings = SettingsPanel.new()
	_settings_layer.add_child(settings)
	settings.build()
	settings.back_requested.connect(close_settings)


func _refresh_controls() -> void:
	for child in _controls.get_children():
		_controls.remove_child(child)
		child.queue_free()
	var keycap := _keycap_style()
	for row in CONTROL_ROWS:
		var keys: Array[String] = []
		for action: StringName in row[0]:
			keys.append(UiKit.action_keys(action) if row[0].size() == 1 else UiKit.key_name(GameSettings.primary_key(action)))
		var key_label := UiKit.label(" ".join(keys), 15, UiKit.INK)
		key_label.add_theme_stylebox_override(&"normal", keycap)
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_label.size_flags_horizontal = Control.SIZE_SHRINK_END
		_controls.add_child(key_label)
		_controls.add_child(UiKit.label(row[1], 15, Color(0.86, 0.85, 0.95)))


static func _keycap_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = UiKit.CREAM
	box.border_width_bottom = 3
	box.border_color = Color(0.7, 0.66, 0.82)
	box.set_corner_radius_all(7)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 3
	box.content_margin_bottom = 5
	return box


func _on_restart_pressed() -> void:
	set_paused(false)
	restart_requested.emit()


func _on_lobby_pressed() -> void:
	set_paused(false)
	lobby_requested.emit()
