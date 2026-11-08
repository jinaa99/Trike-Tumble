class_name Hud
extends CanvasLayer
## In-race overlay: race timer, position + checkpoints, race state, speed
## gauge, drift meter, boost callout, held item slot with its use hint, the
## mount prompt, pop-up messages and a controls hint that fades away. Key
## names come from the current bindings. Only reads state, never changes
## gameplay.

const DRIFT_COLORS: Array[Color] = [
	Color(0.98, 0.95, 0.88), Color(0.35, 0.78, 1.0), Color(1.0, 0.55, 0.15),
]
const DRIFT_TITLES: Array[String] = ["DRIFT", "DRIFT  ·  BOOST 1", "DRIFT  ·  BOOST 2!"]

## Speed (km/h) that fills the gauge.
@export var gauge_max_kmh := 110.0
@export var hint_visible_seconds := 9.0

var _trike: Trike
var _message_time := 0.0
var _time := 0.0
var _drift_alpha := 0.0
var _hint_tween: Tween

@onready var speed_label: Label = %SpeedLabel
@onready var timer_label: Label = %TimerLabel
@onready var speed_gauge: SpeedGauge = %SpeedGauge
@onready var drift_meter: Control = %DriftMeter
@onready var drift_bar: ProgressBar = %DriftBar
@onready var drift_title: Label = %DriftTitle
@onready var tier_mark: ColorRect = %TierMark1
@onready var boost_label: Label = %BoostLabel
@onready var message_label: Label = %MessageLabel
@onready var hint_panel: Control = %HintPanel
@onready var prompt_panel: Control = %PromptPanel
@onready var position_label: Label = %PositionLabel
@onready var position_title: Label = %PositionTitle
@onready var hint_label: Label = %HintLabel
@onready var prompt_key: Label = %PromptKey
var state_chip: Label
var item_label: Label
var item_hint: Label
var _item_name := ""


func _ready() -> void:
	drift_meter.modulate.a = 0.0
	boost_label.visible = false
	message_label.visible = false
	prompt_panel.visible = false
	set_race_time(0.0)
	_build_state_chip()
	_build_item_slot()
	_refresh_keys()
	GameSettings.settings_changed.connect(_refresh_keys)
	_hint_tween = create_tween()
	_hint_tween.tween_interval(hint_visible_seconds)
	_hint_tween.tween_property(hint_panel, "modulate:a", 0.0, 1.2)


func set_vehicle(trike: Trike) -> void:
	_trike = trike
	var tiers := trike.config.drift_boost_tier_times
	var ratio := clampf(tiers.x / tiers.y, 0.0, 1.0)
	tier_mark.anchor_left = ratio
	tier_mark.anchor_right = ratio


func set_race_time(seconds: float) -> void:
	timer_label.text = format_time(seconds)


## Race position "2nd / 5", checkpoint count and (while running) the finish
## timeout, e.g. "POSITION · CP 3/12 · ENDS 12".
func set_race_position(position: int, total: int, checkpoint := 0, checkpoint_total := 0, timeout_left := -1.0) -> void:
	position_label.text = "%s / %d" % [RaceSession.ordinal(position), total]
	var title := "POSITION"
	if checkpoint_total > 0:
		title += "  ·  CP %d/%d" % [checkpoint, checkpoint_total]
	if timeout_left >= 0.0:
		title += "  ·  ENDS %d" % ceili(timeout_left)
	position_title.text = title


func get_race_position_text() -> String:
	return position_label.text


## Countdown numbers and GO!: the big pop-up message, short-lived.
func show_countdown(text: String, duration := 0.9) -> void:
	show_message(text, duration)


func get_message_text() -> String:
	return message_label.text if message_label.visible else ""


func show_message(text: String, duration := 1.5) -> void:
	message_label.text = text
	message_label.visible = true
	message_label.modulate.a = 1.0
	message_label.scale = Vector2.ONE * 1.35
	var tween := create_tween()
	tween.tween_property(message_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_message_time = duration


## Interaction prompt ("[E] GET ON"). Pops in with a small bounce.
func set_mount_prompt(visible_now: bool) -> void:
	if prompt_panel.visible == visible_now:
		return
	prompt_panel.visible = visible_now
	if visible_now:
		prompt_panel.scale = Vector2.ONE * 0.6
		create_tween().tween_property(prompt_panel, "scale", Vector2.ONE, 0.2) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func is_mount_prompt_visible() -> bool:
	return prompt_panel.visible


## Race state chip at the top (GET READY, RACING, FINISHED, ...).
func set_race_state(text: String, color := UiKit.SUN) -> void:
	state_chip.text = text
	(state_chip.get_theme_stylebox(&"normal") as StyleBoxFlat).bg_color = color
	state_chip.visible = not text.is_empty()


func get_race_state_text() -> String:
	return state_chip.text if state_chip.visible else ""


## Held item ("" = empty). Items arrive in a later milestone; the slot and
## its key hint are ready for them.
func set_item(item_name: String) -> void:
	_item_name = item_name
	item_label.text = item_name if not item_name.is_empty() else "EMPTY"
	item_label.modulate.a = 1.0 if not item_name.is_empty() else 0.55
	item_hint.modulate.a = 1.0 if not item_name.is_empty() else 0.45


func get_item_text() -> String:
	return item_label.text


func get_item_hint_text() -> String:
	return item_hint.text


func get_hint_text() -> String:
	return hint_label.text


func get_prompt_key_text() -> String:
	return prompt_key.text


func _build_state_chip() -> void:
	state_chip = UiKit.chip("", UiKit.SUN)
	state_chip.add_theme_font_size_override(&"font_size", 18)
	var box := (state_chip.get_theme_stylebox(&"normal") as StyleBoxFlat).duplicate() as StyleBoxFlat
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 4
	box.content_margin_bottom = 5
	state_chip.add_theme_stylebox_override(&"normal", box)
	state_chip.set_anchors_preset(Control.PRESET_CENTER_TOP)
	state_chip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	state_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state_chip.position.y = 24
	state_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	state_chip.visible = false
	$Root.add_child(state_chip)


func _build_item_slot() -> void:
	var panel := UiKit.panel(14)
	panel.name = "ItemPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.position = Vector2(30, -30)
	$Root.add_child(panel)
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 30
	panel.offset_bottom = -26
	var box := UiKit.vbox(4)
	panel.add_child(box)
	box.add_child(UiKit.label("ITEM", UiKit.SIZE_SMALL, UiKit.SUN))
	item_label = UiKit.title("EMPTY", 26)
	item_label.custom_minimum_size = Vector2(150, 0)
	box.add_child(item_label)
	item_hint = UiKit.label("", UiKit.SIZE_SMALL, UiKit.TEXT)
	box.add_child(item_hint)
	set_item("")


func _refresh_keys() -> void:
	var steer := "%s %s" % [UiKit.key_name(GameSettings.primary_key(&"steer_left")),
			UiKit.key_name(GameSettings.primary_key(&"steer_right"))]
	hint_label.text = "%s   Accelerate      %s   Brake\n%s   Steer\n%s + steer   Drift, release to BOOST\n%s   Reset        %s   Pause" % [
		UiKit.action_keys(&"accelerate"), UiKit.action_keys(&"brake"), steer,
		UiKit.action_keys(&"drift"), UiKit.action_keys(&"reset"), UiKit.action_keys(&"pause")]
	prompt_key.text = UiKit.key_name(GameSettings.primary_key(&"interact"))
	item_hint.text = "[%s] USE ITEM" % UiKit.key_name(GameSettings.primary_key(&"use_item"))


func get_displayed_speed() -> int:
	return int(speed_label.text)


static func format_time(seconds: float) -> String:
	var minutes := int(seconds / 60.0)
	return "%02d:%05.2f" % [minutes, seconds - minutes * 60.0]


func _process(delta: float) -> void:
	_time += delta
	if _message_time > 0.0:
		_message_time -= delta
		if _message_time < 0.3:
			message_label.modulate.a = clampf(_message_time / 0.3, 0.0, 1.0)
		if _message_time <= 0.0:
			message_label.visible = false
	if _trike == null:
		return

	var kmh := _trike.linear_velocity.length() * 3.6
	speed_label.text = "%d" % roundi(kmh)
	speed_gauge.value = kmh / gauge_max_kmh
	speed_gauge.boosting = _trike.boost_time > 0.0

	# Drift meter fades in while drifting.
	_drift_alpha = move_toward(_drift_alpha, 1.0 if _trike.is_drifting else 0.0, delta * 6.0)
	drift_meter.modulate.a = _drift_alpha
	if _trike.is_drifting:
		var tier := _trike.get_drift_tier()
		drift_bar.value = clampf(_trike.drift_charge / _trike.config.drift_boost_tier_times.y, 0.0, 1.0)
		drift_bar.self_modulate = DRIFT_COLORS[tier]
		drift_title.text = DRIFT_TITLES[tier]
		drift_title.add_theme_color_override("font_color", DRIFT_COLORS[tier])

	boost_label.visible = _trike.boost_time > 0.0
	if boost_label.visible:
		boost_label.scale = Vector2.ONE * (1.0 + sin(_time * 18.0) * 0.06)
