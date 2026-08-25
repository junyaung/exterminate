// cel.gdshader 의 페이드 가능 변형 — 분출 바위처럼 알파로 사라지는 물건 전용.
// 본체 cel 에 ALPHA 를 넣지 않는 이유: ALPHA 를 쓰는 순간 투명 파이프라인으로 넘어가
// 화면의 모든 개미가 정렬 비용을 치른다. 사라져야 하는 소수만 이 셰이더를 쓴다.
shader_type spatial;
// ⚠️ depth_draw_always 가 핵심이다. 이 물건들은 **역헐 먹선 껍질**을 뒤에 달고 있는데,
// 껍질 안쪽 면은 실루엣 전체를 덮는다. 본체가 불투명일 땐 가려서 안 보이지만, 알파로
// 사라지기 시작하면 그 검은 껍질이 비쳐 **검은 실루엣**이 뜬다 (유저 지적 2026-08-13).
// 본체가 깊이를 쓰면 껍질 안쪽이 깊이 테스트에서 걸러지고 테두리만 남는다.
// 껍질 쪽에는 render_priority 를 한 단계 높여 본체 **뒤에** 그리도록 맞춰야 한다.
render_mode cull_back, diffuse_lambert, specular_disabled, ambient_light_disabled,
	depth_draw_always;

uniform vec4 light_tone : source_color = vec4(0.529, 0.522, 0.486, 1.0); // #87857c
uniform vec4 dark_tone : source_color = vec4(0.388, 0.400, 0.388, 1.0);  // #636663
uniform float threshold : hint_range(0.0, 1.0, 0.01) = 0.37;
uniform float alpha_mul : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	ALBEDO = vec3(1.0);
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
	ALPHA = alpha_mul;
}

void light() {
	float ndl = dot(normalize(NORMAL), normalize(LIGHT));
	float lit = step(threshold, ndl * ATTENUATION);
	DIFFUSE_LIGHT = mix(dark_tone.rgb, light_tone.rgb, lit);
}
