#include "include_math.inc.glsl"
#include "include_dir/nested.inc.glsl"

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
	bool ok = abs(nested_cube(2.0 + zero) - 8.0) < 0.0001 && abs(include_square(3.0 + zero) - 9.0) < 0.0001;
	final_color = ok ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}
