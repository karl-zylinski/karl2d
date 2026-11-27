uniform mat4 view_projection;
uniform float time;

uint hash(uint x) {
	x ^= x >> 16;
	x *= 0x7feb352du;
	x ^= x >> 15;
	x *= 0x846ca68bu;
	x ^= x >> 16;
	return x;
}

mat2 rotate(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat2(c, s, -s, c);
}

float tile_shape(vec2 q, uint kind) {
	if (kind == 0u) {
		vec2 d = abs(q) - vec2(0.22);
		return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
	}

	if (kind == 1u) {
		return length(q) - 0.28;
	}

	if (kind == 2u) {
		vec2 a = abs(q);
		return min(max(a.x - 0.32, a.y - 0.08), max(a.x - 0.08, a.y - 0.32));
	}

	return (abs(q.x) + abs(q.y) - 0.3) * 0.7071;
}

#vertex

in vec3 position;
in vec2 texcoord;
in vec4 color;

out vec2 uv;

void main() {
	uv = texcoord;
	gl_Position = view_projection * vec4(position, 1.0);
}

#fragment

in vec2 uv;

out vec4 final_color;

void main() {
	vec2 g = uv * 8.0;
	ivec2 cell = ivec2(floor(g));
	vec2 f = fract(g) - 0.5;
	uint h = hash(uint(cell.x) + uint(cell.y) * 8u + 1u);
	float angle = float(h & 255u) / 255.0 * 6.2831853 + time;
	vec2 q = rotate(angle) * f;
	float d = tile_shape(q, (h >> 8) & 3u);
	vec3 fill = vec3(float((h >> 8) & 255u), float((h >> 16) & 255u), float(h >> 24)) / 255.0;
	vec3 background = ((cell.x + cell.y) & 1) == 0 ? vec3(0.12) : vec3(0.2);
	float edge = smoothstep(0.0, 0.03, -d);
	vec3 col = mix(background, fill, edge);
	col = mix(col, vec3(1.0), (1.0 - smoothstep(0.0, 0.02, abs(d))) * 0.6);
	final_color = vec4(col, 1.0);
}
