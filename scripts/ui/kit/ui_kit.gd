class_name UiKit
extends RefCounted
## Trike Tumble design system: palette, type scale, and factories for the
## shared controls (buttons with hover/press motion, labels, panels, fades).
## Every menu, the pause menu, results and lobby are built from these so they
## look and move the same. Visual base: res://resources/ui/trike_theme.tres.

const THEME := preload("res://resources/ui/trike_theme.tres")

# Palette
const INK := Color(0.14, 0.11, 0.3)          ## deep purple: panels, text on light
const INK_SOFT := Color(0.14, 0.12, 0.3, 0.9)
const CREAM := Color(0.99, 0.97, 0.93)
const SUN := Color(1.0, 0.82, 0.22)          ## yellow: titles, highlights
const ORANGE := Color(1.0, 0.55, 0.18)       ## primary action
const SKY := Color(0.25, 0.8, 1.0)           ## focus / info
const MINT := Color(0.42, 0.9, 0.55)         ## ready / ok
const BERRY := Color(1.0, 0.38, 0.45)        ## error / not ready
const TEXT := Color(0.95, 0.94, 1.0)
const TEXT_DIM := Color(0.74, 0.72, 0.88)

# Type scale (px at 1280×720; canvas_items stretch scales it up)
const SIZE_HERO := 96
const SIZE_TITLE := 52
const SIZE_HEADING := 30
const SIZE_BODY := 22
const SIZE_SMALL := 16

const HOVER_SCALE := 1.05
const PRESS_SCALE := 0.96
const MOTION_TIME := 0.12
const SCREEN_FADE_TIME := 0.22

static var _display_font: Font


## Rounded heavy italic used for logos, titles and big numbers.
static func display_font() -> Font:
	if _display_font == null:
		var base := SystemFont.new()
		base.font_names = PackedStringArray(["Arial Rounded MT Bold", "Segoe UI Black", "Arial Black", "Arial"])
		base.font_weight = 900
		var font := FontVariation.new()
		font.base_font = base
		font.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.22, 1), Vector2.ZERO)
		_display_font = font
	return _display_font


static func label(text: String, size := SIZE_BODY, color := TEXT, outline := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	l.add_theme_constant_override(&"outline_size", outline)
	return l


static func title(text: String, size := SIZE_TITLE, color := Color.WHITE) -> Label:
	var l := label(text, size, color, 0)
	l.add_theme_font_override(&"font", display_font())
	return l


## kind: "primary" (orange), "normal" (cream), "quiet" (outlined, for Back).
static func button(text: String, kind := "normal", min_width := 300.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 56)
	b.focus_mode = Control.FOCUS_ALL
	if kind == "primary":
		b.add_theme_stylebox_override(&"normal", _box(ORANGE, Color(0.82, 0.36, 0.08)))
		b.add_theme_color_override(&"font_color", Color.WHITE)
		b.add_theme_color_override(&"font_focus_color", Color.WHITE)
		b.add_theme_font_size_override(&"font_size", 30)
	elif kind == "quiet":
		var quiet := _box(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.25))
		quiet.border_width_left = 2
		quiet.border_width_top = 2
		quiet.border_width_right = 2
		quiet.border_width_bottom = 2
		b.add_theme_stylebox_override(&"normal", quiet)
		b.add_theme_color_override(&"font_color", TEXT)
		b.add_theme_color_override(&"font_focus_color", TEXT)
		b.add_theme_font_size_override(&"font_size", SIZE_BODY)
		b.custom_minimum_size.y = 48
	add_motion(b)
	return b


static func _box(fill: Color, edge: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.border_width_bottom = 6
	box.set_corner_radius_all(16)
	box.content_margin_left = 28
	box.content_margin_right = 28
	box.content_margin_top = 10
	box.content_margin_bottom = 14
	return box


## Hover/focus grows the control a little, press squishes it.
static func add_motion(control: Control) -> void:
	control.resized.connect(func() -> void: control.pivot_offset = control.size * 0.5)
	var grow := func() -> void: _scale_to(control, HOVER_SCALE)
	var shrink := func() -> void:
		if not control.has_focus():
			_scale_to(control, 1.0)
	control.mouse_entered.connect(grow)
	control.focus_entered.connect(grow)
	control.mouse_exited.connect(shrink)
	control.focus_exited.connect(func() -> void: _scale_to(control, 1.0))
	if control is BaseButton:
		(control as BaseButton).button_down.connect(func() -> void: _scale_to(control, PRESS_SCALE))
		(control as BaseButton).button_up.connect(grow)


static func _scale_to(control: Control, value: float) -> void:
	if not control.is_inside_tree():
		return
	var tween := control.create_tween()
	tween.tween_property(control, "scale", Vector2.ONE * value, MOTION_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Dark rounded panel (the theme's PanelContainer look) with custom padding.
static func panel(padding := 28.0) -> PanelContainer:
	var p := PanelContainer.new()
	var box := (THEME.get_stylebox(&"panel", &"PanelContainer") as StyleBoxFlat).duplicate() as StyleBoxFlat
	box.content_margin_left = padding
	box.content_margin_right = padding
	box.content_margin_top = padding * 0.8
	box.content_margin_bottom = padding
	p.add_theme_stylebox_override(&"panel", box)
	return p


## Small rounded tag, e.g. HOST, READY.
static func chip(text: String, color: Color) -> Label:
	var l := label(text, SIZE_SMALL - 2, INK, 0)
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(9)
	box.content_margin_left = 9
	box.content_margin_right = 9
	box.content_margin_top = 1
	box.content_margin_bottom = 2
	l.add_theme_stylebox_override(&"normal", box)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


static func vbox(separation := 12) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override(&"separation", separation)
	return b


static func hbox(separation := 12) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override(&"separation", separation)
	return b


static func line_edit(placeholder: String, width := 300.0) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(width, 48)
	edit.add_theme_font_size_override(&"font_size", SIZE_BODY)
	var box := StyleBoxFlat.new()
	box.bg_color = CREAM
	box.set_corner_radius_all(12)
	box.content_margin_left = 14
	box.content_margin_right = 14
	var focus := box.duplicate() as StyleBoxFlat
	focus.border_color = SKY
	focus.set_border_width_all(3)
	edit.add_theme_stylebox_override(&"normal", box)
	edit.add_theme_stylebox_override(&"focus", focus)
	edit.add_theme_color_override(&"font_color", INK)
	edit.add_theme_color_override(&"font_placeholder_color", Color(INK, 0.45))
	edit.add_theme_color_override(&"caret_color", INK)
	return edit


## Fades/slides a control in (screens, overlays).
static func fade_in(control: Control, offset := Vector2(0, 18)) -> void:
	control.modulate.a = 0.0
	var target := control.position
	control.position = target + offset
	var tween := control.create_tween().set_parallel()
	tween.tween_property(control, "modulate:a", 1.0, SCREEN_FADE_TIME)
	tween.tween_property(control, "position", target, SCREEN_FADE_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# --- Key names for prompts and hints ------------------------------------------

const KEY_SYMBOLS := {
	KEY_UP: "↑", KEY_DOWN: "↓", KEY_LEFT: "←", KEY_RIGHT: "→",
	KEY_SPACE: "SPACE", KEY_ESCAPE: "ESC", KEY_ENTER: "ENTER", KEY_SHIFT: "SHIFT",
	KEY_CTRL: "CTRL", KEY_ALT: "ALT", KEY_TAB: "TAB", KEY_BACKSPACE: "BKSP",
}


static func key_name(physical: Key) -> String:
	if KEY_SYMBOLS.has(physical):
		return KEY_SYMBOLS[physical]
	# The keyboard layout lookup needs a real display (not headless).
	var keycode := KEY_NONE if DisplayServer.get_name() == "headless" \
			else DisplayServer.keyboard_get_keycode_from_physical(physical)
	var text := OS.get_keycode_string(keycode if keycode != KEY_NONE else physical)
	return text.to_upper() if not text.is_empty() else "?"


## Every keyboard key bound to an action, e.g. "W / ↑".
static func action_keys(action: StringName) -> String:
	var names: Array[String] = []
	if InputMap.has_action(action):
		for event in InputMap.action_get_events(action):
			var key := event as InputEventKey
			if key:
				names.append(key_name(key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode))
	return " / ".join(names) if not names.is_empty() else "—"
