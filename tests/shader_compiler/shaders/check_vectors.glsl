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
		vec4 a = vec4(2.0 + zero);
		vec3 b = vec3(1, 2, 3);
		vec2 c = vec2(true, false);
		vec4 d = vec4(one, 2.0 * one, 3.0, 4);
		return near(a, vec4(2.0, 2.0, 2.0, 2.0)) && near(b, vec3(1.0, 2.0, 3.0)) && near(c, vec2(1.0, 0.0)) && near(d, vec4(1.0, 2.0, 3.0, 4.0));
	}

	if (cell == 1) {
		vec2 xy = vec2(1.0, 2.0) * one;
		vec4 a = vec4(xy, 3.0, 4.0);
		vec4 b = vec4(one, vec3(2.0, 3.0, 4.0));
		vec4 c = vec4(xy, vec2(3.0, 4.0));
		vec3 d = vec3(vec2(5.0, 6.0), 7.0 * one);
		vec4 e = vec4(one, xy.yx, 9.0);
		return near(a, vec4(1.0, 2.0, 3.0, 4.0)) && near(b, vec4(1.0, 2.0, 3.0, 4.0)) && near(c, vec4(1.0, 2.0, 3.0, 4.0)) && near(d, vec3(5.0, 6.0, 7.0)) && near(e, vec4(1.0, 2.0, 1.0, 9.0));
	}

	if (cell == 2) {
		vec4 big = vec4(1.0, 2.0, 3.0, 4.0) * one;
		vec2 a = vec2(big);
		vec3 b = vec3(big);
		vec3 c = vec3(big.xy, big.zw);
		float d = float(vec3(7.0, 8.0, 9.0) * one);
		ivec2 e = ivec2(vec3(1.5, -2.5, 3.0) * one);
		return near(a, vec2(1.0, 2.0)) && near(b, vec3(1.0, 2.0, 3.0)) && near(c, vec3(1.0, 2.0, 3.0)) && near(d, 7.0) && e == ivec2(1, -2);
	}

	if (cell == 3) {
		vec4 v = vec4(1.0, 2.0, 3.0, 4.0) * one;
		bool a = near(v.wzyx, vec4(4.0, 3.0, 2.0, 1.0)) && near(v.xxyy, vec4(1.0, 1.0, 2.0, 2.0));
		bool b = near(v.rgba, v) && near(v.stpq, v) && near(v.ba, vec2(3.0, 4.0)) && near(v.q, 4.0);
		bool c = near(v.zyx, vec3(3.0, 2.0, 1.0)) && near(v.wzyx.yx, vec2(3.0, 4.0)) && near(v.y, 2.0) && near(v.t, 2.0) && near(v.g, 2.0);
		bool d = near(v.wwww, vec4(4.0)) && near(v.xyz.zzx, vec3(3.0, 3.0, 1.0));
		return a && b && c && d;
	}

	if (cell == 4) {
		vec4 v = vec4(zero);
		v.xy = vec2(1.0, 2.0);
		v.wz = vec2(4.0, 3.0);
		bool a = near(v, vec4(1.0, 2.0, 3.0, 4.0));
		v.g = 5.0;
		bool b = near(v, vec4(1.0, 5.0, 3.0, 4.0));
		v.ab = v.ba;
		bool c = near(v, vec4(1.0, 5.0, 4.0, 3.0));
		v.stp = vec3(7.0, 8.0, 9.0);
		bool d = near(v, vec4(7.0, 8.0, 9.0, 3.0));
		v.x = v.w = 6.0;
		bool e = near(v, vec4(6.0, 8.0, 9.0, 6.0));
		return a && b && c && d && e;
	}

	if (cell == 5) {
		vec3 v = vec3(1.0, 2.0, 3.0) * one;
		v.xy += vec2(10.0);
		v.z *= 2.0;
		v.x++;
		++v.y;
		bool a = near(v, vec3(12.0, 13.0, 6.0));
		v.yx -= vec2(1.0, 2.0);
		bool b = near(v, vec3(10.0, 12.0, 6.0));
		float old = v.z--;
		bool c = near(old, 6.0) && near(v.z, 5.0);
		return a && b && c;
	}

	if (cell == 6) {
		vec3 a = vec3(1.0, 2.0, 3.0) * one;
		vec3 b = vec3(4.0, 5.0, 6.0);
		return near(a + b, vec3(5.0, 7.0, 9.0)) && near(a * b, vec3(4.0, 10.0, 18.0)) && near(b / a, vec3(4.0, 2.5, 2.0)) && near(b - a, vec3(3.0)) && near(-a, vec3(-1.0, -2.0, -3.0)) && near(+a, a);
	}

	if (cell == 7) {
		vec3 a = vec3(1.0, 2.0, 3.0) * one;
		bool b1 = near(2.0 * a, vec3(2.0, 4.0, 6.0)) && near(a * 2.0, vec3(2.0, 4.0, 6.0)) && near(a + 1.0, vec3(2.0, 3.0, 4.0));
		bool b2 = near(6.0 / a, vec3(6.0, 3.0, 2.0)) && near(a / 2.0, vec3(0.5, 1.0, 1.5)) && near(10.0 - a, vec3(9.0, 8.0, 7.0)) && near(a - 1.0, vec3(0.0, 1.0, 2.0));
		bool b3 = near(a * 2, vec3(2.0, 4.0, 6.0)) && near(3 + a, vec3(4.0, 5.0, 6.0));
		return b1 && b2 && b3;
	}

	if (cell == 8) {
		vec4 v = vec4(1.0, 2.0, 3.0, 4.0) * one;
		int i = int(1.0 + zero);
		bool a = near(v[0], 1.0) && near(v[3], 4.0) && near(v[i], 2.0);
		v[i + 1] = 9.0;
		v[0] += 1.0;
		float s = 0.0;

		for (int k = 0; k < 4; k++) {
			s += v[k];
		}

		bool b = near(v, vec4(2.0, 2.0, 9.0, 4.0)) && near(s, 17.0);
		return a && b;
	}

	if (cell == 9) {
		vec2 p = vec2(1.0, 2.0) * one;
		p *= 3.0;
		p += vec2(1.0);
		p /= vec2(2.0, 7.0);
		bool a = near(p, vec2(2.0, 1.0));
		p -= 1.0;
		bool b = near(p, vec2(1.0, 0.0));
		p += 2;
		bool c = near(p, vec2(3.0, 2.0));
		return a && b && c;
	}

	if (cell == 10) {
		vec3 a = vec3(1.0, 2.0, 3.0) * one;
		bool b1 = a == vec3(1.0, 2.0, 3.0);
		bool b2 = a != vec3(1.0, 2.0, 4.0);
		bool b3 = !(a == vec3(1.0, 2.0, 4.0));
		bool b4 = vec2(1.0, 2.0) == a.xy && a.zy != a.yz;
		return b1 && b2 && b3 && b4;
	}

	if (cell == 11) {
		vec3 a = vec3(1.0, 2.0, 3.0) * one;
		vec3 b = vec3(4.0, 5.0, 6.0);
		vec2 r = zero > 1.0 ? vec2(1.0) : vec2(2.0, 3.0);
		return near(r, vec2(2.0, 3.0)) && near((a + b).zx, vec2(9.0, 5.0)) && near(vec3(1.0, 2.0, 3.0).zy, vec2(3.0, 2.0)) && near((-a).y, -2.0);
	}

	if (cell == 12) {
		ivec2 i2 = ivec2(1, 2);
		uvec2 u2 = uvec2(3u, 4u);
		vec4 a = vec4(i2, u2);
		vec3 b = vec3(ivec3(-1, 0, 1));
		ivec3 c = ivec3(vec3(2.9, -2.9, 0.1) * one);
		uvec2 d = uvec2(vec2(3.7, 1.2) * one);
		bvec3 e = bvec3(vec3(0.0, 1.0, -2.0) * one);
		return near(a, vec4(1.0, 2.0, 3.0, 4.0)) && near(b, vec3(-1.0, 0.0, 1.0)) && c == ivec3(2, -2, 0) && d == uvec2(3u, 1u) && e == bvec3(false, true, true);
	}

	if (cell == 13) {
		vec4 v = vec4(1.0, 2.0, 3.0, 4.0) * one;
		v = v.yzwx * v.wxyz;
		bool a = near(v, vec4(8.0, 3.0, 8.0, 3.0));
		vec3 t = vec3(1.0, 2.0, 3.0) * one;
		t.xz = t.zx;
		bool b = near(t, vec3(3.0, 2.0, 1.0));
		t.zyx = t;
		bool c = near(t, vec3(1.0, 2.0, 3.0));
		return a && b && c;
	}

	if (cell == 14) {
		vec3 a;
		vec3 b;
		a = b = vec3(4.0) * one;
		vec2 c = (a.x += 1.0, vec2(a.x, b.x));
		return near(a, vec3(5.0, 4.0, 4.0)) && near(b, vec3(4.0)) && near(c, vec2(5.0, 4.0));
	}

	vec2 m = vec2(3.0, 4.0) * one;
	vec4 w = vec4(m, m) * vec4(m.x, m.y, 1.0, 0.5);
	return near(sqrt(dot(m, m)), 5.0) && near(m.yx.y, 3.0) && near(w, vec4(9.0, 16.0, 3.0, 2.0));
}

void main() {
	int cell = int(uv.x * 4.0) + int(uv.y * 4.0) * 4;
	final_color = run_cell(cell) ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}
