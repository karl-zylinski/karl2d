#version 330
in vec2 position;
in vec2 uv;
in vec4 color;

out vec2 frag_uv;
out vec4 frag_color;

uniform mat4 mvp;

void main()
{
    frag_uv = uv;
    frag_color = color;
    gl_Position = mvp*vec4(position, 0.0, 1.0);
}
