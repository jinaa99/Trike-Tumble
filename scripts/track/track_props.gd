extends Node3D
## Places obstacles, hazards and ramps along a Track from a data table.
## Each entry: [distance along track (m), lateral offset (m, + = right), kind]
## plus, for some kinds, a parameter dictionary as a 4th element.

const CRATE := preload("res://scenes/props/crate.tscn")
const CONE := preload("res://scenes/props/cone.tscn")
const ROCK := preload("res://scenes/props/rock.tscn")
const RAMP := preload("res://scenes/props/ramp.tscn")
const BOULDER := preload("res://scenes/props/boulder.tscn")
const ROAD_TREE := preload("res://scenes/props/road_tree.tscn")
const FALLING_LOG := preload("res://scenes/props/falling_log.tscn")

## Overridable per track in the inspector. Kinds:
##   crate, crate_stack, cone_line, rock, ramp
##   boulder        big rock on the road ({"radius", "height"} optional)
##   road_tree      pine growing in the road
##   falling_log    timed log hazard; lateral sign = side the logs come from
##                  ({"period", "phase"} optional)
##   big_ramp       full-width kicker for a jump gap ({"length", "height"});
##                  its lip sits at the given distance
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
## Road around solid obstacles, hazards and ramps that is no respawn point
## (m before and after).
@export var unsafe_margin := 10.0


func build_for_track(track: Track) -> void:
	for entry: Array in layout:
		var distance: float = entry[0]
		if distance > track.path.length - track.finish_distance_from_end - 10.0:
			continue
		var lateral: float = entry[1]
		var kind: String = entry[2]
		var params: Dictionary = entry[3] if entry.size() > 3 else {}
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
				track.mark_unsafe(distance - unsafe_margin, distance + unsafe_margin)
			"boulder":
				var boulder: RoadBoulder = BOULDER.instantiate()
				boulder.radius = params.get("radius", boulder.radius)
				boulder.height = params.get("height", boulder.height)
				boulder.random_seed = roundi(distance)
				_place(boulder, frame)
				track.mark_unsafe(distance - unsafe_margin, distance + unsafe_margin)
			"road_tree":
				_place(ROAD_TREE.instantiate(), frame)
				track.mark_unsafe(distance - unsafe_margin, distance + unsafe_margin)
			"falling_log":
				var hazard: FallingLog = FALLING_LOG.instantiate()
				hazard.track = track
				hazard.from_side = -1 if lateral < 0.0 else 1
				hazard.half_width = track.half_width_at(track.path.index_at_distance(distance))
				hazard.period = params.get("period", hazard.period)
				hazard.phase = params.get("phase", hazard.phase)
				# Road space: centered on the road, whatever the lateral sign.
				_place(hazard, frame.translated_local(Vector3(-lateral, 0.0, 0.0)))
				track.mark_unsafe(distance - unsafe_margin, distance + unsafe_margin)
			"big_ramp":
				var ramp: Ramp = RAMP.instantiate()
				var index := track.path.index_at_distance(distance)
				ramp.width = track.half_width_at(index) * 2.0 - 0.3
				ramp.length = params.get("length", 10.0)
				ramp.height = params.get("height", 2.2)
				# Lip at `distance`: the wedge is centered half a length before it.
				var back := track.path.get_frame(track.path.index_at_distance(distance - ramp.length * 0.5))
				_spawn_node(ramp, back)
				track.mark_unsafe(distance - ramp.length - unsafe_margin, distance)
			_:
				push_warning("Unknown prop kind: %s" % kind)


## Puts every knocked-over crate and cone back where it started (new race).
func reset_props() -> void:
	for child in get_children():
		var body := child as RigidBody3D
		if body == null or not body.has_meta(&"start_transform"):
			continue
		body.global_transform = body.get_meta(&"start_transform")
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.reset_physics_interpolation()


## Static or animated props without a start transform to restore.
func _place(node: Node3D, frame: Transform3D) -> void:
	node.transform = frame
	add_child(node)


func _spawn_node(node: Node3D, frame: Transform3D) -> void:
	node.transform = frame
	add_child(node)
	node.set_meta(&"start_transform", node.global_transform)


func _spawn(scene: PackedScene, frame: Transform3D, local_offset: Vector3) -> void:
	var node: Node3D = scene.instantiate()
	node.transform = frame.translated_local(local_offset)
	add_child(node)
	node.set_meta(&"start_transform", node.global_transform)
