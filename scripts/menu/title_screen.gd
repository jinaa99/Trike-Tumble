class_name TitleScreen
extends MenuScreen
## Main menu: logo and PLAY / HOST GAME / JOIN GAME / SETTINGS / QUIT.

var buttons := {}
## Why the last online game ended (shown once).
var notice_label: Label
var _logo: Label
var _time := 0.0


func build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override(&"margin_left", 88)
	margin.add_theme_constant_override(&"margin_top", 40)
	margin.add_theme_constant_override(&"margin_bottom", 32)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var column := UiKit.vbox(10)
	margin.add_child(column)
	_logo = UiKit.title("TRIKE\nTUMBLE", UiKit.SIZE_HERO, UiKit.SUN)
	_logo.add_theme_constant_override(&"outline_size", 22)
	_logo.add_theme_color_override(&"font_outline_color", UiKit.INK)
	_logo.add_theme_constant_override(&"line_spacing", -26)
	column.add_child(_logo)
	var tagline := UiKit.label("Downhill party racing on three wheels", UiKit.SIZE_BODY, Color.WHITE, 10)
	tagline.add_theme_color_override(&"font_outline_color", UiKit.INK)
	column.add_child(tagline)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 14)
	column.add_child(spacer)
	for entry: Array in [["play", "PLAY", "primary"], ["host", "HOST GAME", "normal"], ["join", "JOIN GAME", "normal"],
			["settings", "SETTINGS", "normal"], ["quit", "QUIT", "quiet"]]:
		var button := UiKit.button(entry[1], entry[2], 320)
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		column.add_child(button)
		buttons[entry[0]] = button
	(buttons["play"] as Button).pressed.connect(func() -> void: menu.start_solo())
	(buttons["host"] as Button).pressed.connect(func() -> void: menu.show_screen(&"host"))
	(buttons["join"] as Button).pressed.connect(func() -> void: menu.show_screen(&"join"))
	(buttons["settings"] as Button).pressed.connect(func() -> void: menu.show_screen(&"settings"))
	(buttons["quit"] as Button).pressed.connect(func() -> void: menu.quit_game())
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(fill)
	notice_label = UiKit.label("", UiKit.SIZE_BODY, UiKit.SUN, 8)
	notice_label.add_theme_color_override(&"font_outline_color", UiKit.INK)
	column.add_child(notice_label)
	var footer := UiKit.label("Demo build · race AI solo, or host/join on your local network", UiKit.SIZE_SMALL, UiKit.TEXT, 6)
	footer.add_theme_color_override(&"font_outline_color", UiKit.INK)
	column.add_child(footer)


func on_enter() -> void:
	notice_label.text = GameSession.last_error
	notice_label.visible = not GameSession.last_error.is_empty()
	GameSession.last_error = ""


func get_default_focus() -> Control:
	return buttons["play"]


func _process(delta: float) -> void:
	if _logo and visible:
		_time += delta
		_logo.pivot_offset = _logo.size * 0.5
		_logo.rotation = sin(_time * 1.3) * 0.02
		_logo.scale = Vector2.ONE * (1.0 + sin(_time * 2.1) * 0.012)


## The title page has nothing to go back to.
func _unhandled_input(_event: InputEvent) -> void:
	pass
