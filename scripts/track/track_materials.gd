class_name TrackMaterials
extends RefCounted
## Shared track materials. Vertex colors give the large-scale paint (curbs,
## ruts, grass tones). A procedural noise texture, mapped in world space,
## adds fine surface grain, so the ground doesn't look flat at close range.
## Everything is generated at runtime; there are no image assets.

static var _detail_cache := {}


## Grayscale noise from `min_value` (dark grains) to 1.0. Tileable.
static func detail_texture(min_value := 0.8, frequency := 0.06) -> NoiseTexture2D:
	var key := "%.2f_%.3f" % [min_value, frequency]
	if _detail_cache.has(key):
		return _detail_cache[key]
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_octaves = 4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(min_value, min_value, min_value))
	ramp.set_color(1, Color.WHITE)
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.noise = noise
	texture.color_ramp = ramp
	texture.generate_mipmaps = true
	_detail_cache[key] = texture
	return texture


## The driving surface (road.gdshader): dirt, planks, mud, ice and curbs by
## vertex colour and alpha. `style` is the map's TrackTheme.SceneryStyle.
static func road(style := TrackTheme.SceneryStyle.FOREST) -> Material:
	match style:
		TrackTheme.SceneryStyle.CANYON:
			return MaterialLibrary.road("canyon", "terrain/dirt", {&"damp_amount": 0.1, &"puddle_amount": 0.0,
					&"gravel_amount": 0.75, &"ground_scale": 0.12, &"damp_darkness": 0.2})
		TrackTheme.SceneryStyle.SNOW:
			return MaterialLibrary.road("snow", "snow/snow_packed", {&"damp_amount": 0.22, &"puddle_amount": 0.0,
					&"gravel_amount": 0.0, &"ground_scale": 0.2, &"damp_darkness": 0.1, &"ground_roughness": 1.0,
					&"sparkle": 1.0, &"normal_strength": 1.3})
	return MaterialLibrary.road("forest", "terrain/dirt", {})


## Plank barriers and parapets: wood grain running along the boards.
static func barrier(_style := TrackTheme.SceneryStyle.FOREST) -> Material:
	return MaterialLibrary.terrain("barrier", "wood/planks", "wood/planks", {&"steep_swap": true, &"flat_scale": 0.45,
			&"steep_scale": 0.42, &"macro_strength": 0.1, &"normal_strength": 0.9, &"texture_strength": 0.85})


## Slopes, cliffs and the backdrop terrain: grass / dust / snow on the flat,
## rock on steep faces.
static func grass(style := TrackTheme.SceneryStyle.FOREST) -> Material:
	match style:
		TrackTheme.SceneryStyle.CANYON:
			return MaterialLibrary.terrain("canyon", "terrain/dirt", "stone/sandstone", {&"flat_scale": 0.1,
					&"steep_scale": 0.045, &"steep_stretch": 2.2, &"steep_low": 0.5, &"steep_high": 0.82,
					&"normal_strength": 1.4, &"macro_strength": 0.2})
		TrackTheme.SceneryStyle.SNOW:
			return MaterialLibrary.terrain("snow", "snow/snow_packed", "stone/rock_face", {&"flat_scale": 0.11,
					&"steep_scale": 0.05, &"steep_low": 0.42, &"steep_high": 0.7, &"steep_color": Color(0.27, 0.31, 0.38),
					&"steep_color_mix": 0.85, &"normal_strength": 1.3, &"sparkle": 0.9, &"macro_strength": 0.14,
					&"flat_roughness": 0.95})
	return MaterialLibrary.terrain("forest", "terrain/grass", "stone/rock_face", {&"flat_scale": 0.13,
			&"steep_scale": 0.05, &"steep_low": 0.5, &"steep_high": 0.74, &"steep_color": Color(0.42, 0.43, 0.42),
			&"steep_color_mix": 0.8, &"normal_strength": 1.2, &"macro_strength": 0.26})


static func _vertex_colored(roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = roughness
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return material
