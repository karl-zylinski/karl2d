uniform mat4 view_projection;
uniform float fzero;

const vec3 base = vec3(1.0, 2.0, 3.0);
const float weights[3] = float[3](0.25, 0.5, 2.0);

bool near(float a, float b) {
	return abs(a - b) < 0.001;
}

bool near3(vec3 a, vec3 b) {
	return near(a.x, b.x) && near(a.y, b.y) && near(a.z, b.z);
}

float scaled(float x, float scale) {
	if (scale == 0.0) {
		return 0.0;
	}

	return x * scale + weights[1];
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
	int cell = int(uv.x * 4.0) + int(uv.y * 4.0) * 4;
	bool ok = true;
	float z = fzero;
	vec3 zv = vec3(fzero);
	vec3 run = base + zv;

	if (cell == 0) {
		ok = near(sin(0.5), sin(z + 0.5)) && near(cos(0.5), cos(z + 0.5)) && near(tan(0.5), tan(z + 0.5));
	} else if (cell == 1) {
		ok = near(pow(2.0, 3.0), 8.0) && near(exp(1.0), exp(z + 1.0)) && near(log(2.0), log(z + 2.0)) && near(exp2(3.0), 8.0) && near(log2(8.0), 3.0);
	} else if (cell == 2) {
		ok = near(sqrt(9.0), 3.0) && near(inversesqrt(4.0), 0.5) && near(abs(-2.5), 2.5) && near(sign(-2.0), -1.0) && near(sign(0.0), 0.0) && near(radians(180.0), 3.141593) && near(degrees(3.141593), 180.0);
	} else if (cell == 3) {
		ok = near(floor(-1.5), -2.0) && near(ceil(-1.5), -1.0) && near(fract(-1.25), 0.75) && near(mod(5.5, 2.0), 1.5) && near(mod(-0.5, 2.0), 1.5);
	} else if (cell == 4) {
		ok = near(min(1.0, 2.0), 1.0) && near(max(1.0, 2.0), 2.0) && near(clamp(5.0, 0.0, 1.0), 1.0) && near(mix(2.0, 4.0, 0.25), 2.5) && near(step(0.5, 0.75), 1.0) && near(step(0.5, 0.25), 0.0) && near(smoothstep(0.0, 1.0, 0.25), smoothstep(z, 1.0, z + 0.25));
	} else if (cell == 5) {
		ok = near(dot(base, vec3(1.0, 0.5, 0.25)), dot(run, vec3(1.0, 0.5, 0.25))) && near(length(base), length(run)) && near(distance(base, vec3(1.0)), distance(run, vec3(1.0)));
	} else if (cell == 6) {
		ok = near3(normalize(base), normalize(run)) && near3(cross(base, vec3(0.0, 1.0, 0.0)), cross(run, vec3(0.0, 1.0, 0.0)));
	} else if (cell == 7) {
		vec3 a = base * 2.0 + vec3(1.0, 0.0, -1.0);
		vec3 b = -base / vec3(2.0, 4.0, 8.0);
		ok = near3(a, run * 2.0 + vec3(1.0, 0.0, -1.0)) && near3(b, -run / vec3(2.0, 4.0, 8.0)) && near3(min(base, 2.0), min(run, 2.0)) && near3(clamp(base, 1.5, 2.5), clamp(run, 1.5, 2.5));
	} else if (cell == 8) {
		vec2 s = base.zx;
		float single = base.y;
		ok = near(s.x, 3.0) && near(s.y, 1.0) && near(single, 2.0) && near(base[2], 3.0) && near(vec4(base, 4.0).w, 4.0) && near(vec3(2.0).y, 2.0) && near(vec2(base).y, 2.0);
	} else if (cell == 9) {
		float never_written = 4.0;
		float written = 4.0;
		written += z;
		int index = int(z) + 1;
		vec3 indexed = vec3(5.0, 6.0, 7.0);
		ok = near(never_written * 2.0, 8.0) && near(written * 2.0, 8.0) && near(indexed[index], 6.0) && near(weights[2], 2.0) && near(weights[index], 0.5);
	} else if (cell == 10) {
		float picked = 0.0;

		if (weights[0] > 1.0) {
			picked = 100.0;
		} else {
			picked = 3.0;
		}

		if (base.x == 1.0) {
			picked += 1.0;
		}

		ok = near(picked, 4.0) && near(base.x > 0.5 ? 1.0 : 2.0, 1.0) && (true || z > 5.0) && !(false && z < 5.0) && (z < 5.0 && true) && (z > 5.0 || true);
	} else if (cell == 11) {
		ok = near(pow(z + 3.0, 2.0), 9.0) && near(pow(z + 3.0, 3.0), 27.0) && near(pow(z + 3.0, 4.0), 81.0) && near(pow(z + 4.0, 0.5), 2.0) && near3(pow(run, vec3(2.0)), vec3(1.0, 4.0, 9.0)) && near3(pow(run, vec3(3.0)), vec3(1.0, 8.0, 27.0));
	} else if (cell == 12) {
		ok = near(scaled(z + 2.0, 3.0), 6.5) && near(scaled(2.0, 0.0), 0.0) && near(scaled(2.0, 3.0), 6.5);
	} else if (cell == 13) {
		ivec3 iv = ivec3(1, 2, 3) * 3 + ivec3(1);
		int shifted = (5 << 2) | 1;
		uint wrapped = 3u - 5u;
		ok = iv == ivec3(4, 7, 10) && shifted == 21 && wrapped == 4294967294u && -ivec2(2, -3) == ivec2(-2, 3) && 7 % 4 == 3;
	} else if (cell == 14) {
		vec3 bg = mix(vec3(0.0, 0.5, 1.0), vec3(1.0, 0.5, 0.0), z + 0.25);
		ok = near3(bg, vec3(0.25, 0.5, 0.75)) && near(smoothstep(1.0, 3.0, z + 2.0), 0.5);
	} else {
		ok = near(sqrt(-1.0 + 5.0), 2.0) && near(1.0 / 4.0, 0.25) && near(length(vec2(3.0, 4.0)), 5.0);
	}

	final_color = ok ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}
