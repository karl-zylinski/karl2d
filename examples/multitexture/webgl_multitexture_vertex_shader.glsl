#version 300 es
precision highp float;
layout(location = 0) in vec2 position;
layout(location = 1) in vec2 texcoord;
layout(location = 2) in vec4 color;

out vec2 frag_texcoord;
out vec4 frag_color;

uniform mat4 view_projection;

void main()
{
    frag_texcoord = texcoord;
    frag_color = color;
    gl_Position = view_projection * vec4(position, 0, 1.0);
}
