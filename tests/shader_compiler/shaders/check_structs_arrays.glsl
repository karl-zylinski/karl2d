uniform mat4 view_projection;
uniform float zero;

struct Light {
	vec3 color;
	float intensity;
};

struct Inner {
	int a;
	vec2 b;
};

struct Outer {
	Inner inner;
	float f[3];
	bool flag;
};

struct Scene {
	Light lights[2];
	int count;
	mat2 m;
};

struct Grid {
	ivec2 size;
	bvec2 wrap;
	uint cells[4];
};

const float weights[4] = float[4](0.1, 0.2, 0.3, 0.4);
const vec2 corners[] = vec2[](vec2(0.0, 0.0), vec2(1.0, 0.0), vec2(1.0, 1.0), vec2(0.0, 1.0));
const Light default_light = Light(vec3(1.0, 0.5, 0.25), 2.0);

Light global_light = Light(vec3(0.0), 1.0);

bool near(float a, float b) {
	return abs(a - b) < 0.0001;
}

bool near(vec2 a, vec2 b) {
	return all(lessThan(abs(a - b), vec2(0.0001)));
}

bool near(vec3 a, vec3 b) {
	return all(lessThan(abs(a - b), vec3(0.0001)));
}

float sum4(float v[4]) {
	float s = 0.0;

	for (int i = 0; i < v.length(); i++) {
		s += v[i];
	}

	return s;
}

Light make_light(float i) {
	Light l;
	l.color = vec3(i, i * 0.5, 0.0);
	l.intensity = i * 2.0;
	return l;
}

void brighten(inout Light l, float amount) {
	l.intensity += amount;
	l.color.z = amount;
}

void double_all(inout float v[4]) {
	for (int i = 0; i < 4; i++) {
		v[i] *= 2.0;
	}
}

float total_intensity(Light ls[3]) {
	return ls[0].intensity + ls[1].intensity + ls[2].intensity;
}

void set_global_light(float intensity) {
	global_light.intensity = intensity;
	global_light.color = vec3(intensity);
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
	int z = int(zero);

	if (cell == 0) {
		Light l = Light(vec3(1.0, 0.5, 0.25) * one, 2.0);
		return near(l.color.y, 0.5) && near(l.intensity, 2.0) && near(l.color, vec3(1.0, 0.5, 0.25)) && l == default_light;
	}

	if (cell == 1) {
		Outer o = Outer(Inner(3 + z, vec2(1.0, 2.0)), float[3](4.0, 5.0, 6.0 * one), true);
		return o.inner.a == 3 && near(o.inner.b.y, 2.0) && near(o.f[2], 6.0) && o.flag && o.f.length() == 3;
	}

	if (cell == 2) {
		Outer o = Outer(Inner(3, vec2(1.0, 2.0)), float[3](4.0, 5.0, 6.0), false);
		o.inner.a = 7 + z;
		o.inner.b.x += 1.0;
		o.f[0] = o.f[1] * 2.0;
		o.inner.b = o.inner.b.yx;
		o.flag = !o.flag;
		return o.inner.a == 7 && near(o.inner.b, vec2(2.0, 2.0)) && near(o.f[0], 10.0) && o.flag;
	}

	if (cell == 3) {
		Light ls[3];
		ls[0] = Light(vec3(one), 1.0);
		ls[1] = make_light(2.0);
		ls[2] = ls[1];
		ls[2].intensity = 0.5;
		float s = 0.0;

		for (int i = z; i < 3; i++) {
			s += ls[i].intensity;
		}

		return near(s, 5.5) && near(total_intensity(ls), 5.5) && near(ls[1].color.y, 1.0) && ls.length() == 3;
	}

	if (cell == 4) {
		Light a = Light(vec3(1.0, 2.0, 3.0) * one, 4.0);
		Light b = a;
		bool ok = a == b && !(a != b);
		b.intensity = 3.0;
		ok = ok && a != b && !(a == b);
		Outer o1 = Outer(Inner(1, vec2(one)), float[3](1.0, 2.0, 3.0), true);
		Outer o2 = o1;
		ok = ok && o1 == o2;
		o2.f[1] = 9.0;
		ok = ok && o1 != o2;
		return ok;
	}

	if (cell == 5) {
		float a[3] = float[3](1.0, 2.0, 3.0 * one);
		float b[] = float[](1.0, 2.0, 3.0);
		float c[3];
		c = a;
		bool ok = a == b && c == a && b.length() == 3;
		c[1] = 9.0;
		ok = ok && c != a && near(c[1], 9.0) && near(a[1], 2.0);
		return ok;
	}

	if (cell == 6) {
		float w[4] = weights;
		double_all(w);
		Light l = make_light(one);
		brighten(l, 0.5);
		return near(sum4(weights), 1.0) && near(sum4(w), 2.0) && near(l.intensity, 2.5) && near(l.color, vec3(1.0, 0.5, 0.5));
	}

	if (cell == 7) {
		float s = 0.0;

		for (int i = z; i < 4; i++) {
			s += weights[i] * float(i);
		}

		return near(s, 2.0) && near(weights[3 - z], 0.4) && corners.length() == 4 && near(corners[2 + z], vec2(1.0)) && near(corners[3].y, 1.0);
	}

	if (cell == 8) {
		vec2 pts[3] = vec2[3](vec2(zero), vec2(1.0, 0.0), vec2(0.0, 1.0));
		pts[0].x = 5.0;
		pts[1] += vec2(1.0);
		return near(pts[2].y, 1.0) && near(pts[0], vec2(5.0, 0.0)) && near(pts[1], vec2(2.0, 1.0)) && pts.length() == 3;
	}

	if (cell == 9) {
		int squares[5];

		for (int i = 0; i < 5; i++) {
			squares[i] = i * i + z;
		}

		Light pair[2] = Light[2](Light(vec3(1.0), 1.0), Light(vec3(2.0), 2.0 * one));
		return squares[4] == 16 && squares[2] == 4 && near(pair[1].intensity, 2.0) && near(pair[0].color.x, 1.0) && pair.length() == 2;
	}

	if (cell == 10) {
		Scene s;
		s.lights[0] = default_light;
		s.lights[1] = Light(vec3(zero), 0.0);
		s.lights[1].color.z = 0.5;
		s.count = 2 + z;
		s.m = mat2(2.0 * one);
		s.m[1][1] = 3.0;
		return near(s.lights[1].color, vec3(0.0, 0.0, 0.5)) && near(s.lights[0].intensity, 2.0) && s.count == 2 && near(s.m[0][0], 2.0) && near(s.m[1][1], 3.0) && near(s.m[1][0], 0.0);
	}

	if (cell == 11) {
		Scene a = Scene(Light[2](default_light, default_light), 1, mat2(one));
		Scene b = a;
		bool ok = a == b;
		b.m[0][1] = 1.0;
		ok = ok && a != b;
		b = a;
		b.lights[1].intensity = 0.0;
		ok = ok && a != b;
		return ok;
	}

	if (cell == 12) {
		Grid g = Grid(ivec2(2, 2 + z), bvec2(true, false), uint[4](1u, 2u, 3u, 4u));
		uint s = 0u;

		for (int i = 0; i < g.size.x * g.size.y; i++) {
			s += g.cells[i];
		}

		bvec2 flags[2] = bvec2[2](g.wrap, g.wrap.yx);
		ivec3 iv[2] = ivec3[2](ivec3(1, 2, 3), ivec3(z));
		return s == 10u && flags[1] == bvec2(false, true) && iv[0].z == 3 && iv[1] == ivec3(0) && g.cells[3] == 4u;
	}

	if (cell == 13) {
		set_global_light(3.0 * one);
		Light copy = global_light;
		set_global_light(1.0);
		return near(copy.intensity, 3.0) && near(global_light.intensity, 1.0) && near(global_light.color, vec3(1.0)) && near(copy.color, vec3(3.0));
	}

	if (cell == 14) {
		Light l = default_light;
		brighten(l, 1.0);
		brighten(l, 1.0);
		Light ls[3] = Light[3](l, l, default_light);
		brighten(ls[1], 2.0);
		return near(l.intensity, 4.0) && near(ls[1].intensity, 6.0) && near(ls[1].color.z, 2.0) && near(ls[2].intensity, 2.0);
	}

	float a[4] = float[4](1.0, 2.0, 3.0, 4.0);
	uint i = 1u + uint(z);
	a[i] = 7.0;
	a[i + 1u] += 1.0;
	return near(a[1u], 7.0) && near(a[2], 4.0) && near(sum4(a), 16.0);
}

void main() {
	int cell = int(uv.x * 4.0) + int(uv.y * 4.0) * 4;
	final_color = run_cell(cell) ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}
