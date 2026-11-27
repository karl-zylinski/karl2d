uniform mat4 view_projection;
uniform sampler2D tex;
uniform vec4 tint = vec4(1.0);

#fragment

out vec4 final_color;

void main() {
	final_color = tint;
}
