class_name CheckpointProgress
extends RefCounted
## Ordered checkpoint validation and valid race distance for one racer.
##
## Checkpoints are path sample indices from Track.get_checkpoints(); the last
## one is the finish line (completed through FinishTracker, not here).
## - The next checkpoint counts only while the trike is within `pass_window`
##   samples after it. Jumping past it (teleport, shortcut) doesn't count, and
##   no later checkpoint can count before it: checkpoints can't be skipped.
## - A checkpoint registers once; reversing back over it and driving through
##   again changes nothing.
## - `distance` (valid race distance, m) follows the trike along the path but
##   never goes beyond the next unpassed checkpoint, so skipping or reversing
##   gains nothing. Driving backwards lowers it.
## It reads the trike's progress (VehicleProgress), so it survives ejection:
## the rider being off the trike changes nothing here.

signal checkpoint_passed(checkpoint: int)

## Samples after a checkpoint in which passing it still counts (2 m each).
var pass_window := 15
## Index into `checkpoints` of the next checkpoint to pass.
var next_checkpoint := 0
## Valid distance along the track (m) used for race positions.
var distance := 0.0
## Distance (m) past the last passed checkpoint (or the start).
var segment_distance := 0.0
## True after the trike got past the next checkpoint without passing it.
var missed_checkpoint := false

var track: Track
var checkpoints := PackedInt32Array()
var _start_index := 0


func _init(for_track: Track, start_index := 0) -> void:
	track = for_track
	checkpoints = track.get_checkpoints()
	reset(start_index)


func reset(start_index: int) -> void:
	_start_index = start_index
	next_checkpoint = 0
	missed_checkpoint = false
	distance = start_index * track.path.spacing
	segment_distance = 0.0


## Every physics tick: `index` = the trike's current path sample.
func update(index: int, position: Vector3) -> void:
	if is_complete():
		return
	var path := track.path
	var target := checkpoints[next_checkpoint]
	var is_finish := next_checkpoint == checkpoints.size() - 1
	if not is_finish and index >= target:
		if index <= target + pass_window:
			next_checkpoint += 1
			missed_checkpoint = false
			checkpoint_passed.emit(next_checkpoint - 1)
		else:
			missed_checkpoint = true
	var along := index * path.spacing + (position - path.points[index]).dot(path.forwards[index])
	var cap := checkpoints[next_checkpoint] * path.spacing
	distance = clampf(along, 0.0, cap)
	segment_distance = maxf(distance - _last_passed_distance(), 0.0)


## All checkpoints before the finish line passed, in order.
func can_finish() -> bool:
	return next_checkpoint >= checkpoints.size() - 1


## Finish confirmed: the finish line counts as the last checkpoint.
func complete() -> void:
	next_checkpoint = checkpoints.size()
	distance = checkpoints[checkpoints.size() - 1] * track.path.spacing
	segment_distance = 0.0
	missed_checkpoint = false


func is_complete() -> bool:
	return next_checkpoint >= checkpoints.size()


## Checkpoints passed so far (the finish counts once complete).
func get_passed_count() -> int:
	return next_checkpoint


func get_total_count() -> int:
	return checkpoints.size()


## 0 at the start line .. 1 at the finish.
func get_overall_progress() -> float:
	var start := _start_index * track.path.spacing
	var finish := checkpoints[checkpoints.size() - 1] * track.path.spacing
	if finish <= start:
		return 1.0
	return clampf((distance - start) / (finish - start), 0.0, 1.0)


## Test/tool helper: credits every checkpoint up to path sample `index`
## (never the finish), as if driven there. Use after teleporting a trike.
func force_passed_through(index: int) -> void:
	while next_checkpoint < checkpoints.size() - 1 and checkpoints[next_checkpoint] <= index:
		next_checkpoint += 1
	missed_checkpoint = false


func _last_passed_distance() -> float:
	if next_checkpoint == 0:
		return _start_index * track.path.spacing
	return checkpoints[next_checkpoint - 1] * track.path.spacing
