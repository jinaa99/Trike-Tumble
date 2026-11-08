extends Node3D
## Places obstacles and ramps along a Track from a data table.
## Each entry: [distance along track (m), lateral offset (m, + = right), kind].

const CRATE := preload("res://scenes/props/crate.tscn")
const CONE := preload("res://scenes/props/cone.tscn")
const ROCK := preload("res://scenes/props/rock.tscn")
const RAMP := preload("res://scenes/props/ramp.tscn")

## Overridable per track in the inspector. Kinds: crate, crate_stack,
## cone_line, rock, ramp.
@export var layout: Array = [
	[70.0, -3.5, "crate_stack"],
	[115.0, 0.0, "cone_line"],
	[190.0, 0.0, "ramp"],
	[250.0, 4.5, "rock"],
	[262.0, -2.0, "crate"],
	[330.0, 2.5, "crate_stack"],
	[400.0, -4.0, "rock"],
	[440.0, 0.0, "ramp"],
	[505.0, -3.0, "cone_line"],
	[570.0, 3.5, "crate_stack"],
	[620.0, -4.5, "rock"],
	[640.0, 3.0, "rock"],
	[700.0, 0.0, "ramp"],
	[770.0, 0.0, "cone_line"],
	[840.0, -3.0, "crate_stack"],
	[905.0, 0.0, "ramp"],
	[960.0, 4.0, "rock"],
	[1010.0, -2.5, "crate"],
]


func build_for_track(track: Track) -> void:
	for entry: Array in layout:
		var distance: float = entry[0]
		if distance > track.path.length - track.finish_distance_from_end - 10.0:
			continue
		var lateral: float = entry[1]
		var kind: String = entry[2]
		var frame := track.path.get_frame(track.path.index_at_distance(distance))
		frame.origin += frame.basis.x * lateral
		match kind:
			"crate":
				_spawn(CRATE, frame, Vector3(0.0, 0.55, 0.0))
			"crate_stack":
				for x in [-1.05, 0.0, 1.05]:
					_spawn(CRATE, frame, Vector3(x, 0.55, 0.0))
				for x in [-0.53, 0.53]:
					_spawn(CRATE, frame, Vector3(x, 1.6, 0.0))
				_spawn(CRATE, frame, Vector3(0.0, 2.65, 0.0))
			"cone_line":
				for i in 5:
					_spawn(CONE, frame, Vector3((i - 2) * 2.4, 0.45, -float(i % 2) * 3.0))
			"rock":
				_spawn(ROCK, frame, Vector3(0.0, 0.6, 0.0))
			"ramp":
				_spawn(RAMP, frame, Vector3.ZERO)
			_:
				push_warning("Unknown prop kind: %s" % kind)


func _spawn(scene: PackedScene, frame: Transform3D, local_offset: Vector3) -> void:
	var node: Node3D = scene.instantiate()
	node.transform = frame.translated_local(local_offset)
	add_child(node)
