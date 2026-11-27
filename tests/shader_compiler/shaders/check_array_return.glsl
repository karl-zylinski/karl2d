uniform mat4 view_projection;
uniform float zero;

float[3] make_values(float x) {
	return float[3](x, x * 2.0, x * 3.0);
}

float[3] reversed(float v[3]) {
	return float[3](v[2], v[1], v[0]);
}

ivec2[2] make_pairs(int a) {
	ivec2 result[2];
	result[0] = ivec2(a, a + 1);
	result[1] = ivec2(a * 2, a * 3);
	return result;
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
	float v[3] = make_values(1.0 + zero);
	float r[3] = reversed(v);
	ivec2 p[2] = make_pairs(2 + int(zero));
	bool ok = v[0] == 1.0 && v[2] == 3.0 && r[0] == 3.0 && r[2] == 1.0 && reversed(make_values(2.0))[0] == 6.0;
	ok = ok && p[0] == ivec2(2, 3) && p[1] == ivec2(4, 6) && make_pairs(1).length() == 2;
	final_color = ok ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}
