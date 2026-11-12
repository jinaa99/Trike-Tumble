class_name TrackTheme
extends Resource
## A map's look: road, barrier and slope paint, scenery style and palette,
## backdrop colors and the sky/sun/fog. Every build pass (TrackMeshBuilder,
## TrackDecorator, TrackBackdrop, TrackLandmarks, TrackStructures, gates)
## reads its colors from `Track.theme`, so a new map is data, not code.
##
## The defaults are the Forest Rush (and test track) values: a track without
## a theme looks exactly like it did before themes existed.
## Themes: res://resources/maps/themes/*.tres.

## Which scenery the decorator plants on the slopes.
enum SceneryStyle {
	FOREST,  ## pines, round trees, bushes, boulders, flowers
	CANYON,  ## red rock spires, dry shrubs, boulders, a few desert flowers
	SNOW,  ## snow-covered pines, snow mounds, snow-capped boulders
}

@export var scenery_style := SceneryStyle.FOREST

@export_group("Road")
@export var dirt_color := Color(0.8, 0.58, 0.38)
@export var dirt_dark_color := Color(0.62, 0.42, 0.27)
@export var rut_color := Color(0.66, 0.46, 0.3)
@export var verge_color := Color(0.58, 0.6, 0.3)
@export var curb_colors: Array[Color] = [Color(0.93, 0.2, 0.22), Color(0.98, 0.97, 0.93)]
@export var mud_color := Color(0.4, 0.27, 0.17)
@export var mud_wet_color := Color(0.3, 0.2, 0.14)
## Ice patches: base and polished streaks.
@export var ice_color := Color(0.62, 0.86, 0.98)
@export var ice_shine_color := Color(0.88, 0.97, 1.0)

@export_group("Barriers and bridges")
@export var plank_colors: Array[Color] = [Color(0.96, 0.9, 0.78), Color(0.91, 0.84, 0.7)]
@export var plank_gap_color := Color(0.55, 0.42, 0.3)
@export var post_color := Color(0.5, 0.34, 0.22)
@export var rail_color := Color(0.9, 0.24, 0.22)
@export var deck_colors: Array[Color] = [Color(0.7, 0.5, 0.32), Color(0.62, 0.43, 0.27), Color(0.75, 0.55, 0.36)]
@export var deck_kerb_color := Color(0.42, 0.28, 0.18)
@export var bridge_wall_colors: Array[Color] = [Color(0.6, 0.41, 0.25), Color(0.53, 0.36, 0.22)]
## Bridge legs (trestles) and their lighter braces.
@export var timber_color := Color(0.5, 0.33, 0.2)
@export var timber_light_color := Color(0.66, 0.46, 0.29)
@export var end_blocker_color := Color(0.62, 0.42, 0.26)

@export_group("Slopes and cliffs")
## Slope bands: near, mid, far (blended by depth).
@export var grass_colors: Array[Color] = [Color(0.5, 0.8, 0.33), Color(0.38, 0.7, 0.32), Color(0.29, 0.58, 0.33)]
@export var rock_slope_color := Color(0.5, 0.52, 0.5)
## Gorge faces at bridges and gaps, and "cliff" zone walls.
@export var cliff_colors: Array[Color] = [Color(0.56, 0.52, 0.48), Color(0.47, 0.44, 0.42)]
## Horizontal stripes on cliff walls (rock layers); empty = plain.
@export var cliff_band_colors: Array[Color] = []

@export_group("Scenery")
@export var pine_greens: Array[Color] = [Color(0.16, 0.52, 0.38), Color(0.2, 0.6, 0.4), Color(0.13, 0.45, 0.4)]
@export var leaf_greens: Array[Color] = [Color(0.45, 0.75, 0.28), Color(0.6, 0.8, 0.3), Color(0.98, 0.62, 0.22), Color(0.36, 0.68, 0.3)]
@export var flower_colors: Array[Color] = [Color(1, 1, 1), Color(1.0, 0.85, 0.25), Color(1.0, 0.55, 0.7), Color(0.75, 0.6, 1.0)]
@export var boulder_colors: Array[Color] = [Color(0.6, 0.6, 0.64), Color(0.72, 0.66, 0.58)]
## Boulders on the road and the canyon's falling/rolling rocks.
@export var road_boulder_color := Color(0.6, 0.58, 0.6)
@export var snow_color := Color(0.96, 0.98, 1.0)
## Set dressing (signs, bales, cabin, stands).
@export var wood_color := Color(0.62, 0.42, 0.26)
@export var wood_dark_color := Color(0.45, 0.3, 0.19)
@export var straw_color := Color(0.96, 0.8, 0.4)
@export var structure_rock_color := Color(0.56, 0.55, 0.58)
@export var water_color := Color(0.24, 0.58, 0.86)

@export_group("Backdrop")
@export var terrain_low_color := Color(0.46, 0.7, 0.33)
@export var terrain_high_color := Color(0.32, 0.58, 0.36)
@export var terrain_steep_color := Color(0.58, 0.57, 0.54)
@export var terrain_patch_color := Color(0.58, 0.76, 0.36)
@export var far_peak_color := Color(0.56, 0.6, 0.86)
@export var mid_peak_color := Color(0.38, 0.6, 0.66)
## Height share of the peaks without snow (lower = more snow).
@export_range(0.0, 1.0) var far_snow_line := 0.62
@export_range(0.0, 1.0) var mid_snow_line := 0.7
@export var hill_colors: Array[Color] = [Color(0.36, 0.64, 0.36), Color(0.55, 0.75, 0.35)]
@export var valley_color := Color(0.42, 0.66, 0.34)
@export var lake_color := Color(0.25, 0.6, 0.85)
@export var cloud_emission := Color(0.55, 0.6, 0.7)

@export_group("Sky and light")
## False: the race scene keeps its own WorldEnvironment and sun (forest).
@export var apply_environment := false
@export var sky_top_color := Color(0.26, 0.53, 0.95)
@export var sky_horizon_color := Color(0.74, 0.87, 0.98)
@export var ground_bottom_color := Color(0.33, 0.5, 0.4)
@export var fog_color := Color(0.74, 0.85, 0.96)
@export var fog_density := 0.0005
@export var ambient_color := Color(1, 0.93, 0.84)
@export var sun_color := Color(1, 0.94, 0.82)
@export var sun_energy := 1.45
@export var saturation := 1.18


## Copies the road, barrier, bridge and slope paint into the mesh builder.
func apply_to_builder(builder: TrackMeshBuilder) -> void:
	builder.dirt_color = dirt_color
	builder.dirt_dark_color = dirt_dark_color
	builder.rut_color = rut_color
	builder.verge_color = verge_color
	builder.curb_colors = curb_colors
	builder.mud_color = mud_color
	builder.mud_wet_color = mud_wet_color
	builder.ice_color = ice_color
	builder.ice_shine_color = ice_shine_color
	builder.plank_colors = plank_colors
	builder.plank_gap_color = plank_gap_color
	builder.post_color = post_color
	builder.rail_color = rail_color
	builder.deck_colors = deck_colors
	builder.deck_kerb_color = deck_kerb_color
	builder.bridge_wall_colors = bridge_wall_colors
	builder.cliff_colors = cliff_colors
	builder.cliff_band_colors = cliff_band_colors
	builder.grass_colors = grass_colors
	builder.rock_slope_color = rock_slope_color


## Sky, fog, ambient light and sun for the race scene (only when
## `apply_environment`). The environment is duplicated, never edited in place.
func apply_to_world(world: WorldEnvironment, sun: DirectionalLight3D) -> void:
	if not apply_environment:
		return
	if world and world.environment:
		var environment := world.environment.duplicate(true) as Environment
		var sky_material := environment.sky.sky_material as ProceduralSkyMaterial if environment.sky else null
		if sky_material:
			sky_material.sky_top_color = sky_top_color
			sky_material.sky_horizon_color = sky_horizon_color
			sky_material.ground_horizon_color = sky_horizon_color
			sky_material.ground_bottom_color = ground_bottom_color
		environment.fog_light_color = fog_color
		environment.fog_density = fog_density
		environment.ambient_light_color = ambient_color
		environment.adjustment_saturation = saturation
		world.environment = environment
	if sun:
		sun.light_color = sun_color
		sun.light_energy = sun_energy
