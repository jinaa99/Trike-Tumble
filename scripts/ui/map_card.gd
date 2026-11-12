class_name MapCard
extends PanelContainer
## Selectable map card: preview (or placeholder), name, status, description
## and the map's gameplay characteristic. Unplayable maps show COMING SOON
## and can't be selected.

signal pressed

var map: MapInfo
var selected := false:
	set(value):
		selected = value
		_update_style()
var selectable := true

var _preview: MapPreview


func setup(info: MapInfo, compact := false) -> void:
	map = info
	selectable = map.is_playable()
	focus_mode = Control.FOCUS_ALL if selectable else Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if selectable else Control.CURSOR_ARROW
	custom_minimum_size = Vector2(340, 0)
	var column := UiKit.vbox(8)
	add_child(column)
	_preview = MapPreview.new()
	_preview.map = map
	if compact:
		_preview.custom_minimum_size = Vector2(300, 150)
	column.add_child(_preview)
	var name_row := UiKit.hbox(10)
	name_row.add_child(UiKit.title(map.display_name, UiKit.SIZE_HEADING))
	name_row.add_child(UiKit.chip(map.get_status_text(), UiKit.MINT if selectable else UiKit.TEXT_DIM))
	column.add_child(name_row)
	var feature := UiKit.label("★ " + map.characteristic, UiKit.SIZE_SMALL + 2, UiKit.SUN)
	feature.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Wrapping labels need a width, or they collapse to one word per line.
	feature.custom_minimum_size = Vector2(300, 0)
	column.add_child(feature)
	if not compact:
		var text := UiKit.label(map.description, UiKit.SIZE_SMALL, UiKit.TEXT_DIM)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(300, 0)
		column.add_child(text)
	if not selectable:
		modulate = Color(1, 1, 1, 0.62)
	else:
		UiKit.add_motion(self)
	_update_style()


func is_placeholder_preview() -> bool:
	return _preview.is_placeholder()


## True when the card shows a route map drawn from the map's track data.
func is_route_preview() -> bool:
	return _preview.is_route_map()


func _gui_input(event: InputEvent) -> void:
	if not selectable:
		return
	var click := event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	if click or event.is_action_pressed(&"ui_accept"):
		pressed.emit()
		accept_event()


func press() -> void:
	if selectable:
		pressed.emit()


func _update_style() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(UiKit.INK, 0.94)
	box.set_corner_radius_all(22)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 14
	box.content_margin_bottom = 16
	box.set_border_width_all(4 if selected else 2)
	box.border_color = UiKit.SUN if selected else Color(1, 1, 1, 0.14)
	box.shadow_color = Color(0, 0, 0, 0.3)
	box.shadow_size = 12
	add_theme_stylebox_override(&"panel", box)
