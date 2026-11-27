const float INCLUDE_PI = 3.14159265;

float include_square(float x) {
	return x * x;
}

vec2 include_rotate(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return mat2(c, s, -s, c) * p;
}
