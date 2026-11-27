uniform mat4 view_projection;
uniform float time;

struct Light {
	vec3 direction;
	vec3 color;
};

struct Hit {
	bool found;
	float t;
	vec3 normal;
};

const vec3 sphere_center = vec3(0.0, 0.0, 3.0);
const float sphere_radius = 1.0;

Hit intersect_sphere(vec3 ro, vec3 rd) {
	Hit h = Hit(false, 0.0, vec3(0.0));
	vec3 oc = ro - sphere_center;
	float b = dot(oc, rd);
	float c = dot(oc, oc) - sphere_radius * sphere_radius;
	float disc = b * b - c;

	if (disc < 0.0) {
		return h;
	}

	h.found = true;
	h.t = -b - sqrt(disc);
	h.normal = normalize(ro + rd * h.t - sphere_center);
	return h;
}

vec3 shade(Hit h, vec3 rd, Light lights[2]) {
	vec3 albedo = vec3(0.8, 0.35, 0.2);
	vec3 col = albedo * 0.08;

	for (int i = 0; i < lights.length(); i++) {
		vec3 l = normalize(-lights[i].direction);
		float diffuse = max(dot(h.normal, l), 0.0);
		vec3 r = reflect(-l, h.normal);
		float specular = pow(max(dot(r, -rd), 0.0), 24.0);
		col += lights[i].color * (albedo * diffuse + vec3(specular * 0.6));
	}

	float rim = pow(1.0 - max(dot(h.normal, -rd), 0.0), 3.0);
	return col + vec3(0.2, 0.3, 0.5) * rim;
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
	vec2 p = (uv - 0.5) * 2.0;
	vec3 ro = vec3(0.0);
	vec3 rd = normalize(vec3(p * 0.7, 1.5));
	Light lights[2];
	lights[0] = Light(vec3(cos(time), -0.8, sin(time)), vec3(1.0, 0.95, 0.85));
	lights[1] = Light(vec3(-0.6, 0.3, 0.5), vec3(0.2, 0.3, 0.6));
	vec3 background = mix(vec3(0.05, 0.05, 0.1), vec3(0.25, 0.3, 0.4), uv.y);
	Hit h = intersect_sphere(ro, rd);
	vec3 col = background;

	if (h.found) {
		vec3 lit = shade(h, rd, lights);
		vec3 oc = ro - sphere_center;
		float b = dot(oc, rd);
		float disc = b * b - dot(oc, oc) + sphere_radius * sphere_radius;
		float coverage = smoothstep(0.0, 0.02, disc);
		col = mix(background, lit, coverage);
	}

	col = pow(clamp(col, 0.0, 1.0), vec3(1.0 / 2.2));
	final_color = vec4(col, 1.0);
}
