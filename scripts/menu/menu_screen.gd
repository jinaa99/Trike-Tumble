class_name MenuScreen
extends Control
## Base for full-screen menu pages. MainMenu shows one at a time with a fade
## and slide. Subclasses build their controls in build() and may override
## on_enter() (refresh data) and get_default_focus().

signal back_requested

## The owning MainMenu (set before build()).
var menu: Node


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.THEME
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func build() -> void:
	pass


func on_enter() -> void:
	pass


func get_default_focus() -> Control:
	return null


## Standard page: title at the top left, content column, used by most screens.
func make_page(page_title: String, subtitle := "") -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 72)
	margin.add_theme_constant_override(&"margin_top", 48)
	margin.add_theme_constant_override(&"margin_bottom", 40)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var column := UiKit.vbox(18)
	margin.add_child(column)
	var heading := UiKit.title(page_title, UiKit.SIZE_TITLE, UiKit.SUN)
	heading.add_theme_constant_override(&"outline_size", 12)
	heading.add_theme_color_override(&"font_outline_color", UiKit.INK)
	column.add_child(heading)
	if not subtitle.is_empty():
		column.add_child(UiKit.label(subtitle, UiKit.SIZE_BODY, UiKit.TEXT, 8))
	return column


## Bottom-left Back button.
func make_back_button(parent: Control, text := "Back") -> Button:
	var back := UiKit.button(text, "quiet", 180)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(func() -> void: back_requested.emit())
	parent.add_child(back)
	return back


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()
