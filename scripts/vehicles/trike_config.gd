class_name TrikeConfig
extends Resource
## All tunable handling values for a trike.
##
## Units: meters, seconds, m/s, m/s² (accelerations are mass-independent),
## rad/s for yaw rates. Edit res://resources/vehicles/default_trike_config.tres
## in the inspector to tune without touching code.

@export_group("Geometry")
## Front wheel mount point in trike local space (top of suspension travel).
@export var front_wheel_mount := Vector3(0.0, 0.08, -0.95)
## Right rear wheel mount; the left one is mirrored on X.
@export var rear_wheel_mount := Vector3(0.62, 0.0, 0.6)
@export var front_wheel_radius := 0.38
@export var rear_wheel_radius := 0.3

@export_group("Suspension")
@export var suspension_rest_length := 0.35
## Spring force in Newtons per meter of compression (per wheel).
@export var spring_strength := 6000.0
## Damper force in Newtons per m/s of compression speed (per wheel).
@export var spring_damping := 550.0
## Safety cap so hard landings cannot launch the trike.
@export var max_suspension_force := 9000.0

@export_group("Engine")
## Top speed reachable with throttle alone on flat ground (m/s). 26 m/s ≈ 94 km/h.
@export var max_speed := 26.0
## Acceleration at standstill; fades to zero at max_speed.
@export var acceleration := 14.0
@export var brake_deceleration := 24.0
@export var reverse_acceleration := 8.0
@export var max_reverse_speed := 7.0
## Deceleration while coasting (no throttle, no brake).
@export var rolling_resistance := 1.5
## Below this speed with no input the trike holds still (no creeping on slopes).
@export var idle_hold_speed := 0.8
## Quadratic drag coefficient: decel = air_drag * speed².
@export var air_drag := 0.0015

@export_group("Steering")
## Max yaw rate at low/medium speed (rad/s).
@export var turn_rate := 2.3
## Turn rate multiplier at max_speed (lower = calmer at high speed).
@export_range(0.1, 1.0) var high_speed_turn_factor := 0.55
## Speed at which steering reaches full authority (no turning on the spot).
@export var steer_full_speed := 4.0
## How fast the steering input ramps (units of full lock per second).
@export var steer_speed := 6.0
## How quickly actual yaw rate chases the target yaw rate (1/s).
@export var yaw_response := 10.0
## Cap on yaw correction (rad/s²) so collisions can still spin the trike.
@export var max_yaw_accel := 14.0
## Visual front wheel lock angle.
@export var max_steer_angle_deg := 30.0
## Visual lock multiplier at max_speed.
@export_range(0.1, 1.0) var high_speed_steer_factor := 0.45

@export_group("Grip")
## How fast sideways velocity is removed (1/s). Higher = more planted.
@export var grip := 12.0
## Max sideways acceleration tires can provide (m/s²).
@export var max_lateral_accel := 26.0
## Share of the speed removed by sideways grip that is redirected forward
## instead of lost (0 = realistic scrub, 1 = no speed loss when turning).
@export_range(0.0, 1.0) var grip_speed_retention := 0.6
@export_range(0.0, 1.0) var drift_speed_retention := 0.85

@export_group("Drift")
@export var drift_min_speed := 8.0
## Steering needed (0..1) when pressing drift to enter a drift.
@export_range(0.0, 1.0) var drift_steer_threshold := 0.3
## Sideways grip while drifting (1/s). Steady drift angle ≈ asin(yaw rate / drift_grip).
@export var drift_grip := 2.6
@export var drift_max_lateral_accel := 30.0
## Yaw rate held while drifting with neutral steering (rad/s).
@export var drift_yaw_rate := 1.05
## How much steering tightens (+) or widens (−) the drift (rad/s).
@export var drift_steer_range := 0.45
## Small upward velocity when a drift starts (0 disables the hop).
@export var drift_hop_speed := 1.8
## Drift time needed for boost tier 1 and tier 2.
@export var drift_boost_tier_times := Vector2(0.9, 2.0)
## Boost duration awarded for tier 1 and tier 2.
@export var drift_boost_durations := Vector2(0.5, 1.0)
@export var boost_acceleration := 14.0
@export var boost_max_speed := 34.0
## Handbrake (drift held without steering) deceleration and grip.
@export var handbrake_deceleration := 7.0
@export var handbrake_grip := 4.0

@export_group("Stability")
## Grounded: how strongly the body aligns to the ground normal (1/s²).
@export var upright_strength := 14.0
@export var upright_damping := 5.0
## Airborne: how strongly the body rights itself toward world up.
@export var air_upright_strength := 5.0
@export var air_upright_damping := 1.5
## Yaw rate the player can add while airborne (rad/s).
@export var air_turn_rate := 1.2

@export_group("Riderless")
## Deceleration while nobody is aboard (feet off, nobody pedaling), so an
## abandoned trike rolls to a stop instead of coasting down the mountain.
@export var riderless_brake_deceleration := 5.0
## Velocity changes below this are not reported as impacts (m/s per tick).
@export var impact_report_threshold := 1.0

@export_group("Surfaces")
## Off-road (grass slopes beside the track) and mud. The speed factor scales
## max_speed and boost_max_speed; above that the surface drag (m/s²) slows
## the trike; the grip factor scales sideways grip. Road and bridge planks
## use the plain values.
@export_range(0.1, 1.0) var grass_speed_factor := 0.65
@export var grass_drag := 5.0
@export_range(0.1, 1.0) var grass_grip_factor := 0.8
@export_range(0.1, 1.0) var mud_speed_factor := 0.5
@export var mud_drag := 8.0
@export_range(0.1, 1.0) var mud_grip_factor := 0.55
## Packed snow road (Snow Slide): a little less grip and top speed than dirt.
@export_range(0.1, 1.0) var snow_speed_factor := 0.96
@export var snow_drag := 2.0
@export_range(0.1, 1.0) var snow_grip_factor := 0.8
## Ice: full speed but little sideways grip (the trike slides wide).
@export_range(0.1, 1.0) var ice_speed_factor := 1.0
@export var ice_drag := 0.0
@export_range(0.1, 1.0) var ice_grip_factor := 0.32

@export_group("Recovery")
## Body up·world up below this counts as overturned.
@export var flipped_up_threshold := 0.3
## Seconds overturned before automatic recovery.
@export var flipped_recover_time := 1.5
## Speed under which the trike counts as stuck while the player gives input.
@export var stuck_speed := 0.75
## Seconds stuck (fewer than 2 wheels touching) before automatic recovery.
@export var stuck_recover_time := 3.0
