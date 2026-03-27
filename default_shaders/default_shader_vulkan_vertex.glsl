#version 450
layout(location = 0) in vec2 position;
layout(location = 1) in vec2 texcoord;
layout(location = 2) in vec4 color;

layout(location = 0) out vec2 frag_texcoord;
layout(location = 1) out vec4 frag_color;

layout(push_constant) uniform PushConstants {
    mat4 view_projection;
} pc;

void main()
{
    frag_texcoord = texcoord;
    frag_color = color;
    gl_Position = pc.view_projection * vec4(position, 0.0, 1.0);
}
