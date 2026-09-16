#version 330
precision highp float;
in vec2 frag_texcoord;
in vec4 frag_color;
out vec4 final_color;

uniform sampler2D tex;
uniform float premultiply;

void main()
{
    float c = texture(tex, frag_texcoord).r;
    final_color = vec4(frag_color.rgb * mix(1.0, c, premultiply), frag_color.a * c);
}
