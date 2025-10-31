cbuffer constants : register(b0) {
	float4x4 mvp;

	float seconds;
	float2 size;
	float freqX;
	float freqY;
	float ampX;
	float ampY;
	float speedX;
	float speedY;
}
struct vs_in {
	float3 position : POS;
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
	float pixelWidth = 1.0/size.x;
	float pixelHeight = 1.0/size.y;
	float aspect = pixelHeight/pixelWidth;
	float boxLeft = 0.0;
	float boxTop = 0.0;

	float2 p = input.uv;
    p.x += cos((input.uv.y - boxTop)*freqX/(pixelWidth*750.0) + (seconds*speedX))*ampX*pixelWidth;
    p.y += sin((input.uv.x - boxLeft)*freqY*aspect/(pixelHeight*750.0) + (seconds*speedY))*ampY*pixelHeight;

	float4 c = tex.Sample(smp, p);
	return c * input.color;
}