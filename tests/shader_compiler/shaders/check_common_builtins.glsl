uniform mat4 view_projection;
uniform float zero;

const float EPSILON = 0.0001;

bool near(float a, float b) {
	return abs(a - b) < EPSILON;
}

bool near(vec2 a, vec2 b) {
	return all(lessThan(abs(a - b), vec2(EPSILON)));
}

bool near(vec3 a, vec3 b) {
	return all(lessThan(abs(a - b), vec3(EPSILON)));
}

bool near(vec4 a, vec4 b) {
	return all(lessThan(abs(a - b), vec4(EPSILON)));
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
		bool ok = near(abs(-2.5 * one), 2.5) && near(abs(2.5 * one), 2.5) && near(abs(vec3(-1.0, 0.0, 1.0) * one), vec3(1.0, 0.0, 1.0));
		ok = ok && near(sign(-3.0 * one), -1.0) && near(sign(zero), 0.0) && near(sign(0.25 * one), 1.0) && near(sign(vec3(-0.5, 0.0, 2.0) * one), vec3(-1.0, 0.0, 1.0));
		return ok;
	}

	if (cell == 1) {
		bool ok = near(floor(-1.5 * one), -2.0) && near(floor(1.5 * one), 1.0) && near(floor(-2.0 * one), -2.0) && near(floor(2.0 * one), 2.0);
		ok = ok && near(ceil(-1.5 * one), -1.0) && near(ceil(1.2 * one), 2.0) && near(ceil(3.0 * one), 3.0);
		ok = ok && near(trunc(-1.7 * one), -1.0) && near(trunc(1.7 * one), 1.0) && near(round(-1.7 * one), -2.0) && near(round(1.3 * one), 1.0) && near(round(-1.3 * one), -1.0) && near(round(2.6 * one), 3.0);
		ok = ok && near(fract(-1.25 * one), 0.75) && near(fract(1.25 * one), 0.25) && near(fract(vec2(3.5, -0.5) * one), vec2(0.5, 0.5)) && near(fract(-3.0 * one), 0.0);
		return ok;
	}

	if (cell == 2) {
		bool ok = near(mod(5.5 * one, 2.0), 1.5) && near(mod(-5.5 * one, 2.0), 0.5) && near(mod(5.5 * one, -2.0), -0.5) && near(mod(-5.5 * one, -2.0), -1.5);
		ok = ok && near(mod(vec2(7.0, -7.0) * one, 3.0), vec2(1.0, 2.0)) && near(mod(vec3(5.0, -5.0, 4.5) * one, vec3(3.0, 3.0, -2.0)), vec3(2.0, 1.0, -1.5));
		ok = ok && near(mod(6.0 * one, 2.0), 0.0) && near(mod(-6.0 * one, 2.0), 0.0) && near(mod(7, 4), 3.0);
		return ok;
	}

	if (cell == 3) {
		bool ok = near(min(one, -2.0), -2.0) && near(max(one, -2.0), 1.0) && near(max(vec3(1.0, 5.0, 3.0) * one, vec3(4.0, 2.0, 6.0)), vec3(4.0, 5.0, 6.0));
		ok = ok && near(min(vec3(1.0, 5.0, 3.0) * one, vec3(4.0, 2.0, 6.0)), vec3(1.0, 2.0, 3.0)) && near(min(vec3(1.0, 5.0, 3.0) * one, 2.0), vec3(1.0, 2.0, 2.0));
		ok = ok && near(max(vec2(-1.0, 3.0) * one, 0.0), vec2(0.0, 3.0)) && near(min(vec2(1.5, 3.0) * one, 2), vec2(1.5, 2.0)) && near(max(2, 3.5 * one), 3.5);
		return ok;
	}

	if (cell == 4) {
		bool ok = near(clamp(1.5 * one, 0.0, 1.0), 1.0) && near(clamp(-0.5 * one, 0.0, 1.0), 0.0) && near(clamp(0.25 * one, 0.0, 1.0), 0.25) && near(clamp(1.5 * one, 0, 1), 1.0);
		ok = ok && near(clamp(vec3(-1.0, 0.5, 2.0) * one, 0.0, 1.0), vec3(0.0, 0.5, 1.0)) && near(clamp(vec3(-1.0, 0.5, 2.0) * one, vec3(0.0, 0.6, 0.0), vec3(1.0, 1.0, 1.5)), vec3(0.0, 0.6, 1.5));
		ok = ok && near(clamp(vec4(-2.0, -0.5, 0.5, 2.0) * one, -1.0, 1.0), vec4(-1.0, -0.5, 0.5, 1.0));
		return ok;
	}

	if (cell == 5) {
		bool ok = near(mix(2.0 * one, 4.0, 0.25), 2.5) && near(mix(vec2(0.0, 10.0) * one, vec2(10.0, 20.0), 0.5), vec2(5.0, 15.0));
		ok = ok && near(mix(vec3(zero), vec3(10.0), vec3(0.1, 0.5, 1.0)), vec3(1.0, 5.0, 10.0)) && near(mix(vec4(1.0) * one, vec4(3.0), 0.0), vec4(1.0));
		ok = ok && near(mix(vec2(1.0, 2.0) * one, vec2(3.0, 4.0), bvec2(false, true)), vec2(1.0, 4.0)) && near(mix(5.0 * one, 6.0, false), 5.0) && near(mix(5.0 * one, 6.0, true), 6.0);
		ok = ok && near(mix(-1.0 * one, 1.0, 0.75), 0.5) && near(mix(1, 3, 0.5), 2.0);
		return ok;
	}

	if (cell == 6) {
		bool ok = near(step(0.5, 0.4 * one), 0.0) && near(step(0.5, 0.5 * one), 1.0) && near(step(0.5, 0.6 * one), 1.0);
		ok = ok && near(step(0.5, vec3(0.2, 0.5, 0.8) * one), vec3(0.0, 1.0, 1.0)) && near(step(vec2(1.0, 2.0), vec2(1.5, 1.5) * one), vec2(1.0, 0.0));
		ok = ok && near(step(zero, vec4(-1.0, 0.0, 1.0, -0.001)), vec4(0.0, 1.0, 1.0, 0.0)) && near(step(1, 2.0 * one), 1.0);
		return ok;
	}

	if (cell == 7) {
		bool ok = near(smoothstep(0.0, 1.0, 0.5 * one), 0.5) && near(smoothstep(0.0, 1.0, 0.25 * one), 0.15625) && near(smoothstep(0.0, 2.0, 3.0 * one), 1.0) && near(smoothstep(0.0, 2.0, -one), 0.0);
		ok = ok && near(smoothstep(0.0, 4.0, vec3(1.0, 2.0, 3.0) * one), vec3(0.15625, 0.5, 0.84375));
		ok = ok && near(smoothstep(vec2(0.0, 1.0), vec2(2.0, 3.0), vec2(1.0, 1.5) * one), vec2(0.5, 0.15625));
		ok = ok && near(smoothstep(1.0, 3.0, vec4(0.0, 1.5, 2.0, 5.0) * one), vec4(0.0, 0.15625, 0.5, 1.0)) && near(smoothstep(0, 4, 2.0 * one), 0.5);
		return ok;
	}

	if (cell == 8) {
		return near(floor(vec4(-0.5, 0.5, -1.0, 1.999) * one), vec4(-1.0, 0.0, -1.0, 1.0)) && near(ceil(vec3(-0.5, 0.5, 1.0) * one), vec3(0.0, 1.0, 1.0)) && near(ceil(vec2(-1.999, 2.001) * one), vec2(-1.0, 3.0));
	}

	if (cell == 9) {
		return near(trunc(vec2(-2.5, 2.5) * one), vec2(-2.0, 2.0)) && near(round(vec2(-2.4, 2.6) * one), vec2(-2.0, 3.0)) && near(trunc(vec4(-0.1, 0.1, -9.9, 9.9) * one), vec4(0.0, 0.0, -9.0, 9.0)) && near(round(vec3(0.49, -0.51, 7.2) * one), vec3(0.0, -1.0, 7.0));
	}

	if (cell == 10) {
		float x = clamp(mix(-2.0, 4.0, 0.75 * one), 0.0, 2.0);
		vec2 y = max(min(vec2(-3.0, 3.0) * one, 1.0), -1.0);
		return near(x, 2.0) && near(y, vec2(-1.0, 1.0)) && near(abs(sign(-4.0 * one) * 3.0), 3.0);
	}

	if (cell == 11) {
		float x = -3.75 * one;
		vec3 v = vec3(-3.75, 2.5, -0.125) * one;
		return near(floor(x), -4.0) && near(fract(x), 0.25) && near(floor(x) + fract(x), x) && near(floor(v) + fract(v), v) && near(fract(v), vec3(0.25, 0.5, 0.875));
	}

	if (cell == 12) {
		return near(mod(vec4(-1.0, -0.25, 3.5, -7.5) * one, 2.0), vec4(1.0, 1.75, 1.5, 0.5)) && near(mod(vec2(-1.0, 1.0) * one, vec2(-4.0, -4.0)), vec2(-1.0, -3.0)) && near(mod(-0.5 * one, 0.25), 0.0);
	}

	if (cell == 13) {
		vec3 a = vec3(1.0, -2.0, 3.0) * one;
		return near(abs(a), vec3(1.0, 2.0, 3.0)) && near(sign(a) * abs(a), a) && near(max(a, a.zxy), vec3(3.0, 1.0, 3.0)) && near(min(a.x, a.y), -2.0);
	}

	if (cell == 14) {
		vec2 e0 = vec2(0.0, 2.0);
		vec2 e1 = vec2(4.0, 6.0);
		vec2 x = vec2(2.0, 4.0) * one;
		return near(smoothstep(e0, e1, x), vec2(0.5)) && near(step(e0, x), vec2(1.0)) && near(step(x, e0), vec2(0.0)) && near(clamp(x, e0, e1), x) && near(mix(e0, e1, step(3.0, x)), vec2(0.0, 6.0));
	}

	return near(fract(10.75 * one), 0.75) && near(mod(10.75 * one, 1.0), 0.75) && near(floor(-0.25 * one), -1.0) && near(ceil(-0.75 * one), 0.0) && near(abs(-0.0 * one), 0.0) && near(round(-0.2 * one), 0.0);
}

void main() {
	int cell = int(uv.x * 4.0) + int(uv.y * 4.0) * 4;
	final_color = run_cell(cell) ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}
