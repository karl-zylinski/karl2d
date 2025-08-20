cbuffer constants : register(b0) {
	float4x4 mvp;
}
struct vs_in {
	float2 position : POS;
	float4 color    : COL;
};
struct vs_out {
	float4 position : SV_POSITION;
	float4 color    : COL;
};
vs_out vs_main(vs_in input) {
	vs_out output;
	output.position = mul(mvp, float4(input.position, 0, 1.0f));
	output.color = input.color;
	return output;
}
float4 ps_main(vs_out input) : SV_TARGET {
	return input.color;
}