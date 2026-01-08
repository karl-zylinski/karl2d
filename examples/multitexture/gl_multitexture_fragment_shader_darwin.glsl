#version 410
precision highp float;
in vec2 frag_texcoord;
in vec4 frag_color;
out vec4 final_color;

uniform sampler2D tex;
uniform sampler2D tex2;

void main()
{
    vec4 c = texture(tex, frag_texcoord);
    vec4 c2 = texture(tex2, frag_texcoord);
    final_color = c * frag_color * c2;
}