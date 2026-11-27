uniform mat4 view_projection;
uniform sampler2D tex;
uniform float zero;

vec4 texel(int x, int y) {
	float b = (x + y) % 2 == 0 ? 255.0 : 32.0;
	return vec4(float(x * 36), float(y * 36), b, 255.0) / 255.0;
}

bool near(vec4 a, vec4 b) {
	return all(lessThan(abs(a - b), vec4(0.002)));
}

vec2 texel_center(ivec2 t) {
	return (vec2(t) + 0.5) / 8.0;
}

#vertex

in vec3 position;
in vec2 texcoord;
in vec4 color;

out vec2 uv;
flat out vec4 vertex_fetch;
flat out vec4 vertex_sample;
flat out vec4 vertex_lod;
flat out ivec2 vertex_size;

void main() {
	uv = texcoord;
	vertex_fetch = texelFetch(tex, ivec2(1, 1), 0);
	vertex_sample = texture(tex, texel_center(ivec2(6, 3)));
	vertex_lod = textureLod(tex, texel_center(ivec2(2, 7)), 0.0);
	vertex_size = textureSize(tex, 0);
	gl_Position = view_projection * vec4(position, 1.0);
}

#fragment

in vec2 uv;
flat in vec4 vertex_fetch;
flat in vec4 vertex_sample;
flat in vec4 vertex_lod;
flat in ivec2 vertex_size;

out vec4 final_color;

bool run_cell(int cell, vec4 own) {
	int z = int(zero);
	ivec2 t = ivec2(uv * 8.0);

	if (cell == 0) {
		return near(texture(tex, vec2(0.5, 0.5) / 8.0), vec4(0.0, 0.0, 1.0, 1.0)) && near(texture(tex, vec2(3.5, 2.5) / 8.0 + zero), vec4(108.0, 72.0, 32.0, 255.0) / 255.0) && near(texture(tex, texel_center(ivec2(4, 4))), texel(4, 4));
	}

	if (cell == 1) {
		return near(textureLod(tex, vec2(0.5, 0.5) / 8.0, 0.0), texel(0, 0)) && near(textureLod(tex, texel_center(ivec2(7, 0)), zero), texel(7, 0)) && near(textureLod(tex, texel_center(ivec2(1, 6)), 0), texel(1, 6));
	}

	if (cell == 2) {
		return near(texelFetch(tex, ivec2(5, 6), 0), vec4(180.0, 216.0, 32.0, 255.0) / 255.0) && near(texelFetch(tex, ivec2(7, 7 + z), z), vec4(252.0, 252.0, 255.0, 255.0) / 255.0) && near(texelFetch(tex, ivec2(0), 0), texel(0, 0));
	}

	if (cell == 3) {
		ivec2 s = textureSize(tex, 0);
		return s == ivec2(8, 8) && textureSize(tex, z).x == 8;
	}

	if (cell == 4) {
		return near(texture(tex, vec2(-0.5, 1.5) + zero), texel(0, 7)) && near(texture(tex, vec2(2.0, -1.0) + zero), texel(7, 0)) && near(texelFetch(tex, ivec2(3, 0), 0), texel(3, 0));
	}

	if (cell == 5) {
		return near(texture(tex, ivec2(0, 0)), texel(0, 0)) && near(texture(tex, ivec2(1, 1) + z), texel(7, 7)) && near(texelFetch(tex, ivec2(uvec2(2u, 3u)), int(0u)), texel(2, 3));
	}

	if (cell == 6) {
		return near(own, texel(t.x, t.y)) && near(texture(tex, uv), own);
	}

	if (cell == 7) {
		return near(texture(tex, uv, 0.0), own) && near(texture(tex, texel_center(ivec2(5, 2)), zero), texel(5, 2));
	}

	if (cell == 8) {
		return near(texelFetch(tex, ivec2(uv * 8.0), 0), own) && near(texelFetch(tex, t, 0), texel(t.x, t.y));
	}

	if (cell == 9) {
		vec2 ts = vec2(textureSize(tex, 0));
		return near(texture(tex, (vec2(2.0, 5.0) + 0.5) / ts), vec4(72.0, 180.0, 32.0, 255.0) / 255.0);
	}

	if (cell == 10) {
		vec3 bgr = texture(tex, texel_center(ivec2(3, 2))).bgr;
		float g = texelFetch(tex, ivec2(6, 6), 0).g;
		return all(lessThan(abs(bgr - vec3(32.0, 72.0, 108.0) / 255.0), vec3(0.002))) && abs(g - 216.0 / 255.0) < 0.002 && texture(tex, uv).a == 1.0;
	}

	if (cell == 11) {
		return near(vertex_fetch, texel(1, 1)) && near(vertex_sample, texel(6, 3)) && near(vertex_lod, texel(2, 7)) && vertex_size == ivec2(8);
	}

	if (cell == 12) {
		vec4 sum = vec4(0.0);

		for (int y = 0; y < 8; y++) {
			for (int x = 0; x < 8; x++) {
				sum += texelFetch(tex, ivec2(x, y), 0);
			}
		}

		return all(lessThan(abs(sum - vec4(64.0 * 126.0, 64.0 * 126.0, 32.0 * 255.0 + 32.0 * 32.0, 64.0 * 255.0) / 255.0), vec4(0.05)));
	}

	if (cell == 13) {
		vec4 a = texture(tex, texel_center(ivec2(1, 0)));
		vec4 b = texture(tex, texel_center(ivec2(1, 0)) + vec2(0.06, 0.0));
		vec4 c = texture(tex, texel_center(ivec2(1, 0)) - vec2(0.0, 0.06));
		return near(a, b) && near(a, c);
	}

	if (cell == 14) {
		vec4 m = mix(texture(tex, texel_center(ivec2(0, 0))), texture(tex, texel_center(ivec2(2, 0))), 0.5);
		return near(m, vec4(36.0, 0.0, 255.0, 255.0) / 255.0);
	}

	return near(textureLod(tex, uv, 0.0), own) && near(texture(tex, vec2(t) / 8.0 + 0.01), own);
}

void main() {
	int cell = int(uv.x * 4.0) + int(uv.y * 4.0) * 4;
	vec4 own = texture(tex, uv);
	final_color = run_cell(cell, own) ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}
