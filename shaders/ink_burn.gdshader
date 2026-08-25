// 먹선 껍질(역헐)용 소각 — cel_burn 과 같은 마스크를 써서 구멍이 본체와 정확히 겹친다.
// ⚠️ 반드시 cull_back. 이 헐은 블렌더 Solidify 가 와인딩을 뒤집어 놓은 판이라, 백컬링이
//    **바깥쪽 면을 걸러내는** 역할을 한다 (원본 Mat_border_* 도 기본 cull_back 으로 동작).
//    cull_disabled 로 하면 헐 바깥면이 통째로 그려져 망치 전체가 테두리색으로 덮인다 —
//    실측으로 망치가 소각 내내 갈색 덩어리로 보였던 원인.
shader_type spatial;
render_mode unshaded, cull_back;

#include "res://shaders/burn_noise.gdshaderinc"

uniform vec4 col : source_color = vec4(0.239, 0.2, 0.2, 1.0);
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform float ember_w = 0.05;
uniform float char_w = 0.10;
uniform float noise_scale = 7.0;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float mask = burn_mask(v_local, noise_scale);
	float d = dissolve * (1.0 + ember_w + char_w);
	if (mask < d) {
		discard;
	}
	ALBEDO = col.rgb;
}
