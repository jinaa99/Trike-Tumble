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


static func road() -> StandardMaterial3D:
	var material := _vertex_colored(0.95)
	material.albedo_texture = detail_texture(0.72, 0.09)
	material.uv1_scale = Vector3.ONE * 0.22
	return material


static func barrier() -> StandardMaterial3D:
	var material := _vertex_colored(0.7)
	material.albedo_texture = detail_texture(0.88, 0.2)
	material.uv1_scale = Vector3.ONE * 0.5
	return material


static func grass() -> StandardMaterial3D:
	var material := _vertex_colored(1.0)
	material.albedo_texture = detail_texture(0.78, 0.05)
	material.uv1_scale = Vector3.ONE * 0.12
	return material


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
