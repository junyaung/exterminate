// 하늘에서 떨어지는 물건의 낙하 그림자 (우클릭 특수 공격 예고).
// 조준 원(range_indicator)의 점선과 달리 **면**으로 읽혀야 한다.
// 점선이면 "여기를 노린다", 그림자면 "여기로 떨어진다" 다.
//
// ⚠️ 처음엔 가장자리를 흐리게 빼고 테두리를 한 겹 더 얹었는데, 옅은 띠가 지저분했다
// (유저 지적 2026-08-13). 원 안쪽은 **어디서나 같은 농도**여야 그림자로 읽힌다.
// 경계의 smoothstep 은 그라데이션이 아니라 계단 현상만 없애는 폭이다 (2% 반경).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform vec4 col : source_color = vec4(0.094, 0.078, 0.145, 1.0);  // endesga #181425
uniform float strength = 0.5;   // 원 전체의 농도 (안쪽이 균일하다)

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	ALBEDO = col.rgb;
	ALPHA = (1.0 - smoothstep(0.98, 1.0, r)) * strength;
}
