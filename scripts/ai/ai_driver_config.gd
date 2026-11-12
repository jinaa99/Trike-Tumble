class_name AIDriverConfig
extends Resource
## How an AI racer drives. One resource per difficulty
## (res://resources/ai/ai_easy.tres, ai_medium.tres, ai_hard.tres).
##
## Every value changes real driving behavior through TrikeInput. The AI uses
## the same trike and TrikeConfig as the player: no speed bonus, no
## teleporting along the track.

enum Difficulty { EASY, MEDIUM, HARD }

@export var difficulty := Difficulty.MEDIUM
@export var display_name := "Medium"

@export_group("Speed")
## Highest speed the AI aims for, as a share of TrikeConfig.max_speed.
@export_range(0.3, 1.0) var top_speed_ratio := 0.9
## Sideways acceleration (m/s²) the AI trusts in corners. Lower = slower,
## safer corners.
@export var corner_lateral_accel := 15.0
## Deceleration (m/s²) the AI plans its braking with. Lower = brakes earlier.
@export var planning_deceleration := 14.0
## Brake when this much (m/s) over the planned speed; coast in between.
@export var brake_margin := 1.5
## Throttle used while still under the planned speed but close to it.
@export_range(0.0, 1.0) var cruise_throttle := 0.6

@export_group("Steering")
## Look-ahead point distance: max(lookahead_min, speed × lookahead_time).
@export var lookahead_min := 7.0
@export var lookahead_time := 0.55
## Steering per radian of heading error toward the look-ahead point.
@export var steer_gain := 2.6
## How fast the steering input may change (full range per second / 2).
@export var steer_rate := 6.0
## Steering wobble (input units, 0..1): sloppier driving on easier levels.
@export_range(0.0, 0.5) var steer_noise := 0.06
@export var steer_noise_frequency := 0.7
## How far (0..1 of the free road half-width) the AI cuts to the inside of
## corners. 0 = stays in its lane.
@export_range(0.0, 1.0) var corner_cut := 0.25
## Lateral speed (m/s) for lane changes and dodges.
@export var lane_change_speed := 6.0
## Distance (m) kept from the barriers.
@export var edge_margin := 1.7

@export_group("Drifting")
## Chance (0..1) to drift through a corner that is sharp enough.
@export_range(0.0, 1.0) var drift_chance := 0.3
## Corners at least this sharp (1/m, i.e. 1/radius) can be drifted.
@export var drift_min_curvature := 0.03
## Minimum speed (m/s) to start a drift.
@export var drift_min_speed := 14.0

@export_group("Obstacles")
## How far ahead (m) props and other racers are noticed.
@export var avoid_distance := 40.0
## Extra clearance (m) on top of obstacle + trike size.
@export var avoid_margin := 0.5
## Seconds an obstacle must be in view before the AI reacts (reaction time).
@export var reaction_time := 0.25
## Also dodge cones (light props that are harmless to hit).
@export var avoid_cones := true

@export_group("Recovery")
## No forward progress this long while trying to drive = stuck.
@export var stuck_time := 1.2
## Reverse for this long to get unstuck.
@export var reverse_time := 1.0
## Unable to get going after this many reverse attempts: press reset (R),
## the same respawn a human player has.
@export var max_unstick_attempts := 3
## No new ground gained for this long (s): press reset (R).
@export var no_progress_time := 10.0
## Delay (s) before the AI starts driving when the race starts.
@export var start_delay := 0.2
## Delay (s) before pressing E once the GET ON prompt is available.
@export var mount_delay := 0.2
## Still on foot after this long (e.g. trike behind a barrier): press R, the
## same emergency recovery a human player has. 0 = never.
@export var on_foot_give_up_time := 15.0
## Within this distance (m) of the trike the rider walks instead of running.
@export var on_foot_slow_radius := 1.2

@export_group("Items")
## Seconds after getting an item before the AI thinks about using it.
@export var item_reaction := 0.6
## Uses a held item anyway after this long (except a punch without a target,
## which waits up to twice as long).
@export var item_max_hold := 10.0
## Throws a mud bomb at a racer ahead within this distance (m). At race
## speed the bomb reaches a racer ~16 m ahead.
@export var item_throw_range := 22.0
## ...and no more than this far (m) to the side of the AI's heading.
@export var item_throw_aim := 2.0
## Drops a banana when a racer is behind within this distance (m).
@export var item_drop_range := 22.0
## Punches a racer within this distance (m).
@export var item_punch_range := 6.5
## Uses a turbo when the road ahead is this straight (curvature, 1/m).
@export var item_turbo_max_curvature := 0.012
