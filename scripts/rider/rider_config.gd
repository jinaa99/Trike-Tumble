class_name RiderConfig
extends Resource
## Tunable values for the rider ejection / recovery loop.
## Edit res://resources/rider/default_rider_config.tres in the inspector.

@export_group("Ejection")
## Trike impact (unexplained velocity change, m/s) that throws the rider off.
## Measured: a head-on wall hit reads about 1.1x the hit speed; scrapes,
## crates and ramp landings stay under 2. 11 ~= a head-on hit at 37 km/h.
@export var eject_impact_strength := 11.0
## Trike up-vector Y below this (tilted > ~70°) counts as overturned...
@export_range(-1.0, 1.0) var eject_tilt_up := 0.35
## ...for this long, then the rider falls off.
@export var eject_tilt_time := 0.2
## No ejection for this long after getting back on (no repeat triggers).
@export var eject_grace_time := 1.5
## Share of the trike's pre-impact velocity the rider keeps (flies onward).
@export_range(0.0, 1.5) var fling_carry := 0.75
## Extra upward launch speed (m/s).
@export var fling_up_speed := 7.0
## Forward somersault spin (rad/s) plus a random wobble.
@export var fling_spin := 9.0
@export var fling_wobble := 3.0
## Seed for the random spin wobble (same seed = same tumble; good for replays/netcode).
@export var fling_seed := 7

@export_group("Fall")
## Minimum time from ejection to getting up, so the fall reads (seconds).
@export var min_fall_time := 1.0
## Hard cap on the fall (seconds), even if still sliding.
@export var max_fall_time := 2.0
## Below these speeds for settle_time the rider counts as settled.
@export var settle_speed := 1.2
@export var settle_spin := 2.5
@export var settle_time := 0.2
## Damping once the rider has hit the ground (makes the tumble settle).
@export var ground_linear_damp := 1.6
@export var ground_angular_damp := 3.0

@export_group("Get up")
@export var get_up_duration := 1.0
## Thrown off the road (over a barrier, down a slope): the rider climbs back
## onto the road no farther than this from the trike (keeps recovery quick).
@export var offroad_recover_max_distance := 8.0

@export_group("On foot")
@export var run_speed := 6.5
@export var acceleration := 40.0
@export var turn_speed := 12.0
@export var gravity := 20.0

@export_group("Mounting")
## Max distance (m) from the trike seat at which [E] GET ON works.
@export var mount_distance := 2.6
## The trike must be (nearly) stopped to get on.
@export var mount_max_trike_speed := 4.0
@export var mount_duration := 0.7
## Height of the hop onto the seat (m).
@export var mount_hop_height := 0.6
