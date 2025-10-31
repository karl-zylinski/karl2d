#version 330
layout(location = 0) in vec3 POS;
layout(location = 1) in vec2 UV;
layout(location = 2) in vec4 COL;

out vec2 frag_uv;
out vec4 frag_color;

layout(std140) uniform constants {
    mat4 mvp;
};

void main()
{
    frag_uv = UV;
    frag_color = COL;
    gl_Position = mvp * vec4(POS, 1.0);
}
