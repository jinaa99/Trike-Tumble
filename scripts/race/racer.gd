class_name Racer
extends RefCounted
## One racer in a race: identity, vehicle, rider, control source, progress,
## spawn and finish state. Created and owned by RacerManager; plain data so a
## future network host can mirror it.

enum Type { HUMAN, AI }

var id := 0
var display_name := ""
var type := Type.HUMAN
var trike: Trike
var rider: RiderController
## PlayerInputSource for the local human, AIDriver for bots (null when a test
## drives the trike directly).
var input_source: TrikeInputSource
var progress: VehicleProgress
## Ordered checkpoints and valid race distance (positions, finish gate).
var checkpoints: CheckpointProgress
var spawn_slot := 0
var spawn_transform := Transform3D.IDENTITY
var color := Color.WHITE
## Preferred lateral offset (m, + = right of the centerline) for driving and respawns.
var lane_offset := 0.0
## Node holding the trike/rider/driver of racers RacerManager spawned (null
## for racers placed in the scene, like the local player).
var root: Node3D

## Current race position (1 = leading), updated every physics tick.
var position := 0
var finished := false
var finish_position := 0
var finish_time := 0.0
## Race ended (finish timeout) before this racer finished.
var did_not_finish := false
var respawn_count := 0
## Online: another computer simulates this racer; here it is an
## interpolated proxy (NetRacerSync moves it).
var is_proxy := false
## Online: network peer that owns this racer (1 = host, also for AI).
var owner_peer := 1
## Online: the owner left mid-race (counts as DNF, removed from the track).
var disconnected := false
## Empty trike crossed the line; finish confirmed when its rider is back on.
var pending_finish := false
## Item carried (ItemKind.Kind; one at a time) and for how long. Set only by
## ItemManager events (the host decides).
var held_item := ItemKind.Kind.NONE
var item_hold_time := 0.0


func is_ai() -> bool:
	return type == Type.AI


func get_ai_driver() -> AIDriver:
	return input_source as AIDriver


func get_type_name() -> String:
	return "AI" if is_ai() else "HUMAN"
