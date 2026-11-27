uniform mat4 view_projection;
uniform sampler2D tex;
uniform int zero;

bool near(float a, float b) {
	return abs(a - b) < 0.001;
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

struct Light {
	vec3 dir;
	float power;
	vec2 spot;
	int kind;
};

struct Scene {
	Light lights[2];
	vec4 ambient;
};

const float WEIGHTS[4] = float[4](0.1, 0.2, 0.3, 0.4);

Light make_light(float p) {
	Light l;
	l.dir = vec3(0.0, 1.0, 0.0);
	l.power = p;
	l.spot = vec2(p, p * 2.0);
	l.kind = 3;
	return l;
}

float sum(float values[4]) {
	float total = 0.0;

	for (int i = 0; i < 4; i++) {
		total += values[i];
	}

	return total;
}

void main() {
	int cell = int(uv.x * 4.0) + int(uv.y * 4.0) * 4;
	bool ok = true;
	int one = 1 + zero;

	if (cell == 0) {
		mat2 m = mat2(1.0, 2.0, 3.0, 4.0);
		vec2 v = m * vec2(1.0, 1.0);
		vec2 w = vec2(1.0, 1.0) * m;
		ok = near(v.x, 4.0) && near(v.y, 6.0) && near(w.x, 3.0) && near(w.y, 7.0) && near(m[1][0], 3.0);
	} else if (cell == 1) {
		mat3 m = mat3(2.0);
		m[2] = vec3(1.0, 2.0, 3.0);
		mat3 t = transpose(m);
		ok = near(t[0][2], 1.0) && near(t[1][2], 2.0) && near(t[2][2], 3.0) && near(determinant(m), 12.0);
	} else if (cell == 2) {
		mat4 m = mat4(1.0);
		m[3] = vec4(2.0, 3.0, 4.0, 1.0);
		mat4 inv = inverse(m);
		vec4 p = inv * vec4(2.0, 3.0, 4.0, 1.0);
		ok = near(p.x, 0.0) && near(p.y, 0.0) && near(p.z, 0.0) && near(p.w, 1.0);
	} else if (cell == 3) {
		mat3 a = mat3(1.0, 2.0, 0.0, 0.0, 1.0, 3.0, 4.0, 0.0, 1.0);
		mat3 id = a * inverse(a);
		ok = near(id[0][0], 1.0) && near(id[1][1], 1.0) && near(id[2][2], 1.0) && near(id[1][0], 0.0) && near(id[0][2], 0.0);
	} else if (cell == 4) {
		ok = near(sum(WEIGHTS), 1.0) && near(WEIGHTS[one], 0.2) && near(WEIGHTS[one + 2], 0.4);
	} else if (cell == 5) {
		Light l = make_light(2.0);
		Light k = l;
		k.kind = 4;
		ok = near(l.spot.y, 4.0) && l.kind == 3 && k.kind == 4 && l == l && l != k;
	} else if (cell == 6) {
		Scene s;
		s.lights[0] = make_light(1.0);
		s.lights[1] = make_light(5.0);
		s.ambient = vec4(0.5);
		ok = near(s.lights[one].power, 5.0) && near(s.lights[one - 1].spot.y, 2.0) && near(s.ambient.z, 0.5);
	} else if (cell == 7) {
		vec4 v = vec4(1.0, 2.0, 3.0, 4.0);
		v[one] = 9.0;
		v.zw = v.wz;
		ok = near(v[one], 9.0) && near(v.z, 4.0) && near(v.w, 3.0) && near(v[zero], 1.0);
	} else if (cell == 8) {
		float values[4];

		for (int i = 0; i < 4; i++) {
			values[i] = float(i * i);
		}

		values[one + 1] += 0.5;
		ok = near(sum(values), 14.5);
	} else if (cell == 9) {
		mat2 m = mat2(vec2(1.0, 2.0), vec2(3.0, 4.0));
		m *= 2.0;
		mat2 n = m + mat2(1.0);
		ok = near(n[0][0], 3.0) && near(n[0][1], 4.0) && near(n[1][0], 6.0) && near(n[1][1], 9.0) && near(m[one][one], 8.0);
	} else if (cell == 10) {
		ivec3 a = ivec3(7, -7, 9);
		ivec3 q = a / 2;
		ivec3 r = a % 4;
		uvec2 u = uvec2(7u, 9u) / 2u;
		ok = q == ivec3(3, -3, 4) && r == ivec3(3, -3, 1) && u == uvec2(3u, 4u);
	} else if (cell == 11) {
		vec3 v = vec3(vec2(1.0, 2.0), 3.0);
		vec4 w = vec4(v, 4.0);
		vec2 t = vec2(w);
		mat3 m3 = mat3(mat4(2.0));
		ok = near(w.z, 3.0) && near(t.y, 2.0) && near(m3[2][2], 2.0) && near(m3[2][0], 0.0) && near(vec3(5.0).y, 5.0);
	} else {
		bvec3 b = lessThan(vec3(1.0, 5.0, 3.0), vec3(2.0));
		ok = b.x && !b.y && !b.z && any(b) && !all(b) && all(not(bvec2(false)));
	}

	final_color = ok ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}
