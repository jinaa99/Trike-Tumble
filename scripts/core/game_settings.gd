extends Node
## Autoload "GameSettings": player settings, saved to user://settings.cfg and
## applied at launch and on every change.
##
## Audio: master/music/sfx volume (0..1) on the Master, Music and SFX buses.
## Video: window resolution, fullscreen, graphics quality (Low/Medium/High:
## MSAA, 3D render scale, sun shadows). Controls: the primary keyboard key of
## each rebindable action. Player: name used in lobbies and results.

signal settings_changed

enum Quality { LOW, MEDIUM, HIGH }
const QUALITY_NAMES: Array[String] = ["Low", "Medium", "High"]
## Scenery fade distance factor per quality.
const LOD_SCALE: Array[float] = [0.55, 0.85, 1.0]
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440),
]
## Actions the Controls screen can rebind (primary keyboard key).
const REBINDABLE: Array[StringName] = [
	&"accelerate", &"brake", &"steer_left", &"steer_right", &"drift",
	&"use_item", &"interact", &"reset", &"pause",
]
const ACTION_LABELS := {
	&"accelerate": "Accelerate", &"brake": "Brake / reverse", &"steer_left": "Steer left",
	&"steer_right": "Steer right", &"drift": "Drift / handbrake", &"use_item": "Use item",
	&"interact": "Get back on", &"reset": "Reset trike", &"pause": "Pause",
}
const DEFAULT_PATH := "user://settings.cfg"
const MAX_NAME_LENGTH := 16

var settings_path := DEFAULT_PATH
var master_volume := 1.0
var music_volume := 0.8
var sfx_volume := 0.9
var resolution_index := 0
var fullscreen := false
var quality := Quality.MEDIUM
var player_name := "Player"
## action -> physical keycode of its primary key (only actions the player changed)
var key_overrides := {}

## action -> the project's original events (for Reset Controls)
var _default_events := {}


func _ready() -> void:
	for action in REBINDABLE:
		if InputMap.has_action(action):
			_default_events[action] = InputMap.action_get_events(action).duplicate()
	load_settings()
	apply_all()


# --- Persistence --------------------------------------------------------------

func load_settings() -> void:
	reset_to_defaults(false)
	var file := ConfigFile.new()
	if file.load(settings_path) != OK:
		return
	master_volume = clampf(file.get_value("audio", "master", master_volume), 0.0, 1.0)
	music_volume = clampf(file.get_value("audio", "music", music_volume), 0.0, 1.0)
	sfx_volume = clampf(file.get_value("audio", "sfx", sfx_volume), 0.0, 1.0)
	resolution_index = clampi(file.get_value("video", "resolution", resolution_index), 0, RESOLUTIONS.size() - 1)
	fullscreen = file.get_value("video", "fullscreen", fullscreen)
	quality = clampi(file.get_value("video", "quality", quality), 0, Quality.HIGH) as Quality
	player_name = sanitize_name(file.get_value("player", "name", player_name))
	key_overrides.clear()
	for action in REBINDABLE:
		var code: int = file.get_value("controls", String(action), KEY_NONE)
		if code != KEY_NONE:
			key_overrides[action] = code


func save_settings() -> Error:
	var file := ConfigFile.new()
	file.set_value("audio", "master", master_volume)
	file.set_value("audio", "music", music_volume)
	file.set_value("audio", "sfx", sfx_volume)
	file.set_value("video", "resolution", resolution_index)
	file.set_value("video", "fullscreen", fullscreen)
	file.set_value("video", "quality", quality)
	file.set_value("player", "name", player_name)
	for action: StringName in key_overrides:
		file.set_value("controls", String(action), key_overrides[action])
	return file.save(settings_path)


## Defaults in memory (does not save). `apply` also applies them.
func reset_to_defaults(apply := true) -> void:
	master_volume = 1.0
	music_volume = 0.8
	sfx_volume = 0.9
	resolution_index = 0
	fullscreen = false
	quality = Quality.MEDIUM
	player_name = "Player"
	key_overrides.clear()
	if apply:
		apply_all()


## The test suite uses its own file and the project's default controls, so
## the player's saved settings never affect (or get overwritten by) tests.
func use_test_profile(path: String) -> void:
	settings_path = path
	reset_to_defaults()


# --- Setters (apply + save + notify) ----------------------------------------

func set_volume(bus: String, value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	match bus:
		"Master":
			master_volume = value
		"Music":
			music_volume = value
		"SFX":
			sfx_volume = value
	_apply_audio()
	_commit()


func set_resolution_index(index: int) -> void:
	resolution_index = clampi(index, 0, RESOLUTIONS.size() - 1)
	_apply_display()
	_commit()


func set_fullscreen(value: bool) -> void:
	fullscreen = value
	_apply_display()
	_commit()


func set_quality(value: Quality) -> void:
	quality = value
	apply_graphics(get_tree().root)
	_commit()


func set_player_name(value: String) -> void:
	player_name = sanitize_name(value)
	_commit()


static func sanitize_name(value: String) -> String:
	var clean := value.strip_edges().replace("\n", " ").left(MAX_NAME_LENGTH)
	return clean if not clean.is_empty() else "Player"


## Makes `physical` the primary key of `action`. Returns the action that
## already uses that key (nothing changes then), or &"" on success.
func rebind(action: StringName, physical: Key) -> StringName:
	var owner_action := action_using_key(physical)
	if owner_action != &"" and owner_action != action:
		return owner_action
	key_overrides[action] = physical
	_apply_key(action)
	_commit()
	return &""


func reset_controls() -> void:
	key_overrides.clear()
	_apply_controls()
	_commit()


## The rebindable action whose keyboard keys include `physical`, or &"".
func action_using_key(physical: Key) -> StringName:
	for action in REBINDABLE:
		for event in InputMap.action_get_events(action):
			var key := event as InputEventKey
			if key and (key.physical_keycode == physical or (key.physical_keycode == KEY_NONE and key.keycode == physical)):
				return action
	return &""


func primary_key(action: StringName) -> Key:
	for event in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key:
			return key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	return KEY_NONE


func get_resolution() -> Vector2i:
	return RESOLUTIONS[resolution_index]


func _commit() -> void:
	save_settings()
	settings_changed.emit()


# --- Applying -----------------------------------------------------------------

func apply_all() -> void:
	_apply_audio()
	_apply_display()
	_apply_controls()
	apply_graphics(get_tree().root)
	settings_changed.emit()


func _apply_audio() -> void:
	_set_bus("Master", master_volume)
	_set_bus("Music", music_volume)
	_set_bus("SFX", sfx_volume)


static func _set_bus(bus_name: String, value: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_mute(index, value <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.001)))


## Window size/fullscreen. Skipped headless, and when the window size was
## given on the command line (capture tools).
func _apply_display() -> void:
	if DisplayServer.get_name() == "headless" or "--resolution" in OS.get_cmdline_args():
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var size := get_resolution()
	size = Vector2i(mini(size.x, screen.size.x), mini(size.y, screen.size.y))
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)


## MSAA, render scale and sun shadows for a viewport and the scene under it.
## Scenes call this from _ready (shadows are per light).
func apply_graphics(root: Node) -> void:
	var viewport := root.get_viewport()
	if viewport:
		viewport.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][quality]
		viewport.scaling_3d_scale = 0.75 if quality == Quality.LOW else 1.0
	for node in root.find_children("*", "DirectionalLight3D", true, false):
		var light := node as DirectionalLight3D
		if not light.has_meta(&"shadow_default"):
			light.set_meta(&"shadow_default", light.shadow_enabled)
		light.shadow_enabled = bool(light.get_meta(&"shadow_default")) and quality != Quality.LOW
	# Scenery fade distances (trees, bushes, flowers): shorter on Low.
	for node in root.get_tree().get_nodes_in_group(&"scenery_lod") if root.is_inside_tree() else []:
		var instance := node as GeometryInstance3D
		var distance: float = instance.get_meta(&"lod_range") * LOD_SCALE[quality]
		instance.visibility_range_end = distance
		instance.visibility_range_end_margin = distance * 0.15


func _apply_controls() -> void:
	for action in REBINDABLE:
		if not _default_events.has(action):
			continue
		InputMap.action_erase_events(action)
		for event: InputEvent in _default_events[action]:
			InputMap.action_add_event(action, event.duplicate())
		_apply_key(action)


func _apply_key(action: StringName) -> void:
	if not key_overrides.has(action):
		return
	for event in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key:
			key.physical_keycode = key_overrides[action]
			key.keycode = KEY_NONE
			return
