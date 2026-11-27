uniform mat4 view_projection;
uniform sampler2D tex;
uniform float zero;

struct Pair {
	float a;
	uint b;
};

const float from_int_const = 4;
const uint from_int_uint = 9;
const vec2 vec_from_ints = vec2(1, 2);

bool near(float a, float b) {
	return abs(a - b) < 0.0001;
}

bool near(vec2 a, vec2 b) {
	return all(lessThan(abs(a - b), vec2(0.0001)));
}

bool near(vec3 a, vec3 b) {
	return all(lessThan(abs(a - b), vec3(0.0001)));
}

float takes_float(float x) {
	return x * 0.5;
}

vec3 takes_vec3(vec3 v) {
	return v + 0.5;
}

uint takes_uint(uint x) {
	return x + 1u;
}

float returns_int_as_float() {
	return 3;
}

vec2 returns_ivec_as_vec() {
	return ivec2(1, 2);
}

uvec2 returns_ivec_as_uvec() {
	return ivec2(3, 4);
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
	int z = int(zero);
	uint zu = uint(zero);

	if (cell == 0) {
		float f = 1;
		uint u = 3;
		float g = u;
		vec3 v = ivec3(1, 2, 3 + z);
		vec2 w = uvec2(1u, 2u + zu);
		uvec2 uw = ivec2(1, 2 + z);
		uvec3 from_int = ivec3(z);
		return near(f, 1.0) && u == 3u && near(g, 3.0) && near(v, vec3(1.0, 2.0, 3.0)) && near(w, vec2(1.0, 2.0)) && uw == uvec2(1u, 2u) && from_int == uvec3(0u);
	}

	if (cell == 1) {
		float f;
		vec3 v;
		uint u;
		f = 2 + z;
		v = ivec3(4, 5, 6 + z);
		u = 7 + z;
		return near(f, 2.0) && near(v, vec3(4.0, 5.0, 6.0)) && u == 7u;
	}

	if (cell == 2) {
		int i = 3 + z;
		uint u = 2u + zu;
		float f = 0.5 + zero;
		bool ok = near(i + f, 3.5) && near(u * f, 1.0) && near(f - i, -2.5) && u + i == 5u && i * u == 6u;
		ok = ok && near(ivec2(1, 2) + vec2(f), vec2(1.5, 2.5)) && near(uvec3(1u) * vec3(f), vec3(0.5)) && near(vec2(f) / ivec2(1, 2), vec2(0.5, 0.25));
		ok = ok && near(i / 2.0, 1.5) && near(2 * f, 1.0) && near(ivec3(2) * f, vec3(1.0));
		return ok;
	}

	if (cell == 3) {
		int i = 3 + z;
		uint u = 3u + zu;
		float f = 3.0 + zero;
		return i == f && u == i && u == f && i < 3.5 && u > 2 && f >= u && ivec2(1, 2) == vec2(1.0, 2.0) && uvec2(1u) != ivec2(2);
	}

	if (cell == 4) {
		return near(takes_float(3 + z), 1.5) && near(takes_float(5u + zu), 2.5) && near(takes_vec3(ivec3(1, 2, 3 + z)), vec3(1.5, 2.5, 3.5)) && takes_uint(4 + z) == 5u && near(takes_vec3(uvec3(1u)), vec3(1.5));
	}

	if (cell == 5) {
		return near(returns_int_as_float(), 3.0) && near(returns_ivec_as_vec(), vec2(1.0, 2.0)) && returns_ivec_as_uvec() == uvec2(3u, 4u);
	}

	if (cell == 6) {
		bool c = zero < 1.0;
		float a = c ? 1 : 2.0;
		vec2 b = c ? ivec2(1) : vec2(0.5);
		uint d = c ? 5 : 6u;
		float e = !c ? 1u : 2;
		return near(a, 1.0) && near(b, vec2(1.0)) && d == 5u && near(e, 2.0);
	}

	if (cell == 7) {
		Pair p = Pair(1 + z, 2 + z);
		float arr[2] = float[2](1 + z, 2u + zu);
		uint uarr[] = uint[](1, 2u, 3);
		return near(p.a, 1.0) && p.b == 2u && near(arr[0], 1.0) && near(arr[1], 2.0) && uarr[2] == 3u && uarr.length() == 3;
	}

	if (cell == 8) {
		float f = 1.0 + zero;
		vec3 v = vec3(1.0) + zero;
		uint u = 1u + zu;
		f += 2 + z;
		v *= 2 + z;
		u += 1 + z;
		f *= 2u + zu;
		v -= ivec3(1, 0, 1);
		u *= 3;
		return near(f, 6.0) && near(v, vec3(1.0, 2.0, 1.0)) && u == 6u;
	}

	if (cell == 9) {
		bool ok = near(pow(2 + z, 3), 8.0) && near(mix(1, 3, 0.5 + zero), 2.0) && max(1u + zu, 2) == 2u && min(3 + z, 2u) == 2u && clamp(5 + z, 0u, 3u) == 3u;
		ok = ok && near(texture(tex, ivec2(z)).b, 1.0) && near(sqrt(16 + z), 4.0) && near(step(1, 2 + z), 1.0) && near(length(ivec3(2, 3, 6 + z)), 7.0);
		return ok;
	}

	if (cell == 10) {
		float a[3] = float[3](1.0, 2.0, 3.0);
		uint i = 2u + zu;
		vec4 v = vec4(1.0, 2.0, 3.0, 4.0);
		return near(a[i], 3.0) && near(v[i], 3.0) && near(v[1u], 2.0);
	}

	if (cell == 11) {
		mat2 m = mat2(1.0, 2.0, 3.0, 4.0);
		return near(m * ivec2(1, 1 + z), vec2(4.0, 6.0)) && near(uvec2(1u, zu) * m, vec2(1.0, 3.0)) && near((m * 2)[1], vec2(6.0, 8.0));
	}

	if (cell == 12) {
		float neg = -2.9 + zero;
		float pos = 3.7 + zero;
		return int(neg) == -2 && uint(pos) == 3u && int(pos) == 3 && uint(int(-1 + z)) == 0xFFFFFFFFu && int(0x80000000u + zu) == -2147483647 - 1;
	}

	if (cell == 13) {
		return bool(1 + z) && !bool(z) && bool(0.5 + zero) && !bool(zero) && bool(3u + zu) && int(true) == 1 && uint(true) == 1u && float(false) == 0.0 && ivec2(bvec2(true, false)) == ivec2(1, 0);
	}

	if (cell == 14) {
		return near(from_int_const, 4.0) && from_int_uint == 9u && near(vec_from_ints, vec2(1.0, 2.0)) && near(vec2(1, 2u), vec2(1.0, 2.0)) && ivec3(1.9, -1.9, uint(7)) == ivec3(1, -1, 7);
	}

	int i = 7 + z;
	float f = float(i) / 2;
	uint u = uint(f);
	return near(f, 3.5) && u == 3u && near(float(u) + 0.5, 3.5) && float(i / 2) == 3.0;
}

void main() {
	int cell = int(uv.x * 4.0) + int(uv.y * 4.0) * 4;
	final_color = run_cell(cell) ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}
