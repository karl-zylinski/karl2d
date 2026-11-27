uniform mat4 view_projection;
uniform sampler2D tex;
uniform sampler2D tex2;

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
	vec4 c = texture(tex, frag_texcoord);
	vec4 c2 = texture(tex2, frag_texcoord);
	final_color = c * frag_color * c2;
}
