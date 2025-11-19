#version 330
layout(location = 0) in vec3 position;
layout(location = 1) in vec2 texcoord;
layout(location = 2) in vec4 color;

out vec2 frag_texcoord;
out vec4 frag_color;

uniform mat4 mvp;

void main()
{
    frag_texcoord = texcoord;
    frag_color = color;
    gl_Position = mvp * vec4(position, 1.0);
}
