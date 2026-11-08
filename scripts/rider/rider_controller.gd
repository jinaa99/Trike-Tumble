class_name RiderController
extends Node3D
## Rider ejection and recovery state machine (one per player).
##
##   RIDING ──(big impact / overturned)──▶ EJECTED ──(hits ground)──▶ RAGDOLL
##     ▲                                                                │ settled
##     │                                                                ▼
##  MOUNTING ◀──([E] near own trike)── ON_FOOT ◀──(animation done)── GETTING_UP
##
## Rider state lives here; the Trike only knows has_rider. While RIDING the
## trike drives from its own input source as before. Off the trike, this node
## reads the player's input, moves the rider (RiderRagdoll while falling,
## RiderOnFoot on foot) and poses the Rider model, which is detached from
## the trike (top_level) and follows whichever body is active.
##
## Every transition goes through _change_state() and emits state_changed,
## and get_sync_state() exposes everything a network peer needs.

signal state_changed(old_state: State, new_state: State)
signal ejected(impact_strength: float)
signal mounted
## Emitted when the [E] GET ON prompt should appear or disappear.
signal mount_prompt_changed(available: bool)
## The node the camera should follow changed.
signal focus_changed(node: Node3D)
## R pressed while off the trike. Race logic should put trike + rider back on
## the road. Without a listener the controller handles it itself.
signal emergency_recovery_requested

enum State { RIDING, EJECTED, RAGDOLL, GETTING_UP, ON_FOOT, MOUNTING }
const STATE_NAMES: Array[String] = ["RIDING", "EJECTED", "RAGDOLL", "GETTING_UP", "ON_FOOT", "MOUNTING"]

@export var trike: Trike
@export var config: RiderConfig
## Optional. When null, write to `input` directly (tests, AI, network).
@export var input_source: TrikeInputSource
## Optional. When set, getting up off the road puts the rider back on it.
@export var track: Track

var input := TrikeInput.new()
var state := State.RIDING
## Seconds spent in the current state.
var state_time := 0.0
var can_mount := false
var eject_count := 0

var _rider: Rider
var _grace_time := 0.0
var _tilt_time := 0.0
var _pending_impact := 0.0
var _pending_impact_velocity := Vector3.ZERO
var _fall_time := 0.0
var _get_up_from := Transform3D.IDENTITY
var _mount_from := Transform3D.IDENTITY
var _rng := RandomNumberGenerator.new()
var _ignoring_trike := false
## Network proxy: the owner simulates this rider; state and body transforms
## arrive through apply_network_state(). No local input, physics or ejection.
var network_proxy := false

@onready var ragdoll: RiderRagdoll = $Ragdoll
@onready var on_foot: RiderOnFoot = $OnFoot
@onready var _stars: Node3D = $DizzyStars


func _ready() -> void:
	if config == null:
		config = RiderConfig.new()
	_rng.seed = config.fling_seed
	_stars.visible = false
	on_foot.add_collision_exception_with(ragdoll)
	# A trike set before we were ready (scene export or an early attach_to)
	# is bound now, once the child bodies exist.
	if trike:
		_bind(trike)


## Binds this rider to a trike. Safe to call at any time and repeatedly:
## before _ready the binding is deferred to _ready; calling it again with the
## same trike does nothing; a different trike replaces the old binding.
## Returns false if `target` is not a usable trike.
func attach_to(target: Trike) -> bool:
	if not _is_valid_trike(target):
		return false  # null or freed (e.g. a despawned racer): nothing to bind
	if target.get_node_or_null(^"Visuals/Rider") == null:
		push_error("RiderController.attach_to: trike has no Visuals/Rider model.")
		return false
	if not is_node_ready():
		trike = target  # bound in _ready
		return true
	return _bind(target)


## Releases the current trike (signals, flags). Safe if nothing is attached
## or the trike was already freed.
func detach() -> void:
	if _is_valid_trike(trike) and trike.impact.is_connected(_on_trike_impact):
		trike.impact.disconnect(_on_trike_impact)
	if _is_valid_trike(trike) and is_node_ready():
		ragdoll.remove_collision_exception_with(trike)
		trike.auto_recover_when_flipped = true
	trike = null
	_rider = null
	_set_can_mount(false)


func is_attached() -> bool:
	return _is_valid_trike(trike) and _rider != null and is_instance_valid(_rider)


func _bind(target: Trike) -> bool:
	if target == trike and is_attached() and trike.impact.is_connected(_on_trike_impact):
		return true  # already bound to this trike
	if _is_valid_trike(trike) and trike != target:
		detach()
	var model := target.get_node_or_null(^"Visuals/Rider") as Rider
	if model == null:
		push_error("RiderController: trike has no Visuals/Rider model.")
		return false
	trike = target
	_rider = model
	trike.auto_recover_when_flipped = false
	if not trike.impact.is_connected(_on_trike_impact):
		trike.impact.connect(_on_trike_impact)
	return true


static func _is_valid_trike(target: Object) -> bool:
	return target != null and is_instance_valid(target) and not (target as Node).is_queued_for_deletion()


func is_riding() -> bool:
	return state == State.RIDING


func get_state_name() -> String:
	return STATE_NAMES[state]


## The node the camera should follow right now.
func get_focus_node() -> Node3D:
	match state:
		State.EJECTED, State.RAGDOLL:
			return ragdoll
		State.GETTING_UP, State.ON_FOOT:
			return on_foot
	return trike


## Where the rider is in the world (model position).
func get_rider_position() -> Vector3:
	match state:
		State.EJECTED, State.RAGDOLL:
			return ragdoll.global_position
		State.GETTING_UP, State.ON_FOOT:
			return on_foot.global_position
	return _rider.global_position if _rider else global_position


## Everything a network peer needs to reproduce this rider.
func get_sync_state() -> Dictionary:
	return {
		"state": state, "state_time": state_time,
		"ragdoll_xf": ragdoll.global_transform, "ragdoll_vel": ragdoll.linear_velocity,
		"on_foot_pos": on_foot.global_position, "on_foot_facing": on_foot.facing,
	}


## Turns this rider into a network proxy: no ejection from local impacts,
## ragdoll frozen (moved by the network), no input.
func set_network_proxy(enabled: bool) -> void:
	network_proxy = enabled
	input_source = null
	if enabled and is_attached() and trike.impact.is_connected(_on_trike_impact):
		trike.impact.disconnect(_on_trike_impact)
	ragdoll.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC


## Owner side: rider state for the network.
func get_network_state() -> Dictionary:
	var facing_forward := -on_foot.facing.z
	return {
		"state": state, "state_time": state_time,
		"ragdoll_xf": ragdoll.global_transform,
		"foot": on_foot.global_position, "facing": atan2(-facing_forward.x, -facing_forward.z),
	}


## Proxy side: follows the owner's rider state, using the same transitions
## (model on/off the seat, poses) the local state machine uses.
func apply_network_state(data: Dictionary) -> void:
	if not is_attached():
		return
	var new_state: State = data["state"]
	if new_state != state:
		_enter_remote_state(new_state)
	state_time = data["state_time"]
	if state == State.EJECTED or state == State.RAGDOLL:
		ragdoll.global_transform = data["ragdoll_xf"]
	elif state == State.GETTING_UP or state == State.ON_FOOT:
		on_foot.global_position = data["foot"]
		on_foot.facing = Basis(Vector3.UP, data["facing"])


func _enter_remote_state(new_state: State) -> void:
	var was_riding := state == State.RIDING
	if was_riding:
		trike.set_rider_aboard(false)
		_detach_model()
	match new_state:
		State.EJECTED, State.RAGDOLL:
			ragdoll.process_mode = Node.PROCESS_MODE_INHERIT
			ragdoll.freeze = true
			on_foot.deactivate()
			_rider.set_pose_mode(Rider.PoseMode.FLAIL)
			if was_riding:
				eject_count += 1
		State.GETTING_UP:
			_get_up_from = _rider.global_transform
			ragdoll.deactivate()
			on_foot.process_mode = Node.PROCESS_MODE_INHERIT
			_rider.set_pose_mode(Rider.PoseMode.GET_UP)
		State.ON_FOOT:
			ragdoll.deactivate()
			on_foot.process_mode = Node.PROCESS_MODE_INHERIT
		State.MOUNTING:
			_mount_from = _rider.global_transform
			ragdoll.deactivate()
			on_foot.deactivate()
			_rider.set_pose_mode(Rider.PoseMode.RIDE)
		State.RIDING:
			ragdoll.deactivate()
			on_foot.deactivate()
			_attach_model()
			trike.set_rider_aboard(true)
	var entering_ejection := was_riding and new_state != State.RIDING
	_change_state(new_state)
	if entering_ejection:
		ejected.emit(0.0)
	elif new_state == State.RIDING:
		mounted.emit()


## Throws the rider off now (also used by tests and future items).
func eject(impact_strength := 0.0, velocity_before := Vector3.ZERO) -> void:
	if state != State.RIDING or not is_attached():
		return
	if velocity_before == Vector3.ZERO:
		velocity_before = trike.linear_velocity
	var seat := _rider.global_transform
	trike.set_rider_aboard(false)
	_detach_model()
	_rider.set_pose_mode(Rider.PoseMode.FLAIL)
	var forward := -trike.global_basis.z
	var right := trike.global_basis.x
	var velocity := velocity_before * config.fling_carry + Vector3.UP * config.fling_up_speed
	var wobble := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
	var spin := -right * config.fling_spin + wobble * config.fling_wobble
	var center := seat * Rider.FALL_CENTER + Vector3.UP * 0.2 + forward * 0.2
	# Don't collide with our own trike until clear of it (avoids a pop from
	# starting inside the seat), then bounce off it like anything else.
	ragdoll.add_collision_exception_with(trike)
	_ignoring_trike = true
	ragdoll.launch(Transform3D(seat.basis, center), velocity, spin)
	_fall_time = 0.0
	eject_count += 1
	_change_state(State.EJECTED)
	ejected.emit(impact_strength)


## Puts the rider straight back on the seat (emergency recovery / respawn).
func force_mount() -> void:
	if not is_attached():
		return
	ragdoll.deactivate()
	on_foot.deactivate()
	_attach_model()
	trike.set_rider_aboard(true)
	_grace_time = config.eject_grace_time
	_change_state(State.RIDING)


func _physics_process(delta: float) -> void:
	if not is_attached():
		if trike != null or _rider != null:
			_release_freed_trike()
		return
	state_time += delta
	if network_proxy:
		return
	if state == State.RIDING:
		_physics_riding(delta)
		return

	if input_source:
		input_source.poll(input)
	if input.reset_pressed:
		input.reset_pressed = false
		_request_emergency_recovery()
		return

	match state:
		State.EJECTED, State.RAGDOLL:
			_physics_falling(delta)
		State.GETTING_UP:
			on_foot.move(Vector3.ZERO, delta, config)
			if state_time >= config.get_up_duration:
				_change_state(State.ON_FOOT)
		State.ON_FOOT:
			_physics_on_foot(delta)
		State.MOUNTING:
			if state_time >= config.mount_duration:
				_finish_mount()
	input.interact_pressed = false


func _process(delta: float) -> void:
	if not is_attached() or state == State.RIDING:
		return
	match state:
		State.EJECTED, State.RAGDOLL:
			var body := ragdoll.get_global_transform_interpolated()
			_rider.global_transform = body * Transform3D(Basis.IDENTITY, -Rider.FALL_CENTER)
			_rider.update_free_pose(delta)
		State.GETTING_UP:
			var p := clampf(state_time / config.get_up_duration, 0.0, 1.0)
			var standing := _standing_transform()
			var blend := smoothstep(0.0, 0.45, p)
			_rider.global_transform = Transform3D(
				_get_up_from.basis.slerp(standing.basis, blend).orthonormalized(),
				_get_up_from.origin.lerp(standing.origin, blend))
			_rider.update_free_pose(delta, 0.0, p)
			_place_stars(delta, true)
		State.ON_FOOT:
			_rider.global_transform = _standing_transform()
			_rider.update_free_pose(delta, on_foot.get_speed_ratio(config))
			_place_stars(delta, state_time < 0.6)
		State.MOUNTING:
			var p := clampf(state_time / config.mount_duration, 0.0, 1.0)
			var eased := smoothstep(0.0, 1.0, p)
			var seat := trike.get_global_transform_interpolated()
			var origin := _mount_from.origin.lerp(seat.origin, eased) + Vector3.UP * sin(p * PI) * config.mount_hop_height
			_rider.global_transform = Transform3D(_mount_from.basis.slerp(seat.basis, eased).orthonormalized(), origin)
			# Seated pose with hands reaching for the grips and feet for the pegs.
			_rider.update_pose(0.0, 0.0, delta)


# --- States -----------------------------------------------------------------

func _physics_riding(delta: float) -> void:
	_grace_time = maxf(_grace_time - delta, 0.0)
	var impact := _pending_impact
	var impact_velocity := _pending_impact_velocity
	_pending_impact = 0.0
	if trike.global_basis.y.y < config.eject_tilt_up:
		_tilt_time += delta
	else:
		_tilt_time = 0.0
	if _grace_time > 0.0:
		return
	if impact >= config.eject_impact_strength:
		eject(impact, impact_velocity)
	elif _tilt_time >= config.eject_tilt_time:
		eject(0.0, trike.linear_velocity)


func _physics_falling(delta: float) -> void:
	_fall_time += delta
	ragdoll.update_fall(delta, config)
	if _ignoring_trike and ragdoll.global_position.distance_to(trike.global_position) > 1.6:
		ragdoll.remove_collision_exception_with(trike)
		_ignoring_trike = false
	if state == State.EJECTED and ragdoll.has_touched_ground():
		_change_state(State.RAGDOLL)
	var lost := _is_lost(ragdoll.global_position)
	var settled := ragdoll.is_settled(config) and _fall_time >= config.min_fall_time
	if settled or lost or _fall_time >= config.max_fall_time:
		_begin_get_up()


func _begin_get_up() -> void:
	_get_up_from = _rider.global_transform
	var spot := _ground_below(ragdoll.global_position)
	if track and (spot == Vector3.INF or not _is_on_road(spot)):
		spot = _nearest_road_spot(ragdoll.global_position)
		var from_trike := spot - trike.global_position
		if from_trike.length() > config.offroad_recover_max_distance:
			spot = _nearest_road_spot(trike.global_position + from_trike.normalized() * config.offroad_recover_max_distance)
	elif spot == Vector3.INF:
		spot = ragdoll.global_position
	ragdoll.deactivate()
	on_foot.activate(spot, trike.global_position - spot)
	_rider.set_pose_mode(Rider.PoseMode.GET_UP)
	_change_state(State.GETTING_UP)


func _physics_on_foot(delta: float) -> void:
	on_foot.move(_move_direction(), delta, config)
	if _is_lost(on_foot.global_position):
		on_foot.activate(_nearest_road_spot(on_foot.global_position), trike.global_position - on_foot.global_position)
	var near := on_foot.global_position.distance_to(trike.global_position) <= config.mount_distance
	var slow := trike.linear_velocity.length() <= config.mount_max_trike_speed
	_set_can_mount(near and slow)
	if can_mount and input.interact_pressed:
		_begin_mount()


func _begin_mount() -> void:
	_set_can_mount(false)
	_mount_from = _rider.global_transform
	on_foot.deactivate()
	if trike.global_basis.y.y < 0.7:
		trike.set_upright()
	_rider.set_pose_mode(Rider.PoseMode.RIDE)
	_change_state(State.MOUNTING)


func _finish_mount() -> void:
	_attach_model()
	trike.set_rider_aboard(true)
	_grace_time = config.eject_grace_time
	_change_state(State.RIDING)
	mounted.emit()


# --- Helpers ----------------------------------------------------------------

## The trike (or its rider model) was freed under us: stop driving bodies
## and forget it. A new attach_to() starts fresh.
func _release_freed_trike() -> void:
	ragdoll.deactivate()
	on_foot.deactivate()
	_stars.visible = false
	trike = null
	_rider = null
	_set_can_mount(false)
	if state != State.RIDING:
		_change_state(State.RIDING)

func _change_state(new_state: State) -> void:
	var old := state
	state = new_state
	state_time = 0.0
	_tilt_time = 0.0
	if new_state != State.ON_FOOT:
		_set_can_mount(false)
	if new_state == State.ON_FOOT:
		_rider.set_pose_mode(Rider.PoseMode.STAND)
	_stars.visible = new_state == State.GETTING_UP
	state_changed.emit(old, new_state)
	if _focus_for(old) != _focus_for(new_state):
		focus_changed.emit(get_focus_node())


func _focus_for(s: State) -> int:
	match s:
		State.EJECTED, State.RAGDOLL:
			return 1
		State.GETTING_UP, State.ON_FOOT:
			return 2
	return 0


func _set_can_mount(value: bool) -> void:
	if can_mount != value:
		can_mount = value
		mount_prompt_changed.emit(value)


func _on_trike_impact(strength: float, velocity_before: Vector3) -> void:
	if strength > _pending_impact:
		_pending_impact = strength
		_pending_impact_velocity = velocity_before


func _request_emergency_recovery() -> void:
	if emergency_recovery_requested.get_connections().is_empty():
		trike.request_respawn()
		force_mount()
	else:
		emergency_recovery_requested.emit()


## Model off the trike: it follows the active body from now on.
func _detach_model() -> void:
	var xf := _rider.global_transform
	_rider.top_level = true
	_rider.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rider.global_transform = xf


## Model back on the seat.
func _attach_model() -> void:
	_rider.top_level = false
	_rider.transform = Transform3D.IDENTITY
	_rider.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	_rider.set_pose_mode(Rider.PoseMode.RIDE)
	_rider.reset_physics_interpolation()
	_stars.visible = false


func _standing_transform() -> Transform3D:
	var body := on_foot.get_global_transform_interpolated()
	var feet := Transform3D(on_foot.facing, body.origin)
	return feet * Transform3D(Basis.IDENTITY, Rider.STAND_ROOT_OFFSET)


## Camera-relative movement from WASD/arrows (forward = away from camera),
## or the world-space direction an AI/network source wrote.
func _move_direction() -> Vector3:
	if input.move_direction != Vector3.ZERO:
		var world := input.move_direction
		world.y = 0.0
		return world.limit_length(1.0)
	var forward := Vector3.FORWARD
	var right := Vector3.RIGHT
	var camera := get_viewport().get_camera_3d()
	if camera:
		forward = -camera.global_basis.z
		right = camera.global_basis.x
	forward.y = 0.0
	right.y = 0.0
	var direction := forward.normalized() * (input.throttle - input.brake) + right.normalized() * input.steer
	return direction.limit_length(1.0)


func _place_stars(delta: float, visible_now: bool) -> void:
	_stars.visible = visible_now
	if visible_now:
		_stars.global_position = _rider.get_head_global_position() + Vector3.UP * (0.5 + sin(state_time * 9.0) * 0.04)
		_stars.rotate_y(delta * 7.0)


func _ground_below(from: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.5, from + Vector3.DOWN * 4.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return Vector3.INF if hit.is_empty() else hit["position"]


func _is_lost(position: Vector3) -> bool:
	if position.y < trike.global_position.y - 25.0:
		return true
	if track == null:
		return false
	return track.is_out_of_bounds(position, track.path.find_nearest(position))


func _is_on_road(position: Vector3) -> bool:
	return track.is_on_road(position, track.path.find_nearest(position))


## Nearest point on the road near the trike (never a different road section).
func _nearest_road_spot(from: Vector3) -> Vector3:
	var path := track.path
	var index := path.find_nearest(from, path.find_nearest(trike.global_position), 40)
	var frame := path.get_frame(index)
	var half := track.half_width_at(index) - 1.5
	var lateral := clampf((from - frame.origin).dot(frame.basis.x), -half, half)
	return frame.origin + frame.basis.x * lateral + frame.basis.y * 0.1
