uniform mat4 view_projection;
uniform float fzero;

float two_guards(float x) {
	if (x < 1.0) {
		return 10.0;
	}

	float y = x * 2.0;

	if (y > 7.0) {
		if (y > 20.0) {
			return 30.0;
		}

		return 20.0;
	}

	y += 1.0;
	return y;
}

int guard_in_loop(int limit) {
	int sum = 0;

	for (int i = 0; i < 8; i++) {
		if (i == limit) {
			return sum;
		}

		sum += i;
	}

	if (sum > 100) {
		return -1;
	}

	return sum + 1000;
}

int guard_in_switch(int which, int v) {
	switch (which) {
	case 0:
		if (v > 5) {
			return 1;
		}

		v += 10;

	case 1:
		v += 100;
		break;

	default:
		return 3;
	}

	if (v > 105) {
		return v;
	}

	return 2;
}

void guard_out(float x, out float result) {
	result = 1.0;

	if (x > 2.0) {
		result = 5.0;
		return;
	}

	result += x;
}

#vertex

in vec3 position;
in vec2 texcoord;
in vec4 color;

void main() {
	gl_Position = view_projection * vec4(position, 1.0);
}

#fragment

out vec4 final_color;

void main() {
	float z = fzero;
	int iz = int(fzero);
	bool ok = two_guards(z + 0.5) == 10.0 && two_guards(z + 2.0) == 5.0 && two_guards(z + 4.0) == 20.0 && two_guards(z + 11.0) == 30.0;
	ok = ok && guard_in_loop(iz + 3) == 3 && guard_in_loop(iz + 9) == 1028;
	ok = ok && guard_in_switch(iz, 9) == 1 && guard_in_switch(iz, 2) == 112 && guard_in_switch(iz + 1, 2) == 2 && guard_in_switch(iz + 1, 7) == 107 && guard_in_switch(iz + 2, 7) == 3;
	float a;
	float b;
	guard_out(z + 3.0, a);
	guard_out(z + 1.5, b);
	ok = ok && a == 5.0 && b == 2.5;

	if (!ok) {
		final_color = vec4(1.0, 0.0, 0.0, 1.0);
		return;
	}

	final_color = vec4(0.0, 1.0, 0.0, 1.0);
}
