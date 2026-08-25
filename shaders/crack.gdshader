// 지면 균열. UV.x 에 "중심에서의 거리"(0~1)가 구워져 있어서,
// wave_pos 를 0 -> 1 로 밀면 빛이 중심에서 바깥으로 번져나간다 (여진 예고).
//
// 먹선(2026-08-13 유저 테스트 요청): 바닥에 붙은 납작한 메시라 역헐이 안 통한다.
// 대신 UV.y 에 "가로 방향 정규화 위치(-1~1)", UV2.x 에 "그 지점의 반폭(월드)"을 구워서
// 가장자리에서 ink_width 만큼 안쪽까지를 먹선으로 칠한다 — 굵기가 균열 두께와 무관하게
// 일정해서 손으로 그은 펜선처럼 읽힌다. ink_width = 0 이면 완전히 꺼진다.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform vec4 base_col : source_color = vec4(0.239, 0.200, 0.200, 1.0);  // #3d3333
uniform vec4 glow_col : source_color = vec4(0.949, 0.722, 0.533, 1.0);  // #f2b888
uniform float wave_pos = -1.0;    // -1 = 꺼짐. 0 -> 1 로 밀면 중심에서 바깥으로.
uniform float wave_width : hint_range(0.02, 1.0, 0.01) = 0.28;
uniform float fade : hint_range(0.0, 1.0, 0.01) = 1.0;
// 분출 순간의 발광 배율. 1.0 을 넘기면 환경 glow(bloom)가 번진다.
uniform float boost = 1.0;
// 평상시 잔열. **기본은 0 = 그냥 검은 균열.**
// 불 속성 카드가 여진과 결합했을 때 켜는 훅 (0.9 면 bloom 문턱 1.1 바로 아래라
// 번지진 않고 은은히 빛나고, 분출 때 boost 가 곱해지며 폭발적으로 번진다).
uniform float ember : hint_range(0.0, 3.0, 0.05) = 0.0;
// 먹선. 색은 게임 공통 잉크 #14233a, 굵기는 월드 단위(0 = 끔).
uniform vec4 ink_col : source_color = vec4(0.078, 0.137, 0.227, 1.0);
uniform float ink_width : hint_range(0.0, 0.3, 0.005) = 0.0;

void fragment() {
	// 여진 예고 파동 — 중심에서 바깥으로 지나가는 밝은 띠
	float g = 1.0 - smoothstep(0.0, wave_width, abs(UV.x - wave_pos));
	// 잔열 — 충돌 지점(UV.x=0)이 가장 뜨겁고 갈래 끝으로 갈수록 식는다.
	// sin 위상에 UV.x 를 섞어 일렁임이 균열을 따라 흐르게 한다.
	float heat = 1.0 - smoothstep(0.0, 0.9, UV.x);
	heat *= 0.88 + 0.12 * sin(TIME * 1.6 + UV.x * 6.0);

	vec3 c = mix(base_col.rgb, glow_col.rgb, g);
	c += glow_col.rgb * heat * ember;

	// 가장자리까지 남은 거리(월드). UV.y 는 -1~1, UV2.x 는 그 지점의 반폭.
	float d_edge = (1.0 - abs(UV.y)) * UV2.x;
	float ink = ink_width > 0.0
		? 1.0 - smoothstep(ink_width * 0.55, ink_width, d_edge)
		: 0.0;
	// 먹선은 boost 를 **곱하지 않는다** — 분출로 균열이 확 밝아져도 선은 검게 남아야
	// 카툰 문법이 유지된다.
	ALBEDO = mix(c * boost, ink_col.rgb, ink);
	ALPHA = base_col.a * fade;
}
