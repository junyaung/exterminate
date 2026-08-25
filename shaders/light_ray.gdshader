// 분출 순간 균열 틈새에서 솟는 빛줄기.
// 뿌리(아래)가 진하고 위로 갈수록 사라지는 세로 쿼드. blend_add 라 겹칠수록 밝아진다.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled;

uniform vec4 col : source_color = vec4(0.992, 0.820, 0.475, 1.0); // nice31 #fdd179
uniform float intensity = 2.2;   // 1.0 을 넘겨 환경 glow(bloom)를 일으킨다
uniform float alpha_mul = 0.0;   // 스크립트가 페이드 인/아웃

void fragment() {
	// QuadMesh UV: y=0 이 위, y=1 이 아래. 뿌리(아래)가 밝다.
	float v = UV.y * UV.y;
	// 좌우 가장자리는 부드럽게
	float edge = 1.0 - abs(UV.x * 2.0 - 1.0);
	ALBEDO = col.rgb * intensity;
	ALPHA = v * edge * alpha_mul * col.a;
}
