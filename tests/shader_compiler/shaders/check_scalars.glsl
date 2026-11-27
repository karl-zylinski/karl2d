uniform mat4 view_projection;
uniform sampler2D tex;

const float EPSILON = 0.0001;

bool near(float a, float b) {
	return abs(a - b) < EPSILON;
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
	float one = 1;
	int three = 3;
	uint five = 5u;

	if (cell == 0) {
		ok = near(one + 2.5, 3.5) && near(7.0 - one * 2.0, 5.0);
	} else if (cell == 1) {
		ok = three / 2 == 1 && three % 2 == 1 && -three / 2 == -1;
	} else if (cell == 2) {
		ok = near(float(three) / 2.0, 1.5) && near(three / 2.0, 1.5);
	} else if (cell == 3) {
		ok = five / 2u == 2u && five % 3u == 2u && five - 6u == 4294967295u;
	} else if (cell == 4) {
		ok = (three & 6) == 2 && (three | 4) == 7 && (three ^ 1) == 2 && ~three == -4;
	} else if (cell == 5) {
		ok = (three << 2) == 12 && (-16 >> 2) == -4 && (five >> 1u) == 2u;
	} else if (cell == 6) {
		int i = three;
		i++;
		++i;
		int j = i--;
		ok = i == 4 && j == 5 && --i == 3;
	} else if (cell == 7) {
		float f = 2.0;
		f += 1.0;
		f *= 3.0;
		f -= 1.0;
		f /= 4.0;
		ok = near(f, 2.0);
	} else if (cell == 8) {
		ok = (three > 2) && !(three < 3) && (three >= 3) && (three <= 3) && (three != 4);
	} else if (cell == 9) {
		bool t = true;
		bool f = false;
		ok = (t || f) && !(t && f) && (t ^^ f) && !(t ^^ t);
	} else if (cell == 10) {
		float picked = three > 2 ? 4.0 : 5.0;
		int other = three < 2 ? 1 : 2;
		ok = near(picked, 4.0) && other == 2;
	} else if (cell == 11) {
		ok = int(2.9) == 2 && int(-2.9) == -2 && uint(3.7) == 3u && float(five) == 5.0;
	} else if (cell == 12) {
		ok = bool(1) && !bool(0) && bool(0.5) && int(true) == 1 && float(false) == 0.0;
	} else if (cell == 13) {
		ok = near(1e2, 100.0) && near(.5, 0.5) && near(2.5e-1, 0.25) && 0x10 == 16;
	} else if (cell == 14) {
		int a = 1, b = 2, c;
		c = a + b;
		ok = c == 3 && (a = 5, a + b) == 7;
	} else {
		const int N = 3 * 2 + 1;
		float values[N];
		values[N - 1] = 2.0;
		ok = near(values[6], 2.0) && values.length() == 7;
	}

	final_color = ok ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}
