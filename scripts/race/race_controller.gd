class_name RaceController
extends Node
## Runs the race flow on top of RacerManager through RaceStateMachine:
##
##   LOBBY      racers on the grid, controls locked. Starts the countdown
##              after `lobby_delay` when `auto_start`, else on begin_countdown().
##   COUNTDOWN  "3", "2", "1" (one per `countdown_step_time`), controls locked.
##   RACING     "GO!": controls unlocked, AI start, race clock runs. When the
##              first racer finishes the others keep racing until everyone is
##              done or `finish_timeout` runs out.
##   FINISHED   clock stopped, unfinished racers DNF, controls locked; after
##              `results_delay` →
##   RESULTS    results (position, name, time) until race_again() or
##              return_to_lobby(), which reset the race in place (no reload).

signal state_changed(old_state: RaceStateMachine.State, new_state: RaceStateMachine.State)
## "3", "2", "1", "GO!"
signal countdown_step(text: String)
signal race_finished(results: Array[Dictionary])
signal race_reset

## Countdown counts down from this number, then GO.
@export var countdown_from := 3
@export var countdown_step_time := 1.0
@export var go_text := "GO!"
## Start the countdown by itself after `lobby_delay` (first race only;
## after Return to Lobby the lobby waits for begin_countdown()).
@export var auto_start := true
@export var lobby_delay := 1.0
## Seconds the others may keep racing after the first finisher (0 = wait
## for everyone).
@export var finish_timeout := 45.0
## Seconds between FINISHED and the results screen.
@export var results_delay := 2.5

var machine := RaceStateMachine.new()
var racers: RacerManager
## Last number shown during the countdown (3, 2, 1), 0 at GO.
var countdown_value := 0
## Seconds left after the first finisher; < 0 = not running.
var timeout_left := -1.0
## Race clock when the race ended (last finisher or timeout).
var race_duration := 0.0
var results: Array[Dictionary] = []
## Races started so far (Race Again increments it).
var race_count := 0
## Online clients: the host decides every transition (apply_remote_state);
## locally only the countdown numbers are shown.
var follower := false
var _auto_start_pending := true


func setup(manager: RacerManager) -> void:
	racers = manager
	racers.racer_finished.connect(_on_racer_finished)
	machine.state_changed.connect(func(old: RaceStateMachine.State, new_state: RaceStateMachine.State) -> void:
		state_changed.emit(old, new_state))
	_auto_start_pending = auto_start and not follower
	racers.set_controls_locked(true)


func get_state() -> RaceStateMachine.State:
	return machine.state


func get_state_name() -> String:
	return machine.get_state_name()


func is_racing() -> bool:
	return machine.state == RaceStateMachine.State.RACING


func _physics_process(delta: float) -> void:
	if racers == null:
		return
	machine.advance(delta)
	match machine.state:
		RaceStateMachine.State.LOBBY:
			if _auto_start_pending and machine.state_time >= lobby_delay:
				begin_countdown()
		RaceStateMachine.State.COUNTDOWN:
			var remaining := countdown_from - floori(machine.state_time / countdown_step_time)
			if remaining <= 0:
				if not follower:
					_go()
			elif remaining != countdown_value:
				countdown_value = remaining
				countdown_step.emit(str(remaining))
		RaceStateMachine.State.RACING:
			if follower:
				return
			if racers.is_everyone_finished():
				_end_race()
			elif timeout_left >= 0.0:
				timeout_left -= delta
				if timeout_left <= 0.0:
					_end_race()
		RaceStateMachine.State.FINISHED:
			if not follower and machine.state_time >= results_delay:
				machine.transition(RaceStateMachine.State.RESULTS)


## LOBBY → COUNTDOWN. Shows the first number right away.
func begin_countdown() -> bool:
	if not machine.transition(RaceStateMachine.State.COUNTDOWN):
		return false
	_auto_start_pending = false
	racers.set_controls_locked(true)
	countdown_value = countdown_from
	countdown_step.emit(str(countdown_value))
	return true


## LOBBY → COUNTDOWN → RACING in one tick (tools and tests that don't need
## the countdown).
func start_immediately() -> bool:
	if machine.state == RaceStateMachine.State.LOBBY and not begin_countdown():
		return false
	if machine.state != RaceStateMachine.State.COUNTDOWN:
		return false
	_go()
	return true


## RESULTS → LOBBY (reset) → COUNTDOWN.
func race_again() -> bool:
	if not _reset_to_lobby():
		return false
	return begin_countdown()


## RESULTS → LOBBY (reset); waits there for begin_countdown().
func return_to_lobby() -> bool:
	return _reset_to_lobby()


## Online clients: follow the host's race state. `race_time` re-syncs the
## clock; `results`/`duration` arrive with FINISHED and RESULTS.
func apply_remote_state(state: RaceStateMachine.State, race_time: float, remote_results: Array, duration: float) -> void:
	match state:
		RaceStateMachine.State.LOBBY:
			if machine.state != RaceStateMachine.State.LOBBY:
				_reset_to_lobby()
		RaceStateMachine.State.COUNTDOWN:
			if machine.state != RaceStateMachine.State.LOBBY and machine.state != RaceStateMachine.State.COUNTDOWN:
				_reset_to_lobby()
			if machine.state == RaceStateMachine.State.LOBBY:
				begin_countdown()
		RaceStateMachine.State.RACING:
			if machine.state == RaceStateMachine.State.LOBBY:
				begin_countdown()
			if machine.state == RaceStateMachine.State.COUNTDOWN:
				_go()
			racers.race_time = race_time
		RaceStateMachine.State.FINISHED, RaceStateMachine.State.RESULTS:
			if machine.state == RaceStateMachine.State.RACING:
				timeout_left = -1.0
				machine.transition(RaceStateMachine.State.FINISHED)
				racers.race_time = race_time
				racers.stop_race()
				racers.set_controls_locked(true)
			race_duration = duration
			results.clear()
			for entry: Dictionary in remote_results:
				results.append(entry)
			if state == RaceStateMachine.State.RESULTS and machine.state == RaceStateMachine.State.FINISHED:
				machine.transition(RaceStateMachine.State.RESULTS)


## Remaining time of the finish timeout, or -1 if it isn't running.
func get_timeout_left() -> float:
	return timeout_left


func _go() -> void:
	machine.transition(RaceStateMachine.State.RACING)
	countdown_value = 0
	timeout_left = -1.0
	race_count += 1
	racers.set_controls_locked(false)
	racers.start_race()
	countdown_step.emit(go_text)


func _on_racer_finished(_racer: Racer) -> void:
	if follower:
		return
	if timeout_left < 0.0 and finish_timeout > 0.0 and machine.state == RaceStateMachine.State.RACING:
		timeout_left = finish_timeout


func _end_race() -> void:
	if not machine.transition(RaceStateMachine.State.FINISHED):
		return
	timeout_left = -1.0
	race_duration = racers.race_time
	if racers.is_everyone_finished():
		race_duration = 0.0
		for racer in racers.get_racers():
			race_duration = maxf(race_duration, racer.finish_time)
	racers.stop_race()
	racers.set_controls_locked(true)
	results = build_results()
	race_finished.emit(results)


## One entry per racer in final order:
## {"position", "id", "name", "is_ai", "finished", "time"}.
func build_results() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for racer in racers.get_ranking():
		list.append({
			"position": racer.position, "id": racer.id, "name": racer.display_name,
			"is_ai": racer.is_ai(), "finished": racer.finished,
			"time": racer.finish_time if racer.finished else -1.0,
		})
	return list


func _reset_to_lobby() -> bool:
	if not machine.transition(RaceStateMachine.State.LOBBY):
		return false
	timeout_left = -1.0
	countdown_value = 0
	race_duration = 0.0
	results.clear()
	racers.reset_for_new_race()
	race_reset.emit()
	return true
