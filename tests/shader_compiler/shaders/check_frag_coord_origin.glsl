uniform mat4 view_projection;

bool near(float a, float b) {
	return abs(a - b) < 0.01;
}

vec2 pixel() {
	return gl_FragCoord.xy;
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

	if (cell < 4) {
		ok = near(gl_FragCoord.y, floor(uv.y * 256.0) + 0.5) && gl_FragCoord.y < 64.0;
	} else if (cell < 8) {
		ok = near(gl_FragCoord.x, floor(uv.x * 256.0) + 0.5) && near(pixel().y, floor(uv.y * 256.0) + 0.5);
	} else if (cell < 12) {
		ok = near(dFdy(uv.y * 256.0), 1.0) && near(dFdx(uv.x * 256.0), 1.0);
	} else {
		ok = near(dFdy(gl_FragCoord.y), 1.0) && near(fwidth(uv.y * 256.0), 1.0) && gl_FragCoord.y > 192.0;
	}

	final_color = ok ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}
