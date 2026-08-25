// 판정 범위 표시 (개발용). 분출 도넛이 **실제로 때리는 띠**를 그대로 그린다.
// 연출이 아니라 계측 도구라 예쁘게 만들 이유가 없다 — 경계가 어디인지만 분명하면 된다.
//
// ⚠️ 메시 UV 규약은 충격파와 같다: U = 중심에서의 거리(0..1), V = 각도.
//    디스크를 **도넛 바깥 반경으로** 구워서 U=1 이 곧 바깥 경계가 되게 한다.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform float inner = 0.2857;   // 안쪽 경계 (바깥 반경 대비 비율)
uniform vec4 col : source_color = vec4(0.404, 0.690, 0.757, 1.0);  // 하늘색 — 게임 팔레트와 섞이지 않게
uniform vec4 edge_col : source_color = vec4(0.945, 0.965, 0.941, 1.0);
uniform float fill_alpha = 0.22;
uniform float alpha_mul = 1.0;
uniform float edge_w = 0.02;    // 경계선 두께 (반경 비율)

void fragment() {
	float r = UV.x;
	if (r < inner || r > 1.0) {
		discard;
	}
	// 경계선: 안쪽·바깥 딱 두 줄. 어디까지 맞는지는 이 두 줄이 말한다.
	float line = step(r, inner + edge_w) + step(1.0 - edge_w, r);
	// 각도 눈금 12개 — 회전과 크기 변화를 눈으로 세기 쉽게
	float ticks = step(0.97, abs(sin(UV.y * TAU * 6.0))) * step(1.0 - edge_w * 3.0, r);
	float mark = clamp(line + ticks, 0.0, 1.0);
	ALBEDO = mix(col.rgb, edge_col.rgb, mark);
	ALPHA = mix(fill_alpha, 0.9, mark) * alpha_mul;
}
