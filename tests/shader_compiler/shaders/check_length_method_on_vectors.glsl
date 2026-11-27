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
	vec3 v = vec3(zero);
	mat4 m = mat4(zero);
	bool ok = v.length() == 3 && m.length() == 4 && m[0].length() == 4 && vec2(1.0).length() == 2;
	final_color = ok ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}
