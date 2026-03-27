#version 450
layout(location = 0) in vec2 frag_texcoord;
layout(location = 1) in vec4 frag_color;

layout(location = 0) out vec4 final_color;

layout(set = 0, binding = 0) uniform sampler2D tex;

void main()
{
    vec4 c = texture(tex, frag_texcoord);
    final_color = c * frag_color;
}
