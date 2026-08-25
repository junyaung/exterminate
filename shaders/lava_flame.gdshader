// 분화구 균열에서 솟는 용암 불길 — **부드러운 VFX 판** (유저 지시: "카툰 말고 그냥 vfx 불꽃").
// flame_jet(카툰 겹불꽃)과 반대 문법이다: 스텝 타임 없음, 하드 컷 없음, 잉크 림 없음.
// 매끄러운 그라데이션 + 연속 시간 흔들림 + 부드러운 알파 감쇠 = 일렁이는 불.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform vec4 col_root : source_color = vec4(0.992, 0.820, 0.475, 1.0); // #fdd179
uniform vec4 col_mid : source_color = vec4(0.922, 0.588, 0.380, 1.0);  // #eb9661
uniform vec4 col_tip : source_color = vec4(0.710, 0.349, 0.271, 1.0);  // #b55945
uniform float seed = 0.0;
uniform float intensity = 1.35;  // 뿌리만 살짝 bloom 문턱(1.1)을 넘는다
uniform float alpha_mul = 0.0;   // 스크립트가 페이드 인/아웃
// 실루엣 가장자리 먹선 (UV 단위). **기본 0 = 꺼짐** —
// 이 셰이더는 폭연(Deflagration)도 쓰는데 그 룩은 손대지 말라는 지시가 있어서,
// 켜는 쪽(여진 분출 화염)에서만 값을 넣는다.
uniform vec4 ink_col : source_color = vec4(0.078, 0.137, 0.227, 1.0);  // #14233a
uniform float ink_width : hint_range(0.0, 0.2, 0.005) = 0.0;

void fragment() {
	// QuadMesh UV: y=1 이 아래(뿌리). up = 뿌리 0 -> 끝 1
	float up = 1.0 - UV.y;
	// 연속 시간 흔들림 — 위로 갈수록 크게 휜다
	float wob = sin(TIME * 9.0 + seed + up * 7.0) * 0.14 * up;
	float x = UV.x - 0.5 - wob;
	// 실루엣: 아래는 넓고 위는 뾰족
	float half_w = mix(0.46, 0.10, up);
	float body = 1.0 - smoothstep(half_w * 0.5, half_w, abs(x));
	float flick = 0.8 + 0.2 * sin(TIME * 16.0 + seed * 3.1);

	vec3 c = mix(col_root.rgb, col_mid.rgb, smoothstep(0.0, 0.45, up));
	c = mix(c, col_tip.rgb, smoothstep(0.45, 1.0, up));

	float a = body * (1.0 - up * up * 0.55) * flick * alpha_mul;
	// 먹선: 실루엣 경계(|x| = half_w) 안쪽 ink_width 만큼. 불꽃은 가장자리가 부드럽게
	// 사라지므로 **선 부분의 알파를 따로 올려야** 선이 흐리멍덩해지지 않는다.
	float edge = half_w - abs(x);
	float ink = ink_width > 0.0
		? (1.0 - smoothstep(ink_width * 0.35, ink_width, edge)) * step(0.0, edge)
		: 0.0;
	ALBEDO = mix(c * intensity, ink_col.rgb, ink);
	ALPHA = max(a, ink * alpha_mul * flick * 0.95);
}
