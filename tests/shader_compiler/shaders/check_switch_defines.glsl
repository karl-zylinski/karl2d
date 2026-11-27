#define PI 3.14159265
#define TWO_PI (2.0 * PI)
#define SQUARE(x) ((x) * (x))
#define LERP(a, b, t) mix(a, b, t)
#define ADD3(a, b, c) (SQUARE(a) + (b) + (c))
#define GREEN vec4(0.0, 1.0, 0.0, 1.0)
#define ENABLED

#ifdef ENABLED
#define CHOSEN 7
#else
#define CHOSEN 8
#endif

#ifndef MISSING
#define FALLBACK 3
#endif

#ifdef MISSING
this text is never compiled
#endif

#define TEMPORARY 5
#undef TEMPORARY
#define TEMPORARY 6

#define LONG_SUM(a, b) \
	((a) + \
	(b))

uniform mat4 view_projection;
uniform float zero;

bool near(float a, float b) {
	return abs(a - b) < 0.001;
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

int classify(int v) {
	switch (v) {
	case 0:
		return 10;
	case 1:
	case 2:
		return 20;
	case 3:
		v += 100;
	case 4:
		v += 1;
		break;
	default:
		return -1;
	}

	return v;
}

int count_until(int limit) {
	int found = 0;

	for (int i = 0; i < 10; i++) {
		switch (i % 3) {
		case 0:
			continue;
		case 1:
			found += 1;
			break;
		default:
			if (i > limit) {
				return found;
			}

			found += 10;
		}
	}

	return found;
}

float pick(uint which) {
	float result = 0.0;

	switch (which) {
	case 1u:
		result = 1.5;
		break;
	case 2u:
		result = 2.5;
		break;
	}

	return result;
}

void main() {
	int cell = int(uv.x * 4.0) + int(uv.y * 4.0) * 4;
	int z = int(zero);
	bool ok = true;

	switch (cell) {
	case 0:
		ok = classify(0 + z) == 10 && classify(1 + z) == 20 && classify(2 + z) == 20;
		break;
	case 1:
		ok = classify(3 + z) == 104 && classify(4 + z) == 5 && classify(9 + z) == -1;
		break;
	case 2:
		ok = count_until(100 + z) == 33;
		break;
	case 3:
		ok = count_until(4 + z) == 12;
		break;
	case 4:
		ok = near(pick(uint(1 + z)), 1.5) && near(pick(uint(2 + z)), 2.5) && near(pick(uint(3 + z)), 0.0);
		break;
	case 5:
		ok = near(TWO_PI, 6.2831853) && near(SQUARE(3.0 + zero), 9.0);
		break;
	case 6:
		ok = near(LERP(2.0, 4.0, 0.5 + zero), 3.0) && near(ADD3(2.0, 1.0, zero), 5.0);
		break;
	case 7:
		ok = CHOSEN == 7 && FALLBACK == 3 && TEMPORARY == 6;
		break;
	case 8:
		ok = near(LONG_SUM(1.5, zero + 2.0), 3.5) && near(SQUARE(SQUARE(2.0)), 16.0);
		break;
	default:
		ok = true;
	}

	final_color = ok ? GREEN : vec4(1.0, 0.0, 0.0, 1.0);
}
