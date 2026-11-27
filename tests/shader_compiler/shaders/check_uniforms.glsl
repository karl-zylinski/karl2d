uniform mat4 view_projection;

struct Material {
	vec4 tint;
	float roughness;
	vec3 normal;
	int id;
	float values[2];
};

const vec3 base_color = vec3(0.25, 0.5, 0.75);

uniform float time;
uniform vec2 resolution;
uniform float u_float = 1.5;
uniform int u_int = -3;
uniform uint u_uint = 7u;
uniform bool u_bool = true;
uniform vec2 u_vec2 = vec2(1.0, 2.0);
uniform vec3 u_vec3 = vec3(3.0);
uniform float u_after_vec3 = 4.5;
uniform vec4 u_vec4 = vec4(vec2(1.0, 2.0), 3.0, 4.0);
uniform ivec2 u_ivec2 = ivec2(-1, 2);
uniform uvec3 u_uvec3 = uvec3(1u, 2u, 3u);
uniform bvec2 u_bvec2 = bvec2(true, false);
uniform mat2 u_mat2 = mat2(1.0, 2.0, 3.0, 4.0);
uniform mat3 u_mat3 = mat3(2.0);
uniform mat4 u_mat4 = mat4(vec4(1.0, 0.0, 0.0, 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(5.0, 6.0, 7.0, 1.0));
uniform float u_neg = -2.5;
uniform vec2 u_neg_vec = -vec2(1.0, 2.0);
uniform vec3 u_from_const = base_color;
uniform float u_from_int = 3;
uniform vec2 u_vec2_from_ivec = ivec2(5, 6);
uniform vec4 u_splat_int = vec4(2);
uniform mat3 u_mat3_columns = mat3(vec3(1.0, 2.0, 3.0), vec3(4.0, 5.0, 6.0), vec3(7.0, 8.0, 9.0));
uniform float u_zero;
uniform vec3 u_zero_vec;
uniform Material u_material;
uniform Material u_materials[2];
uniform float u_weights[4];
uniform vec3 u_points[2];
uniform float u_last = 8.0;

const float EPSILON = 0.0001;

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

uniform float u_shared = 0.5;
uniform vec2 u_vertex_only = vec2(0.125, 0.25);

in vec3 position;
in vec2 texcoord;
in vec4 color;

out vec2 uv;
out vec2 from_vertex;

void main() {
	uv = texcoord;
	from_vertex = u_vertex_only * 2.0 + vec2(u_shared);
	gl_Position = view_projection * vec4(position, 1.0);
}

#fragment

uniform float u_shared = 0.5;

in vec2 uv;
in vec2 from_vertex;

out vec4 final_color;

bool run_cell(int cell) {
	if (cell == 0) {
		return near(time, 1.25) && near(resolution, vec2(256.0, 256.0)) && near(u_float, 1.5) && u_int == -3 && u_uint == 7u && u_bool;
	}

	if (cell == 1) {
		return near(u_vec2, vec2(1.0, 2.0)) && near(u_vec3, vec3(3.0)) && near(u_after_vec3, 4.5) && near(u_vec4, vec4(1.0, 2.0, 3.0, 4.0));
	}

	if (cell == 2) {
		return u_ivec2 == ivec2(-1, 2) && u_uvec3 == uvec3(1u, 2u, 3u) && u_bvec2 == bvec2(true, false) && u_bvec2.x && !u_bvec2.y;
	}

	if (cell == 3) {
		return near(u_mat2[0], vec2(1.0, 2.0)) && near(u_mat2[1], vec2(3.0, 4.0)) && near(u_mat2 * vec2(1.0, 1.0), vec2(4.0, 6.0));
	}

	if (cell == 4) {
		return near(u_mat3[0], vec3(2.0, 0.0, 0.0)) && near(u_mat3[1], vec3(0.0, 2.0, 0.0)) && near(u_mat3[2], vec3(0.0, 0.0, 2.0));
	}

	if (cell == 5) {
		return near(u_mat4 * vec4(1.0, 1.0, 1.0, 1.0), vec4(6.0, 7.0, 8.0, 1.0)) && near(u_mat4[3], vec4(5.0, 6.0, 7.0, 1.0)) && near(u_mat4[0], vec4(1.0, 0.0, 0.0, 0.0));
	}

	if (cell == 6) {
		return near(u_neg, -2.5) && near(u_neg_vec, vec2(-1.0, -2.0)) && near(u_from_const, vec3(0.25, 0.5, 0.75)) && near(u_from_int, 3.0);
	}

	if (cell == 7) {
		return near(u_vec2_from_ivec, vec2(5.0, 6.0)) && near(u_splat_int, vec4(2.0)) && near(u_last, 8.0);
	}

	if (cell == 8) {
		return near(u_mat3_columns[0], vec3(1.0, 2.0, 3.0)) && near(u_mat3_columns[1], vec3(4.0, 5.0, 6.0)) && near(u_mat3_columns[2], vec3(7.0, 8.0, 9.0));
	}

	if (cell == 9) {
		return near(u_zero, 0.0) && near(u_zero_vec, vec3(0.0)) && u_zero == 0.0;
	}

	if (cell == 10) {
		return near(u_material.tint, vec4(0.0)) && near(u_material.roughness, 0.0) && near(u_material.normal, vec3(0.0)) && u_material.id == 0 && near(u_material.values[1], 0.0);
	}

	if (cell == 11) {
		float s = 0.0;

		for (int i = 0; i < 4; i++) {
			s += abs(u_weights[i]);
		}

		return near(s, 0.0) && near(u_points[1], vec3(0.0)) && u_weights.length() == 4 && u_points.length() == 2;
	}

	if (cell == 12) {
		return near(from_vertex, vec2(0.75, 1.0)) && near(u_shared, 0.5);
	}

	if (cell == 13) {
		vec3 lit = base_color * u_float + u_vec3 * u_zero;
		return near(lit, vec3(0.375, 0.75, 1.125)) && near(float(u_int) * u_float, -4.5) && u_uint + uint(u_int + 3) == 7u;
	}

	if (cell == 14) {
		Material m = u_material;
		m.id = 4;
		return m.id == 4 && u_material.id == 0 && m != u_material && u_materials[1].id == 0 && near(u_materials[0].normal, vec3(0.0)) && u_materials.length() == 2 && u_materials[1] == u_material;
	}

	return near(time * 4.0, 5.0) && near(resolution.x / resolution.y, 1.0);
}

void main() {
	int cell = int(uv.x * 4.0) + int(uv.y * 4.0) * 4;
	final_color = run_cell(cell) ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}
