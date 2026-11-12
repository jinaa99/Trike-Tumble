class_name ItemConfig
extends Resource
## Every tunable item value. Edit res://resources/items/default_item_config.tres.
##
## Balance rules built into these values: one item at a time, no item use
## while off the trike, a short immunity after any item hit (no chain-stuns),
## spring punch range-limited, ejection only from a point-blank punch, every
## slow-down effect is short, and the roll favors racers at the back.

@export_group("Boxes")
## Seconds before a collected box comes back.
@export var box_respawn_delay := 6.0
## A box only comes back when no trike is this close (never inside a racer).
@export var box_respawn_clearance := 3.5
## Distance (m) from the box center at which a passing trike collects it.
@export var box_pickup_radius := 1.9
## Host check: the racer must be this close (host's view) to the box.
## Generous because the host sees other players ~0.1–0.2 s in the past.
@export var plausible_distance := 14.0
## Seconds after using an item before the next box can be collected.
@export var pickup_cooldown := 0.6

@export_group("Roll")
## Roll weights in ItemKind.ALL order (mud bomb, spring punch, turbo, banana)
## for the race leader...
@export var leader_weights := PackedFloat32Array([3.0, 2.0, 1.0, 4.0])
## ...and for the last racer. Positions in between are blended.
@export var last_weights := PackedFloat32Array([2.0, 3.0, 5.0, 1.0])

@export_group("Use")
## Seconds the item must be held before it can be used (no instant
## pickup-and-fire at a racer right next to the box).
@export var use_delay := 0.35
## After any item hit, more item hits are ignored for this long.
@export var hit_immunity := 2.5

@export_group("Mud bomb")
## Throw speeds: at race speed a bomb lands ~35 m ahead and reaches a
## same-speed racer ~16 m ahead.
@export var mud_throw_speed := 26.0
@export var mud_throw_up_speed := 6.0
## Share of the thrower's own velocity the bomb inherits.
@export_range(0.0, 1.0) var mud_inherit_velocity := 0.8
@export var mud_gravity := 20.0
## Bomb flight is cut short after this long.
@export var mud_max_flight := 3.0
## A trike (chassis center, or the rider up to `mud_rider_height` above it)
## this close to the bomb is hit directly.
@export var mud_hit_radius := 1.7
@export var mud_rider_height := 1.4
@export var mud_patch_radius := 3.8
## Seconds the mud patch stays on the road.
@export var mud_patch_duration := 8.0
## The thrower isn't slowed by its own fresh puddle for this long (a forward
## throw would otherwise land right in its own path).
@export var mud_owner_grace := 3.0
## While in a patch the trike counts as slippery for this long (keeps sliding
## a moment after leaving it).
@export var mud_linger := 0.35
@export_range(0.1, 1.0) var mud_grip_factor := 0.3
@export_range(0.1, 1.0) var mud_speed_factor := 0.7
## Direct hit: slippery for this long and a small wobble.
@export var mud_direct_slip := 1.4
@export var mud_direct_spin := 2.5

@export_group("Spring punch")
## Opponents within this distance (m) and inside the cone can be punched.
@export var punch_range := 9.0
## Half-angle (deg) of the punch cone around the attacker's heading. Wide:
## it reaches racers beside you as well as ahead.
@export var punch_cone_deg := 110.0
## Sideways knock (m/s) at the edge of the range and at point-blank range.
@export var punch_min_speed := 5.0
@export var punch_max_speed := 10.0
@export var punch_up_speed := 2.5
@export var punch_spin := 3.0
## Grip loss after a punch so the trike slides instead of stopping dead.
@export var punch_slip := 0.6
@export_range(0.1, 1.0) var punch_grip_factor := 0.35
## Punch strength (knock speed, m/s) at or above which the rider is thrown off.
## Only reachable close in: point-blank punches eject.
@export var punch_eject_speed := 8.5

@export_group("Turbo bottle")
@export var turbo_duration := 2.2

@export_group("Banana peel")
## Dropped this far behind the trike's center.
@export var banana_drop_distance := 2.6
## The dropper can't slip on it for this long.
@export var banana_arm_time := 1.0
## Peel disappears after this long.
@export var banana_lifetime := 45.0
## Most peels on the track; the oldest goes first.
@export var banana_max_count := 8
@export var banana_trigger_radius := 1.3
## Spin-out: yaw spin (rad/s), speed kept and how long the grip stays low.
@export var banana_spin := 7.0
@export_range(0.0, 1.0) var banana_speed_keep := 0.55
@export var banana_slip := 1.0
@export_range(0.1, 1.0) var banana_grip_factor := 0.25
