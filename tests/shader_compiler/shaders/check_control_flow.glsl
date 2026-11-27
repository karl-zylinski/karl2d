uniform mat4 view_projection;
uniform float zero;
uniform float time;

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

int find_first(int target) {
	for (int i = 0; i < 10; i++) {
		if (i * i >= target) {
			return i;
		}
	}

	return -1;
}

int find_pair(int sum) {
	for (int a = 0; a < 5; a++) {
		for (int b = 0; b < 5; b++) {
			if (a * b == sum && a < b) {
				return a * 10 + b;
			}
		}
	}

	return -1;
}

float deep_three(float x) {
	if (x > 1.0) {
		return x * 2.0;
	}

	return x;
}

float deep_two(float x) {
	return deep_three(x) + deep_three(x * 0.5);
}

float deep_one(float x) {
	if (x < 0.0) {
		return -deep_two(-x);
	}

	return deep_two(x) + 1.0;
}

int classify(float x) {
	if (x < 0.0)
		if (x < -10.0)
			return 0;
		else
			return 1;

	return 2;
}

void early_out(out int r, int x) {
	r = 0;

	if (x > 5) {
		r = 1;
		return;
	}

	r = 2;
}

int loop_return(int n) {
	int i = 0;

	while (true) {
		do {
			i++;

			if (i == n) {
				return i * 100;
			}
		} while (i % 3 != 0);

		i += 10;
	}

	return -1;
}

bool run_cell(int cell) {
	int z = int(zero);

	if (cell == 0) {
		int sum = 0;

		for (int i = 0; i < 4 + z; i++) {
			for (int j = 0; j < 3; j++) {
				sum += i * j;
			}
		}

		return sum == 18;
	}

	if (cell == 1) {
		int s = 0;

		for (int i = z; i < 10; i++) {
			if (i % 2 == 0) {
				continue;
			}

			if (i > 7) {
				break;
			}

			s += i;
		}

		return s == 16;
	}

	if (cell == 2) {
		int n = 27 + z;
		int steps = 0;

		while (n != 1) {
			n = n % 2 == 0 ? n / 2 : 3 * n + 1;
			steps++;
		}

		return steps == 111;
	}

	if (cell == 3) {
		int k = 10 + z;
		int c = 0;

		do {
			c++;
			k -= 3;
		} while (k > 0);

		int once = 0;

		do {
			once++;
		} while (false);

		return c == 4 && k == -2 && once == 1;
	}

	if (cell == 4) {
		return find_first(20 + z) == 5 && find_first(1000 + z) == -1 && find_first(z) == 0 && find_pair(6 + z) == 23 && find_pair(7 + z) == -1;
	}

	if (cell == 5) {
		return deep_one(3.0 + zero) == 10.0 && deep_one(-3.0 + zero) == -9.0 && deep_one(1.0 + zero) == 2.5;
	}

	if (cell == 6) {
		return classify(-20.0 + zero) == 0 && classify(-5.0 + zero) == 1 && classify(5.0 + zero) == 2;
	}

	if (cell == 7) {
		int count = 0;
		int last_j = 0;

		for (int i = z, j = 10; i < j; i++, j--) {
			count++;
			last_j = j;
		}

		return count == 5 && last_j == 6;
	}

	if (cell == 8) {
		int i = z;

		for (;;) {
			i++;

			if (i == 7) {
				break;
			}
		}

		int j;

		for (j = 2 + z; j < 5; j++);

		return i == 7 && j == 5;
	}

	if (cell == 9) {
		int i = z;
		int s = 0;

		while (i < 10) {
			i++;

			if (i % 3 == 0) {
				continue;
			}

			s += i;
		}

		return s == 37;
	}

	if (cell == 10) {
		int s = 0;

		for (int i = 0; i < 3; i++) {
			for (int j = z; j < 10; j++) {
				if (j == 2) {
					break;
				}

				s++;
			}
		}

		int i2 = z;
		int s2 = 0;

		do {
			i2++;

			if (i2 == 2) {
				continue;
			}

			s2 += i2;
		} while (i2 < 4);

		return s == 6 && s2 == 8;
	}

	if (cell == 11) {
		int a;
		int b;
		early_out(a, 9 + z);
		early_out(b, 2 + z);
		return a == 1 && b == 2 && loop_return(2 + z) == 200 && loop_return(14 + z) == 1400;
	}

	if (cell == 12) {
		int x = 1 + z;

		{
			int x = 2;
			x++;
		}

		if (x == 1) {
			float x = 5.0;
			x += 1.0;
		}

		for (int x = 0; x < 3; x++) {
		}

		return x == 1;
	}

	if (cell == 13) {
		float s = 0.0;

		for (float f = zero; f < 1.0; f += 0.25) {
			s += f;
		}

		return s == 1.5;
	}

	if (cell == 14) {
		int n = 0;
		int guard = 0;

		while (true) {
			n += 3;
			guard++;

			if (n > 20 || guard > 100) {
				break;
			}
		}

		if (n == 21) {
		} else {
			return false;
		}

		return guard == 7;
	}

	int n = int(time * 4.0);
	int sum = 0;

	for (int i = 0; i < n; i++) {
		sum += i;
	}

	if (sum != 10) {
		return false;
	} else if (n != 5) {
		return false;
	}

	return true;
}

void main() {
	int cell = int(uv.x * 4.0) + int(uv.y * 4.0) * 4;
	final_color = run_cell(cell) ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}
