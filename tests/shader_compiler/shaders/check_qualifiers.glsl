#version 330
#extension GL_ARB_separate_shader_objects : enable

precision highp float;
precision mediump int;

uniform highp mat4 view_projection;
uniform mediump float zero;

highp float scaled(in highp float x, const in float s) {
	return x * s;
}

void store(in float v, out highp float o, inout lowp float acc) {
	o = v;
	acc += v;
}

#vertex

layout(location = 0) in highp vec3 position;
layout(location = 1) in mediump vec2 texcoord;
in lowp vec4 color;

smooth out highp vec2 uv;
flat out mediump int tag;

void main() {
	uv = texcoord;
	tag = 3;
	gl_Position = view_projection * vec4(position, 1.0);
}

#fragment

smooth in highp vec2 uv;
flat in mediump int tag;

layout(location = 0) out lowp vec4 final_color;

void main() {
	highp float a = scaled(2.0 + zero, 3.0);
	mediump float o;
	lowp float acc = 1.0;
	store(a, o, acc);
	const highp int n = 2;
	bool ok = a == 6.0 && o == 6.0 && acc == 7.0 && tag == 3 && n == 2;
	final_color = ok ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}
