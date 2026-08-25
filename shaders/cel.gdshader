// 2톤 셀 셰이더 — 블렌더의 Shader to RGB + Constant ColorRamp 를 Godot로 옮긴 것.
// 색을 light() 에서 직접 확정하므로 팔레트 hex 가 화면에 그대로 나온다.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled, ambient_light_disabled;

// 불빛(횃불·폭연·불덩이)이 벌레를 물들인다. light() 는 건드리지 않는다 — 자세한 건 include 주석에.
#include "res://shaders/fire_light.gdshaderinc"
// 벌레는 몸이 거의 검정(#3d3333)이라 조금만 얹어도 확 읽힌다. 지면보다 약하게 잡는다.
uniform float fire_gain : hint_range(0.0, 3.0) = 0.85;

// source_color 힌트가 붙은 값은 sRGB 로 적어야 한다 (Godot 이 linear 로 변환해 준다).
uniform vec4 light_tone : source_color = vec4(0.733, 0.765, 0.816, 1.0); // #bbc3d0
uniform vec4 dark_tone : source_color = vec4(0.388, 0.400, 0.388, 1.0);  // #636663

// 밴드 경계. 순수 N·L 기준이라 광량(light_energy)을 바꿔도 경계가 흔들리지 않는다.
uniform float threshold : hint_range(0.0, 1.0, 0.01) = 0.37;

// 폭연 예열. 0 = 평소(기존 룩 그대로), 1 = 금색으로 달아올라 bloom 문턱(1.1)을 넘는다.
// 시체가 부풀 때 스크립트가 사본 머티리얼에서 올린다 — 공유 머티리얼에선 항상 0.
uniform float heat : hint_range(0.0, 1.0) = 0.0;

// 피격 플래시. 맞은 개체만 확 달았다 식는다. 색은 피해의 종류를 말한다 —
// 주홍 #eb9661 = 불(폭연·불덩이), 흰색 #f1f6f0 = 물리 타격(분출 바위).
// ⚠️ **둘 다 instance uniform 이어야 한다.** 머티리얼은 몹 종류별로 공유되므로 일반 uniform 에
// 쓰면 화면의 같은 종류가 전부 같이 번쩍인다. set_instance_shader_parameter 로 개체별로 넣는다.
instance uniform float flash = 0.0;
instance uniform vec4 flash_col = vec4(0.922, 0.588, 0.380, 1.0);
uniform float flash_energy = 2.2;   // bloom 문턱(1.1) 위 — 맞는 순간 잠깐 발광한다

// 시간대 색조 (Mood). ⚠️ 한 색으로 전체를 곱하면 채도가 죽어 탁해진다 —
// **밝은 밴드는 빛색, 어두운 밴드는 그림자색**으로 갈라 칠해야 대비와 색감이 산다.
global uniform vec4 mood_tint;
global uniform vec4 mood_shadow_tint;

void fragment() {
	// 실제 색은 전부 light() 가 정한다. ALBEDO 는 마지막에 곱해지므로 흰색으로 둔다.
	ALBEDO = vec3(1.0);
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
	// 플래시는 EMISSION 으로 얹는다 — light() 밖이라 셀 밴딩을 건드리지 않고,
	// 조명이 안 닿는 어두운 면에서도 똑같이 보인다(검은 개미라 이게 중요하다).
	// 불빛은 EMISSION 에 **더한다**. light() 밖이라 셀 밴딩을 안 건드리고,
	// 조명이 안 닿는 뒷면에서도 똑같이 물든다 (검은 개미라 이게 중요하다 — 플래시와 같은 이유).
	// ⚠️ fragment() 의 VERTEX/NORMAL 은 **뷰 공간**이다. 불 위치는 월드 좌표로 넘어오므로
	//    INV_VIEW_MATRIX 로 월드로 돌려서 비교해야 한다. 안 그러면 불빛이 카메라를 따라다닌다.
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wn = mat3(INV_VIEW_MATRIX) * NORMAL;
	EMISSION = flash_col.rgb * (flash * flash_energy) + fire_light(wp, wn) * fire_gain;
}

void light() {
	float ndl = dot(normalize(NORMAL), normalize(LIGHT));
	// ATTENUATION 에 그림자가 들어있어, 그림자 진 곳도 어두운 밴드로 딱 떨어진다.
	float lit = step(threshold, ndl * ATTENUATION);
	// += 가 아니라 = : 라이트가 늘어도 두 색 밖으로 새지 않게 고정한다.
	// 두 밴드에 각각 다른 시간대 색을 입힌다 (빛=따뜻, 그림자=차가움).
	vec3 base = mix(dark_tone.rgb * mood_shadow_tint.rgb, light_tone.rgb * mood_tint.rgb, lit);
	// 달궈짐: 톤을 금색(#fdd179)으로 밀며 밝기를 끌어올린다. heat 1 = 2.6배 = HDR glow.
	vec3 hot = vec3(0.992, 0.820, 0.475) * (1.0 + heat * 1.6);
	DIFFUSE_LIGHT = mix(base, hot, heat);
}
