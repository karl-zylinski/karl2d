uniform mat4 view_projection;
uniform float zero;

#vertex

in vec3 position;
in vec2 texcoord;
in vec4 color;

out vec2 uv;
out vec3 extra;
flat out int marker;

vec4 transformed_position() {
	return view_projection * vec4(position, 1.0);
}

void write_outputs(float scale) {
	uv = texcoord;
	extra = vec3(texcoord * scale, color.a);
	marker = gl_InstanceID == 0 ? 7 : 0;
}

void write_position() {
	gl_Position = transformed_position();
}

void main() {
	write_outputs(3.0);
	write_position();
	extra.z *= 0.5;
}

#fragment

in vec2 uv;
in vec3 extra;
flat in int marker;

out vec4 final_color;

bool near(float a, float b) {
	return abs(a - b) < 0.001;
}

float read_input_x() {
	return extra.x;
}

float frag_x() {
	return gl_FragCoord.x;
}

void write_color(bool ok) {
	final_color = ok ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}

void force_red_if(bool bad) {
	if (bad) {
		final_color.r = 1.0;
		final_color.g = 0.0;
	}
}

void main() {
	int cell = int(uv.x * 2.0) + int(uv.y * 2.0) * 2;
	bool ok = true;

	if (cell == 0) {
		ok = near(read_input_x(), uv.x * 3.0) && near(extra.y, uv.y * 3.0);
	} else if (cell == 1) {
		ok = near(extra.z, 0.5) && marker == 7;
	} else if (cell == 2) {
		ok = abs(frag_x() - uv.x * 256.0) < 0.01;
	} else {
		ok = true;
	}

	write_color(ok);
	force_red_if(final_color.g < 0.5 + zero);
}
