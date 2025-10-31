cbuffer constants : register(b0) {
	float4x4 mvp;
}
struct vs_in {
	float3 position : position;
	float2 uv       : texcoord;
	float4 color    : color;
	float2 wobble   : wobble;
};
struct vs_out {
	float4 position : SV_POSITION;
	float2 uv       : texcoord;
	float4 color    : color;
};
Texture2D    tex : register(t0);
SamplerState smp : register(s0);
vs_out vs_main(vs_in input) {
	vs_out output;
	output.position = mul(mvp, float4(input.position + float3(input.wobble, 0), 1.0f));
	output.uv = input.uv;
	output.color = input.color;
	return output;
}
float4 ps_main(vs_out input) : SV_TARGET {
	float4 c = tex.Sample(smp, input.uv);
	return c * input.color;
}