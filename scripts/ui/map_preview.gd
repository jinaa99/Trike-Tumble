class_name MapPreview
extends Control
## A map's preview image. Until the map is finished (no preview texture), it
## draws a clearly labelled placeholder from the map's theme colors instead
## of a fake screenshot.

var map: MapInfo:
	set(value):
		map = value
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(320, 170)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_placeholder() -> bool:
	return map == null or map.preview == null


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if map and map.preview:
		draw_texture_rect(map.preview, rect, false)
		return
	var colors: Array[Color] = map.theme_colors if map else [Color.GRAY, Color.DIM_GRAY, Color.DARK_GRAY, Color.WHITE]
	var w := size.x
	var h := size.y
	draw_rect(rect, colors[0])
	# Far hills, near ground and a winding road: an abstract, not a screenshot.
	draw_colored_polygon(PackedVector2Array([Vector2(0, h * 0.62), Vector2(w * 0.18, h * 0.3), Vector2(w * 0.36, h * 0.55),
			Vector2(w * 0.58, h * 0.22), Vector2(w * 0.8, h * 0.5), Vector2(w, h * 0.34), Vector2(w, h), Vector2(0, h)]), colors[1])
	draw_colored_polygon(PackedVector2Array([Vector2(0, h * 0.7), Vector2(w * 0.4, h * 0.62), Vector2(w, h * 0.72),
			Vector2(w, h), Vector2(0, h)]), colors[2])
	draw_colored_polygon(PackedVector2Array([Vector2(w * 0.47, h * 0.64), Vector2(w * 0.53, h * 0.64),
			Vector2(w * 0.7, h), Vector2(w * 0.3, h)]), colors[3])
	draw_rect(rect, Color(0, 0, 0, 0.18))
	var font := get_theme_default_font()
	var text := "PREVIEW PLACEHOLDER"
	var font_size := 14
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var box := Rect2(Vector2((w - text_size.x) * 0.5 - 10, h * 0.42 - 16), Vector2(text_size.x + 20, 26))
	draw_rect(box, Color(UiKit.INK, 0.8))
	draw_string(font, Vector2(box.position.x + 10, box.position.y + 18), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
