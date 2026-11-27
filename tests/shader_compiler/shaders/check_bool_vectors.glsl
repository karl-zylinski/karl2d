uniform mat4 view_projection;
uniform float zero;

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

bool bump(inout int n) {
	n++;
	return true;
}

int bump_value(inout int n, int v) {
	n += 10;
	return v;
}

bool run_cell(int cell) {
	bool t = zero < 1.0;
	bool f = !t;
	int z = int(zero);

	if (cell == 0) {
		bvec2 a = bvec2(t, f);
		bvec3 b = bvec3(t);
		bvec4 c = bvec4(bvec2(t, f), f, true);
		bvec2 d = bvec2(ivec2(z, 3));
		bvec2 e = bvec2(vec2(0.0, -0.5) + zero);
		bvec3 g = bvec3(uvec3(0u, 1u, 2u) + uint(z));
		return a.x && !a.y && b.x && b.y && b.z && c == bvec4(true, false, false, true) && d == bvec2(false, true) && e == bvec2(false, true) && g == bvec3(false, true, true);
	}

	if (cell == 1) {
		vec3 a = vec3(1.0, 2.0, 3.0) + zero;
		vec3 b = vec3(2.0);
		return lessThan(a, b) == bvec3(true, false, false) && lessThanEqual(a, b) == bvec3(true, true, false) && greaterThan(a, b) == bvec3(false, false, true) && greaterThanEqual(a, b) == bvec3(false, true, true);
	}

	if (cell == 2) {
		ivec3 a = ivec3(1, 2, 3 + z);
		ivec3 b = ivec3(1, 0, 3);
		uvec2 c = uvec2(4u, 5u) + uint(z);
		bvec2 d = bvec2(t, f);
		bool ok = equal(a, b) == bvec3(true, false, true) && notEqual(a, b) == bvec3(false, true, false);
		ok = ok && equal(c, uvec2(4u, 6u)) == bvec2(true, false) && notEqual(c, uvec2(4u, 6u)) == bvec2(false, true);
		ok = ok && equal(d, bvec2(true, true)) == bvec2(true, false) && notEqual(d, bvec2(true, true)) == bvec2(false, true);
		ok = ok && equal(vec4(1.0, 2.0, 3.0, 4.0) + zero, vec4(1.0, 0.0, 3.0, 0.0)) == bvec4(true, false, true, false);
		return ok;
	}

	if (cell == 3) {
		bool ok = any(bvec3(f, f, t)) && !any(bvec2(f)) && all(bvec4(t)) && !all(bvec3(t, f, t));
		ok = ok && not(bvec2(t, f)) == bvec2(false, true) && all(not(bvec3(f))) && any(not(bvec4(t, t, f, t)));
		return ok;
	}

	if (cell == 4) {
		bvec4 b = bvec4(t, f, t, f);
		bool ok = b.yx == bvec2(false, true) && b.rg == bvec2(true, false) && b.q == false && b[2];
		b.w = true;
		b[1] = t;
		ok = ok && b == bvec4(true, true, true, true) && all(b);
		b.zx = bvec2(f, f);
		ok = ok && b == bvec4(false, true, false, true);
		return ok;
	}

	if (cell == 5) {
		return lessThan(ivec2(1, 5 + z), vec2(1.5, 4.5)) == bvec2(true, false) && lessThan(uvec2(1u, 5u), uvec2(2u) + uint(z)) == bvec2(true, false) && greaterThanEqual(ivec3(z), ivec3(0, 1, -1)) == bvec3(true, false, true);
	}

	if (cell == 6) {
		int n = 0;
		bool r1 = f && bump(n);
		bool ok = !r1 && n == 0;
		bool r2 = t || bump(n);
		ok = ok && r2 && n == 0;
		bool r3 = t && bump(n);
		ok = ok && r3 && n == 1;
		bool r4 = f || bump(n);
		ok = ok && r4 && n == 2;
		bool r5 = t ^^ bump(n);
		ok = ok && !r5 && n == 3;
		int v = t ? 1 : bump_value(n, 2);
		ok = ok && v == 1 && n == 3;
		int w = f ? 1 : bump_value(n, 2);
		ok = ok && w == 2 && n == 13;
		return ok;
	}

	if (cell == 7) {
		bvec2 b = bvec2(1.0 + zero < 2.0, 3 + z > 4);
		bool c = 2.5 + zero >= 2.5;
		bool d = 2u + uint(z) <= 1u;
		return b == bvec2(true, false) && c && !d;
	}

	if (cell == 8) {
		vec3 m = mix(vec3(1.0, 2.0, 3.0) + zero, vec3(4.0, 5.0, 6.0), bvec3(t, f, t));
		float s = mix(1.0 + zero, 2.0, t);
		return all(equal(m, vec3(4.0, 2.0, 6.0))) && s == 2.0;
	}

	if (cell == 9) {
		return ivec3(bvec3(t, f, t)) == ivec3(1, 0, 1) && vec2(bvec2(f, t)) == vec2(0.0, 1.0) && uvec2(bvec2(t)) == uvec2(1u, 1u) && int(t) + int(f) == 1 && float(t) == 1.0;
	}

	if (cell == 10) {
		int found = 0;

		for (int i = 0; i < 4; i++) {
			bvec4 m = equal(ivec4(0, 1, 2, 3), ivec4(i + z));

			if (any(m) && !all(m)) {
				found++;
			}
		}

		return found == 4;
	}

	if (cell == 11) {
		bvec2 a = bvec2(t, f);
		return a == bvec2(true, false) && a != bvec2(false, false) && !(a != bvec2(true, false)) && (a.x == t) && (a.y != t);
	}

	bool x = t ? (f ? false : true) : false;
	bool y = !(t && f) == (!t || !f);
	bool w = (t == true) && (f == false) && (t != f);
	return x && y && w && !!t;
}

void main() {
	int cell = int(uv.x * 4.0) + int(uv.y * 4.0) * 4;
	final_color = run_cell(cell) ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}
