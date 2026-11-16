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
const FALLING_ROCK := preload("res://scenes/props/falling_rock.tscn")
const ROLLING_ROCK := preload("res://scenes/props/rolling_rock.tscn")
const SNOWMAN := preload("res://scenes/props/snowman.tscn")
const FALLING_TREE := preload("res://scenes/props/falling_tree.tscn")

## Overridable per track in the inspector. Kinds:
##   crate, crate_stack, cone_line, rock
##   ramp           kicker ({"length", "height", "width"} optional)
##   boulder        big rock on the road ({"radius", "height"} optional)
##   road_tree      pine growing in the road
##   falling_log    timed log hazard; lateral sign = side the logs come from
##                  ({"period", "phase"} optional)
##   big_ramp       full-width kicker for a jump gap ({"length", "height"});
##                  its lip sits at the given distance
##   falling_rock   timed rock dropping off a cliff on the lateral sign's side
##                  ({"period", "phase", "height"} optional)
##   rolling_rock   timed boulder rolling diagonally across ({"period", "phase"})
##   falling_tree   timed pine that falls across the road from the side of
##                  the lateral sign ({"period", "phase", "reach", "down"})
##   rockslide      three falling rocks landing in different lanes, one of
##                  which rests on the road ({"period", "phase", "rest"})
##   barricade      a breakable wall of crates across most of the road
##   snowman        knockable snowman (like crates)
##   snowman_group  three snowmen in a row across part of the road
## Boulders take the theme's `road_boulder_color` ({"color"} overrides it).
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
				# {"length", "height", "width"} make a bigger kicker (Snow Slide).
				var kicker: Ramp = RAMP.instantiate()
				kicker.length = params.get("length", kicker.length)
				kicker.height = params.get("height", kicker.height)
				kicker.width = params.get("width", kicker.width)
				_spawn_node(kicker, frame)
				var run_up := kicker.length * 0.5 if params.has("length") else 0.0
				track.mark_unsafe(distance - unsafe_margin - run_up, distance + unsafe_margin)
			"boulder":
				var boulder: RoadBoulder = BOULDER.instantiate()
				boulder.radius = params.get("radius", boulder.radius)
				boulder.height = params.get("height", boulder.height)
				boulder.random_seed = roundi(distance)
				boulder.color = params.get("color", track.theme.road_boulder_color if track.theme else boulder.color)
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
				hazard.track_distance = distance
				# Road space: centered on the road, whatever the lateral sign.
				_place(hazard, frame.translated_local(Vector3(-lateral, 0.0, 0.0)))
				track.mark_unsafe(distance - unsafe_margin, distance + unsafe_margin)
			"falling_rock", "rolling_rock":
				var rock: RollingRock = (FALLING_ROCK if kind == "falling_rock" else ROLLING_ROCK).instantiate()
				rock.track = track
				rock.from_side = -1 if lateral < 0.0 else 1
				rock.half_width = track.half_width_at(track.path.index_at_distance(distance))
				rock.period = params.get("period", rock.period)
				rock.phase = params.get("phase", rock.phase)
				rock.drop_height = params.get("height", rock.drop_height)
				rock.random_seed = roundi(distance)
				rock.track_distance = distance
				rock.rest_time = params.get("rest", rock.rest_time)
				rock.landing_share = params.get("land", rock.landing_share)
				if track.theme:
					rock.color = track.theme.road_boulder_color
				_place(rock, frame.translated_local(Vector3(-lateral, 0.0, 0.0)))
				track.mark_unsafe(distance - unsafe_margin - (rock.downhill_drift if kind == "rolling_rock" else 0.0),
						distance + unsafe_margin + (rock.downhill_drift if kind == "rolling_rock" else 0.0))
			"falling_tree":
				var tree: FallingTree = FALLING_TREE.instantiate()
				tree.track = track
				tree.from_side = -1 if lateral < 0.0 else 1
				tree.half_width = track.half_width_at(track.path.index_at_distance(distance))
				tree.track_distance = distance
				tree.period = params.get("period", tree.period)
				tree.phase = params.get("phase", tree.phase)
				tree.reach = params.get("reach", tree.reach)
				tree.down_time = params.get("down", tree.down_time)
				if track.theme and not track.theme.pine_greens.is_empty():
					tree.leaf_color = track.theme.pine_greens[0]
				_place(tree, frame.translated_local(Vector3(-lateral, 0.0, 0.0)))
				track.mark_unsafe(distance - unsafe_margin - 4.0, distance + unsafe_margin + 4.0)
			"rockslide":
				# Three rocks 9 m apart along the road, half a second apart,
				# landing in different lanes; the middle one stays a while.
				var slide_side := -1 if lateral < 0.0 else 1
				var lanes: Array[float] = [0.7, 0.1, 0.4]
				for k in 3:
					var along := distance + (k - 1) * 9.0
					var slide: RollingRock = FALLING_ROCK.instantiate()
					slide.track = track
					slide.from_side = slide_side
					slide.half_width = track.half_width_at(track.path.index_at_distance(along))
					slide.period = params.get("period", 11.0)
					slide.phase = float(params.get("phase", 0.0)) - k * 0.5
					slide.track_distance = distance
					slide.landing_share = lanes[k]
					slide.rest_time = float(params.get("rest", 3.0)) if k == 1 else 0.0
					slide.radius = 1.05 if k == 1 else 0.85
					slide.random_seed = roundi(along)
					slide.rumble = k == 0
					if track.theme:
						slide.color = track.theme.road_boulder_color
					_place(slide, track.path.get_frame(track.path.index_at_distance(along)))
				track.mark_unsafe(distance - unsafe_margin - 9.0, distance + unsafe_margin + 9.0)
			"barricade":
				var usable := track.half_width_at(track.path.index_at_distance(distance)) - 2.6
				var across := -usable
				while across <= usable + 0.01:
					_spawn(CRATE, frame, Vector3(across - lateral, 0.55, 0.0))
					_spawn(CRATE, frame, Vector3(across - lateral, 1.6, 0.0))
					across += 1.08
			"snowman":
				_spawn(SNOWMAN, frame, Vector3(0.0, 0.6, 0.0))
			"snowman_group":
				for x in [-2.2, 0.0, 2.2]:
					_spawn(SNOWMAN, frame, Vector3(x, 0.6, -absf(x) * 0.4))
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
