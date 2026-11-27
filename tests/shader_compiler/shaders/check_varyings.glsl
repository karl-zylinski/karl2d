uniform mat4 view_projection;

const float EPSILON = 0.001;

bool near(float a, float b) {
	return abs(a - b) < EPSILON;
}

bool near(vec2 a, vec2 b) {
	return all(lessThan(abs(a - b), vec2(EPSILON)));
}

bool near(vec3 a, vec3 b) {
	return all(lessThan(abs(a - b), vec3(EPSILON)));
}

bool near(vec4 a, vec4 b) {
	return all(lessThan(abs(a - b), vec4(EPSILON)));
}

#vertex

layout(location = 2) in vec3 position;
layout(location = 0) in vec2 texcoord;
layout(location = 1) in vec4 color;

out vec2 uv;
out vec3 v_pos3;
out vec4 v_col;
smooth out float v_scalar;
flat out int v_flat_id;
flat out ivec2 v_ivec;
out uvec2 v_uvec;
noperspective out vec2 v_noperspective;
flat out vec3 v_flat_vec;
out float v_unused;
out vec4 v_clip;

void main() {
	int vid = gl_VertexID;
	uv = texcoord;
	v_pos3 = vec3(texcoord * 2.0, 1.0 - texcoord.x);
	v_col = color * vec4(texcoord, 0.5, 1.0);
	v_scalar = 1.0;
	v_scalar *= texcoord.y;
	v_scalar = v_scalar * 0.5 + 0.25;
	v_flat_id = vid >= 0 ? 42 : 0;
	v_ivec = ivec2(7, -3);
	v_uvec = uvec2(5u, 0xFFFFFFFFu);
	v_noperspective = texcoord.yx;
	v_flat_vec = vec3(0.25, 0.5, 0.75);
	v_unused = 3.0;
	gl_Position = view_projection * vec4(position, 1.0);
	v_clip = gl_Position;
}

#fragment

in vec2 uv;
in vec3 v_pos3;
in vec4 v_col;
smooth in float v_scalar;
flat in int v_flat_id;
in ivec2 v_ivec;
flat in uvec2 v_uvec;
noperspective in vec2 v_noperspective;
flat in vec3 v_flat_vec;
in vec4 v_clip;

out vec4 final_color;

bool run_cell(int cell) {
	if (cell == 0) {
		return near(v_pos3, vec3(uv * 2.0, 1.0 - uv.x));
	}

	if (cell == 1) {
		return near(v_col, vec4(uv, 0.5, 1.0));
	}

	if (cell == 2) {
		return near(v_scalar, uv.y * 0.5 + 0.25);
	}

	if (cell == 3) {
		return v_flat_id == 42;
	}

	if (cell == 4) {
		return v_ivec == ivec2(7, -3) && v_ivec.y < 0;
	}

	if (cell == 5) {
		return v_uvec == uvec2(5u, 4294967295u);
	}

	if (cell == 6) {
		return near(v_noperspective, uv.yx);
	}

	if (cell == 7) {
		return near(v_flat_vec, vec3(0.25, 0.5, 0.75));
	}

	if (cell == 8) {
		return near(v_clip.w, 1.0) && near(v_clip.x, uv.x * 2.0 - 1.0) && near(abs(v_clip.y), abs(uv.y * 2.0 - 1.0));
	}

	if (cell == 9) {
		vec3 local = v_pos3;
		local.z += 1.0;
		return near(local.z, 2.0 - uv.x) && near(v_pos3.z, 1.0 - uv.x);
	}

	return near(v_col.rg + v_pos3.xy, uv * 3.0) && v_flat_id + v_ivec.x == 49;
}

void main() {
	int cell = int(uv.x * 4.0) + int(uv.y * 4.0) * 4;
	final_color = run_cell(cell) ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}
