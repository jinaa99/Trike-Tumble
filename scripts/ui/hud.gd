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
var skill_label: Label
var skill_hint: Label
var skill_bar: ProgressBar
var skill_panel: PanelContainer
var draft_box: Control
var draft_bar: ProgressBar
var debug_label: Label
var _perfect_marks: Array[ColorRect] = []
var _drift_scale := 2.35
var _skills: SkillManager
var _skill_racer: Racer
var _skill_was_ready := false
var _skill_key := ""


func _ready() -> void:
	drift_meter.modulate.a = 0.0
	boost_label.visible = false
	message_label.visible = false
	prompt_panel.visible = false
	set_race_time(0.0)
	_build_state_chip()
	_build_item_slot()
	_build_skill_slot()
	_build_draft_meter()
	_build_debug_label()
	_refresh_keys()
	GameSettings.settings_changed.connect(_refresh_keys)
	_hint_tween = create_tween()
	_hint_tween.tween_interval(hint_visible_seconds)
	_hint_tween.tween_property(hint_panel, "modulate:a", 0.0, 1.2)


func set_vehicle(trike: Trike) -> void:
	_trike = trike
	var tiers := trike.config.drift_boost_tier_times
	# The bar runs to the end of the second PERFECT window.
	_drift_scale = tiers.y + trike.config.drift_perfect_window
	var ratio := clampf(tiers.x / _drift_scale, 0.0, 1.0)
	tier_mark.anchor_left = ratio
	tier_mark.anchor_right = ratio
	for mark in _perfect_marks:
		mark.queue_free()
	_perfect_marks.clear()
	# Bright bands: let go inside one for a PERFECT release.
	for start: float in [tiers.x, tiers.y]:
		var band := ColorRect.new()
		band.name = "PerfectBand"
		band.color = Color(1.0, 1.0, 1.0, 0.55)
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		band.anchor_left = clampf(start / _drift_scale, 0.0, 1.0)
		band.anchor_right = clampf((start + trike.config.drift_perfect_window) / _drift_scale, 0.0, 1.0)
		band.anchor_top = 0.0
		band.anchor_bottom = 1.0
		drift_bar.add_child(band)
		_perfect_marks.append(band)


## The local racer's signature skill (name, key, cooldown) and slipstream.
func set_skills(skills: SkillManager, racer: Racer) -> void:
	_skills = skills
	_skill_racer = racer
	if racer == null:
		skill_panel.visible = false
		return
	var kind := racer.get_skill()
	skill_label.text = SkillKind.display_name(kind)
	skill_label.modulate = SkillKind.color_of(kind).lerp(Color.WHITE, 0.25)
	skill_panel.visible = true
	_refresh_keys()


func get_skill_text() -> String:
	return skill_label.text


func get_skill_hint_text() -> String:
	return skill_hint.text


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


## Held item ("" = empty) in its item color; a new item pops in.
func set_item(item_name: String, color := Color.WHITE) -> void:
	var is_new := not item_name.is_empty() and item_name != _item_name
	_item_name = item_name
	item_label.text = item_name if not item_name.is_empty() else "EMPTY"
	# Lightened so dark item colors (mud) stay readable on the panel.
	item_label.modulate = Color(color.lerp(Color.WHITE, 0.35), 1.0) if not item_name.is_empty() else Color(1, 1, 1, 0.55)
	item_hint.modulate.a = 1.0 if not item_name.is_empty() else 0.45
	if is_new and is_inside_tree():
		var panel := item_label.get_parent().get_parent() as Control
		panel.pivot_offset = panel.size * 0.5
		panel.scale = Vector2.ONE * 1.25
		create_tween().tween_property(panel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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
	var panel := UiKit.panel(10)
	panel.name = "ItemPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.position = Vector2(30, -30)
	$Root.add_child(panel)
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 20
	panel.offset_bottom = -18
	var box := UiKit.vbox(0)
	panel.add_child(box)
	box.add_child(UiKit.label("ITEM", 12, UiKit.SUN))
	item_label = UiKit.title("EMPTY", 22)
	item_label.custom_minimum_size = Vector2(124, 0)
	box.add_child(item_label)
	item_hint = UiKit.label("", 12, UiKit.TEXT)
	box.add_child(item_hint)
	set_item("")


func _build_skill_slot() -> void:
	skill_panel = UiKit.panel(10)
	skill_panel.name = "SkillPanel"
	skill_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skill_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	skill_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	$Root.add_child(skill_panel)
	skill_panel.anchor_top = 1.0
	skill_panel.anchor_bottom = 1.0
	skill_panel.offset_left = 184
	skill_panel.offset_bottom = -18
	var box := UiKit.vbox(0)
	skill_panel.add_child(box)
	box.add_child(UiKit.label("SKILL", 12, UiKit.SKY))
	skill_label = UiKit.title("", 22)
	skill_label.custom_minimum_size = Vector2(150, 0)
	box.add_child(skill_label)
	skill_bar = ProgressBar.new()
	skill_bar.name = "SkillBar"
	skill_bar.min_value = 0.0
	skill_bar.max_value = 1.0
	skill_bar.show_percentage = false
	skill_bar.custom_minimum_size = Vector2(150, 6)
	box.add_child(skill_bar)
	skill_hint = UiKit.label("", 12, UiKit.TEXT)
	box.add_child(skill_hint)
	skill_panel.visible = false


func _build_draft_meter() -> void:
	var box := UiKit.vbox(2)
	box.name = "DraftMeter"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.position.y = 64
	var title := UiKit.label("SLIPSTREAM", 14, UiKit.SKY, 4)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	draft_bar = ProgressBar.new()
	draft_bar.min_value = 0.0
	draft_bar.max_value = 1.0
	draft_bar.show_percentage = false
	draft_bar.custom_minimum_size = Vector2(160, 8)
	draft_bar.self_modulate = UiKit.SKY
	box.add_child(draft_bar)
	box.modulate.a = 0.0
	$Root.add_child(box)
	draft_box = box


func _build_debug_label() -> void:
	debug_label = UiKit.label("", 14, UiKit.CREAM, 4)
	debug_label.name = "SurfaceDebug"
	debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_label.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	debug_label.position = Vector2(24, -40)
	debug_label.visible = false
	$Root.add_child(debug_label)


func _update_skill(delta: float) -> void:
	if _skills == null or _skill_racer == null:
		return
	var id := _skill_racer.id
	var ready := _skills.is_ready(id)
	var left := _skills.get_cooldown(id)
	skill_bar.value = 1.0 - _skills.get_cooldown_ratio(id) if _skills.cooldowns.has(id) else (1.0 if ready else 0.0)
	skill_bar.self_modulate = UiKit.MINT if ready else UiKit.TEXT_DIM
	if _skills.has_shield(id):
		skill_hint.text = "SHIELD UP"
	elif ready:
		skill_hint.text = "[%s] READY" % _skill_key
	elif left > 0.0:
		skill_hint.text = "%d s" % ceili(left)
	else:
		skill_hint.text = "[%s]" % _skill_key
	skill_label.modulate.a = 1.0 if ready else 0.5
	if ready and not _skill_was_ready and is_inside_tree():
		skill_panel.pivot_offset = skill_panel.size * 0.5
		skill_panel.scale = Vector2.ONE * 1.18
		create_tween().tween_property(skill_panel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_skill_was_ready = ready
	var meter := _skills.get_draft(id)
	draft_bar.value = meter
	draft_bar.self_modulate = UiKit.SUN if meter >= 0.999 else UiKit.SKY
	draft_box.modulate.a = move_toward(draft_box.modulate.a, 1.0 if meter > 0.05 else 0.0, delta * 5.0)


func _refresh_keys() -> void:
	_skill_key = UiKit.key_name(GameSettings.primary_key(&"use_skill"))
	var steer := "%s %s" % [UiKit.key_name(GameSettings.primary_key(&"steer_left")),
			UiKit.key_name(GameSettings.primary_key(&"steer_right"))]
	hint_label.text = "%s   Accelerate      %s   Brake\n%s   Steer\n%s + steer   Drift, release to BOOST\n%s   Skill      %s   Item      %s   Taunt\n%s   Trick in the air\n%s   Reset        %s   Pause" % [
		UiKit.action_keys(&"accelerate"), UiKit.action_keys(&"brake"), steer,
		UiKit.action_keys(&"drift"), UiKit.action_keys(&"use_skill"), UiKit.action_keys(&"use_item"),
		UiKit.action_keys(&"emote"), UiKit.action_keys(&"trick"),
		UiKit.action_keys(&"reset"), UiKit.action_keys(&"pause")]
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
		drift_bar.value = clampf(_trike.drift_charge / _drift_scale, 0.0, 1.0)
		drift_bar.self_modulate = DRIFT_COLORS[tier]
		var perfect := _trike.is_in_perfect_window()
		drift_title.text = "RELEASE NOW!" if perfect else DRIFT_TITLES[tier]
		for mark in _perfect_marks:
			mark.color.a = 0.95 if perfect and sin(_time * 30.0) > 0.0 else 0.55
		drift_title.add_theme_color_override("font_color", DRIFT_COLORS[tier])

	_update_skill(delta)
	debug_label.visible = GameSettings.surface_debug
	if debug_label.visible:
		debug_label.text = _trike.format_surface_report()
	boost_label.visible = _trike.boost_time > 0.0
	if boost_label.visible:
		boost_label.scale = Vector2.ONE * (1.0 + sin(_time * 18.0) * 0.06)
