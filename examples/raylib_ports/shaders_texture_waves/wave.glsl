uniform mat4 view_projection;
uniform sampler2D tex;

uniform float seconds;
uniform vec2 size;
uniform float freqX;
uniform float freqY;
uniform float ampX;
uniform float ampY;
uniform float speedX;
uniform float speedY;

#vertex

in vec2 position;
in vec2 texcoord;
in vec4 color;

out vec2 frag_texcoord;
out vec4 frag_color;

void main() {
	frag_texcoord = texcoord;
	frag_color = color;
	gl_Position = view_projection * vec4(position, 0.0, 1.0);
}

#fragment

in vec2 frag_texcoord;
in vec4 frag_color;

out vec4 final_color;

void main() {
	float pixelWidth = 1.0 / size.x;
	float pixelHeight = 1.0 / size.y;
	float aspect = pixelHeight / pixelWidth;
	float boxLeft = 0.0;
	float boxTop = 0.0;

	vec2 p = frag_texcoord;
	p.x += cos((frag_texcoord.y - boxTop) * freqX / (pixelWidth * 750.0) + (seconds * speedX)) * ampX * pixelWidth;
	p.y += sin((frag_texcoord.x - boxLeft) * freqY * aspect / (pixelHeight * 750.0) + (seconds * speedY)) * ampY * pixelHeight;

	vec4 c = texture(tex, p);
	final_color = c * frag_color;
}
