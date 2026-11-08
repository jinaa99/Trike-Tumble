class_name NetSnapshot
extends RefCounted
## Compact network form of one racer's state (trike + rider), sent by the
## owner ~30 times a second, validated by the host and interpolated by
## everyone else. Array layout (FIELD_COUNT entries):
##   0 t (owner clock, s)  1 position  2 rotation (Quaternion)  3 velocity
##   4 steer_amount  5 steer_angle  6 forward_speed  7 drift_dir  8 drift_charge
##   9 boost  10 suspension (PackedFloat32Array[3])  11 wheel contact bits
##   12 has_rider  13 rider state  14 rider state_time  15 ragdoll position
##   16 ragdoll rotation  17 on-foot position  18 on-foot facing (yaw)
##   19 teleport counter (owner respawns: never interpolate across one)

const FIELD_COUNT := 20
## Host sanity limits: anything beyond is dropped (corrupt or bogus data).
const MAX_SPEED := 80.0
const MAX_COORD := 20000.0


static func encode(t: float, trike: Dictionary, rider: Dictionary) -> Array:
	var xf: Transform3D = trike["xf"]
	var rag: Transform3D = rider["ragdoll_xf"]
	return [t, xf.origin, xf.basis.get_rotation_quaternion(), trike["vel"], trike["steer_amount"], trike["steer_angle"],
			trike["forward_speed"], trike["drift_dir"], trike["drift_charge"], trike["boost"], trike["susp"],
			trike["contact"], trike["has_rider"], int(rider["state"]), rider["state_time"], rag.origin,
			rag.basis.get_rotation_quaternion(), rider["foot"], rider["facing"], int(trike.get("teleports", 0))]


## "" if `data` is a well-formed, plausible snapshot, else why not.
static func validate(data: Variant) -> String:
	if not data is Array or (data as Array).size() != FIELD_COUNT:
		return "malformed"
	var a := data as Array
	var types := [TYPE_FLOAT, TYPE_VECTOR3, TYPE_QUATERNION, TYPE_VECTOR3, TYPE_FLOAT, TYPE_FLOAT, TYPE_FLOAT, TYPE_INT,
			TYPE_FLOAT, TYPE_FLOAT, TYPE_PACKED_FLOAT32_ARRAY, TYPE_INT, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_VECTOR3,
			TYPE_QUATERNION, TYPE_VECTOR3, TYPE_FLOAT, TYPE_INT]
	for i in FIELD_COUNT:
		if typeof(a[i]) != types[i]:
			return "field %d has the wrong type" % i
	for i in [1, 3, 15, 17]:
		var v: Vector3 = a[i]
		if not v.is_finite() or v.length() > MAX_COORD:
			return "field %d out of range" % i
	if (a[3] as Vector3).length() > MAX_SPEED:
		return "impossible speed"
	if not (a[2] as Quaternion).is_finite() or not (a[16] as Quaternion).is_finite():
		return "bad rotation"
	if (a[10] as PackedFloat32Array).size() != 3 or int(a[13]) < 0 or int(a[13]) > RiderController.State.MOUNTING:
		return "bad rider/suspension data"
	return ""


static func time_of(data: Array) -> float:
	return data[0]


## Interpolates two snapshots (w = 0..1) into trike/rider dictionaries for
## Trike.apply_network_state / RiderController.apply_network_state.
## Discrete values (states, flags) come from `a`.
static func blend(a: Array, b: Array, w: float) -> Dictionary:
	if int(a[19]) != int(b[19]):
		# A teleport happened between the two: show one side, never in between.
		var side := b if w > 0.0 else a
		a = side
		b = side
		w = 0.0
	var rot := (a[2] as Quaternion).slerp(b[2], w)
	var susp := PackedFloat32Array()
	for i in 3:
		susp.append(lerpf((a[10] as PackedFloat32Array)[i], (b[10] as PackedFloat32Array)[i], w))
	var same_rider_state := int(a[13]) == int(b[13])
	var trike := {
		"xf": Transform3D(Basis(rot), (a[1] as Vector3).lerp(b[1], w)), "vel": (a[3] as Vector3).lerp(b[3], w),
		"steer_amount": lerpf(a[4], b[4], w), "steer_angle": lerpf(a[5], b[5], w), "forward_speed": lerpf(a[6], b[6], w),
		"drift_dir": a[7], "drift_charge": lerpf(a[8], b[8], w), "boost": lerpf(a[9], b[9], w), "susp": susp,
		"contact": a[11], "has_rider": a[12], "teleports": int(a[19]),
	}
	var rider := {
		"state": int(a[13]), "state_time": lerpf(a[14], b[14], w) if same_rider_state else float(a[14]),
		"ragdoll_xf": Transform3D(Basis((a[16] as Quaternion).slerp(b[16], w)), (a[15] as Vector3).lerp(b[15], w)),
		"foot": (a[17] as Vector3).lerp(b[17], w), "facing": lerp_angle(a[18], b[18], w),
	}
	return {"trike": trike, "rider": rider}


## Moves a snapshot forward `dt` seconds along its velocity (short gaps).
static func extrapolate(a: Array, dt: float) -> Dictionary:
	var result := blend(a, a, 0.0)
	var xf: Transform3D = result["trike"]["xf"]
	xf.origin += (a[3] as Vector3) * dt
	result["trike"]["xf"] = xf
	return result
