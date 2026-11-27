uniform mat4 view_projection;

void discard_outside_circle(ivec2 p, int radius) {
	ivec2 d = p - ivec2(128);

	if (d.x * d.x + d.y * d.y > radius * radius) {
		discard;
	}
}

bool in_hole(ivec2 p) {
	ivec2 tile = p / 16;
	return (tile.x + tile.y) % 2 == 0;
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
	ivec2 p = ivec2(uv * 256.0);
	final_color = vec4(1.0, 0.0, 1.0, 1.0);
	discard_outside_circle(p, 120);
	ivec2 d = p - ivec2(128);
	int r2 = d.x * d.x + d.y * d.y;

	if (r2 < 70 * 70 && r2 > 30 * 30 && in_hole(p)) {
		discard;
	}

	for (int i = 0; i < 4; i++) {
		if (p.x == 40 + i * 50) {
			discard;
		}
	}

	if (p.y > 200 && (p.x & 4) == 0) {
		discard;
	}

	final_color = vec4(uv, 1.0 - uv.x * uv.y, 1.0);
}
