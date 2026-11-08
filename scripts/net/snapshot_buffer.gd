class_name SnapshotBuffer
extends RefCounted
## Jitter buffer for one remote racer. Snapshots are placed on the local
## clock (owner clock + estimated offset) and shown `delay` seconds in the
## past, so there are almost always two snapshots to interpolate between:
## smooth motion despite network jitter. If snapshots stop, the last one is
## extrapolated briefly, then held (no wild flying).

## Seconds behind the newest data (≈ 3 snapshots at 30 Hz).
var delay := 0.1
## Longest extrapolation past the newest snapshot (s).
var max_extrapolation := 0.2
var max_snapshots := 40

var _snapshots: Array[Array] = []
## local clock - owner clock (minimum seen = least network delay).
var _offset := NAN


func push(data: Array, local_time: float) -> void:
	var t := NetSnapshot.time_of(data)
	if not _snapshots.is_empty() and t <= NetSnapshot.time_of(_snapshots[-1]):
		return  # duplicate or out of order
	var sample := local_time - t
	if is_nan(_offset) or sample < _offset:
		_offset = sample
	else:
		_offset += (sample - _offset) * 0.002  # follow slow clock drift
	_snapshots.append(data)
	if _snapshots.size() > max_snapshots:
		_snapshots.pop_front()


func count() -> int:
	return _snapshots.size()


func clear() -> void:
	_snapshots.clear()
	_offset = NAN


## Seconds since the newest snapshot was taken, on the local clock.
func newest_age(local_time: float) -> float:
	if _snapshots.is_empty():
		return INF
	return local_time - _offset - NetSnapshot.time_of(_snapshots[-1])


## Interpolated state at `local_time`, or {} with no data yet.
func sample(local_time: float) -> Dictionary:
	if _snapshots.is_empty():
		return {}
	var target := local_time - _offset - delay
	# Keep exactly one snapshot at or before the target.
	while _snapshots.size() > 2 and NetSnapshot.time_of(_snapshots[1]) <= target:
		_snapshots.pop_front()
	var a := _snapshots[0]
	var ta := NetSnapshot.time_of(a)
	if target <= ta:
		return NetSnapshot.blend(a, a, 0.0)
	if _snapshots.size() >= 2:
		var b := _snapshots[1]
		var tb := NetSnapshot.time_of(b)
		if target <= tb:
			return NetSnapshot.blend(a, b, (target - ta) / maxf(tb - ta, 1e-4))
	var last := _snapshots[-1]
	return NetSnapshot.extrapolate(last, minf(target - NetSnapshot.time_of(last), max_extrapolation))
