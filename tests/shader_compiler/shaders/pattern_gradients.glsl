uniform mat4 view_projection;
uniform float time;
uniform vec3 top_color = vec3(0.1, 0.4, 0.9);
uniform vec3 bottom_color = vec3(0.95, 0.5, 0.1);
uniform float band_count = 6.0;

vec3 hue(float h) {
	vec3 k = vec3(0.0, 2.0, 4.0) / 3.0;
	return clamp(abs(mod(h * 6.0 + k * 3.0, 6.0) - 3.0) - 1.0, 0.0, 1.0);
}

#vertex

in vec3 position;
in vec2 texcoord;
in vec4 color;

out vec2 uv;
out vec3 vertex_color;
out float vertex_wave;

void main() {
	uv = texcoord;
	vertex_color = mix(top_color, bottom_color, texcoord.y) * color.rgb;
	vertex_wave = texcoord.x * 4.0 + texcoord.y;
	gl_Position = view_projection * vec4(position, 1.0);
}

#fragment

in vec2 uv;
in vec3 vertex_color;
in float vertex_wave;

out vec4 final_color;

void main() {
	float x = gl_FragCoord.x / 256.0;
	vec3 col = vertex_color;
	float band = floor(uv.y * band_count) / band_count;
	vec3 rainbow = hue(x + time * 0.1);
	float band_mask = 1.0 - smoothstep(0.0, 0.02, 0.5 - abs(fract(uv.y * band_count) - 0.5));
	col = mix(col, rainbow, 0.35 + 0.3 * band);
	col *= 0.85 + 0.15 * sin(vertex_wave * 3.14159265);
	col = mix(col, vec3(1.0), band_mask * 0.5);
	vec3 ramp = vec3(x, x * x, sqrt(x));

	if (uv.y > 0.85) {
		col = ramp;
	} else if (uv.y < 0.1) {
		col = vec3(step(0.5, x), smoothstep(0.2, 0.8, x), clamp(x * 2.0 - 0.5, 0.0, 1.0));
	}

	final_color = vec4(col, 1.0);
}
