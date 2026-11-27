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

int first_above(int limit) {
	for (int i = 0; i < 10; i++) {
		if (i * i > limit) {
			return i;
		}
	}

	return -1;
}

float pick(float x) {
	if (x < 1.0) {
		return 10.0;
	}

	if (x < 2.0) {
		return 20.0;
	}

	return 30.0;
}

void split(float v, out float whole, inout float total) {
	whole = floor(v);
	total += v - whole;
}

int nested(int n) {
	int count = 0;

	for (int i = 0; i < n; i++) {
		for (int j = 0; j < n; j++) {
			if (j > i) {
				break;
			}

			if ((i + j) % 2 == 1) {
				continue;
			}

			count++;

			if (count > 100) {
				return -5;
			}
		}
	}

	return count;
}

int do_loop(int n) {
	int i = 0;
	int sum = 0;

	do {
		i++;

		if (i == 3) {
			continue;
		}

		sum += i;
	} while (i < n);

	return sum;
}

void main() {
	int cell = int(uv.x * 4.0) + int(uv.y * 4.0) * 4;
	bool ok = true;

	if (cell == 0) {
		ok = first_above(10 + zero) == 4 && first_above(1000) == -1;
	} else if (cell == 1) {
		ok = near(pick(0.5), 10.0) && near(pick(1.5), 20.0) && near(pick(2.5), 30.0);
	} else if (cell == 2) {
		float whole;
		float total = 1.0;
		split(3.25, whole, total);
		ok = near(whole, 3.0) && near(total, 1.25);
	} else if (cell == 3) {
		ok = nested(4 + zero) == 6;
	} else if (cell == 4) {
		ok = do_loop(5 + zero) == 12;
	} else if (cell == 5) {
		int i = 0;
		int n = 0;

		while (true) {
			i += 2;

			if (i > 20) {
				break;
			}

			if (i % 4 == 0) {
				continue;
			}

			n++;
		}

		ok = n == 5;
	} else if (cell == 6) {
		vec4 v = vec4(1.0, 2.0, 3.0, 4.0);
		float whole;
		split(7.5, whole, v.z);
		ok = near(whole, 7.0) && near(v.z, 3.5) && near(v.w, 4.0);
	} else if (cell == 7) {
		int calls = 0;
		bool a = (calls++ > 5) && (calls++ > 5);
		bool b = (calls++ < 5) || (calls++ > 5);
		ok = !a && b && calls == 2;
	} else if (cell == 8) {
		int x = zero;
		int y = x == 0 ? (x += 3) : (x += 100);
		ok = x == 3 && y == 3;
	} else if (cell == 9) {
		float acc = 0.0;

		for (int i = 0, j = 10; i < j; i++, j--) {
			acc += float(j - i);
		}

		ok = near(acc, 30.0);
	} else {
		ok = first_above(first_above(3)) == 2;
	}

	final_color = ok ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}
