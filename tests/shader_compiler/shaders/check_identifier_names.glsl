uniform mat4 view_projection;
uniform float zero;
uniform vec2 cbuffer = vec2(1.0, 2.0);

struct Texture2D {
	float SamplerState;
	vec2 POSITION;
};

struct VS_INPUT {
	vec4 SV_Target;
	int TEXCOORD0;
};

const float packoffset = 3.0;

float lerp(float a, float b, float t) {
	return a + (b - a) * t;
}

float frac(float x) {
	return x - floor(x);
}

float saturate(float x) {
	return clamp(x, 0.0, 1.0);
}

vec2 mul(mat2 m, vec2 v) {
	return v * m;
}

float rsqrt(float x) {
	return 1.0 / sqrt(x);
}

#vertex

in vec3 position;
in vec2 texcoord;
in vec4 color;

out vec2 uv;
out vec2 float2;

void main() {
	vec4 vertex = vec4(position, 1.0);
	uv = texcoord;
	float2 = texcoord * 2.0;
	gl_Position = view_projection * vertex;
}

#fragment

in vec2 uv;
in vec2 float2;

out vec4 SV_Target0;

bool near(float a, float b) {
	return abs(a - b) < 0.0001;
}

bool run_cell(int cell) {
	float point = 0.25 + zero;
	float line = 0.5;
	float triangle = 0.75;
	vec4 float4 = vec4(point, line, triangle, 1.0);
	mat2 matrix = mat2(1.0, 2.0, 3.0, 4.0);
	vec3 vector = vec3(1.0);
	int string = 3;
	float fragment = 2.0;
	float kernel = 1.0;
	float device = 4.0;
	float constant = 5.0;
	float thread = 6.0;
	float linear = 7.0;
	float nointerpolation = 8.0;
	float groupshared = 9.0;
	float technique = 10.0;
	float pass = 11.0;
	float clip = 12.0;
	float ddx = 13.0;
	float self = 14.0;
	float main0 = 15.0;

	if (cell == 0) {
		return near(lerp(point, triangle, 0.5), 0.5) && near(frac(2.25), 0.25) && near(saturate(1.5), 1.0) && near(rsqrt(4.0), 0.5);
	}

	if (cell == 1) {
		vec2 r = mul(matrix, vec2(1.0, 1.0));
		return near(r.x, 3.0) && near(r.y, 7.0) && near(float4.y, 0.5) && near(vector.z, 1.0) && string == 3;
	}

	if (cell == 2) {
		Texture2D t = Texture2D(1.0, vec2(2.0));
		VS_INPUT v = VS_INPUT(vec4(1.0), 4);
		return near(t.SamplerState, 1.0) && near(t.POSITION.y, 2.0) && near(v.SV_Target.w, 1.0) && v.TEXCOORD0 == 4;
	}

	if (cell == 3) {
		float s = fragment + kernel + device + constant + thread + linear + nointerpolation + groupshared + technique + pass + clip + ddx + self + main0;
		return near(s, 117.0) && near(packoffset, 3.0) && near(cbuffer.y, 2.0);
	}

	return all(lessThan(abs(float2 - uv * 2.0), vec2(0.001)));
}

void main() {
	int cell = int(uv.x * 4.0) + int(uv.y * 4.0) * 4;
	SV_Target0 = run_cell(cell) ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}
