uniform mat4 view_projection;
uniform float zero;

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
	mat2 m = mat2(1.0, 2.0, 3.0, 4.0 + zero);
	vec4 v = vec4(m);
	bool ok = v == vec4(1.0, 2.0, 3.0, 4.0);
	final_color = ok ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}
