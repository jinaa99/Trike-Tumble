class_name HazardMarker
extends Marker3D
## A point of a wide timed hazard (a fallen tree's trunk) that AI drivers and
## the near-miss check treat as an obstacle. Active while its hazard is.

var hazard: Node


func is_active() -> bool:
	if hazard == null or not is_instance_valid(hazard):
		return false
	# From the first warning until the trunk is gone: a driver who sees the
	# crown shake already picks the free side.
	return bool(hazard.call(&"is_threat")) if hazard.has_method(&"is_threat") else bool(hazard.call(&"is_active"))
