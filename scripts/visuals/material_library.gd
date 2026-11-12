class_name MaterialLibrary
extends RefCounted
## Shared PBR materials (Visual Overhaul V2). One place builds every textured
## material, so meshes share them (fewer draw-call state changes, textures
## loaded once). Textures are the CC0 sets in res://assets/textures (see
## docs/ASSET_CREDITS.md), stored near-neutral so vertex colour or
## `albedo_color` supplies the palette (docs/ART_DIRECTION_BIBLE.md).

const TEXTURES := "res://assets/textures/"
const TERRAIN_SHADER := preload("res://assets/materials/terrain.gdshader")
const ROAD_SHADER := preload("res://assets/materials/road.gdshader")

static var _cache := {}
static var _macro: NoiseTexture2D


## "terrain/dirt" + "albedo" -> res://assets/textures/terrain/dirt_albedo.jpg
static func texture(set_name: String, map: String) -> Texture2D:
	var path := "%s%s_%s.jpg" % [TEXTURES, set_name, map]
	if not _cache.has(path):
		_cache[path] = load(path) as Texture2D
	return _cache[path]


## Low-frequency tileable noise: breaks up texture tiling, places damp
## patches, frost and glints. Generated once.
static func macro_noise() -> NoiseTexture2D:
	if _macro == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.seed = 11
		noise.frequency = 0.012
		noise.fractal_octaves = 5
		noise.fractal_gain = 0.55
		_macro = NoiseTexture2D.new()
		_macro.width = 512
		_macro.height = 512
		_macro.seamless = true
		_macro.noise = noise
		_macro.generate_mipmaps = true
	return _macro


## Ground shader material: `flat_set` from above, `steep_set` on steep faces.
## `params` overrides shader uniforms. Cached by `key`.
static func terrain(key: String, flat_set: String, steep_set: String, params := {}) -> ShaderMaterial:
	var cache_key := "terrain:" + key
	if _cache.has(cache_key):
		return _cache[cache_key]
	var material := ShaderMaterial.new()
	material.shader = TERRAIN_SHADER
	material.set_shader_parameter(&"flat_albedo", texture(flat_set, "albedo"))
	material.set_shader_parameter(&"flat_normal", texture(flat_set, "normal"))
	material.set_shader_parameter(&"flat_rough", texture(flat_set, "rough"))
	material.set_shader_parameter(&"steep_albedo", texture(steep_set, "albedo"))
	material.set_shader_parameter(&"steep_normal", texture(steep_set, "normal"))
	material.set_shader_parameter(&"steep_rough", texture(steep_set, "rough"))
	material.set_shader_parameter(&"macro_noise", macro_noise())
	for uniform: StringName in params:
		material.set_shader_parameter(uniform, params[uniform])
	_cache[cache_key] = material
	return material


static func road(key: String, ground_set: String, params := {}) -> ShaderMaterial:
	var cache_key := "road:" + key
	if _cache.has(cache_key):
		return _cache[cache_key]
	var material := ShaderMaterial.new()
	material.shader = ROAD_SHADER
	material.set_shader_parameter(&"ground_albedo", texture(ground_set, "albedo"))
	material.set_shader_parameter(&"ground_normal", texture(ground_set, "normal"))
	material.set_shader_parameter(&"ground_rough", texture(ground_set, "rough"))
	material.set_shader_parameter(&"wood_albedo", texture("wood/planks", "albedo"))
	material.set_shader_parameter(&"wood_normal", texture("wood/planks", "normal"))
	material.set_shader_parameter(&"mud_normal", texture("terrain/mud", "normal"))
	material.set_shader_parameter(&"macro_noise", macro_noise())
	for uniform: StringName in params:
		material.set_shader_parameter(uniform, params[uniform])
	_cache[cache_key] = material
	return material


## Vertex-coloured prop material with a triplanar PBR texture set: rocks,
## trunks, timber, snow drifts. `world` maps in world space (static scenery),
## otherwise in object space (things that move or are instanced).
static func textured(set_name: String, scale := 0.35, roughness := 1.0, normal_strength := 1.0, world := false,
		tint := Color.WHITE) -> StandardMaterial3D:
	var cache_key := "prop:%s:%.3f:%.2f:%.2f:%s:%s" % [set_name, scale, roughness, normal_strength, world, tint.to_html()]
	if _cache.has(cache_key):
		return _cache[cache_key]
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	# Textures are stored around 0.8 brightness; lift so the paint keeps its value.
	material.albedo_color = Color(tint.r * 1.22, tint.g * 1.22, tint.b * 1.22)
	material.albedo_texture = texture(set_name, "albedo")
	material.normal_enabled = true
	material.normal_texture = texture(set_name, "normal")
	material.normal_scale = normal_strength
	material.roughness_texture = texture(set_name, "rough")
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.roughness = roughness
	material.uv1_triplanar = true
	material.uv1_world_triplanar = world
	material.uv1_triplanar_sharpness = 4.0
	material.uv1_scale = Vector3.ONE * scale
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[cache_key] = material
	return material


## Soft matte foliage: vertex-coloured, wrapped diffuse and a little
## back-light so canopies glow at the edges instead of going flat.
static func foliage(roughness := 0.85) -> StandardMaterial3D:
	var cache_key := "foliage:%.2f" % roughness
	if _cache.has(cache_key):
		return _cache[cache_key]
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = roughness
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	material.backlight_enabled = true
	material.backlight = Color(0.22, 0.3, 0.1)
	material.rim_enabled = true
	material.rim = 0.25
	material.rim_tint = 0.6
	material.albedo_texture = macro_detail()
	material.uv1_triplanar = true
	material.uv1_scale = Vector3.ONE * 0.9
	_cache[cache_key] = material
	return material


## Fine grey grain (0.78..1) for foliage and painted props.
static func macro_detail() -> NoiseTexture2D:
	return TrackMaterials.detail_texture(0.78, 0.11)


## Snow on props and scenery: capped below white, cool, slightly glossy.
static func snow() -> StandardMaterial3D:
	return textured("snow/snow_packed", 0.45, 0.82, 0.6, false)


## Still or slow water: glossy, tinted, slightly see-through.
static func water(color: Color, alpha := 0.82) -> StandardMaterial3D:
	var cache_key := "water:%s:%.2f" % [color.to_html(), alpha]
	if _cache.has(cache_key):
		return _cache[cache_key]
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if alpha < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	material.roughness = 0.08
	material.metallic = 0.0
	material.metallic_specular = 0.9
	material.normal_enabled = true
	material.normal_texture = _water_normal()
	material.normal_scale = 0.35
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE * 0.08
	material.rim_enabled = true
	material.rim = 0.4
	material.rim_tint = 0.3
	_cache[cache_key] = material
	return material


static func _water_normal() -> NoiseTexture2D:
	if not _cache.has("water_normal"):
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.03
		noise.fractal_octaves = 3
		var normal := NoiseTexture2D.new()
		normal.width = 256
		normal.height = 256
		normal.seamless = true
		normal.as_normal_map = true
		normal.bump_strength = 6.0
		normal.noise = noise
		normal.generate_mipmaps = true
		_cache["water_normal"] = normal
	return _cache["water_normal"]


## Drops every cached material and texture (called when the game quits, so
## no resource is still referenced at shutdown).
static func release() -> void:
	_cache.clear()
	_macro = null
