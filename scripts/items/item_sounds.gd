class_name ItemSounds
extends Node
## Item sound effects from the SoundBank (synthesized in code, original):
## pickup chime, throw whoosh, splat, boing, slip and turbo. Sounds that
## concern the local player play flat; others play positioned in the world.
## Everything goes to the "SFX" bus (Settings volume).

enum Sound { PICKUP, USE, SPLAT, PUNCH, SLIP, TURBO, DENIED }

const BUS := &"SFX"

@export var volume_db := -6.0
@export var world_volume_db := 0.0

var _player: AudioStreamPlayer
## Sounds played so far (tests check feedback without listening).
var played: Array[Sound] = []


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "LocalPlayer"
	_player.bus = BUS
	_player.volume_db = volume_db
	_player.max_polyphony = 4
	add_child(_player)


## Non-positional (the local player's own pickups and hits).
func play(sound: Sound) -> void:
	played.append(sound)
	_player.stream = stream_for(sound)
	_player.play()


## Positioned in the world (other racers' items).
func play_at(sound: Sound, position: Vector3) -> void:
	played.append(sound)
	if not is_inside_tree():
		return
	var player := AudioStreamPlayer3D.new()
	player.bus = BUS
	player.stream = stream_for(sound)
	player.volume_db = world_volume_db
	player.unit_size = 12.0
	player.max_distance = 90.0
	add_child(player)
	player.global_position = position
	player.play()
	# Freed on a timer, not on `finished`: headless runs (dummy audio
	# driver, network tests) never emit it.
	get_tree().create_timer(player.stream.get_length() + 0.2).timeout.connect(player.queue_free)


const NAMES := {
	Sound.PICKUP: &"item_pickup", Sound.USE: &"item_throw", Sound.SPLAT: &"item_splat", Sound.PUNCH: &"item_punch",
	Sound.SLIP: &"item_slip", Sound.TURBO: &"item_turbo", Sound.DENIED: &"item_denied",
}


static func stream_for(sound: Sound) -> AudioStreamWAV:
	return SoundBank.use(NAMES[sound])
