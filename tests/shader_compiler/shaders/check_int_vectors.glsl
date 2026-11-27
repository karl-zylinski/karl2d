uniform mat4 view_projection;
uniform float zero;

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

int count_bits(uint v) {
	int n = 0;

	for (int i = 0; i < 32; i++) {
		if ((v & (1u << uint(i))) != 0u) {
			n++;
		}
	}

	return n;
}

bool run_cell(int cell) {
	int z = int(zero);
	uint zu = uint(zero);

	if (cell == 0) {
		ivec3 a = ivec3(1, 2, 3 + z);
		ivec4 b = ivec4(5 + z);
		ivec2 c = ivec2(vec2(-1.5, 2.5) + zero);
		ivec3 d = ivec3(ivec2(1, 2 + z), 3);
		ivec2 e = ivec2(uvec2(7u, 8u + zu));
		return a.x == 1 && a.y == 2 && a.z == 3 && b == ivec4(5, 5, 5, 5) && c == ivec2(-1, 2) && d == ivec3(1, 2, 3) && e == ivec2(7, 8);
	}

	if (cell == 1) {
		ivec3 a = ivec3(7, -8, 9 + z);
		ivec3 b = ivec3(2, 3, 4);
		ivec3 p = ivec3(7, 8, 9 + z);
		return a + b == ivec3(9, -5, 13) && a - b == ivec3(5, -11, 5) && a * b == ivec3(14, -24, 36) && a / b == ivec3(3, -2, 2) && p % b == ivec3(1, 2, 1) && -a == ivec3(-7, 8, -9);
	}

	if (cell == 2) {
		ivec3 b = ivec3(2, 3, 4 + z);
		return b * 2 == ivec3(4, 6, 8) && 10 - b == ivec3(8, 7, 6) && b / 2 == ivec3(1, 1, 2) && b + 1 == ivec3(3, 4, 5) && 12 / b == ivec3(6, 4, 3) && b % 3 == ivec3(2, 0, 1);
	}

	if (cell == 3) {
		ivec2 a = ivec2(12, 10 + z);
		return (a & ivec2(10)) == ivec2(8, 10) && (a | 1) == ivec2(13, 11) && (a ^ ivec2(5, 5)) == ivec2(9, 15) && ~ivec2(z, -1) == ivec2(-1, 0) && (3 & a) == ivec2(0, 2);
	}

	if (cell == 4) {
		ivec2 a = ivec2(1, 3 + z);
		bool ok = (a << 2) == ivec2(4, 12) && (ivec2(1, 2 + z) << ivec2(3, 4)) == ivec2(8, 32) && (ivec2(-16, 64 + z) >> 2) == ivec2(-4, 16);
		ok = ok && (uvec2(0x80000000u, 256u + zu) >> 4u) == uvec2(0x08000000u, 16u) && (uvec2(1u, 2u + zu) << 31) == uvec2(0x80000000u, 0u);
		ok = ok && (ivec3(256 + z) >> ivec3(1, 2, 3)) == ivec3(128, 64, 32) && (a << 1u) == ivec2(2, 6);
		return ok;
	}

	if (cell == 5) {
		uvec3 a = uvec3(10u, 20u, 30u + zu);
		uvec2 m = uvec2(0u + zu) - 1u;
		bool ok = a / 3u == uvec3(3u, 6u, 10u) && a % 7u == uvec3(3u, 6u, 2u) && m == uvec2(0xFFFFFFFFu);
		ok = ok && (uvec2(0xF0F0F0F0u + zu) ^ uvec2(0xFFFFFFFFu)) == uvec2(0x0F0F0F0Fu) && ~uvec2(zu) == uvec2(4294967295u);
		ok = ok && (uvec2(0xFF00u, 0x0FF0u + zu) & uvec2(0x0FF0u)) == uvec2(0x0F00u, 0x0FF0u) && (uvec2(1u, 2u + zu) | 4u) == uvec2(5u, 6u);
		return ok;
	}

	if (cell == 6) {
		int x = 6 + z;
		x &= 3;
		bool ok = x == 2;
		x |= 8;
		ok = ok && x == 10;
		x ^= 15;
		ok = ok && x == 5;
		x <<= 3;
		ok = ok && x == 40;
		x >>= 2;
		ok = ok && x == 10;
		x %= 4;
		ok = ok && x == 2;
		uint u = 100u + zu;
		u >>= 2u;
		ok = ok && u == 25u;
		u <<= 1;
		ok = ok && u == 50u;
		ivec2 v = ivec2(3, 5 + z);
		v <<= 1;
		ok = ok && v == ivec2(6, 10);
		v |= ivec2(1);
		ok = ok && v == ivec2(7, 11);
		v &= 6;
		ok = ok && v == ivec2(6, 2);
		v ^= ivec2(1, 1);
		ok = ok && v == ivec2(7, 3);
		v %= ivec2(4, 2);
		ok = ok && v == ivec2(3, 1);
		return ok;
	}

	if (cell == 7) {
		ivec4 v = ivec4(1, 2, 3, 4 + z);
		bool ok = v.wx == ivec2(4, 1) && v[2] == 3 && v.ba == ivec2(3, 4) && v.q == 4;
		v.yz = ivec2(9, 8);
		v.w += 10;
		v[z] = -1;
		ok = ok && v == ivec4(-1, 9, 8, 14);
		return ok;
	}

	if (cell == 8) {
		ivec2 v = ivec2(1, 2 + z);
		v++;
		bool ok = v == ivec2(2, 3);
		--v;
		ok = ok && v == ivec2(1, 2);
		ivec2 old = v--;
		ok = ok && old == ivec2(1, 2) && v == ivec2(0, 1);
		uint u = zu;
		u--;
		ok = ok && u == 0xFFFFFFFFu;
		u++;
		ok = ok && u == 0u;
		return ok;
	}

	if (cell == 9) {
		return abs(-5 + z) == 5 && abs(ivec3(-1, 0, 2 + z)) == ivec3(1, 0, 2) && sign(-7 + z) == -1 && sign(z) == 0 && sign(ivec3(-3, 0, 4 + z)) == ivec3(-1, 0, 1);
	}

	if (cell == 10) {
		bool ok = min(3 + z, -2) == -2 && max(ivec2(1, 5 + z), ivec2(4, 2)) == ivec2(4, 5) && min(ivec3(1, 5, 9 + z), 4) == ivec3(1, 4, 4);
		ok = ok && clamp(ivec3(-5, 5, 15 + z), 0, 10) == ivec3(0, 5, 10) && clamp(7 + z, 1, 3) == 3 && clamp(ivec2(-1, 9 + z), ivec2(0, 2), ivec2(4, 6)) == ivec2(0, 6);
		ok = ok && min(5u + zu, 3u) == 3u && max(uvec2(1u, 9u + zu), 4u) == uvec2(4u, 9u) && clamp(uvec2(1u, 20u + zu), uvec2(2u), uvec2(10u)) == uvec2(2u, 10u);
		return ok;
	}

	if (cell == 11) {
		uint big = 0xFFFFFFFFu + zu;
		int neg = -1 + z;
		return 0xFF == 255 && 0x7fffffff == 2147483647 && 0xFFFFFFFFu == 4294967295u && int(big) == -1 && uint(neg) == 0xFFFFFFFFu && 0xaBu == 171u && 1u == uint(1);
	}

	if (cell == 12) {
		ivec2 a = ivec2(7, 9 + z);
		return a / ivec2(2) == ivec2(3, 4) && a / 2 == ivec2(3, 4) && -a / 2 == ivec2(-3, -4) && a * a - a == ivec2(42, 72);
	}

	if (cell == 13) {
		uvec2 a = uvec2(3u, 4u + zu);
		return count_bits(0xB7u + zu) == 6 && count_bits(0xFFFFFFFFu + zu) == 32 && count_bits(zu) == 0 && a == uvec2(3u, 4u) && a != uvec2(4u, 3u) && a.yx == uvec2(4u, 3u);
	}

	if (cell == 14) {
		uint u = 5u + zu;
		int i = 3 + z;
		return (u & 3) == 1u && (u | i) == 7u && (u ^ 1) == 4u && u + i == 8u && i * u == 15u && (u % 3) == 2u;
	}

	uvec2 w = uvec2(0xFFFFFFFFu, 1u + zu) + uvec2(2u);
	uint big_mul = (0x10000u + zu) * 0x10000u;
	int imax = 0x7fffffff + z;
	return w == uvec2(1u, 3u) && big_mul == 0u && imax - 1 == 2147483646 && 0x10000u * 3u == 196608u;
}

void main() {
	int cell = int(uv.x * 4.0) + int(uv.y * 4.0) * 4;
	final_color = run_cell(cell) ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}
