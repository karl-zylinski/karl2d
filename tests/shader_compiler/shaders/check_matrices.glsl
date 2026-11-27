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

bool near(mat2 a, mat2 b) {
	return near(a[0], b[0]) && near(a[1], b[1]);
}

bool near(mat3 a, mat3 b) {
	return near(a[0], b[0]) && near(a[1], b[1]) && near(a[2], b[2]);
}

bool near(mat4 a, mat4 b) {
	return near(a[0], b[0]) && near(a[1], b[1]) && near(a[2], b[2]) && near(a[3], b[3]);
}

bool loose(mat3 a, mat3 b) {
	bool ok = true;

	for (int i = 0; i < 3; i++) {
		ok = ok && all(lessThan(abs(a[i] - b[i]), vec3(0.001)));
	}

	return ok;
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
	mat2 a = mat2(1.0, 2.0, 3.0, 4.0) * one;
	mat2 b = mat2(5.0, 6.0, 7.0, 8.0) * one;

	if (cell == 0) {
		mat3 m = mat3(2.0 * one);
		mat2 n = mat2(1);
		mat4 k = mat4(one);
		bool ok = near(m[0], vec3(2.0, 0.0, 0.0)) && near(m[1], vec3(0.0, 2.0, 0.0)) && near(m[2], vec3(0.0, 0.0, 2.0));
		ok = ok && near(n[0], vec2(1.0, 0.0)) && near(n[1], vec2(0.0, 1.0));
		ok = ok && near(k[3], vec4(0.0, 0.0, 0.0, 1.0)) && near(k[1][1], 1.0) && near(k[2][1], 0.0);
		return ok;
	}

	if (cell == 1) {
		mat2 m = mat2(1.0, 2.0, 3.0 * one, 4);
		return near(m[0], vec2(1.0, 2.0)) && near(m[1], vec2(3.0, 4.0)) && near(m[1][0], 3.0) && near(m[0][1], 2.0) && near(m, a);
	}

	if (cell == 2) {
		mat3 m = mat3(vec3(1.0, 2.0, 3.0), vec3(4.0, 5.0, 6.0) * one, vec3(7.0, 8.0, 9.0));
		mat2 n = mat2(vec2(1.0, 2.0) * one, 3.0, 4.0);
		mat2 p = mat2(vec4(1.0, 2.0, 3.0, 4.0) * one);
		mat3 q = mat3(vec2(1.0, 2.0), 3.0, vec4(4.0, 5.0, 6.0, 7.0) * one, vec2(8.0, 9.0));
		return near(m[2][1], 8.0) && near(m[1], vec3(4.0, 5.0, 6.0)) && near(n, a) && near(p, a) && near(q, m);
	}

	if (cell == 3) {
		mat4 big = mat4(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0) * one;
		mat3 m3 = mat3(big);
		mat2 m2 = mat2(big);
		mat4 m4 = mat4(a);
		mat3 m3b = mat3(a);
		bool ok = near(m3[0], vec3(1.0, 2.0, 3.0)) && near(m3[1], vec3(5.0, 6.0, 7.0)) && near(m3[2], vec3(9.0, 10.0, 11.0));
		ok = ok && near(m2[0], vec2(1.0, 2.0)) && near(m2[1], vec2(5.0, 6.0));
		ok = ok && near(m4[0], vec4(1.0, 2.0, 0.0, 0.0)) && near(m4[1], vec4(3.0, 4.0, 0.0, 0.0)) && near(m4[2], vec4(0.0, 0.0, 1.0, 0.0)) && near(m4[3], vec4(0.0, 0.0, 0.0, 1.0));
		ok = ok && near(m3b[0], vec3(1.0, 2.0, 0.0)) && near(m3b[2], vec3(0.0, 0.0, 1.0)) && near(mat2(m3b), a);
		return ok;
	}

	if (cell == 4) {
		vec2 v = vec2(5.0, 6.0) * one;
		mat3 r = mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0) * one;
		return near(a * v, vec2(23.0, 34.0)) && near(v * a, vec2(17.0, 39.0)) && near(r * vec3(1.0, 2.0, 3.0), vec3(-2.0, 1.0, 3.0)) && near(vec3(1.0, 2.0, 3.0) * r, vec3(2.0, -1.0, 3.0));
	}

	if (cell == 5) {
		mat2 ab = a * b;
		mat2 ba = b * a;
		return near(ab[0], vec2(23.0, 34.0)) && near(ab[1], vec2(31.0, 46.0)) && near(ba[0], vec2(19.0, 22.0)) && near(ba[1], vec2(43.0, 50.0)) && near((a * b) * vec2(1.0, 0.0), a * (b * vec2(1.0, 0.0)));
	}

	if (cell == 6) {
		bool ok = near(a * 2.0, mat2(2.0, 4.0, 6.0, 8.0)) && near(2.0 * a, mat2(2.0, 4.0, 6.0, 8.0));
		ok = ok && near(a + b, mat2(6.0, 8.0, 10.0, 12.0)) && near(b - a, mat2(4.0, 4.0, 4.0, 4.0)) && near(mat2(4.0), mat2(4.0, 0.0, 0.0, 4.0));
		ok = ok && near(a + 1.0, mat2(2.0, 3.0, 4.0, 5.0)) && near(a / 2.0, mat2(0.5, 1.0, 1.5, 2.0)) && near(-a, mat2(-1.0, -2.0, -3.0, -4.0));
		ok = ok && near(b / a, mat2(5.0, 3.0, 7.0 / 3.0, 2.0)) && near(a * 2, mat2(2.0, 4.0, 6.0, 8.0));
		return ok;
	}

	if (cell == 7) {
		mat3 m = mat3(one);
		m[1] = vec3(4.0, 5.0, 6.0);
		m[2][0] = 7.0;
		m[0].y = 8.0;
		int i = int(2.0 + zero);
		bool ok = near(m[0], vec3(1.0, 8.0, 0.0)) && near(m[1], vec3(4.0, 5.0, 6.0)) && near(m[2], vec3(7.0, 0.0, 1.0));
		ok = ok && near(m[i][i], 1.0) && near(m[i - 1], vec3(4.0, 5.0, 6.0)) && near(m[i].x, 7.0);
		m[1] += vec3(1.0);
		m[i][1] = 3.0;
		ok = ok && near(m[1], vec3(5.0, 6.0, 7.0)) && near(m[2], vec3(7.0, 3.0, 1.0));
		return ok;
	}

	if (cell == 8) {
		mat2 t2 = transpose(a);
		mat3 t3 = transpose(mat3(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0) * one);
		mat4 t4 = transpose(mat4(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0) * one);
		return near(t2, mat2(1.0, 3.0, 2.0, 4.0)) && near(t3[0], vec3(1.0, 4.0, 7.0)) && near(t3[2], vec3(3.0, 6.0, 9.0)) && near(t4[1], vec4(2.0, 6.0, 10.0, 14.0)) && near(t4[3][2], 12.0);
	}

	if (cell == 9) {
		bool ok = near(determinant(a), -2.0) && near(determinant(mat3(2.0, 0.0, 0.0, 0.0, 3.0, 0.0, 0.0, 0.0, 4.0) * one), 24.0);
		ok = ok && abs(determinant(mat3(1.0, 2.0, 3.0, 0.0, 1.0, 4.0, 5.0, 6.0, 0.0) * one) - 1.0) < 0.001;
		ok = ok && near(determinant(mat4(2.0 * one)), 16.0) && near(determinant(mat4(0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0) * one), -1.0);
		return ok;
	}

	if (cell == 10) {
		mat3 m = mat3(1.0, 2.0, 3.0, 0.0, 1.0, 4.0, 5.0, 6.0, 0.0) * one;
		bool ok = near(inverse(a), mat2(-2.0, 1.0, 1.5, -0.5));
		ok = ok && near(inverse(mat3(2.0, 0.0, 0.0, 0.0, 4.0, 0.0, 0.0, 0.0, 8.0) * one), mat3(0.5, 0.0, 0.0, 0.0, 0.25, 0.0, 0.0, 0.0, 0.125));
		ok = ok && near(inverse(mat4(2.0 * one)), mat4(0.5));
		ok = ok && loose(inverse(m) * m, mat3(1.0)) && loose(m * inverse(m), mat3(1.0));
		return ok;
	}

	if (cell == 11) {
		return near(matrixCompMult(a, b), mat2(5.0, 12.0, 21.0, 32.0)) && near(matrixCompMult(mat3(2.0), mat3(3.0 * one)), mat3(6.0));
	}

	if (cell == 12) {
		mat2 c = a;
		bool ok = a == mat2(1.0, 2.0, 3.0, 4.0) && a != b && c == a;
		c[1][1] = 5.0;
		ok = ok && c != a && !(c == a);
		return ok;
	}

	if (cell == 13) {
		vec2 v = vec2(5.0, 6.0) * one;
		v *= a;
		mat2 c = a;
		c *= b;
		mat2 d = a;
		d += b;
		d -= 1.0;
		d *= 2.0;
		d /= 4.0;
		return near(v, vec2(17.0, 39.0)) && near(c, a * b) && near(d, mat2(2.5, 3.5, 4.5, 5.5));
	}

	if (cell == 14) {
		mat4 t = mat4(one);
		t[3] = vec4(10.0, 20.0, 30.0, 1.0);
		mat4 tt = t * t;
		mat4 s = mat4(vec4(2.0, 0.0, 0.0, 0.0), vec4(0.0, 3.0, 0.0, 0.0), vec4(0.0, 0.0, 4.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
		return near(t * vec4(1.0, 2.0, 3.0, 1.0), vec4(11.0, 22.0, 33.0, 1.0)) && near(tt[3], vec4(20.0, 40.0, 60.0, 1.0)) && near((t * s) * vec4(1.0), vec4(12.0, 23.0, 34.0, 1.0)) && near((s * t) * vec4(1.0), vec4(22.0, 63.0, 124.0, 1.0));
	}

	mat2 from_ints = mat2(ivec2(1, 2), ivec2(3, 4));
	mat2 picked = zero > 0.5 ? b : a;
	vec2 col = a[1];
	return near(from_ints, a) && near(picked, a) && near(col, vec2(3.0, 4.0)) && near(a[0].y, 2.0) && near(a[1].yx, vec2(4.0, 3.0));
}

void main() {
	int cell = int(uv.x * 4.0) + int(uv.y * 4.0) * 4;
	final_color = run_cell(cell) ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}
