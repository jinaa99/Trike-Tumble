class_name RaceMenuBase
extends CanvasLayer
## Shared look for the race's full-screen panels (lobby, results): dimmed
## background, centered themed panel, display-font title. Built in code from
## res://resources/ui/trike_theme.tres so the screens stay small.

const THEME := preload("res://resources/ui/trike_theme.tres")
const TITLE_COLOR := UiKit.SUN
const TEXT_COLOR := UiKit.TEXT
const DIM_TEXT_COLOR := UiKit.TEXT_DIM

var root: Control
var box: VBoxContainer


func _build_frame(title: String) -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = THEME
	add_child(root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.06, 0.04, 0.16, 0.6)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	box = VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 12)
	panel.add_child(box)
	var logo := _label("TRIKE TUMBLE", 18, TITLE_COLOR)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(logo)
	var heading := _label(title, 56, Color.WHITE)
	heading.add_theme_font_override(&"font", display_font())
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(heading)
	root.visible = false


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_constant_override(&"outline_size", 0)
	return label


func _button(text: String) -> Button:
	var button := UiKit.button(text, "normal", 300)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return button


func is_open() -> bool:
	return root != null and root.visible


static func display_font() -> Font:
	return UiKit.display_font()
