extends Node
## Development tool: one AI racer drives a whole map alone and every
## wipeout, reset and respawn is printed with the distance it happened at.
##   Godot --headless --path . --fixed-fps 60 --scene res://tests/tools/ai_probe.tscn -- forest hard [seed] [racers]
## Maps: forest, canyon, snow. Difficulty: easy, medium, hard (or mixed
## with 5 racers: the timed runner's field). Exit code 0 if
## the racer finished without resets or respawns.

const MAPS := {
	"forest": "res://scenes/tracks/forest_rush.tscn", "canyon": "res://scenes/tracks/rocky_canyon.tscn",
	"snow": "res://scenes/tracks/snow_slide.tscn", "test": "res://scenes/tracks/test_track.tscn",
}
const AI_CONFIGS: Array[AIDriverConfig] = [
	preload("res://resources/ai/ai_easy.tres"), preload("res://resources/ai/ai_medium.tres"),
	preload("res://resources/ai/ai_hard.tres"),
]


func _ready() -> void:
	GameSettings.use_test_profile("user://test_settings.cfg")
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var map: String = args[0] if args.size() > 0 else "forest"
	var difficulty := maxi(["easy", "medium", "hard"].find(args[1] if args.size() > 1 else "hard"), 0)
	var track: Track = (load(MAPS[map]) as PackedScene).instantiate()
	add_child(track)
	track.hazard_seed = int(args[2]) if args.size() > 2 else 0
	var manager := RacerManager.new()
	manager.ai_configs = AI_CONFIGS.duplicate()
	add_child(manager)
	manager.setup(track)
	var count := clampi(int(args[3]) if args.size() > 3 else 1, 1, 5)
	var field: Array[Racer] = []
	for k in count:
		# "mixed" = the timed runner's field: hard, medium, medium, easy, hard.
		var level: int = [2, 1, 1, 0, 2][k] if (args.size() > 1 and args[1] == "mixed") else difficulty
		field.append(manager.add_ai_racer(level as AIDriverConfig.Difficulty))
	await get_tree().physics_frame
	manager.start_race()
	var seen := {}
	var t := 0.0
	var clean := true
	while not field.all(func(r: Racer) -> bool: return r.finished) and t < 700.0:
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		var trace_at := float(OS.get_environment("PROBE_TRACE")) if OS.has_environment("PROBE_TRACE") else -1.0
		if trace_at > 0.0 and t > trace_at - 15.0 and t < trace_at + 1.0 and fmod(t, 0.5) < 1.0 / 60.0:
			for racer in field:
				var d := racer.get_ai_driver()
				var i := racer.progress.current_index
				print("    t%.1f %-8s %5.0f m lat %5.1f v %4.1f %s rev=%s blk=%s dodge=%s up=%.2f" % [t, racer.display_name, i * track.path.spacing,
						(racer.trike.global_position - track.path.points[i]).dot(track.path.rights[i]), racer.trike.forward_speed,
						racer.rider.get_state_name(), d.is_reversing, d.blocked, d.dodging, racer.trike.global_basis.y.y])
		for racer in field:
			var driver := racer.get_ai_driver()
			var at := racer.progress.current_index * track.path.spacing
			var row: Dictionary = seen.get_or_add(racer.id, {"ejects": 0, "resets": 0, "respawns": 0})
			if racer.rider.eject_count > int(row["ejects"]):
				row["ejects"] = racer.rider.eject_count
				print("  %6.1f s  %-8s wipeout at %5.0f m  (%.1f m/s, %s, impact %.1f)" % [t, racer.display_name, at,
						racer.trike.linear_velocity.length(), TrackSurface.name_of(racer.trike.surface), racer.trike.last_impact_strength])
			if driver.reset_count + driver.emergency_count > int(row["resets"]):
				row["resets"] = driver.reset_count + driver.emergency_count
				clean = false
				print("  %6.1f s  %-8s RESET at %5.0f m" % [t, racer.display_name, at])
			if racer.respawn_count > int(row["respawns"]):
				row["respawns"] = racer.respawn_count
				clean = false
				print("  %6.1f s  %-8s RESPAWN at %5.0f m" % [t, racer.display_name, at])
	for racer in field:
		print("%s %s: %s in %.1f s, %d wipeouts, tricks %d, landings %s" % [map, racer.display_name,
				"finished" if racer.finished else "DID NOT FINISH", racer.finish_time if racer.finished else t,
				racer.rider.eject_count, racer.trike.trick_count, str(racer.trike.landing_counts)])
	get_tree().quit(0 if clean and field.all(func(r: Racer) -> bool: return r.finished) else 1)
