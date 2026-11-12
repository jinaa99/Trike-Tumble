class_name SettingsPanel
extends MenuScreen
## Settings, used by the main menu and the pause menu. Every control edits
## GameSettings directly, which applies and saves immediately.
## Sections: Audio, Video, Controls, Player.

var sections := {}
var section_buttons := {}
var current_section := ""
var volume_sliders := {}
var resolution_option: OptionButton
var fullscreen_check: CheckButton
var quality_option: OptionButton
var name_edit: LineEdit
var key_buttons := {}
var controls_message: Label
var reset_controls_button: Button
var back_button: Button
## Action waiting for a key press (Controls), or &"".
var listening_action := &""


func build() -> void:
	var column := make_page("SETTINGS")
	var tabs := UiKit.hbox(10)
	column.add_child(tabs)
	var card := UiKit.panel(28)
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	card.custom_minimum_size = Vector2(760, 0)
	column.add_child(card)
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(700, 330)
	card.add_child(stack)
	for entry: Array in [["audio", "Audio"], ["video", "Video"], ["controls", "Controls"], ["player", "Player"]]:
		var tab := UiKit.button(entry[1], "normal", 150)
		tab.toggle_mode = true
		tab.pressed.connect(show_section.bind(entry[0]))
		tabs.add_child(tab)
		section_buttons[entry[0]] = tab
		var page := UiKit.vbox(14)
		page.set_anchors_preset(Control.PRESET_FULL_RECT)
		page.visible = false
		stack.add_child(page)
		sections[entry[0]] = page
	_build_audio(sections["audio"])
	_build_video(sections["video"])
	_build_controls(sections["controls"])
	_build_player(sections["player"])
	var footer := UiKit.hbox(16)
	column.add_child(footer)
	back_button = make_back_button(footer)
	footer.add_child(UiKit.label("Changes are saved automatically.", UiKit.SIZE_SMALL, UiKit.TEXT, 6))
	show_section("audio")


func on_enter() -> void:
	refresh()


func refresh() -> void:
	for bus: String in volume_sliders:
		var slider: HSlider = volume_sliders[bus]["slider"]
		slider.set_value_no_signal(_volume(bus) * 100.0)
		(volume_sliders[bus]["value"] as Label).text = "%d%%" % roundi(_volume(bus) * 100.0)
	resolution_option.select(GameSettings.resolution_index)
	resolution_option.disabled = GameSettings.fullscreen
	fullscreen_check.set_pressed_no_signal(GameSettings.fullscreen)
	quality_option.select(GameSettings.quality)
	name_edit.text = GameSettings.player_name
	for action: StringName in key_buttons:
		(key_buttons[action] as Button).text = "Press a key…" if action == listening_action else UiKit.action_keys(action)


func show_section(section: String) -> void:
	current_section = section
	for key: String in sections:
		(sections[key] as Control).visible = key == section
		(section_buttons[key] as Button).set_pressed_no_signal(key == section)
	cancel_listening()


func _row(page: Control, text: String, control: Control) -> HBoxContainer:
	var row := UiKit.hbox(20)
	var caption := UiKit.label(text, UiKit.SIZE_BODY, UiKit.TEXT)
	caption.custom_minimum_size = Vector2(230, 0)
	row.add_child(caption)
	row.add_child(control)
	page.add_child(row)
	return row


func _build_audio(page: Control) -> void:
	for entry: Array in [["Master", "Master volume"], ["Music", "Music volume"], ["SFX", "Sound effects"], ["UI", "Menu sounds"]]:
		var bus: String = entry[0]
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 5
		slider.custom_minimum_size = Vector2(320, 32)
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var value := UiKit.label("", UiKit.SIZE_BODY, UiKit.SUN)
		value.custom_minimum_size = Vector2(70, 0)
		slider.value_changed.connect(func(v: float) -> void:
			GameSettings.set_volume(bus, v / 100.0)
			value.text = "%d%%" % roundi(v))
		var holder := UiKit.hbox(14)
		holder.add_child(slider)
		holder.add_child(value)
		_row(page, entry[1], holder)
		volume_sliders[bus] = {"slider": slider, "value": value}
	page.add_child(UiKit.label("Engine, surface, rider and item sounds are CC0 recordings. Music: two CC0 loops (credits in the README).",
			UiKit.SIZE_SMALL, UiKit.TEXT_DIM))


func _build_video(page: Control) -> void:
	resolution_option = OptionButton.new()
	for size in GameSettings.RESOLUTIONS:
		resolution_option.add_item("%d × %d" % [size.x, size.y])
	resolution_option.custom_minimum_size = Vector2(260, 48)
	resolution_option.item_selected.connect(func(index: int) -> void: GameSettings.set_resolution_index(index))
	_row(page, "Resolution", resolution_option)
	fullscreen_check = CheckButton.new()
	fullscreen_check.toggled.connect(func(on: bool) -> void:
		GameSettings.set_fullscreen(on)
		resolution_option.disabled = on)
	_row(page, "Fullscreen", fullscreen_check)
	quality_option = OptionButton.new()
	for quality_name in GameSettings.QUALITY_NAMES:
		quality_option.add_item(quality_name)
	quality_option.custom_minimum_size = Vector2(260, 48)
	quality_option.item_selected.connect(func(index: int) -> void: GameSettings.set_quality(index as GameSettings.Quality))
	_row(page, "Graphics quality", quality_option)
	page.add_child(UiKit.label("Low: no shadows, lower 3D resolution, no anti-aliasing. High: 4× anti-aliasing.",
			UiKit.SIZE_SMALL, UiKit.TEXT_DIM))


func _build_controls(page: Control) -> void:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override(&"h_separation", 18)
	grid.add_theme_constant_override(&"v_separation", 6)
	page.add_child(grid)
	for action in GameSettings.REBINDABLE:
		grid.add_child(UiKit.label(GameSettings.ACTION_LABELS[action], UiKit.SIZE_SMALL + 2, UiKit.TEXT))
		var key := Button.new()
		key.custom_minimum_size = Vector2(150, 36)
		key.add_theme_font_size_override(&"font_size", UiKit.SIZE_SMALL + 2)
		key.pressed.connect(start_listening.bind(action))
		key.name = "Key_" + String(action)
		grid.add_child(key)
		key_buttons[action] = key
	controls_message = UiKit.label("Click a key to change it, then press the new key (ESC cancels).",
			UiKit.SIZE_SMALL, UiKit.TEXT_DIM)
	page.add_child(controls_message)
	reset_controls_button = UiKit.button("Reset Controls", "normal", 240)
	reset_controls_button.pressed.connect(func() -> void:
		GameSettings.reset_controls()
		controls_message.text = "Controls reset to the defaults."
		refresh())
	page.add_child(reset_controls_button)


func _build_player(page: Control) -> void:
	name_edit = UiKit.line_edit("Your name", 320)
	name_edit.max_length = GameSettings.MAX_NAME_LENGTH
	name_edit.text_changed.connect(func(text: String) -> void: GameSettings.set_player_name(text))
	_row(page, "Player name", name_edit)
	page.add_child(UiKit.label("Shown in lobbies and on the results screen.", UiKit.SIZE_SMALL, UiKit.TEXT_DIM))


func start_listening(action: StringName) -> void:
	listening_action = action
	controls_message.text = "Press a key for %s…" % GameSettings.ACTION_LABELS[action]
	controls_message.add_theme_color_override(&"font_color", UiKit.SKY)
	refresh()


func cancel_listening() -> void:
	if listening_action == &"":
		return
	listening_action = &""
	controls_message.add_theme_color_override(&"font_color", UiKit.TEXT_DIM)
	refresh()


## Assigns `physical` to the listening action (or reports the conflict).
func assign_key(physical: Key) -> void:
	var action := listening_action
	listening_action = &""
	var taken := GameSettings.rebind(action, physical)
	if taken == &"":
		controls_message.text = "%s is now %s." % [GameSettings.ACTION_LABELS[action], UiKit.key_name(physical)]
		controls_message.add_theme_color_override(&"font_color", UiKit.MINT)
	else:
		controls_message.text = "%s is already used for %s." % [UiKit.key_name(physical), GameSettings.ACTION_LABELS[taken]]
		controls_message.add_theme_color_override(&"font_color", UiKit.BERRY)
	refresh()


func _input(event: InputEvent) -> void:
	if listening_action == &"" or not visible:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()
	var physical := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	if physical == KEY_ESCAPE and listening_action != &"pause":
		cancel_listening()
		controls_message.text = "Cancelled."
		return
	assign_key(physical)


func _unhandled_input(event: InputEvent) -> void:
	if listening_action == &"":
		super(event)


static func _volume(bus: String) -> float:
	match bus:
		"Music":
			return GameSettings.music_volume
		"SFX":
			return GameSettings.sfx_volume
		"UI":
			return GameSettings.ui_volume
	return GameSettings.master_volume


func get_default_focus() -> Control:
	return section_buttons["audio"]
