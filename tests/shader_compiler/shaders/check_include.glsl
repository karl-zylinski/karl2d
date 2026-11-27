#include "include_common.inc.glsl"
#include "include_math.inc.glsl"
#include "include_common.inc.glsl"

uniform mat4 view_projection;
uniform float zero;

bool near(float a, float b) {
	return abs(a - b) < 0.0001;
}

#vertex

in vec3 position;
in vec2 texcoord;
in vec4 color;

out vec2 uv;
flat out float vertex_square;

void main() {
	uv = texcoord;
	vertex_square = include_twice_square(3.0);
	gl_Position = view_projection * vec4(position, 1.0);
}

#fragment

#include "include_fragment.inc.glsl"

in vec2 uv;
flat in float vertex_square;

out vec4 final_color;

void main() {
	float one = 1.0 + zero;
	Include_Shape s = Include_Shape(vec2(1.0, 0.0), 0.5);
	vec2 r = include_rotate(vec2(one, 0.0), INCLUDE_PI * 0.5);
	bool ok = near(include_square(3.0 * one), 9.0) && near(vertex_square, 18.0) && near(include_uniform, 0.75);
	ok = ok && near(include_shape_distance(s, vec2(3.0 * one, 0.0)), 1.5) && abs(r.x) < 0.0001 && near(r.y, 1.0);
	ok = ok && near(include_fragment_only(one), 5.0);
	final_color = ok ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}
