class_name Hud
extends CanvasLayer
## In-race overlay: race timer, speed gauge, drift meter, boost callout,
## short pop-up messages and a controls hint that fades away.
## Only reads vehicle state and never changes gameplay.

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


func _ready() -> void:
	drift_meter.modulate.a = 0.0
	boost_label.visible = false
	message_label.visible = false
	prompt_panel.visible = false
	set_race_time(0.0)
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
