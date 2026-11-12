class_name ResultsScreen
extends RaceMenuBase
## End-of-race results: every racer's place, name and finishing time (DNF if
## the finish timeout ended their race), the race duration, and the Race
## Again / Return to Lobby actions.

## Place colors for the podium (gold, silver, bronze).
const MEDALS: Array[Color] = [Color(1.0, 0.8, 0.2), Color(0.82, 0.86, 0.92), Color(0.86, 0.55, 0.3)]
## Seconds between rows popping in.
const ROW_DELAY := 0.12

signal race_again_pressed
signal lobby_pressed

var _rows: GridContainer
var _duration_label: Label
var _again_button: Button
var _lobby_button: Button
## Text of each row as shown: "1st|Pip|00:49.50" (tests, debugging).
var row_texts: Array[String] = []


func _ready() -> void:
	layer = 8
	_build_frame("RESULTS")
	_rows = GridContainer.new()
	_rows.columns = 3
	_rows.add_theme_constant_override(&"h_separation", 36)
	_rows.add_theme_constant_override(&"v_separation", 6)
	_rows.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_rows)
	_duration_label = _label("", 18, RaceMenuBase.DIM_TEXT_COLOR)
	_duration_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_duration_label)
	_again_button = _button("Race Again")
	_lobby_button = _button("Return to Lobby")
	box.add_child(_again_button)
	box.add_child(_lobby_button)
	_again_button.pressed.connect(func() -> void: race_again_pressed.emit())
	_lobby_button.pressed.connect(func() -> void: lobby_pressed.emit())


## results: RaceController.build_results() entries.
func show_results(results: Array[Dictionary], race_duration: float, local_id: int) -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	row_texts.clear()
	for row in results.size():
		var entry: Dictionary = results[row]
		var is_local: bool = entry["id"] == local_id
		var color := RaceMenuBase.TITLE_COLOR if is_local else RaceMenuBase.TEXT_COLOR
		var place := RaceSession.ordinal(entry["position"])
		var player_name: String = entry["name"]
		var time := Hud.format_time(entry["time"]) if entry["finished"] else "DNF"
		var texts := [place, player_name, time]
		for k in texts.size():
			var cell_color := color
			if k == 0 and entry["finished"] and int(entry["position"]) <= MEDALS.size():
				cell_color = MEDALS[int(entry["position"]) - 1]
			var cell := _label(texts[k], 30, cell_color)
			_rows.add_child(cell)
			_pop_in(cell, row * ROW_DELAY)
		row_texts.append("%s|%s|%s" % [place, player_name, time])
	_duration_label.text = "Race duration  %s" % Hud.format_time(race_duration)
	root.visible = true
	_again_button.grab_focus()


## Fades and slides a cell in after `delay` seconds.
func _pop_in(cell: Control, delay: float) -> void:
	cell.modulate.a = 0.0
	var tween := cell.create_tween()
	tween.tween_interval(delay)
	tween.tween_property(cell, "modulate:a", 1.0, 0.25)


## Online: only the host decides Race Again; clients can leave.
func set_online(is_host: bool) -> void:
	if not is_host:
		_again_button.disabled = true
		_again_button.text = "Host decides…"
		_lobby_button.text = "Leave Game"


func hide_results() -> void:
	root.visible = false


func press_race_again() -> void:
	_again_button.pressed.emit()


func press_return_to_lobby() -> void:
	_lobby_button.pressed.emit()
