uniform mat4 view_projection;
uniform sampler2D tex;
uniform vec4 tint = vec4(1.0);

void clip_negative(float v) {
	if (v < 0.0) {
		discard;
	}
}

#vertex

in vec3 position;
in vec2 texcoord;
in vec4 color;

out vec2 uv;

void main() {
	clip_negative(position.x);
	uv = texcoord;
	gl_Position = view_projection * vec4(position, 1.0);
}

#fragment

in vec2 uv;

out vec4 final_color;

void main() {
	final_color = texture(tex, uv) * tint;
}
