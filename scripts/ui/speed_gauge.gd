@tool
class_name SpeedGauge
extends Control
## Arcade speedometer arc. Fill runs teal -> yellow -> orange with speed and
## glows hot pink-orange while boosting. Pure drawing, no game logic.

@export_range(0.0, 1.0) var value := 0.0:
	set(v):
		value = clampf(v, 0.0, 1.0)
		queue_redraw()
@export var boosting := false:
	set(v):
		boosting = v
		queue_redraw()
@export var arc_width := 16.0
@export var start_angle_deg := 140.0
@export var sweep_deg := 260.0
@export var track_color := Color(0.1, 0.08, 0.22, 0.55)
@export var fill_gradient: Gradient
@export var boost_color := Color(1.0, 0.42, 0.35)
@export var tick_color := Color(1, 1, 1, 0.75)

const SEGMENTS := 60


func _draw() -> void:
	var center := Vector2(size.x * 0.5, size.y * 0.56)
	var radius := minf(size.x, size.y * 1.15) * 0.42
	var a0 := deg_to_rad(start_angle_deg)
	var sweep := deg_to_rad(sweep_deg)
	draw_arc(center, radius, a0, a0 + sweep, 72, track_color, arc_width + 8.0, true)
	var filled := int(round(value * SEGMENTS))
	for i in filled:
		var t := float(i) / SEGMENTS
		var color := boost_color if boosting else _gradient_color(t)
		var from := a0 + sweep * t
		var to := a0 + sweep * (float(i + 1) / SEGMENTS) + 0.01
		draw_arc(center, radius, from, to, 3, color, arc_width, true)
	for k in 9:
		var angle := a0 + sweep * k / 8.0
		var dir := Vector2(cos(angle), sin(angle))
		var inner := radius - arc_width * 0.5 - 10.0
		var length := 8.0 if k % 2 == 0 else 4.0
		draw_line(center + dir * inner, center + dir * (inner - length), tick_color, 3.0, true)


func _gradient_color(t: float) -> Color:
	if fill_gradient:
		return fill_gradient.sample(t)
	return Color(0.2, 0.85, 0.8).lerp(Color(1.0, 0.8, 0.2), t)
