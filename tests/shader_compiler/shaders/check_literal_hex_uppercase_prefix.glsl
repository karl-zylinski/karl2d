uniform mat4 view_projection;

#vertex

in vec3 position;
in vec2 texcoord;
in vec4 color;

void main() {
	gl_Position = view_projection * vec4(position, 1.0);
}

#fragment

out vec4 final_color;

void main() {
	bool ok = 0XFF == 255 && 0X10u == 16u && 0xAbC == 2748;
	final_color = ok ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}
