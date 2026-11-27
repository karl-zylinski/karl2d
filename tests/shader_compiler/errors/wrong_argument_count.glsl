uniform mat4 view_projection;
uniform sampler2D tex;
uniform vec4 tint = vec4(1.0);

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

float blend(float a, float b) {
	return a * 0.5 + b * 0.5;
}

void main() {
	float v = blend(uv.x);
	final_color = vec4(v);
}
