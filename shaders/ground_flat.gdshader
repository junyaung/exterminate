// 평지용 지면 — **색은 고정, 그림자만 받는다.**
//
// 왜 이런 셰이더가 필요했나 (2026-08-16):
//   · 일반 셰이딩(StandardMaterial3D)으로 두면 지면이 통째로 시커멓게 나왔다. 그림자를 꺼도,
//     법선이 전부 위를 봐도 마찬가지였다 — 원인을 좁히지 못한 채 화면만 어두웠다.
//   · unshaded 로 두니 색은 정확히 나왔지만 **그림자가 통째로 사라졌다** (unshaded 는 빛을
//     아예 안 받으므로 그림자도 안 받는다).
//   · 그래서 둘을 갈랐다: 밝기는 N·L 을 **안 보고** 고정하고, ATTENUATION(= 그림자)만 곱한다.
//     평평한 바닥은 어차피 명암이 정보를 주지 않고, 그림자는 물체가 어디 있는지를 알려준다.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled, ambient_light_disabled;

// 불빛이 바닥을 물들인다 (횃불의 가짜 빛웅덩이와 별개 — 이건 폭연·불덩이도 같이 쓴다).
#include "res://shaders/fire_light.gdshaderinc"

uniform vec4 col : source_color = vec4(0.388, 0.780, 0.302, 1.0); // #63c74d (Endesga 32 밝은 잔디)
/// 시간대 색조 — Mood 가 전역으로 뿌린다 (낮/여명/밤).
/// ⚠️ **빛과 그림자를 다른 색으로 칠한다.** 한 가지 색조로 전체를 곱하면 채도가 죽어
///    화면이 탁해진다 (유저 지적 2026-08-17: "색이 탁하고 대비가 낮다").
///    빛은 따뜻하게, 그림자는 차갑게 — 애니메이션 배경화의 기본 문법이다.
global uniform vec4 mood_tint;         // 빛 받는 쪽
global uniform vec4 mood_shadow_tint;  // 그림자 쪽
global uniform float mood_shade;       // 그림자 깊이 (낮을수록 대비가 세다)
/// ⚠️ **지면만** 더 어둡게 하는 배수. 밤을 어둡게 할 때 색조를 통째로 내리면 벌레까지
///    같이 묻힌다 (벌레 밝은 톤이 이미 #3d3333 로 거의 검정이다). 바닥만 내리면
///    실루엣 대비는 오히려 살아난다.
global uniform float mood_ground_mul;
/// 바닥은 면적이 넓어 세게 얹으면 화면이 통째로 주황이 된다 — 벌레보다 낮게 잡는다.
uniform float fire_gain : hint_range(0.0, 3.0) = 0.55;

void fragment() {
	ALBEDO = col.rgb * mood_ground_mul;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
	// ⚠️ 뷰 공간 → 월드 변환 (fragment 의 VERTEX/NORMAL 은 뷰 공간이다).
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wn = mat3(INV_VIEW_MATRIX) * NORMAL;
	EMISSION = fire_light(wp, wn) * fire_gain;
}

void light() {
	// ⚠️ N·L 을 곱하지 않는다. 태양 각도나 법선이 어떻든 밝기가 변하지 않으므로
	//    "왜 어둡지"를 다시 겪지 않는다. 그림자(ATTENUATION)만 남긴다.
	// 그림자: 그림자색 × 깊이 / 빛: 빛색. 둘 사이를 그림자 정도로 섞는다.
	DIFFUSE_LIGHT = mix(mood_shadow_tint.rgb * mood_shade, mood_tint.rgb, ATTENUATION);
}
