shader_type spatial;
// World-space PBR ground for slopes, cliffs, barriers and the backdrop terrain.
// Vertex colour is the paint (palette); the CC0 texture sets add grain, normal
// detail and roughness. Flat ground uses the "flat" set projected from above,
// steep faces use the "steep" set projected from the sides, so cliffs get
// rock strata without any UVs. A low-frequency noise breaks up the tiling.

uniform sampler2D flat_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D flat_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D flat_rough : filter_linear_mipmap, repeat_enable;
uniform sampler2D steep_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D steep_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D steep_rough : filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;

uniform float flat_scale = 0.16;
uniform float steep_scale = 0.09;
// Stretch of the steep texture along the vertical (rock strata read wider than tall).
uniform float steep_stretch = 1.0;
// Swap the steep projection's axes (plank barriers: boards run along the road).
uniform bool steep_swap = false;
// World normal.y below `steep_low` is fully steep, above `steep_high` fully flat.
uniform float steep_low = 0.55;
uniform float steep_high = 0.8;
// Steep faces blend toward this colour (rock under the grass); 0 = keep the paint.
uniform vec3 steep_color : source_color = vec3(0.5, 0.5, 0.5);
uniform float steep_color_mix = 0.0;
uniform float normal_strength = 1.0;
uniform float flat_roughness = 1.0;
uniform float steep_roughness = 1.0;
// How strongly the texture's own brightness shows (0 = flat paint).
uniform float texture_strength = 1.0;
uniform float macro_strength = 0.22;
// Glints on snow.
uniform float sparkle = 0.0;
uniform float specular_level = 0.35;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

vec2 unpack(vec4 n) {
	return n.xy * 2.0 - 1.0;
}

void fragment() {
	vec3 n = normalize(world_normal);
	float steep = 1.0 - smoothstep(steep_low, steep_high, n.y);
	vec3 paint = pow(COLOR.rgb, vec3(2.2));

	float macro = texture(macro_noise, world_pos.xz * 0.0041).r;
	float macro2 = texture(macro_noise, world_pos.zx * 0.021 + vec2(0.37, 0.11)).r;

	// Flat: top-down projection, two scales mixed so the tile never repeats visibly.
	vec2 uv_flat = world_pos.xz * flat_scale;
	vec3 a_flat = mix(texture(flat_albedo, uv_flat).rgb, texture(flat_albedo, uv_flat * 0.27 + vec2(0.5, 0.2)).rgb, 0.35 + 0.3 * macro2);
	vec2 tn_flat = unpack(texture(flat_normal, uv_flat));
	float r_flat = texture(flat_rough, uv_flat).r * flat_roughness;

	vec3 albedo_tex = a_flat;
	float rough = r_flat;
	vec3 wn = n + vec3(tn_flat.x, 0.0, -tn_flat.y) * normal_strength * (1.0 - steep);

	if (steep > 0.001) {
		vec2 wx = abs(n.x) > abs(n.z) ? world_pos.zy : world_pos.xy;
		vec2 uv_steep = vec2(wx.x, -wx.y * steep_stretch) * steep_scale;
		if (steep_swap) {
			uv_steep = uv_steep.yx;
		}
		vec3 a_steep = texture(steep_albedo, uv_steep).rgb;
		vec2 tn_steep = unpack(texture(steep_normal, uv_steep));
		if (steep_swap) {
			tn_steep = tn_steep.yx;
		}
		float r_steep = texture(steep_rough, uv_steep).r * steep_roughness;
		albedo_tex = mix(albedo_tex, a_steep, steep);
		rough = mix(rough, r_steep, steep);
		vec3 side = abs(n.x) > abs(n.z) ? vec3(0.0, tn_steep.y, tn_steep.x) : vec3(tn_steep.x, tn_steep.y, 0.0);
		wn += side * normal_strength * steep;
		paint = mix(paint, steep_color, steep * steep_color_mix);
	}

	// Textures are stored around 0.8 brightness: 1.25 keeps the paint's value.
	vec3 grain = mix(vec3(1.0), albedo_tex * 1.25, texture_strength);
	ALBEDO = paint * grain * mix(1.0 - macro_strength, 1.0 + macro_strength * 0.6, macro);
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	SPECULAR = specular_level;
	if (sparkle > 0.0) {
		float glint = texture(macro_noise, world_pos.xz * 1.7).r * texture(macro_noise, world_pos.zx * 2.9 + VIEW.xy * 0.6).r;
		float g = smoothstep(0.52, 0.6, glint) * sparkle * (1.0 - steep);
		ROUGHNESS = mix(ROUGHNESS, 0.15, g);
		SPECULAR = mix(SPECULAR, 1.0, g);
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(wn), 0.0)).xyz);
}
