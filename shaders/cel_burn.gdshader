// 우클릭 특수 망치의 소각 — 종이가 타듯 노이즈 경계가 쓸고 지나가며 사라진다.
// 알파 페이드가 아니라 **discard 디졸브**다. 이유가 둘:
//   1) 불투명 파이프라인에 남아서 타는 동안에도 그림자를 드리운다 (구멍도 그림자에 뚫린다)
//   2) "옅어진다"가 아니라 "갉아먹힌다"로 읽힌다 — 타는 것의 문법
// 구멍 가장자리는 두 겹: 얇은 잉걸(발광 주홍) + 그 바깥의 그을음(탄 종이색).
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled, ambient_light_disabled;

#include "res://shaders/burn_noise.gdshaderinc"

uniform vec4 light_tone : source_color = vec4(0.733, 0.765, 0.816, 1.0);
uniform vec4 dark_tone : source_color = vec4(0.388, 0.400, 0.388, 1.0);
uniform float threshold : hint_range(0.0, 1.0, 0.01) = 0.37;
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform vec4 char_col : source_color = vec4(0.239, 0.2, 0.2, 1.0);     // #3d3333 탄 자국
uniform vec4 ember_col : source_color = vec4(0.922, 0.588, 0.380, 1.0); // #eb9661 = 게임의 불 색
uniform float ember_energy = 2.2;   // bloom 문턱 위 — 잉걸이 살짝 발광한다 (피격 플래시와 동일)
uniform float ember_w = 0.05;
uniform float char_w = 0.10;
uniform float noise_scale = 7.0;

// ⚠️ 구역 판정을 fragment 에서 varying 에 써서 light() 로 넘기면 안 된다 — 실측으로
//    light() 가 항상 그을음 분기를 타서 망치 전체가 탄 색이 됐다 (fragment 가 쓴 varying 을
//    light 가 읽는 게 이 환경에선 미덥지 않다). vertex 가 쓴 v_local 은 확실하므로,
//    light() 에서 마스크를 **다시 계산**한다. 값노이즈 한 번이라 비용은 미미하다.
varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float mask = burn_mask(v_local, noise_scale);
	// dissolve 1.0 에 잉걸·그을음 밴드까지 다 쓸려나가도록 범위를 늘려 잡는다
	float d = dissolve * (1.0 + ember_w + char_w);
	if (mask < d) {
		discard;
	}
	ALBEDO = vec3(1.0);
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
	if (mask < d + ember_w) {
		EMISSION = ember_col.rgb * ember_energy;
	}
}

void light() {
	float mask = burn_mask(v_local, noise_scale);
	float d = dissolve * (1.0 + ember_w + char_w);
	if (mask < d + ember_w) {
		DIFFUSE_LIGHT = vec3(0.0);            // 잉걸은 EMISSION 만 — 조명이 섞이면 탁해진다
	} else if (mask < d + ember_w + char_w) {
		DIFFUSE_LIGHT = char_col.rgb;         // 그을음은 조명 무시 — 탄 자리는 빛을 안 받는다
	} else {
		// 평소의 cel 2톤 밴딩 (cel.gdshader 와 동일)
		float ndl = dot(normalize(NORMAL), normalize(LIGHT));
		float lit = step(threshold, ndl * ATTENUATION);
		DIFFUSE_LIGHT = mix(dark_tone.rgb, light_tone.rgb, lit);
	}
}
