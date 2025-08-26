cbuffer constants : register(b0) {
	float4x4 mvp;
}
struct vs_in {
	float2 position : POS;
	float2 uv       : UV;
	float4 color    : COL;
};
struct vs_out {
	float4 position : SV_POSITION;
	float2 uv       : UV;
	float4 color    : COL;
};
Texture2D    tex : register(t0);
SamplerState smp : register(s0);
vs_out vs_main(vs_in input) {
	vs_out output;
	output.position = mul(mvp, float4(input.position, 0, 1.0f));
	output.uv = input.uv;
	output.color = input.color;
	return output;
}
float4 ps_main(vs_out input) : SV_TARGET {
	float4 c = tex.Sample(smp, input.uv);
	return c * input.color;
}