uniform mat4 view_projection;
uniform float zero;

const float PIXEL = 1.0 / 256.0;

bool near(float a, float b) {
	return abs(a - b) < 0.00001;
}

float pixel_width(float v) {
	return fwidth(v);
}

vec2 abs_dx_dy(float v) {
	return vec2(abs(dFdx(v)), abs(dFdy(v)));
}

#vertex

in vec3 position;
in vec2 texcoord;
in vec4 color;

out vec2 uv;
out vec3 ramp;

void main() {
	uv = texcoord;
	ramp = vec3(texcoord.x * 3.0 + texcoord.y, texcoord.y * 256.0, 1.0 - texcoord.x);
	gl_Position = view_projection * vec4(position, 1.0);
}

#fragment

in vec2 uv;
in vec3 ramp;

out vec4 final_color;

void main() {
	int cell = int(uv.x * 4.0) + int(uv.y * 4.0) * 4;
	vec4 fc = gl_FragCoord;
	float dx_u = dFdx(uv.x);
	float dx_v = dFdx(uv.y);
	float dy_v = dFdy(uv.y);
	float dy_u = dFdy(uv.x);
	vec2 fw_uv = fwidth(uv);
	vec2 dx_fc = dFdx(fc.xy);
	vec2 fw_fc = fwidth(gl_FragCoord.xy);
	vec3 dx_ramp = dFdx(ramp);
	vec3 fw_ramp = fwidth(ramp);
	float helper_fw = pixel_width(uv.x * 2.0);
	vec2 helper_dxdy = abs_dx_dy(uv.y * 4.0);
	vec2 dx_quad = dFdx(uv * uv);
	vec4 dx_v4 = dFdx(vec4(uv, uv * 2.0 + zero));
	bool ok = true;

	if (cell == 0) {
		ok = abs(fc.x - uv.x * 256.0) < 0.01 && fract(fc.x) == 0.5 && fract(fc.y) == 0.5;
	} else if (cell == 1) {
		ok = near(fc.w, 1.0) && fc.x >= 64.0 && fc.x < 128.0 && fc.y > 0.0 && fc.y < 256.0;
	} else if (cell == 2) {
		ok = near(dx_u, PIXEL) && near(dx_v, 0.0) && near(abs(dy_v), PIXEL) && near(dy_u, 0.0);
	} else if (cell == 3) {
		ok = near(fw_uv.x, PIXEL) && near(fw_uv.y, PIXEL);
	} else if (cell == 4) {
		ok = abs(dx_fc.x - 1.0) < 0.0001 && abs(dx_fc.y) < 0.0001 && abs(fw_fc.x - 1.0) < 0.0001 && abs(fw_fc.y - 1.0) < 0.0001;
	} else if (cell == 5) {
		ok = near(dx_ramp.x, 3.0 * PIXEL) && near(dx_ramp.y, 0.0) && near(dx_ramp.z, -PIXEL);
	} else if (cell == 6) {
		ok = near(fw_ramp.x, 4.0 * PIXEL) && abs(fw_ramp.y - 1.0) < 0.0001 && near(fw_ramp.z, PIXEL);
	} else if (cell == 7) {
		ok = near(helper_fw, 2.0 * PIXEL) && near(helper_dxdy.x, 0.0) && near(helper_dxdy.y, 4.0 * PIXEL);
	} else if (cell == 8) {
		ok = dx_quad.x > 0.0 && abs(dx_quad.x - 2.0 * uv.x * PIXEL) < 0.0001 && near(dx_quad.y, 0.0);
	} else if (cell == 9) {
		ok = near(dx_v4.x, PIXEL) && near(dx_v4.y, 0.0) && near(dx_v4.z, 2.0 * PIXEL) && near(dx_v4.w, 0.0);
	} else if (cell == 10) {
		int px = int(fc.x);
		ok = px == int(uv.x * 256.0) && px / 64 == 2;
	} else if (cell == 11) {
		float column = floor(fc.x / 64.0);
		ok = column == 3.0 && mod(fc.x, 1.0) == 0.5;
	} else if (cell == 12) {
		ok = gl_FrontFacing || !gl_FrontFacing;
	} else if (cell == 13) {
		ok = abs(fc.x / 256.0 - uv.x) < 0.0001 && abs(abs(fc.y / 256.0 - 0.5) - abs(uv.y - 0.5)) < 0.0001;
	} else if (cell == 14) {
		ok = fc.z >= 0.0 && fc.z <= 1.0;
	} else {
		ok = near(fwidth(uv.x + uv.y), 2.0 * PIXEL);
	}

	gl_FragDepth = gl_FragCoord.z;
	final_color = ok ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}
