class_name SkillConfig
extends Resource
## Every tunable value of the signature skills, slipstream, near misses and
## taunts. Edit res://resources/skills/default_skill_config.tres.
##
## Balance rules built into these values: every skill has a cooldown of
## 10–18 s, attacks are short-range with a cone, traps arm late and glow,
## nothing chains (shared hit immunity with items) and nobody is thrown off
## twice in a row by skills or items (eject_guard).

@export_group("General")
## Seconds after GO before any skill can be used.
@export var start_lockout := 4.0
## Cooldown multiplier for the race leader and for the last racer; positions
## in between are blended (a small comeback tilt).
@export var leader_cooldown_factor := 1.15
@export var last_cooldown_factor := 0.75
## After any skill hit, more item/skill hits on the victim are ignored for
## this long (same table as ItemConfig.hit_immunity).
@export var hit_immunity := 2.5
## A rider who was off the trike can't be thrown off by an item or skill for
## this long after getting back on.
@export var eject_guard := 6.0
## Host check: the racer must be this close (host's view) to what it claims
## to touch. Generous: the host sees others ~0.1–0.2 s in the past.
@export var plausible_distance := 14.0

@export_group("Zip: Slingshot")
@export var slingshot_cooldown := 12.0
## The rival must be this far ahead (m), within this sideways distance (m).
@export var slingshot_min_ahead := 2.5
@export var slingshot_max_ahead := 20.0
@export var slingshot_max_side := 3.5
## Boost seconds granted.
@export var slingshot_boost := 1.3

@export_group("Pip: Spring Bonk")
@export var bonk_cooldown := 14.0
## Cooldown after hitting nobody.
@export var bonk_whiff_cooldown := 6.0
@export var bonk_range := 5.0
## Half-angle (deg) around the attacker's heading: beside and ahead.
@export var bonk_cone_deg := 100.0
## Sideways shove (m/s) at the edge of the range and point-blank.
@export var bonk_min_speed := 4.5
@export var bonk_max_speed := 7.5
@export var bonk_up_speed := 1.6
@export var bonk_spin := 2.6
@export var bonk_slip := 0.55
@export_range(0.1, 1.0) var bonk_grip_factor := 0.4
## Closer than this (m) the bonk may throw the rider off (unless guarded).
@export var bonk_eject_distance := 1.8

@export_group("Bramble: Root Snare")
@export var snare_cooldown := 15.0
@export var snare_drop_distance := 3.0
@export var snare_lifetime := 14.0
## The dropper can't trip on it, and nobody can, for this long (warning time).
@export var snare_arm_time := 0.8
@export var snare_radius := 1.25
@export_range(0.0, 1.0) var snare_speed_keep := 0.6
## Sideways tug (m/s), wobble spin (rad/s) and loose-steering time (s).
@export var snare_pull := 3.5
@export var snare_spin := 1.6
@export var snare_slip := 0.9
@export_range(0.1, 1.0) var snare_grip_factor := 0.4
## Hitting the snare faster than this (m/s, boost speeds only) throws the
## rider off (unless guarded).
@export var snare_eject_speed := 29.0

@export_group("Nutmeg: Fake Box")
@export var fake_box_cooldown := 16.0
@export var fake_box_drop_distance := 3.5
@export var fake_box_lifetime := 25.0
@export var fake_box_arm_time := 1.0
@export var fake_box_radius := 1.7
@export_range(0.0, 1.0) var fake_box_speed_keep := 0.8
@export var fake_box_hop := 3.0
@export var fake_box_spin := 3.6
@export var fake_box_slip := 0.7
@export_range(0.1, 1.0) var fake_box_grip_factor := 0.45

@export_group("Rusty: Pillow Shield")
@export var shield_cooldown := 18.0
@export var shield_duration := 6.0
## While the shield is up a crash must be this many times the normal eject
## threshold to throw the rider off; a weaker one (but over the threshold)
## pops the shield instead.
@export var shield_impact_factor := 1.4

@export_group("Slipstream")
## Tucked in behind a rival: this far behind (m), within this sideways
## distance of its line (m), both above this speed (m/s).
@export var draft_min_behind := 3.0
@export var draft_max_behind := 16.0
@export var draft_max_side := 1.7
@export var draft_min_speed := 12.0
## Seconds in the tow to fill the meter, and to lose it again.
@export var draft_charge_time := 1.1
@export var draft_decay_time := 0.6
## Zip reads the air better: the meter fills this much faster.
@export var draft_zip_bonus := 1.4

@export_group("Near miss")
## Gap (m, surface to surface) that counts, and the speed (m/s) needed.
@export var near_miss_gap := 1.3
@export var near_miss_min_speed := 14.0
## Rivals only count when passed at least this much faster (m/s).
@export var near_miss_pass_speed := 2.0
@export var near_miss_boost := 0.35
## The same obstacle pays again only after this long; any near miss only
## after `near_miss_rearm`.
@export var near_miss_repeat := 25.0
@export var near_miss_rearm := 2.0
## An impact this recent (s) cancels the near miss: it was a hit.
@export var near_miss_impact_window := 0.6
@export var near_miss_radii := {"rock": 1.1, "boulder": 2.0, "road_tree": 0.6, "falling_log": 2.4, "falling_rock": 1.6,
		"rolling_rock": 2.2, "falling_tree": 0.9, "racer": 0.9}

@export_group("Taunt")
## Seconds between taunts of one racer.
@export var emote_cooldown := 2.5
## A racer overtaking another within this distance (m) teases them, at most
## once per this many seconds.
@export var overtake_tease_distance := 10.0
@export var overtake_tease_cooldown := 8.0


func cooldown_of(kind: int) -> float:
	match kind:
		SkillKind.Kind.SLINGSHOT:
			return slingshot_cooldown
		SkillKind.Kind.BONK:
			return bonk_cooldown
		SkillKind.Kind.SNARE:
			return snare_cooldown
		SkillKind.Kind.FAKE_BOX:
			return fake_box_cooldown
		SkillKind.Kind.SHIELD:
			return shield_cooldown
	return 0.0
