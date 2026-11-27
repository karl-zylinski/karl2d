uniform mat4 view_projection;
uniform sampler2D tex;
uniform float fzero;

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

void main() {
	int cell = int(uv.x * 4.0) + int(uv.y * 4.0) * 4;
	bool ok = true;
	float z = fzero;

	if (cell == 0) {
		ok = near(sin(z + 0.5), 0.479426) && near(cos(z + 0.5), 0.877583) && near(tan(z + 0.5), 0.546302);
	} else if (cell == 1) {
		ok = near(asin(z + 0.5), 0.523599) && near(acos(z + 0.5), 1.047198) && near(asin(z - 0.5), -0.523599) && near(acos(z - 0.5), 2.094395);
	} else if (cell == 2) {
		ok = near(atan(z + 2.0), 1.107149) && near(atan(z - 0.5), -0.463648) && near(atan(z + 1.0, z - 1.0), 2.356194) && near(atan(z - 1.0, z - 1.0), -2.356194) && near(atan(z + 1.0, z + 2.0), 0.463648);
	} else if (cell == 3) {
		ok = near(pow(z + 2.0, 3.0), 8.0) && near(exp(z + 1.0), 2.718282) && near(log(z + 2.0), 0.693147) && near(exp2(z + 3.0), 8.0) && near(log2(z + 8.0), 3.0);
	} else if (cell == 4) {
		ok = near(sqrt(z + 9.0), 3.0) && near(inversesqrt(z + 4.0), 0.5) && near(abs(z - 2.5), 2.5) && near(sign(z - 2.0), -1.0) && near(sign(z), 0.0) && near(sign(z + 3.0), 1.0);
	} else if (cell == 5) {
		ok = near(floor(z - 1.5), -2.0) && near(ceil(z - 1.5), -1.0) && near(trunc(z - 1.5), -1.0) && near(fract(z - 1.25), 0.75) && near(round(z + 2.6), 3.0);
	} else if (cell == 6) {
		ok = near(mod(z + 5.5, 2.0), 1.5) && near(mod(z - 0.5, 2.0), 1.5) && near(mod(vec2(z + 7.0, z - 1.0), vec2(3.0)).y, 2.0);
	} else if (cell == 7) {
		ok = near(min(z + 1.0, 2.0), 1.0) && near(max(z + 1.0, 2.0), 2.0) && near(clamp(z + 5.0, 0.0, 1.0), 1.0) && min(3, 2) == 2 && clamp(ivec2(-5, 5), -1, 1) == ivec2(-1, 1);
	} else if (cell == 8) {
		ok = near(mix(z + 2.0, 4.0, 0.25), 2.5) && near(step(0.5, z + 0.75), 1.0) && near(step(0.5, z + 0.25), 0.0) && near(smoothstep(0.0, 1.0, z + 0.5), 0.5) && near(mix(vec2(1.0), vec2(2.0), bvec2(true, false)).x, 2.0);
	} else if (cell == 9) {
		vec3 a = vec3(z + 1.0, 2.0, 2.0);
		ok = near(length(a), 3.0) && near(distance(a, vec3(1.0, 2.0, 0.0)), 2.0) && near(dot(a, vec3(1.0, 0.5, 0.25)), 2.5) && near(normalize(a).x, 0.333333);
	} else if (cell == 10) {
		vec3 c = cross(vec3(z + 1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0));
		vec3 r = reflect(vec3(z + 1.0, -1.0, 0.0), vec3(0.0, 1.0, 0.0));
		ok = near(c.z, 1.0) && near(c.x, 0.0) && near(r.x, 1.0) && near(r.y, 1.0);
	} else if (cell == 11) {
		ok = near(sinh(z + 1.0), 1.175201) && near(cosh(z + 1.0), 1.543081) && near(tanh(z + 1.0), 0.761594) && near(radians(z + 180.0), 3.141593) && near(degrees(z + 3.141593), 180.0);
	} else if (cell == 12) {
		vec4 t = texture(tex, vec2(0.3125, 0.5625));
		vec4 f = texelFetch(tex, ivec2(2, 4), 0);
		ivec2 size = textureSize(tex, 0);
		ok = near(t.r, 72.0 / 255.0) && near(t.g, 144.0 / 255.0) && near(f.r, 72.0 / 255.0) && near(f.b, 1.0) && size == ivec2(8, 8) && near(textureLod(tex, vec2(0.3125, 0.5625), 0.0).g, 144.0 / 255.0) && near(textureGrad(tex, vec2(0.3125, 0.5625), vec2(0.001, 0.0), vec2(0.0, 0.001)).r, 72.0 / 255.0);
	} else if (cell == 13) {
		float dx = dFdx(uv.x * 256.0);
		float w = fwidth(uv.x * 256.0 + uv.y * 256.0);
		ok = near(dx, 1.0) && near(w, 2.0) && near(abs(dFdy(uv.y * 256.0)), 1.0);
	} else if (cell == 14) {
		vec3 r = refract(normalize(vec3(z + 1.0, -1.0, 0.0)), vec3(0.0, 1.0, 0.0), 0.5);
		ok = near(r.x, 0.353553) && near(r.y, -0.935414);
	} else {
		ok = near(gl_FragCoord.x, floor(uv.x * 256.0) + 0.5);
	}

	final_color = ok ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}
