#include "include_math.inc.glsl"

struct Include_Shape {
	vec2 center;
	float radius;
};

uniform float include_uniform = 0.75;

float include_shape_distance(Include_Shape s, vec2 p) {
	return length(p - s.center) - s.radius;
}

float include_twice_square(float x) {
	return include_square(x) * 2.0;
}
