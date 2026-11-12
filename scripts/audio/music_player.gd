extends Node
## Background music (autoload `MusicPlayer`, "Music" bus). Two looping CC0
## tracks (docs/ASSET_CREDITS.md): a menu theme and a race track. `play()`
## crossfades between them; `duck()` lowers the music under results and
## pause screens. Process mode ALWAYS, so fades finish while the game is
## paused.

const TRACKS := {
	&"menu": "res://assets/audio/music/menu_flowerbed_fields.ogg",
	&"race": "res://assets/audio/music/race_sky_blue_street.ogg",
}
## Mix level per track (dB): music sits under the engine and effects.
const TRACK_DB := {&"menu": -9.0, &"race": -13.0}

@export var fade_seconds := 1.2
@export var duck_db := -7.0

## Name of the track playing (or fading in); &"" = silence.
var current: StringName = &""
var ducked := false

var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _streams := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.name = "Deck%d" % i
		player.bus = &"Music"
		player.volume_db = -80.0
		add_child(player)
		_players.append(player)


## Crossfades to `track` (&"menu", &"race" or &"" for silence). Playing the
## current track again does nothing, so scenes can call this freely.
func play(track: StringName) -> void:
	if track == current:
		return
	current = track
	if track == &"" or not TRACKS.has(track):
		return
	_active = 1 - _active
	var player := _players[_active]
	player.stream = _stream(track)
	player.volume_db = -80.0
	player.play()


func stop() -> void:
	play(&"")


func duck(on: bool) -> void:
	ducked = on


## Target level (dB) of the active deck right now (tests and mixing).
func target_db() -> float:
	if current == &"":
		return -80.0
	return float(TRACK_DB.get(current, -10.0)) + (duck_db if ducked else 0.0)


func _process(delta: float) -> void:
	var step := delta / maxf(fade_seconds, 0.05)
	for i in _players.size():
		var player := _players[i]
		var target := target_db() if i == _active and current != &"" else -80.0
		# Fade in decibels: about 60 dB per `fade_seconds`.
		player.volume_db = move_toward(player.volume_db, target, step * 60.0)
		if player.playing and player.volume_db <= -79.0 and target <= -79.0:
			player.stop()


func _exit_tree() -> void:
	# Last autoload work at shutdown: let go of shared visual caches.
	for player in _players:
		player.stop()
		player.stream = null
	_streams.clear()
	SoundBank.release()
	MaterialLibrary.release()
	TrikeDetail.release()


func _stream(track: StringName) -> AudioStream:
	if not _streams.has(track):
		var stream := load(TRACKS[track]) as AudioStream
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		_streams[track] = stream
	return _streams[track]
