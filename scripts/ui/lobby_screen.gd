class_name LobbyScreen
extends RaceMenuBase
## Pre-race lobby: the racers on the grid and a Start Race button. Shown
## while the race waits in LOBBY (after Return to Lobby, or when the race
## doesn't auto-start). Online lobbies come with networking later.

signal start_pressed

var _list: GridContainer
var _start_button: Button


func _ready() -> void:
	layer = 8
	_build_frame("LOBBY")
	_list = GridContainer.new()
	_list.columns = 3
	_list.add_theme_constant_override(&"h_separation", 28)
	_list.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_list)
	_start_button = _button("Start Race")
	box.add_child(_start_button)
	_start_button.pressed.connect(func() -> void: start_pressed.emit())


func show_lobby(racers: Array[Racer]) -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for racer in racers:
		var swatch := ColorRect.new()
		swatch.color = racer.color
		swatch.custom_minimum_size = Vector2(22, 22)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_list.add_child(swatch)
		_list.add_child(_label(racer.display_name, 28, RaceMenuBase.TEXT_COLOR))
		var kind := "Player" if not racer.is_ai() else "AI · %s" % racer.get_ai_driver().config.display_name
		_list.add_child(_label(kind, 20, RaceMenuBase.DIM_TEXT_COLOR))
	root.visible = true
	_start_button.grab_focus()


func hide_lobby() -> void:
	root.visible = false


func press_start() -> void:
	_start_button.pressed.emit()
