uniform mat4 view_projection;

bool near(float a, float b) {
	return abs(a - b) < 0.00001;
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
	if (cell == 0) {
		return near(1., 1.0) && near(.5, 0.5) && near(1e3, 1000.0) && near(1.5E-2, 0.015) && near(1e+2, 100.0) && near(2.0f, 2.0) && near(2.5F, 2.5);
	}

	if (cell == 1) {
		return 0xFF == 255 && 0xff == 255 && 0x0 == 0 && 0xFFFFFFFF == -1 && 0x80000000u == 2147483648u && 10u == 10U;
	}

	if (cell == 2) {
		return 010 == 8 && 0777 == 511 && 0 == 00 && 017u == 15u;
	}

	if (cell == 3) {
		return near(3.4028235e38 / 1e38, 3.4028235) && near(1e-30 * 1e30, 1.0) && near(0.000001 * 1000000.0, 1.0);
	}

	if (cell == 4) {
		return 2147483647 == 0x7FFFFFFF && 4294967295u == 0xFFFFFFFFu && -2147483647 - 1 == int(0x80000000u);
	}

	if (cell == 5) {
		return near(1.0e0, 1.0) && near(5E1, 50.0) && near(0.0e0, 0.0) && near(123.456e-1, 12.3456);
	}

	if (cell == 6) {
		float a = -1.0;
		float b = 2.0 - -1.0;
		float c = - -2.0;
		int d = -(-3);
		return near(a, -1.0) && near(b, 3.0) && near(c, 2.0) && d == 3 && near(-a, 1.0) && -(-a) == a;
	}

	if (cell == 7) {
		float tiny = 1e-7;
		float huge = 1e20;
		return tiny > 0.0 && tiny < 0.000001 && huge > 1e19 && near(huge / 1e20, 1.0);
	}

	return true;
}

void main() {
	int cell = int(uv.x * 4.0) + int(uv.y * 4.0) * 4;
	final_color = run_cell(cell) ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}
