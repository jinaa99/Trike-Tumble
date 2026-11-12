shader_type spatial;
// The driving surface. Vertex colour is the paint (dirt tones, ruts, verge,
// curbs, planks, mud, ice); its alpha picks the surface response:
//   1.0 ground (dirt / packed snow)   0.9 painted curb   0.75 mud
//   0.5 bridge planks                 0.25 ice
// Ground gets a CC0 PBR texture set in world space, gravel speckle, damp
// patches and small puddles. Render only: collision is a separate pass.

uniform sampler2D ground_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_rough : filter_linear_mipmap, repeat_enable;
uniform sampler2D wood_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;

uniform float ground_scale = 0.14;
uniform float wood_scale = 0.3;
uniform float normal_strength = 1.0;
uniform float ground_roughness = 1.0;
uniform float texture_strength = 1.0;
// Share of the road that is damp, and how dark damp ground gets.
uniform float damp_amount = 0.3;
uniform float damp_darkness = 0.32;
// Standing-water puddles inside the dampest spots (0 = none).
uniform float puddle_amount = 0.5;
uniform vec3 puddle_color : source_color = vec3(0.32, 0.36, 0.4);
// Light pebbles / gravel speckle.
uniform float gravel_amount = 0.5;
uniform float sparkle = 0.0;
uniform vec3 ice_deep_color : source_color = vec3(0.17, 0.5, 0.65);

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

vec2 unpack(vec4 n) {
	return n.xy * 2.0 - 1.0;
}

float band(float a, float center) {
	return 1.0 - step(0.07, abs(a - center));
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 paint = pow(COLOR.rgb, vec3(2.2));
	float a = COLOR.a;
	float is_ground = step(0.96, a);
	float is_curb = band(a, 0.9);
	float is_mud = band(a, 0.75);
	float is_wood = band(a, 0.5);
	float is_ice = 1.0 - step(0.35, a);

	float macro = texture(macro_noise, world_pos.xz * 0.0052).r;
	float macro2 = texture(macro_noise, world_pos.zx * 0.019 + vec2(0.31, 0.17)).r;
	float fine = texture(macro_noise, world_pos.xz * 0.11 + vec2(0.7, 0.4)).r;

	vec2 uv = world_pos.xz * ground_scale;
	vec3 tex = mix(texture(ground_albedo, uv).rgb, texture(ground_albedo, uv * 0.23 + vec2(0.4, 0.7)).rgb, 0.3 + 0.3 * macro2);
	vec2 tn = unpack(texture(ground_normal, uv)) * normal_strength;
	float rough = texture(ground_rough, uv).r * ground_roughness;
	vec3 grain = mix(vec3(1.0), tex * 1.25, texture_strength);
	vec3 albedo = paint * grain * mix(0.84, 1.1, macro);

	// Gravel: pale pebbles where the fine noise peaks.
	float pebble = smoothstep(0.66, 0.72, fine * (0.6 + 0.4 * tex.r * 1.25)) * gravel_amount * is_ground;
	albedo = mix(albedo, albedo * 1.35 + vec3(0.03), pebble);

	// Damp patches and puddles (ground only).
	float wet_field = macro2 * 0.65 + macro * 0.35;
	float damp = smoothstep(1.0 - damp_amount - 0.12, 1.0 - damp_amount + 0.06, wet_field) * is_ground;
	float puddle = smoothstep(1.0 - damp_amount * 0.42, 1.0 - damp_amount * 0.42 + 0.025, wet_field + (tex.r - 0.64) * 0.25) * puddle_amount * is_ground;
	albedo *= 1.0 - damp * damp_darkness;
	rough = mix(rough, 0.42, damp);
	albedo = mix(albedo, albedo * 0.5 + puddle_color * 0.1, puddle);
	rough = mix(rough, 0.04, puddle);
	tn *= 1.0 - puddle;
	float spec = mix(0.3, 0.75, max(puddle, damp * 0.3));

	// Painted curbs: smoother, a little chipped.
	albedo = mix(albedo, paint * mix(0.9, 1.04, tex.g * 1.25), is_curb);
	rough = mix(rough, 0.55 + 0.25 * fine, is_curb);

	// Mud: glossy wet slop with churned normals.
	if (is_mud > 0.5) {
		vec2 mn = unpack(texture(mud_normal, world_pos.xz * 0.22));
		tn = mn * 1.6;
		albedo = paint * mix(0.75, 1.1, tex.r * 1.25) * mix(0.8, 1.05, fine);
		rough = mix(0.18, 0.55, smoothstep(0.35, 0.7, fine));
		spec = 0.7;
	}

	// Bridge planks: wood grain along the boards (vertex colour draws the boards).
	if (is_wood > 0.5) {
		vec2 wuv = world_pos.xz * wood_scale;
		vec3 w = texture(wood_albedo, wuv).rgb * 1.25;
		tn = unpack(texture(wood_normal, wuv)) * 0.8;
		albedo = paint * mix(vec3(1.0), w, 0.7) * mix(0.88, 1.06, macro2);
		rough = 0.78;
		spec = 0.3;
	}

	// Ice: clear and glossy with frosted streaks and deeper blue cracks.
	if (is_ice > 0.5) {
		float frost = smoothstep(0.45, 0.75, texture(macro_noise, world_pos.xz * 0.06).r);
		float crack = smoothstep(0.495, 0.5, fine) - smoothstep(0.5, 0.505, fine);
		albedo = mix(mix(ice_deep_color, paint, 0.55), paint * 1.05, frost);
		albedo = mix(albedo, vec3(0.9, 0.97, 1.0), crack * 0.6);
		rough = mix(0.05, 0.32, frost);
		tn = unpack(texture(ground_normal, uv * 0.5)) * 0.12;
		spec = 0.9;
	}

	if (sparkle > 0.0) {
		float glint = texture(macro_noise, world_pos.xz * 1.9).r * texture(macro_noise, world_pos.zx * 3.1 + VIEW.xy * 0.6).r;
		float g = smoothstep(0.52, 0.6, glint) * sparkle * is_ground;
		rough = mix(rough, 0.15, g);
		spec = mix(spec, 1.0, g);
	}

	ALBEDO = albedo;
	ROUGHNESS = clamp(rough, 0.03, 1.0);
	SPECULAR = spec;
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(n + vec3(tn.x, 0.0, -tn.y)), 0.0)).xyz);
}
