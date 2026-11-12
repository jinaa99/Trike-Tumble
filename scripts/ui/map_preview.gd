class_name MapPreview
extends Control
## A map's preview. With a `preview` texture it shows that. Otherwise, for a
## map with a track, it draws a top-down ROUTE MAP from the track scene's own
## data (route segments and zones, read from the saved scene without building
## it): the course shaded from the top (light) to the bottom (map accent),
## start and finish, bridges, jumps, ice, mud, cliff walls, wind, and the
## real length and drop. A map without a track gets a clearly labelled
## placeholder. Never a fake screenshot.

const MARGIN := 16.0

## Route data per track scene path: {"points": PackedVector3Array, "step",
## "zones", "length", "drop"} (built once, shared by all cards).
static var _routes := {}

var map: MapInfo:
	set(value):
		map = value
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(320, 170)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_placeholder() -> bool:
	return map == null or (map.preview == null and get_route().is_empty())


## True when the preview is a route map drawn from the track data.
func is_route_map() -> bool:
	return map != null and map.preview == null and not get_route().is_empty()


## The map's route (see `_routes`), or {} without a track scene.
func get_route() -> Dictionary:
	if map == null or map.track_scene.is_empty():
		return {}
	if not _routes.has(map.track_scene):
		_routes[map.track_scene] = load_route(map.track_scene)
	return _routes[map.track_scene]


## Reads a Track scene's route data from its saved state (no instancing).
static func load_route(path: String) -> Dictionary:
	var scene := load(path) as PackedScene
	if scene == null:
		return {}
	var state := scene.get_state()
	var values := {"route_start": Vector3.ZERO, "route_heading_deg": 0.0, "route_step": 8.0,
			"route_segments": PackedVector3Array(), "zones": []}
	for i in state.get_node_property_count(0):
		var property := String(state.get_node_property_name(0, i))
		if values.has(property):
			values[property] = state.get_node_property_value(0, i)
	var segments: PackedVector3Array = values["route_segments"]
	if segments.is_empty():
		return {}
	var points := TrackRoute.build_points(values["route_start"], values["route_heading_deg"], segments, values["route_step"])
	return {"points": points, "step": TrackRoute.total_length(segments) / maxf(points.size() - 1, 1.0),
			"zones": values["zones"], "length": TrackRoute.total_length(segments), "drop": points[0].y - points[-1].y}


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if map and map.preview:
		draw_texture_rect(map.preview, rect, false)
		return
	var colors: Array[Color] = map.theme_colors if map else [Color.GRAY, Color.DIM_GRAY, Color.DARK_GRAY, Color.WHITE]
	var route := get_route()
	if route.is_empty():
		_draw_placeholder(rect, colors)
		return
	_draw_route(rect, colors, route)


func _draw_route(rect: Rect2, colors: Array[Color], route: Dictionary) -> void:
	draw_rect(rect, colors[2].darkened(0.45))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.5)), Color(colors[1], 0.18))
	var points: PackedVector3Array = route["points"]
	var screen := _project(points, rect)
	var top := points[0].y
	var drop := maxf(float(route["drop"]), 1.0)
	var step: float = route["step"]
	# Outline, then the course shaded by height.
	draw_polyline(screen, Color(UiKit.INK, 0.85), 7.0, true)
	for i in screen.size() - 1:
		var k := clampf((top - points[i].y) / drop, 0.0, 1.0)
		draw_line(screen[i], screen[i + 1], Color(1.0, 0.97, 0.88).lerp(colors[3], k), 3.5, true)
	for zone: Array in route["zones"]:
		var first := clampi(roundi(float(zone[0]) / step), 0, screen.size() - 1)
		var last := clampi(roundi(float(zone[1]) / step), 0, screen.size() - 1)
		match String(zone[2]):
			"bridge":
				_draw_stretch(screen, first, last, Color(0.62, 0.4, 0.22), 6.0)
			"ice":
				_draw_stretch(screen, first, last, Color(0.62, 0.9, 1.0), 6.0)
			"mud":
				_draw_stretch(screen, first, last, Color(0.36, 0.22, 0.12), 6.0)
			"cliff":
				_draw_side(screen, first, last, int(zone[3]), Color(0.45, 0.2, 0.16))
			"wind":
				_draw_wind(screen, first, last)
			"gap":
				draw_circle(screen[first], 6.5, Color(UiKit.INK, 0.9))
				draw_circle(screen[first], 4.5, Color(1.0, 0.82, 0.2))
	_draw_flag(screen[0], UiKit.MINT, false)
	_draw_flag(screen[-1], Color.WHITE, true)
	var font := get_theme_default_font()
	var text := "ROUTE MAP  ·  %.1f km  ·  %d m drop" % [float(route["length"]) / 1000.0, roundi(float(route["drop"]))]
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	var box := Rect2(Vector2(6, rect.size.y - 24), Vector2(text_size.x + 14, 19))
	draw_rect(box, Color(UiKit.INK, 0.8))
	draw_string(font, box.position + Vector2(7, 14), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)


## Top-down projection fitted into the rect; turned 90° if the route is taller
## than it is wide (cards are landscape).
func _project(points: PackedVector3Array, rect: Rect2) -> PackedVector2Array:
	var flat := PackedVector2Array()
	for p in points:
		flat.append(Vector2(p.x, p.z))
	var bounds := Rect2(flat[0], Vector2.ZERO)
	for p in flat:
		bounds = bounds.expand(p)
	if bounds.size.y > bounds.size.x:
		for i in flat.size():
			flat[i] = Vector2(-flat[i].y, flat[i].x)
		bounds = Rect2(flat[0], Vector2.ZERO)
		for p in flat:
			bounds = bounds.expand(p)
	var area := rect.grow(-MARGIN)
	area.size.y -= 18.0  # room for the caption
	var scale := minf(area.size.x / maxf(bounds.size.x, 1.0), area.size.y / maxf(bounds.size.y, 1.0))
	var offset := area.position + (area.size - bounds.size * scale) * 0.5
	var out := PackedVector2Array()
	for p in flat:
		out.append(offset + (p - bounds.position) * scale)
	return out


func _draw_stretch(screen: PackedVector2Array, first: int, last: int, color: Color, width: float) -> void:
	if last > first:
		draw_polyline(screen.slice(first, last + 1), color, width, true)


## A dark edge on one side of the course (cliff walls).
func _draw_side(screen: PackedVector2Array, first: int, last: int, side: int, color: Color) -> void:
	var edge := PackedVector2Array()
	for i in range(first, last + 1):
		var a := screen[maxi(i - 1, 0)]
		var b := screen[mini(i + 1, screen.size() - 1)]
		var normal := (b - a).orthogonal().normalized()
		# Screen y points down, so "right of travel" is +orthogonal.
		edge.append(screen[i] - normal * 4.5 * float(side))
	if edge.size() > 1:
		draw_polyline(edge, color, 2.5, true)


func _draw_wind(screen: PackedVector2Array, first: int, last: int) -> void:
	for i in range(first, last + 1, maxi((last - first) >> 2, 1)):
		var a := screen[maxi(i - 1, 0)]
		var b := screen[mini(i + 1, screen.size() - 1)]
		var across := (b - a).orthogonal().normalized() * 7.0
		var tip := screen[i] + across
		draw_line(screen[i] - across, tip, Color(0.85, 0.95, 1.0), 1.5, true)
		draw_line(tip, tip - across.rotated(0.5) * 0.5, Color(0.85, 0.95, 1.0), 1.5, true)


func _draw_flag(at: Vector2, color: Color, checkered: bool) -> void:
	draw_circle(at, 7.0, UiKit.INK)
	if checkered:
		for k in 4:
			var cell := Rect2(at + Vector2(-4 + (k % 2) * 4, -4 + (k >> 1) * 4), Vector2(4, 4))
			draw_rect(cell, Color.WHITE if (k % 2) == (k >> 1) else Color.BLACK)
	else:
		draw_circle(at, 4.5, color)


func _draw_placeholder(rect: Rect2, colors: Array[Color]) -> void:
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
