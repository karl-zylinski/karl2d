#version 330
in vec2 frag_uv;
in vec4 frag_color;
out vec4 final_color;

uniform sampler2D tex;

void main()
{
    //vec4 c = texture(tex, frag_uv);
    //final_color = c * frag_color;
    final_color = vec4(frag_color.r,frag_uv.r,1,1);
}