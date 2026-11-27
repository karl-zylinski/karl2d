uniform mat4 view_projection;
uniform float zero;

const float EPSILON = 0.0005;

bool near(float a, float b) {
	return abs(a - b) < EPSILON;
}

bool near(vec2 a, vec2 b) {
	return all(lessThan(abs(a - b), vec2(EPSILON)));
}

bool near(vec3 a, vec3 b) {
	return all(lessThan(abs(a - b), vec3(EPSILON)));
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

bool run_cell(int cell) {
	float one = 1.0 + zero;

	if (cell == 0) {
		return near(length(vec2(3.0, 4.0) * one), 5.0) && near(length(vec3(1.0, 2.0, 2.0) * one), 3.0) && near(length(-2.0 * one), 2.0) && near(length(vec4(one)), 2.0);
	}

	if (cell == 1) {
		return near(distance(vec2(1.0, 1.0) * one, vec2(4.0, 5.0)), 5.0) && near(distance(one, 4.0), 3.0) && near(distance(vec3(zero), vec3(2.0, 3.0, 6.0)), 7.0) && near(distance(vec4(1.0) * one, vec4(2.0)), 2.0);
	}

	if (cell == 2) {
		return near(dot(vec3(1.0, 2.0, 3.0) * one, vec3(4.0, -5.0, 6.0)), 12.0) && near(dot(2.0 * one, 3.0), 6.0) && near(dot(vec4(one), vec4(1.0, 2.0, 3.0, 4.0)), 10.0) && near(dot(vec2(1.0, 0.0) * one, vec2(0.0, 1.0)), 0.0);
	}

	if (cell == 3) {
		return near(cross(vec3(1.0, 0.0, 0.0) * one, vec3(0.0, 1.0, 0.0)), vec3(0.0, 0.0, 1.0)) && near(cross(vec3(1.0, 2.0, 3.0) * one, vec3(4.0, 5.0, 6.0)), vec3(-3.0, 6.0, -3.0)) && near(cross(vec3(0.0, 1.0, 0.0) * one, vec3(1.0, 0.0, 0.0)), vec3(0.0, 0.0, -1.0));
	}

	if (cell == 4) {
		return near(normalize(vec2(3.0, 4.0) * one), vec2(0.6, 0.8)) && near(normalize(vec3(0.0, 0.0, -5.0) * one), vec3(0.0, 0.0, -1.0)) && near(normalize(-2.0 * one), -1.0) && near(length(normalize(vec4(1.0, 2.0, 3.0, 4.0) * one)), 1.0);
	}

	if (cell == 5) {
		return near(reflect(vec2(1.0, -1.0) * one, vec2(0.0, 1.0)), vec2(1.0, 1.0)) && near(reflect(vec3(1.0, -2.0, 0.0) * one, normalize(vec3(0.0, 3.0, 0.0))), vec3(1.0, 2.0, 0.0)) && near(reflect(vec2(3.0, 0.5) * one, vec2(-1.0, 0.0)), vec2(-3.0, 0.5)) && near(reflect(-2.0 * one, 1.0), 2.0);
	}

	if (cell == 6) {
		vec2 i = normalize(vec2(1.0, -1.0) * one);
		vec2 n = vec2(0.0, 1.0);
		bool ok = near(refract(i, n, 1.0), i) && near(refract(i, n, 0.5), vec2(0.3535534, -0.9354143)) && near(refract(i, n, 2.0), vec2(0.0));
		ok = ok && near(refract(-one, 1.0, 0.5), -1.0) && near(refract(vec3(0.0, 0.0, -1.0) * one, vec3(0.0, 0.0, 1.0), 1.5), vec3(0.0, 0.0, -1.0));
		return ok;
	}

	if (cell == 7) {
		vec3 c = cross(vec3(0.0, 0.0, 2.0) * one, vec3(3.0, 0.0, 0.0));
		return near(c, vec3(0.0, 6.0, 0.0)) && near(normalize(c), vec3(0.0, 1.0, 0.0)) && near(length(c), 6.0);
	}

	if (cell == 8) {
		vec3 a = vec3(1.0, 2.0, 3.0) * one;
		vec3 b = vec3(-2.0, 0.5, 4.0);
		return near(dot(a, cross(a, b)), 0.0) && near(dot(b, cross(a, b)), 0.0) && near(dot(a, a), length(a) * length(a)) && near(distance(a, b), length(a - b));
	}

	if (cell == 9) {
		vec2 d = normalize(vec2(1.0, 1.0) * one);
		return near(d, vec2(0.7071068)) && near(dot(d, d), 1.0) && near(reflect(d, vec2(0.0, -1.0)), vec2(0.7071068, -0.7071068));
	}

	if (cell == 10) {
		return near(length(ivec2(3, 4)), 5.0) && near(dot(ivec2(1, 2), vec2(3.0, 4.0) * one), 11.0) && near(distance(2, 5.0 * one), 3.0);
	}

	if (cell == 11) {
		vec3 n = normalize(vec3(1.0, 1.0, 0.0) * one);
		vec3 i = vec3(1.0, 0.0, 0.0);
		vec3 r = reflect(i, n);
		return near(r, vec3(0.0, -1.0, 0.0)) && near(length(r), 1.0);
	}

	if (cell == 12) {
		vec2 i = normalize(vec2(0.6, -0.8) * one);
		vec2 n = vec2(0.0, 1.0);
		float eta = 0.8;
		float k = 1.0 - eta * eta * (1.0 - dot(n, i) * dot(n, i));
		vec2 expected = eta * i - (eta * dot(n, i) + sqrt(k)) * n;
		return near(refract(i, n, eta), expected) && near(refract(i, n, eta), vec2(0.48, -0.8772685)) && near(length(refract(i, n, eta)), 1.0);
	}

	if (cell == 13) {
		vec4 a = vec4(1.0, -1.0, 1.0, -1.0) * one;
		return near(length(a), 2.0) && near(dot(a, a.yxwz), -4.0) && near(distance(a, -a), 4.0);
	}

	if (cell == 14) {
		return near(length(vec3(1e-3, 0.0, 0.0) * one), 1e-3) && near(length(vec2(300.0, 400.0) * one), 500.0) && near(normalize(vec2(300.0, -400.0) * one), vec2(0.6, -0.8));
	}

	return near(cross(vec3(2.0, 0.0, 0.0) * one, vec3(0.0, 3.0, 0.0)).z, 6.0) && near(normalize(vec3(1.0, 2.0, 2.0) * one), vec3(1.0, 2.0, 2.0) / 3.0);
}

void main() {
	int cell = int(uv.x * 4.0) + int(uv.y * 4.0) * 4;
	final_color = run_cell(cell) ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}
