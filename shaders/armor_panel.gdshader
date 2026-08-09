shader_type spatial;

// Progressive battle damage driven by one uniform: `damage`, 0..1.
//
// The panel is dented by pushing vertices along their own normals using value
// noise, so the plate visibly buckles before it shears off. That is the whole
// point of doing it in the vertex stage rather than faking it with a texture --
// the silhouette changes, so a beaten panel reads as beaten even from across the
// arena and even in a dark corner of it.
//
// The mesh has to be subdivided for this to show. A stock box has eight corners
// and nothing in between, so displacing it just moves the corners.

uniform float damage : hint_range(0.0, 1.0) = 0.0;
uniform vec3 clean_color : source_color = vec3(0.68, 0.7, 0.74);
uniform vec3 beaten_color : source_color = vec3(0.19, 0.15, 0.13);
uniform float dent_depth = 0.035;
uniform float dent_scale = 7.0;
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.85;

varying float wear;

// Cheap hash-based value noise. No texture to author, load or keep in sync, and
// smooth enough that dents read as beaten metal rather than as static.
float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash(i);
	float n100 = hash(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z);
}

void vertex() {
	// Two octaves: broad buckling from the big one, tooth marks from the fine.
	float coarse = noise(VERTEX * dent_scale) - 0.5;
	float fine = (noise(VERTEX * dent_scale * 3.3) - 0.5) * 0.4;
	wear = clamp(coarse + 0.5, 0.0, 1.0);
	VERTEX -= NORMAL * (coarse + fine) * dent_depth * damage;
}

void fragment() {
	// Scorch the hollows harder than the high spots, so the damage follows the
	// dents instead of washing the whole plate evenly.
	float scorch = clamp(damage * (0.55 + wear * 0.9), 0.0, 1.0);
	ALBEDO = mix(clean_color, beaten_color, scorch);
	METALLIC = metallic_amount * (1.0 - 0.45 * damage);
	ROUGHNESS = mix(0.28, 0.85, damage);
}
