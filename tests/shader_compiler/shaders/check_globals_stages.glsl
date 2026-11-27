uniform mat4 view_projection;
uniform float zero;

const float scale = 2.0;
const vec3 tint = vec3(0.5, 0.25, 1.0);
const int count = 3;
const int derived = count * 2 + 1;
const float table[3] = float[](1.0, 10.0, 100.0);
const mat2 swap = mat2(0.0, 1.0, 1.0, 0.0);
const bool enabled = true;
const uint mask = 0xF0u | 0x0Fu;

float g_accum = 0.0;
int g_calls = 0;
float g_scaled = scale * 3.0;
vec3 g_color = tint * 0.5;
float g_history[4];

float shared_scale(float x) {
	return x * scale;
}

void bump() {
	g_calls += 1;
	g_accum += shared_scale(1.0);
}

void discard_if(bool b) {
	if (b) {
		discard;
	}
}

float shared_slope(float v) {
	return abs(dFdx(v));
}

vec2 vertex_side_helper(vec2 p) {
	return p * scale + vec2(derived);
}

#vertex

in vec3 position;
in vec2 texcoord;
in vec4 color;

out vec2 uv;
out vec2 helped;
flat out float vertex_scaled;
flat out int vertex_calls;

int v_counter = 10;

float stage_helper(float x) {
	return x + 1.0;
}

void main() {
	uv = texcoord;
	helped = vertex_side_helper(texcoord);
	bump();
	bump();
	v_counter += g_calls;
	vertex_scaled = stage_helper(shared_scale(g_accum));
	vertex_calls = v_counter;
	gl_Position = view_projection * vec4(position, 1.0);
}

#fragment

in vec2 uv;
in vec2 helped;
flat in float vertex_scaled;
flat in int vertex_calls;

out vec4 final_color;

float stage_helper(float x) {
	return x * 100.0;
}

bool near(float a, float b) {
	return abs(a - b) < 0.0001;
}

bool near(vec2 a, vec2 b) {
	return all(lessThan(abs(a - b), vec2(0.0001)));
}

bool near(vec3 a, vec3 b) {
	return all(lessThan(abs(a - b), vec3(0.0001)));
}

bool run_cell(int cell, float slope) {
	int z = int(zero);

	if (cell == 0) {
		return near(scale, 2.0) && near(tint, vec3(0.5, 0.25, 1.0)) && count == 3 && derived == 7 && enabled && mask == 255u;
	}

	if (cell == 1) {
		float s = 0.0;

		for (int i = z; i < count; i++) {
			s += table[i];
		}

		return near(s, 111.0) && near(table[2], 100.0) && table.length() == count && near(swap * vec2(1.0, 2.0), vec2(2.0, 1.0));
	}

	if (cell == 2) {
		return near(g_scaled, 6.0) && near(g_color, vec3(0.25, 0.125, 0.5)) && g_calls == 0 && near(g_accum, 0.0);
	}

	if (cell == 3) {
		bump();
		bump();
		bump();
		return g_calls == 3 && near(g_accum, 6.0);
	}

	if (cell == 4) {
		for (int i = 0; i < 4; i++) {
			g_history[i] = float(i) * scale;
		}

		g_history[1 + z] += 1.0;
		return near(g_history[3], 6.0) && near(g_history[1], 3.0);
	}

	if (cell == 5) {
		return near(vertex_scaled, 9.0) && vertex_calls == 12;
	}

	if (cell == 6) {
		return near(helped, uv * 2.0 + vec2(7.0));
	}

	if (cell == 7) {
		return near(stage_helper(0.5 + zero), 50.0) && near(shared_scale(1.5 + zero), 3.0);
	}

	if (cell == 8) {
		discard_if(zero > 1.0);
		return true;
	}

	if (cell == 9) {
		return abs(slope - 3.0 / 256.0) < 0.00001;
	}

	if (cell == 10) {
		const float local_const = scale * 4.0;
		const vec2 local_vec = vec2(local_const, scale);
		float arr[derived];
		arr[derived - 1] = local_const;
		return near(local_const, 8.0) && near(local_vec, vec2(8.0, 2.0)) && near(arr[6], 8.0) && arr.length() == 7;
	}

	return true;
}

void main() {
	int cell = int(uv.x * 4.0) + int(uv.y * 4.0) * 4;
	float slope = shared_slope(uv.x * 3.0);
	final_color = run_cell(cell, slope) ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}
