uniform mat4 view_projection;
uniform sampler2D tex;
uniform float time;

vec4 fetch_clamped(sampler2D s, ivec2 p) {
	ivec2 size = textureSize(s, 0);
	return texelFetch(s, clamp(p, ivec2(0), size - 1), 0);
}

vec4 bilinear(sampler2D s, vec2 p) {
	vec2 g = p * vec2(textureSize(s, 0)) - 0.5;
	ivec2 i = ivec2(floor(g));
	vec2 f = fract(g);
	vec4 a = fetch_clamped(s, i);
	vec4 b = fetch_clamped(s, i + ivec2(1, 0));
	vec4 c = fetch_clamped(s, i + ivec2(0, 1));
	vec4 d = fetch_clamped(s, i + ivec2(1, 1));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
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

void main() {
	vec2 centered = uv - 0.5;
	float r = length(centered);
	float angle = 2.0 * exp(-r * 4.0) + time * 0.5;
	float c = cos(angle);
	float s = sin(angle);
	vec2 swirled = mat2(c, s, -s, c) * centered + 0.5;
	vec2 wave = swirled + vec2(sin(uv.y * 12.0 + time), cos(uv.x * 10.0 - time)) * 0.02;
	vec4 smooth_sample = bilinear(tex, wave);
	ivec2 texel = ivec2(uv * 8.0);
	vec4 exact = texelFetch(tex, texel, 0);
	vec4 point_sample = texture(tex, (vec2(texel) + 0.5) / 8.0);
	float split = smoothstep(0.45, 0.55, uv.x + 0.1 * sin(uv.y * 6.2831853));
	vec4 col = mix(smooth_sample, mix(exact, point_sample, 0.5), split * 0.35);
	final_color = vec4(col.rgb * (1.1 - r), 1.0);
}
