uniform mat4 view_projection;
uniform sampler2D tex;
uniform vec4 tint = vec4(1.0);

#vertex

in vec3 position;
in vec2 texcoord;
in vec4 color;

out vec2 uv;
out vec3 shade;

void main() {
	shade = color.rgb;
	uv = texcoord;
	gl_Position = view_projection * vec4(position, 1.0);
}

#fragment

in vec2 uv;

in vec4 shade;

out vec4 final_color;

void main() {
	final_color = texture(tex, uv) * shade;
}
