// 지면 전용 2톤 셀. cel.gdshader 와 문법은 같지만 **밝은 톤을 정점 색에서 받는다** —
// 지면은 흙·이끼·모래가 면마다 다른 색이라 머티리얼 유니폼 한 장으로는 못 칠한다.
//
// ⚠️ 두 가지를 일부러 이렇게 뒀다. 둘 다 "지면이 통째로 안 보이던" 사고의 원인 후보였다:
//   1) **varying 을 쓰지 않는다.** 처음엔 vertex() 에서 varying 에 색을 담아 light() 에서
//      읽었는데, light() 안의 varying 은 렌더러에 따라 컴파일이 막힐 수 있다. 헤드리스는
//      셰이더를 실제로 컴파일하지 않아서 검증으로도 안 걸린다. ALBEDO 에 실어 보낸다.
//   2) **cull_disabled.** 절차 생성 메시의 감기 방향이 뒤집혀 있으면 위에서 볼 때 전부
//      컬링돼 화면에서 사라진다(배경색만 남는다). 지면은 양면으로 그려도 비용이 거의 없다.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled, ambient_light_disabled;

// 불빛이 지형을 물들인다.
#include "res://shaders/fire_light.gdshaderinc"
uniform float fire_gain : hint_range(0.0, 3.0) = 0.55;

// 그늘의 깊이. 면 색에 곱해지므로 0.45 면 그늘이 그 색의 45% 밝기가 된다.
uniform float shade : hint_range(0.0, 1.0) = 0.45;
uniform float threshold : hint_range(0.0, 1.0, 0.01) = 0.34;

void fragment() {
	// 면마다 색이 다르다 — 정점을 공유하지 않게 구웠으므로 보간 없이 면 단색이 된다.
	ALBEDO = COLOR.rgb;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
	// ⚠️ 뷰 공간 → 월드 변환.
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wn = mat3(INV_VIEW_MATRIX) * NORMAL;
	EMISSION = fire_light(wp, wn) * fire_gain;
}

void light() {
	float ndl = dot(normalize(NORMAL), normalize(LIGHT));
	// ATTENUATION 에 그림자가 들어있어, 그림자 진 곳도 어두운 밴드로 딱 떨어진다.
	float lit = step(threshold, ndl * ATTENUATION);
	// DIFFUSE_LIGHT 는 마지막에 ALBEDO 와 곱해진다. 그래서 여기선 **밝기 계수**만 낸다.
	DIFFUSE_LIGHT = vec3(mix(shade, 1.0, lit));
}
