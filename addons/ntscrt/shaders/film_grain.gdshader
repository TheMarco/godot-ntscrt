shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float intensity : hint_range(0.0, 1.0) = 0.4;

// Film grain is a fresh, stationary exposure each frame. There is no moving
// UV offset or low-frequency noise sheet to look like a scrolling texture.
uvec3 pcg3(uvec3 value) {
	value = value * 1664525u + 1013904223u;
	value.x += value.y * value.z;
	value.y += value.z * value.x;
	value.z += value.x * value.y;
	value = value ^ (value >> 16u);
	value.x += value.y * value.z;
	value.y += value.z * value.x;
	value.z += value.x * value.y;
	return value;
}

float gaussian(uvec2 pixel, uint frame) {
	uvec3 bits = pcg3(uvec3(pixel, frame ^ 0x5bd1u));
	vec2 sample_uv = vec2(bits.xy >> 8u) * (1.0 / 16777216.0);
	return sqrt(-2.0 * log(max(sample_uv.x, 0.0000001)))
		* cos(6.2831853 * sample_uv.y);
}

void fragment() {
	vec4 source = texture(screen_texture, SCREEN_UV);
	if (intensity <= 0.0) {
		COLOR = source;
	} else {
		uint frame = uint(floor(TIME * 24.0));
		uvec3 bits = pcg3(uvec3(uvec2(FRAGCOORD.xy), frame));
		vec3 random_value = vec3(bits >> 8u) * (1.0 / 16777216.0);
		float radius = sqrt(-2.0 * log(max(random_value.x, 0.0000001)));
		float fine = radius * cos(6.2831853 * random_value.y);
		float chroma_a = radius * sin(6.2831853 * random_value.y);
		float chroma_b = (random_value.z - 0.5) * 3.4641;

		// A 1.5-pixel grain lattice gives the random grains a small, organic
		// footprint. Renormalising the four weights keeps strength even within
		// each cell; fine pixel grain restores detail at the edges.
		vec2 lattice = FRAGCOORD.xy / 1.5;
		vec2 cell = floor(lattice);
		vec2 fraction = fract(lattice);
		uvec2 corner = uvec2(cell);
		vec4 weights = vec4(
			(1.0 - fraction.x) * (1.0 - fraction.y),
			fraction.x * (1.0 - fraction.y),
			(1.0 - fraction.x) * fraction.y,
			fraction.x * fraction.y);
		float correlated = dot(weights, vec4(
			gaussian(corner, frame),
			gaussian(corner + uvec2(1u, 0u), frame),
			gaussian(corner + uvec2(0u, 1u), frame),
			gaussian(corner + uvec2(1u, 1u), frame)))
			* inversesqrt(max(dot(weights, weights), 0.0001));

		float luma = dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
		float response = (0.8 + 0.5 * sqrt(luma))
			* (1.0 - 0.45 * smoothstep(0.35, 0.8, luma))
			* (1.0 - 0.85 * smoothstep(0.8, 1.0, luma));
		float sigma = intensity * 0.018 * response;
		float grain = (0.8 * correlated + 0.6 * fine) * sigma;
		vec3 dye_grain = vec3(chroma_a, -0.5 * chroma_a - 0.3 * chroma_b,
			chroma_b) * (sigma * 0.10);
		COLOR = vec4(clamp(source.rgb + vec3(grain) + dye_grain,
			vec3(0.0), vec3(1.0)), source.a);
	}
}
