class_name MapInfo
extends Resource
## One map in the catalog (map selection, lobby). `race_scene` empty = not
## playable yet. The card shows `preview` if set; otherwise a route map
## drawn from `track_scene`'s own data (MapPreview), or a labelled
## placeholder when there is no track yet. Never a fake screenshot.

enum Status { COMING_SOON, PROTOTYPE, READY }

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
## The map's signature gameplay twist (shown on its card).
@export var characteristic := ""
@export var status := Status.COMING_SOON
## Scene to load for a race on this map ("" = not playable).
@export_file("*.tscn") var race_scene := ""
## The map's track scene (route data for the preview).
@export_file("*.tscn") var track_scene := ""
@export var preview: Texture2D
## Placeholder preview palette: sky, far hills, ground, accent.
@export var theme_colors: Array[Color] = [Color(0.55, 0.78, 0.98), Color(0.4, 0.55, 0.75), Color(0.35, 0.6, 0.35), Color(1, 0.82, 0.22)]


func is_playable() -> bool:
	return status != Status.COMING_SOON and not race_scene.is_empty()


func get_status_text() -> String:
	match status:
		Status.PROTOTYPE:
			return "PROTOTYPE"
		Status.READY:
			return "READY"
	return "COMING SOON"
