#include "../include_math.inc.glsl"

float nested_cube(float x) {
	return include_square(x) * x;
}
