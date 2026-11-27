uniform mat4 view_projection;
uniform sampler2D tex;
uniform float zero;

struct Counter {
	int count;
	float total;
};

struct Range {
	float low;
	float high;
};

bool near(float a, float b) {
	return abs(a - b) < 0.0001;
}

bool near(vec2 a, vec2 b) {
	return all(lessThan(abs(a - b), vec2(0.0001)));
}

bool near(vec4 a, vec4 b) {
	return all(lessThan(abs(a - b), vec4(0.002)));
}

float later_defined(float x);
int later_int(int, int);

float uses_prototype(float x) {
	return later_defined(x) + float(later_int(2, 3));
}

float twice(float x) {
	return x * 2.0;
}

vec2 twice(vec2 x) {
	return x * 2.0;
}

int twice(int x) {
	return x * 2;
}

float twice(float x, float y) {
	return (x + y) * 2.0;
}

void split(float v, out float whole, out float part) {
	whole = floor(v);
	part = v - whole;
}

void increment(inout int n) {
	n++;
}

void increment(inout float n) {
	n += 1.0;
}

void scale(inout vec3 v, float s) {
	v *= s;
}

void add_to(inout float a, float b) {
	a += b;
}

void try_modify(float x) {
	x = 100.0;
}

float modify_local(float x) {
	x *= 3.0;
	return x;
}

float with_const(const float x) {
	return x + 1.0;
}

void fill(out float values[3]) {
	values[0] = 1.0;
	values[1] = 2.0;
	values[2] = 3.0;
}

float sum3(float values[3]) {
	return values[0] + values[1] + values[2];
}

Range make_range(float a, float b) {
	return Range(min(a, b), max(a, b));
}

void grow(inout Range r, float amount) {
	r.low -= amount;
	r.high += amount;
}

void count_into(inout Counter c, float v) {
	c.count++;
	c.total += v;
}

vec4 sample_at(sampler2D s, vec2 p) {
	return texture(s, p);
}

vec4 sample_twice(sampler2D s, vec2 a, vec2 b) {
	return sample_at(s, a) + sample_at(s, b);
}

float many(float a, float b, float c, float d, float e, float f, int g, int h) {
	return a + b * 2.0 + c * 3.0 + d * 4.0 + e * 5.0 + f * 6.0 + float(g * 7) + float(h * 8);
}

bool is_positive(float x) {
	return x > 0.0;
}

vec2 set_out_parts(out vec2 o) {
	o.x = 1.0;
	o.y = 2.0;
	return o * 3.0;
}

float later_defined(float x) {
	return x * 10.0;
}

int later_int(int a, int b) {
	return a * b;
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
		return near(twice(1.5 * one), 3.0) && near(twice(vec2(1.0, 2.0) * one), vec2(2.0, 4.0)) && twice(3 + z) == 6 && near(twice(one, 2.0), 6.0) && near(twice(3u), 6.0);
	}

	if (cell == 1) {
		return near(uses_prototype(one), 16.0) && near(later_defined(2.0 * one), 20.0) && later_int(4 + z, 5) == 20;
	}

	if (cell == 2) {
		float w;
		float p;
		split(3.25 * one, w, p);
		vec4 v = vec4(zero);
		split(7.5 * one, v.x, v.z);
		return near(w, 3.0) && near(p, 0.25) && near(v.x, 7.0) && near(v.z, 0.5) && near(v.y, 0.0);
	}

	if (cell == 3) {
		float a[3] = float[3](zero, zero, zero);
		split(2.75 * one, a[1], a[2]);
		int idx = 2 + z;
		increment(a[idx]);
		return near(a[0], 0.0) && near(a[1], 2.0) && near(a[2], 1.75);
	}

	if (cell == 4) {
		Counter c = Counter(z, zero);
		increment(c.count);
		increment(c.total);
		count_into(c, 2.5);
		count_into(c, 0.5);
		return c.count == 3 && near(c.total, 4.0);
	}

	if (cell == 5) {
		int n = 5 + z;
		increment(n);
		increment(n);
		vec3 v = vec3(1.0, 2.0, 3.0) * one;
		scale(v, 2.0);
		vec3 w = vec3(one);
		scale(w, 4.0);
		return n == 7 && near(v.xy, vec2(2.0, 4.0)) && near(v.z, 6.0) && near(w.y, 4.0);
	}

	if (cell == 6) {
		float x = 3.0 * one;
		add_to(x, x);
		float y = 2.0 * one;
		try_modify(y);
		float m = modify_local(y);
		return near(x, 6.0) && near(y, 2.0) && near(m, 6.0) && near(with_const(y), 3.0);
	}

	if (cell == 7) {
		float values[3];
		fill(values);
		return near(sum3(values), 6.0) && near(sum3(float[3](1.0, 1.0, one)), 3.0) && near(values[2], 3.0);
	}

	if (cell == 8) {
		Range r = make_range(5.0 * one, 2.0);
		grow(r, 1.0);
		return near(r.low, 1.0) && near(r.high, 6.0) && near(make_range(-one, -3.0).high, -1.0);
	}

	if (cell == 9) {
		vec4 t00 = sample_at(tex, vec2(0.5, 0.5) / 8.0);
		vec4 t32 = sample_at(tex, vec2(3.5, 2.5) / 8.0);
		vec4 sum = sample_twice(tex, vec2(0.5, 0.5) / 8.0, vec2(1.5, 0.5) / 8.0);
		return near(t00, vec4(0.0, 0.0, 1.0, 1.0)) && near(t32, vec4(108.0, 72.0, 32.0, 255.0) / 255.0) && near(sum, vec4(36.0, 0.0, 287.0, 510.0) / 255.0);
	}

	if (cell == 10) {
		return near(many(one, 1.0, 1.0, 1.0, 1.0, 1.0, 1, 1 + z), 36.0) && near(many(zero, 0.0, 0.0, 0.0, 0.0, 0.0, 0, 2), 16.0);
	}

	if (cell == 11) {
		int hits = 0;

		for (int i = -2; i < 3; i++) {
			if (is_positive(float(i) + zero)) {
				hits++;
			}
		}

		return hits == 2 && !is_positive(-one) && is_positive(one);
	}

	if (cell == 12) {
		vec2 o;
		vec2 r = set_out_parts(o);
		return near(o, vec2(1.0, 2.0)) && near(r, vec2(3.0, 6.0));
	}

	if (cell == 13) {
		return near(twice(twice(twice(one))), 8.0) && twice(twice(2 + z)) == 8 && near(twice(twice(vec2(one)).yx), vec2(4.0));
	}

	if (cell == 14) {
		Range r = make_range(one, 2.0);
		Range s = r;
		grow(s, 0.5);
		return near(r.low, 1.0) && near(s.low, 0.5) && near(s.high, 2.5) && r != s;
	}

	float acc = zero;

	for (int i = 0; i < 4; i++) {
		add_to(acc, twice(float(i)));
	}

	return near(acc, 12.0);
}

void main() {
	int cell = int(uv.x * 4.0) + int(uv.y * 4.0) * 4;
	final_color = run_cell(cell) ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}
