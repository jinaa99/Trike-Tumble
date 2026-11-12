class_name RaceSession
extends Node3D
## Offline race session: 1 local player plus 0–4 AI racers.
##
## Wires track, the local player's trike + rider, camera, HUD, pause menu,
## lobby and results screens together. Racer bookkeeping (ids, spawning AI,
## per-racer progress, checkpoints, positions, respawns, finish resolution,
## race clock) lives in RacerManager; the race flow (lobby, countdown, racing,
## finished, results, race again) in RaceController; the rider's
## fall/recovery loop in RiderController. This node only binds the local
## racer and the race flow to camera and UI.
##
## Started from the main menu, the racers come from the lobby in
## GameSession (names, AI difficulties) and Return to Lobby goes back to the
## menu's lobby. Launched directly (editor, tests, tools), AI count and
## difficulty come from the exports below or the command line:
##   Godot --path . res://scenes/main/main.tscn -- --ai=4 --difficulty=mixed

## Player id of the local racer.
const LOCAL_PLAYER_ID := 1
## Difficulty order used by "mixed".
const MIXED_DIFFICULTIES: Array[AIDriverConfig.Difficulty] = [
	AIDriverConfig.Difficulty.HARD, AIDriverConfig.Difficulty.MEDIUM,
	AIDriverConfig.Difficulty.MEDIUM, AIDriverConfig.Difficulty.EASY,
]

## The track (map) this race is on; built when the scene loads.
@export var track_scene: PackedScene
@export var respawn_message := "Back on track!"
@export var wipeout_messages: Array[String] = ["WIPEOUT!", "BONK!", "OOF!", "WHOOPS!"]
@export var player_name := "You"
## AI opponents next to the local player (total racers = 1 + this, max 5).
@export_range(0, 4) var ai_racer_count := 0
## 0 Easy, 1 Medium, 2 Hard, 3 Mixed (hard, medium, medium, easy).
@export_enum("Easy", "Medium", "Hard", "Mixed") var ai_difficulty := 1
## Start the countdown by itself shortly after loading (otherwise the lobby
## screen waits for Start Race).
@export var auto_start := true
## Skip lobby and countdown: racing from the first tick (tools and tests).
@export var skip_countdown := false

## Replaced by tests: how the scene switches back to the menu.
var scene_changer := func(path: String) -> void: get_tree().change_scene_to_file(path)
## True when this race was started from a menu lobby (GameSession).
var from_lobby := false
## Online race (host or client); `net_sync` moves the other players' racers.
var online := false
var net_sync: NetRaceSync
## Countdown, finish and results sounds, finish confetti.
var race_audio: RaceAudio

var _local_racer: Racer
var _race_time := 0.0
var _race_finished := false

var track: Track
@onready var trike: Trike = $Trike
@onready var rider: RiderController = $RiderCharacter
@onready var follow_camera: FollowCamera = $FollowCamera
@onready var hud: Hud = $HUD
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var racers: RacerManager = $RacerManager
@onready var items: ItemManager = $Items
@onready var race: RaceController = $RaceController
@onready var results_screen: ResultsScreen = $ResultsScreen
@onready var lobby_screen: LobbyScreen = $LobbyScreen


func _ready() -> void:
	_load_track()
	_apply_command_line(OS.get_cmdline_user_args())
	GameSettings.apply_graphics(self)
	racers.setup(track)
	from_lobby = GameSession.race_active and GameSession.has_lobby()
	online = from_lobby and GameSession.is_online()
	if online:
		_build_online_racers(GameSession.get_race_setup()["racers"])
	elif from_lobby:
		var setup := GameSession.get_race_setup()
		_local_racer = racers.add_human_racer(trike, rider, LOCAL_PLAYER_ID, setup["player_name"])
		for ai: Dictionary in setup["ai"]:
			racers.add_ai_racer(ai["difficulty"], ai["name"])
	else:
		_local_racer = racers.add_human_racer(trike, rider, LOCAL_PLAYER_ID, player_name)
		for i in mini(ai_racer_count, racers.max_racers - 1):
			racers.add_ai_racer(_difficulty_for(i))

	items.setup(racers, track)
	items.local_racer_id = _local_racer.id if _local_racer else -1
	items.item_changed.connect(_on_item_changed)
	items.feedback.connect(_on_item_feedback)

	trike.respawned.connect(follow_camera.snap_to_target)
	racers.racer_respawned.connect(_on_racer_respawned)
	pause_menu.restart_requested.connect(restart)
	pause_menu.lobby_requested.connect(return_to_lobby)

	racers.racer_finished.connect(_on_racer_finished)
	racers.racer_pending.connect(_on_finish_pending)

	rider.focus_changed.connect(follow_camera.set_target)
	rider.mount_prompt_changed.connect(hud.set_mount_prompt)
	rider.ejected.connect(_on_rider_ejected)

	follow_camera.target = trike
	follow_camera.snap_to_target()
	# Camera feedback from the local trike: hits shake, landings dip.
	trike.impact.connect(func(strength: float, _v: Vector3) -> void: follow_camera.add_impact_shake(strength))
	(trike.get_node("Visuals") as TrikeVisuals).landed.connect(follow_camera.add_landing)
	hud.set_vehicle(trike)

	race.finish_timeout = track.finish_timeout
	race.auto_start = auto_start and not online
	race.follower = online and not Net.is_host()
	race.setup(racers)
	race.countdown_step.connect(hud.show_countdown)
	race.state_changed.connect(_on_race_state_changed)
	race.race_reset.connect(_on_race_reset)
	race.race_reset.connect(items.reset_for_new_race)
	race_audio = RaceAudio.new()
	race_audio.name = "RaceAudio"
	add_child(race_audio)
	race_audio.setup(self)
	results_screen.race_again_pressed.connect(race_again)
	results_screen.lobby_pressed.connect(return_to_lobby)
	lobby_screen.start_pressed.connect(start_from_lobby)
	_show_race_state(race.get_state())
	if online:
		_start_online()
	elif skip_countdown:
		race.start_immediately()
	elif not auto_start:
		lobby_screen.show_lobby(racers.get_racers())


## Builds the map. The track keeps its scene's root name (e.g. "TestTrack").
func _load_track() -> void:
	track = track_scene.instantiate()
	add_child(track)
	move_child(track, 0)
	# The map's sky, fog and sun (themes that ask for it; forest keeps the scene's).
	track.theme.apply_to_world(get_node_or_null(^"WorldEnvironment") as WorldEnvironment,
			get_node_or_null(^"Sun") as DirectionalLight3D)


func _physics_process(_delta: float) -> void:
	if racers.is_race_started and not _race_finished:
		_race_time = racers.race_time
		hud.set_race_time(_race_time)
	hud.set_race_position(_local_racer.position, racers.get_racer_count(),
			_local_racer.checkpoints.get_passed_count(), _local_racer.checkpoints.get_total_count(),
			race.get_timeout_left())


func race_again() -> void:
	if online and not Net.is_host():
		return  # the host decides
	results_screen.hide_results()
	race.race_again()


## From the results screen or the pause menu. Races started from the menu
## go back to the menu's lobby; a directly launched race resets in place and
## shows its own lobby panel.
func return_to_lobby() -> void:
	results_screen.hide_results()
	if online and not Net.is_host():
		leave_online_game()
		return
	if online:
		Net.return_all_to_lobby()
	if from_lobby:
		get_tree().paused = false
		GameSession.end_race_for_lobby()
		scene_changer.call(GameSession.MENU_SCENE)
		return
	if race.return_to_lobby() or race.get_state() == RaceStateMachine.State.LOBBY:
		lobby_screen.show_lobby(racers.get_racers())


func start_from_lobby() -> void:
	lobby_screen.hide_lobby()
	race.begin_countdown()


## Client: leave the online game (back to the title).
func leave_online_game() -> void:
	get_tree().paused = false
	GameSession.leave_lobby()
	scene_changer.call(GameSession.MENU_SCENE)


# --- Online -------------------------------------------------------------------

## Grid order = the host's list. Our player drives the scene's trike; the
## host also simulates the AI; everything else is a proxy.
func _build_online_racers(list: Array) -> void:
	var me := Net.my_id()
	for slot in list.size():
		var entry: Dictionary = list[slot]
		var id := int(entry["id"])
		var owner_peer := int(entry["owner"])
		var is_ai := bool(entry["ai"])
		var racer: Racer
		if not is_ai and owner_peer == me:
			racer = racers.add_human_racer(trike, rider, id, entry["name"], slot)
			_local_racer = racer
		elif is_ai and Net.is_host():
			racer = racers.add_ai_racer(int(entry["difficulty"]) as AIDriverConfig.Difficulty, entry["name"], id, slot)
		else:
			racer = racers.add_proxy_racer(entry["name"], id, slot, is_ai, owner_peer)
		if racer:
			racer.owner_peer = owner_peer
	racers.authoritative = Net.is_host()


func _start_online() -> void:
	net_sync = NetRaceSync.new()
	net_sync.name = "NetRaceSync"
	add_child(net_sync)
	net_sync.setup(racers)
	items.authoritative = Net.is_host()
	items.send_request = Net.send_item_request
	if Net.is_host():
		items.broadcast = Net.send_item_event
	pause_menu.set_online(Net.is_host())
	results_screen.set_online(Net.is_host())
	if Net.is_host():
		race.state_changed.connect(func(_old: RaceStateMachine.State, new_state: RaceStateMachine.State) -> void:
			Net.send_race_state(new_state, racers.race_time, race.results, race.race_duration))
	race.race_reset.connect(net_sync.clear_buffers)
	GameSession.disconnected.connect(_on_connection_lost)
	GameSession.lobby_return_requested.connect(func() -> void: scene_changer.call(GameSession.MENU_SCENE))
	Net.attach_race(self, net_sync)
	hud.show_message("Waiting for players…", 2.0)


func _exit_tree() -> void:
	if online:
		Net.detach_race(self)


## Host: every client has loaded the race (or the wait timed out).
func net_all_loaded() -> void:
	if race.get_state() == RaceStateMachine.State.LOBBY:
		race.begin_countdown()


## Clients: race state from the host.
func net_apply_race_state(state: int, race_time: float, results: Array, duration: float) -> void:
	race.apply_remote_state(state as RaceStateMachine.State, race_time, results, duration)


## Clients: positions, checkpoints and finishes from the host.
func net_apply_status(status: Array) -> void:
	racers.apply_remote_status(status)


## Host: an item request from the client that owns `racer_id`.
func net_item_request(racer_id: int, req_id: int, kind: int, data: Array) -> void:
	items.handle_request(racer_id, req_id, kind, data)


## Clients: an item decision from the host.
func net_apply_item_event(event: Array) -> void:
	items.apply_remote_event(event)


## A player left mid-race: their racer is DNF and leaves the track.
func net_player_left(peer_id: int) -> void:
	for racer in racers.get_racers_owned_by(peer_id):
		racers.mark_disconnected(racer.id)
		hud.show_message("%s left the race" % racer.display_name, 2.0)


func _on_connection_lost(_reason: String) -> void:
	get_tree().paused = false
	scene_changer.call(GameSession.MENU_SCENE)


## Reloads the whole scene (pause menu Restart).
func restart() -> void:
	get_tree().reload_current_scene()


func get_progress() -> VehicleProgress:
	return _local_racer.progress


func get_local_racer() -> Racer:
	return _local_racer


func get_race_time() -> float:
	return _race_time


func is_race_finished() -> bool:
	return _race_finished


func get_finish_tracker() -> FinishTracker:
	return racers.finish_tracker


func _difficulty_for(ai_index: int) -> AIDriverConfig.Difficulty:
	if ai_difficulty >= 3:
		return MIXED_DIFFICULTIES[ai_index % MIXED_DIFFICULTIES.size()]
	return ai_difficulty as AIDriverConfig.Difficulty


## Reads `--ai=N` and `--difficulty=easy|medium|hard|mixed` (after `--`).
## Other arguments are ignored (tools pass their own).
func _apply_command_line(args: PackedStringArray) -> void:
	for arg in args:
		if arg.begins_with("--ai="):
			ai_racer_count = clampi(arg.trim_prefix("--ai=").to_int(), 0, 4)
		elif arg.begins_with("--difficulty="):
			var index := ["easy", "medium", "hard", "mixed"].find(arg.trim_prefix("--difficulty=").to_lower())
			if index >= 0:
				ai_difficulty = index


func _on_race_state_changed(_old: RaceStateMachine.State, new_state: RaceStateMachine.State) -> void:
	_show_race_state(new_state)
	match new_state:
		RaceStateMachine.State.COUNTDOWN:
			lobby_screen.hide_lobby()
		RaceStateMachine.State.FINISHED:
			if not _race_finished:
				hud.show_message("RACE OVER", 2.0)
		RaceStateMachine.State.RESULTS:
			results_screen.show_results(race.results, race.race_duration, _local_racer.id)


const STATE_CHIPS := {
	RaceStateMachine.State.LOBBY: ["GET READY", UiKit.SKY],
	RaceStateMachine.State.COUNTDOWN: ["STARTING", UiKit.SUN],
	RaceStateMachine.State.RACING: ["RACING", UiKit.MINT],
	RaceStateMachine.State.FINISHED: ["RACE OVER", UiKit.ORANGE],
	RaceStateMachine.State.RESULTS: ["RESULTS", UiKit.SUN],
}


func _show_race_state(state: RaceStateMachine.State) -> void:
	var chip: Array = STATE_CHIPS[state]
	var text: String = chip[0]
	if state == RaceStateMachine.State.RACING and _race_finished:
		text = "FINISHED · WAITING FOR OTHERS"
	hud.set_race_state(text, chip[1])


## Race Again / Return to Lobby put everyone back on the grid.
func _on_race_reset() -> void:
	_race_finished = false
	_race_time = 0.0
	hud.set_race_time(0.0)
	hud.set_mount_prompt(false)
	follow_camera.set_target(trike)
	follow_camera.snap_to_target()


func _on_racer_respawned(racer: Racer) -> void:
	if racer == _local_racer:
		hud.show_message(respawn_message, 1.2)


func _on_rider_ejected(_strength: float) -> void:
	hud.show_message(wipeout_messages[randi() % wipeout_messages.size()], 1.2)


func _on_item_changed(racer: Racer, kind: ItemKind.Kind) -> void:
	if racer == _local_racer:
		hud.set_item(ItemKind.display_name(kind), ItemKind.color_of(kind))


func _on_item_feedback(racer: Racer, text: String) -> void:
	if racer == _local_racer:
		hud.show_message(text, 1.0)


func _on_finish_pending(racer: Racer) -> void:
	if racer == _local_racer:
		hud.show_message("Get back on to finish!", 2.5)


func _on_racer_finished(racer: Racer) -> void:
	if racer != _local_racer:
		return
	_race_finished = true
	_race_time = racer.finish_time
	# Cool-down: the finished trike brakes gently to a stop (controls locked,
	# like before GO) instead of rolling on into the wall at the end of the
	# road. Race Again / the lobby unlock it again.
	trike.input_locked = true
	_show_race_state(race.get_state())
	hud.set_race_time(racer.finish_time)
	hud.show_message("FINISH!  %s  %s" % [ordinal(racer.finish_position), Hud.format_time(racer.finish_time)], 6.0)


static func ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		suffix = {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
	return "%d%s" % [n, suffix]
