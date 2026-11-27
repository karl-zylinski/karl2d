uniform mat4 view_projection;
uniform sampler2D tex;
uniform vec4 tint = vec4(1.0);

float brightness(vec3 c) {
	return max(c.r, max(c.g, c.b));
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
	float brightness = 2.0;
	vec4 c = texture(tex, uv);
	final_color = c * brightness(c.rgb) * brightness;
}
