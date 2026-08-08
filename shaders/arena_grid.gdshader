shader_type spatial;

// Antialiased world-space grid for the arena floor. This is a tuning aid as
// much as decoration: on a featureless plane you cannot see wheel slip, drift,
// or how far a shove actually moved something. The metre grid makes speed and
// slide legible at a glance.

uniform vec3 base_color : source_color = vec3(0.16, 0.16, 0.18);
uniform vec3 line_color : source_color = vec3(0.34, 0.36, 0.42);
uniform float cell_size = 1.0;
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.6;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.55;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Distance to the nearest cell boundary, divided by the pixel footprint --
	// that division is what keeps the lines one pixel wide at any camera range
	// instead of aliasing into moire.
	vec2 uv = world_pos.xz / cell_size;
	vec2 grid = abs(fract(uv - 0.5) - 0.5) / fwidth(uv);
	float line = 1.0 - min(min(grid.x, grid.y), 1.0);

	ALBEDO = mix(base_color, line_color, line);
	METALLIC = metallic_amount;
	ROUGHNESS = roughness_amount;
}
