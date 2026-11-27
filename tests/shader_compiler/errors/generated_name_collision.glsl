uniform mat4 view_projection;
uniform float zero;

float Karl2D_Constants = 1.0;

#vertex

in vec3 position;
in vec2 texcoord;
in vec4 color;

void main() {
	gl_Position = view_projection * vec4(position, Karl2D_Constants);
}

#fragment

out vec4 final_color;

void main() {
	bool ok = Karl2D_Constants + zero == 1.0;
	final_color = ok ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}
