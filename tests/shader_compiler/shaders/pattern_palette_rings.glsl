uniform mat4 view_projection;
uniform float time;
uniform vec2 resolution;

const float TAU = 6.28318531;

vec3 palette(float t) {
	vec3 a = vec3(0.5, 0.5, 0.5);
	vec3 b = vec3(0.5, 0.5, 0.5);
	vec3 c = vec3(1.0, 1.0, 1.0);
	vec3 d = vec3(0.263, 0.416, 0.557);
	return a + b * cos(TAU * (c * t + d));
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
	vec2 frag = uv * resolution;
	vec2 p = (frag * 2.0 - resolution) / resolution.y;
	vec3 col = vec3(0.0);

	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		vec2 center = vec2(cos(fi * 1.7 + time), sin(fi * 2.3 + time * 0.7)) * 0.45;
		float d = length(p - center);
		float ring = abs(sin(d * 12.0 - time * 2.0));
		col += palette(d + fi * 0.25 + time * 0.1) * (0.08 / (ring * 0.5 + 0.05)) * exp(-d * 2.0);
	}

	col = col / (1.0 + col);
	col = pow(col, vec3(0.8));
	final_color = vec4(col, 1.0);
}
