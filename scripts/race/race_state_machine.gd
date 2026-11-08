class_name RaceStateMachine
extends RefCounted
## The race flow as explicit states and allowed transitions:
##
##   LOBBY ──▶ COUNTDOWN ──▶ RACING ──▶ FINISHED ──▶ RESULTS
##     ▲          │            │                        │
##     └──────────┴────────────┴── (abort / reset) ◀────┘
##
## LOBBY: racers on the grid, controls locked. COUNTDOWN: 3-2-1, locked.
## RACING: GO!, driving and the clock run; finishers wait for the others.
## FINISHED: everyone finished or the finish timeout ran out; controls
## locked, clock stopped. RESULTS: results screen. RESULTS → LOBBY resets
## the race (Race Again continues straight into COUNTDOWN).
## transition() refuses anything else and returns false.

signal state_changed(old_state: State, new_state: State)

enum State { LOBBY, COUNTDOWN, RACING, FINISHED, RESULTS }
const STATE_NAMES: Array[String] = ["LOBBY", "COUNTDOWN", "RACING", "FINISHED", "RESULTS"]
const ALLOWED := {
	State.LOBBY: [State.COUNTDOWN],
	State.COUNTDOWN: [State.RACING, State.LOBBY],
	State.RACING: [State.FINISHED, State.LOBBY],
	State.FINISHED: [State.RESULTS, State.LOBBY],
	State.RESULTS: [State.LOBBY],
}

var state := State.LOBBY
## Seconds in the current state (advanced by the owner).
var state_time := 0.0
## Every state entered, oldest first (tests, debugging).
var history: Array[State] = [State.LOBBY]


func can_transition(to: State) -> bool:
	return (ALLOWED[state] as Array).has(to)


func transition(to: State) -> bool:
	if not can_transition(to):
		return false
	var old := state
	state = to
	state_time = 0.0
	history.append(to)
	state_changed.emit(old, to)
	return true


func advance(delta: float) -> void:
	state_time += delta


func get_state_name() -> String:
	return STATE_NAMES[state]


func is_state(s: State) -> bool:
	return state == s
