class_name ResultsScreen
extends RaceMenuBase
## End-of-race results: every racer's place, name and finishing time (DNF if
## the finish timeout ended their race), the race duration, and the Race
## Again / Return to Lobby actions.

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
	for entry in results:
		var is_local: bool = entry["id"] == local_id
		var color := RaceMenuBase.TITLE_COLOR if is_local else RaceMenuBase.TEXT_COLOR
		var place := RaceSession.ordinal(entry["position"])
		var player_name: String = entry["name"]
		var time := Hud.format_time(entry["time"]) if entry["finished"] else "DNF"
		for text in [place, player_name, time]:
			var cell := _label(text, 30, color)
			_rows.add_child(cell)
		row_texts.append("%s|%s|%s" % [place, player_name, time])
	_duration_label.text = "Race duration  %s" % Hud.format_time(race_duration)
	root.visible = true
	_again_button.grab_focus()


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
