cbuffer constants : register(b0) {
	float4x4 mvp;
}
struct vs_in {
	float2 position : position;
	float2 texcoord : texcoord;
	float4 color    : color;
};
struct vs_out {
	float4 position : SV_POSITION;
	float2 texcoord : texcoord;
	float4 color    : color;
};
Texture2D    tex : register(t0);
SamplerState smp : register(s0);
vs_out vs_main(vs_in input) {
	vs_out output;
	output.position = mul(mvp, float4(input.position, 0, 1.0f));
	output.texcoord = input.texcoord;
	output.color = input.color;
	return output;
}
float4 ps_main(vs_out input) : SV_TARGET {
	float4 c = tex.Sample(smp, input.texcoord);
	return c * input.color;
}