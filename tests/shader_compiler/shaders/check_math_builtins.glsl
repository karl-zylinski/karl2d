uniform mat4 view_projection;
uniform float zero;

const float PI = 3.14159265;
const float EPSILON = 0.001;

bool near(float a, float b) {
	return abs(a - b) < EPSILON;
}

bool near(vec2 a, vec2 b) {
	return all(lessThan(abs(a - b), vec2(EPSILON)));
}

bool near(vec3 a, vec3 b) {
	return all(lessThan(abs(a - b), vec3(EPSILON)));
}

bool near(vec4 a, vec4 b) {
	return all(lessThan(abs(a - b), vec4(EPSILON)));
}

#vertex

in vec3 position;
in vec2 texcoord;
in vec4 color;

out vec2 uv;

void main() {
	uv = texcoord;
	gl_Position = view_projection * vec4(position, 1.0);
}

#fragment

in vec2 uv;

out vec4 final_color;

bool run_cell(int cell) {
	float one = 1.0 + zero;

	if (cell == 0) {
		return near(radians(180.0 * one), PI) && abs(degrees(PI * one) - 180.0) < 0.01 && near(radians(vec2(90.0, -45.0) * one), vec2(1.5707963, -0.7853982)) && near(degrees(vec3(0.5, 1.0, -2.0) * one), vec3(28.647890, 57.295780, -114.591559));
	}

	if (cell == 1) {
		bool ok = near(sin(zero), 0.0) && near(sin(PI / 2.0 * one), 1.0) && near(sin(PI / 6.0 * one), 0.5) && near(sin(-PI / 2.0 * one), -1.0);
		ok = ok && near(cos(zero), 1.0) && near(cos(PI / 3.0 * one), 0.5) && near(cos(PI * one), -1.0);
		ok = ok && near(tan(PI / 4.0 * one), 1.0) && near(tan(-PI / 4.0 * one), -1.0) && near(tan(zero), 0.0);
		ok = ok && near(sin(vec2(PI / 2.0, -PI / 2.0) * one), vec2(1.0, -1.0)) && near(cos(vec3(0.0, PI, PI / 2.0) * one), vec3(1.0, -1.0, 0.0));
		return ok;
	}

	if (cell == 2) {
		bool ok = near(asin(one), 1.5707963) && near(asin(0.5 * one), 0.5235988) && near(asin(-one), -1.5707963) && near(asin(zero), 0.0);
		ok = ok && near(acos(one), 0.0) && near(acos(zero), 1.5707963) && near(acos(-one), PI) && near(acos(0.5 * one), 1.0471976);
		ok = ok && near(asin(vec2(0.5, -0.5) * one), vec2(0.5235988, -0.5235988)) && near(acos(vec2(0.5, -0.5) * one), vec2(1.0471976, 2.0943951));
		return ok;
	}

	if (cell == 3) {
		bool ok = near(atan(one), 0.7853982) && near(atan(-one), -0.7853982) && near(atan(zero), 0.0) && near(atan(vec2(1.0, -1.0) * one), vec2(0.7853982, -0.7853982));
		ok = ok && near(atan(one, one), 0.7853982) && near(atan(one, -one), 2.3561945) && near(atan(-one, -one), -2.3561945) && near(atan(-one, one), -0.7853982);
		ok = ok && near(atan(one, zero), 1.5707963) && near(atan(-one, zero), -1.5707963) && near(atan(zero, one), 0.0) && near(abs(atan(zero, -one)), PI);
		ok = ok && near(atan(2.0 * one, one), 1.1071487) && near(atan(one, 2.0), 0.4636476) && near(atan(-2.0 * one, -1.0), -2.0344439) && near(atan(2.0 * one, -1.0), 2.0344439);
		ok = ok && near(atan(vec2(3.0, 4.0) * one, vec2(-3.0, 4.0)), vec2(2.3561945, 0.7853982));
		return ok;
	}

	if (cell == 4) {
		bool ok = near(sinh(one), 1.1752012) && near(cosh(one), 1.5430806) && near(tanh(one), 0.7615942);
		ok = ok && near(sinh(zero), 0.0) && near(cosh(zero), 1.0) && near(tanh(-0.5 * one), -0.4621172) && near(sinh(-2.0 * one), -3.6268604);
		ok = ok && near(cosh(vec2(-1.0, 2.0) * one), vec2(1.5430806, 3.7621957)) && near(tanh(vec3(0.0, 2.0, -2.0) * one), vec3(0.0, 0.9640276, -0.9640276));
		return ok;
	}

	if (cell == 5) {
		bool ok = abs(pow(2.0 * one, 10.0) - 1024.0) < 0.01 && near(pow(9.0 * one, 0.5), 3.0) && near(pow(one, 7.0), 1.0) && near(pow(8.0 * one, 1.0 / 3.0), 2.0);
		ok = ok && near(pow(vec2(4.0, 27.0) * one, vec2(1.5, 1.0 / 3.0)), vec2(8.0, 3.0)) && near(pow(vec3(2.0) * one, vec3(0.0, 1.0, 2.0)), vec3(1.0, 2.0, 4.0)) && near(pow(0.5 * one, 2.0), 0.25);
		return ok;
	}

	if (cell == 6) {
		bool ok = near(exp(zero), 1.0) && near(exp(one), 2.7182818) && near(exp(-one), 0.3678794) && near(exp(2.0 * one), 7.3890561);
		ok = ok && near(log(one), 0.0) && near(log(2.7182818 * one), 1.0) && near(log(10.0 * one), 2.3025851) && near(log(0.5 * one), -0.6931472);
		ok = ok && near(exp2(3.0 * one), 8.0) && near(exp2(-2.0 * one), 0.25) && near(exp2(zero), 1.0) && near(log2(8.0 * one), 3.0) && near(log2(0.5 * one), -1.0) && near(log2(1024.0 * one), 10.0);
		ok = ok && near(exp(vec2(0.0, 1.0) * one), vec2(1.0, 2.7182818)) && near(log2(vec3(1.0, 2.0, 4.0) * one), vec3(0.0, 1.0, 2.0)) && near(exp2(vec4(0.0, 1.0, 2.0, 3.0) * one), vec4(1.0, 2.0, 4.0, 8.0)) && near(log(vec2(1.0, 7.3890561) * one), vec2(0.0, 2.0));
		return ok;
	}

	if (cell == 7) {
		bool ok = near(sqrt(16.0 * one), 4.0) && near(sqrt(2.0 * one), 1.4142136) && near(sqrt(0.25 * one), 0.5) && near(sqrt(zero), 0.0);
		ok = ok && near(inversesqrt(4.0 * one), 0.5) && near(inversesqrt(0.25 * one), 2.0) && near(inversesqrt(vec2(16.0, 1.0) * one), vec2(0.25, 1.0)) && near(sqrt(vec3(1.0, 4.0, 9.0) * one), vec3(1.0, 2.0, 3.0));
		return ok;
	}

	if (cell == 8) {
		float a = 0.7 * one;
		return near(sin(a) * sin(a) + cos(a) * cos(a), 1.0) && near(tan(a), sin(a) / cos(a)) && near(asin(sin(a)), a) && near(acos(cos(a)), a) && near(atan(tan(a)), a) && near(exp(log(5.0 * one)), 5.0);
	}

	if (cell == 9) {
		return near(sin(1), 0.8414710) && near(cos(2), -0.4161468) && near(exp2(4), 16.0) && near(sqrt(9u), 3.0) && near(pow(2, 3), 8.0) && near(atan(1, 1), 0.7853982) && near(radians(90), 1.5707963);
	}

	if (cell == 10) {
		vec4 a = vec4(0.1, 0.2, 0.3, 0.4) * one;
		return near(sin(a), vec4(0.0998334, 0.1986693, 0.2955202, 0.3894183)) && near(cos(a), vec4(0.9950042, 0.9800666, 0.9553365, 0.9210610)) && near(tan(a), vec4(0.1003347, 0.2027100, 0.3093362, 0.4227932));
	}

	if (cell == 11) {
		vec3 a = vec3(-0.9, 0.0, 0.9) * one;
		return near(asin(a), vec3(-1.1197695, 0.0, 1.1197695)) && near(acos(a), vec3(2.6905658, 1.5707963, 0.4510268)) && near(atan(a), vec3(-0.7328151, 0.0, 0.7328151));
	}

	if (cell == 12) {
		return near(sinh(vec2(0.5, -0.5) * one), vec2(0.5210953, -0.5210953)) && near(exp(vec3(-2.0, 0.5, 3.0) * one), vec3(0.1353353, 1.6487213, 20.0855369)) && abs(exp(10.0 * one) - 22026.4658) < 2.0;
	}

	if (cell == 13) {
		return near(pow(vec4(1.0, 4.0, 9.0, 16.0) * one, vec4(0.5)), vec4(1.0, 2.0, 3.0, 4.0)) && near(inversesqrt(vec4(1.0, 4.0, 16.0, 64.0) * one), vec4(1.0, 0.5, 0.25, 0.125)) && near(log2(vec2(0.25, 0.125) * one), vec2(-2.0, -3.0));
	}

	if (cell == 14) {
		float x = 0.3 * one;
		return near(cosh(x) * cosh(x) - sinh(x) * sinh(x), 1.0) && near(tanh(x), sinh(x) / cosh(x)) && near(exp2(log2(x)), x) && near(sqrt(x) * sqrt(x), x) && near(inversesqrt(x) * sqrt(x), 1.0);
	}

	float d = degrees(radians(37.0 * one));
	return abs(d - 37.0) < 0.001 && near(atan(sin(1.0 * one), cos(1.0 * one)), 1.0) && near(atan(sin(3.0 * one), cos(3.0 * one)), 3.0) && near(atan(sin(-2.5 * one), cos(-2.5 * one)), -2.5);
}

void main() {
	int cell = int(uv.x * 4.0) + int(uv.y * 4.0) * 4;
	final_color = run_cell(cell) ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}
