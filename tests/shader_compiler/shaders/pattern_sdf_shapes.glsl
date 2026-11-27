uniform mat4 view_projection;
uniform float time;

mat2 rotate(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat2(c, s, -s, c);
}

float sd_circle(vec2 p, float r) {
	return length(p) - r;
}

float sd_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sd_round_box(vec2 p, vec2 b, float r) {
	return sd_box(p, b - r) - r;
}

float sd_segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

float sd_equilateral_triangle(vec2 p, float r) {
	const float k = sqrt(3.0);
	p.x = abs(p.x) - r;
	p.y = p.y + r / k;

	if (p.x + k * p.y > 0.0) {
		p = vec2(p.x - k * p.y, -k * p.x - p.y) / 2.0;
	}

	p.x -= clamp(p.x, -2.0 * r, 0.0);
	return -length(p) * sign(p.y);
}

float smooth_min(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

float scene(vec2 p) {
	float blob = smooth_min(sd_circle(p - vec2(-0.45, -0.35), 0.28), sd_round_box(rotate(time * 0.6) * (p - vec2(0.05, -0.4)), vec2(0.25, 0.15), 0.05), 0.15);
	float bar = sd_segment(p, vec2(-0.75, 0.55), vec2(0.7, 0.3)) - 0.04;
	float ring = abs(sd_circle(p - vec2(-0.2, 0.15), 0.25)) - 0.03;
	float tri = sd_equilateral_triangle(rotate(-time) * (p - vec2(0.5, 0.0)), 0.22);
	return min(min(blob, bar), min(ring, tri));
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
	vec2 p = (uv - 0.5) * 2.0;
	float d = scene(p);
	vec3 col = d > 0.0 ? vec3(0.9, 0.6, 0.3) : vec3(0.65, 0.85, 1.0);
	col *= 1.0 - exp(-6.0 * abs(d));
	col *= 0.8 + 0.2 * cos(120.0 * d);
	col = mix(col, vec3(1.0), 1.0 - smoothstep(0.0, 0.015, abs(d)));
	final_color = vec4(col, 1.0);
}
