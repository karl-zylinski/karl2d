cbuffer constants : register(b0) {
	float4x4 projection;
}
struct vs_in {
	float3 position : POS;
};
struct vs_out {
	float4 position : SV_POSITION;
};
vs_out vs_main(vs_in input) {
	vs_out output;
	output.position = mul(projection, float4(input.position, 1.0f));
	return output;
}
float4 ps_main(vs_out input) : SV_TARGET {
	return float4(1,1,1,1);
}