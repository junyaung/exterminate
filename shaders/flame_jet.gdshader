// 화염 혀 — 카툰판 v2: **겹불꽃(nested flames)**.
//
// v1 은 색을 수평 띠(up 기준 if)로 잘랐다가 "명확한 레이어층"으로 읽혀 폐기(유저 지적).
// 카툰 불의 정석은 불꽃 안에 작은 불꽃 — 바깥(검붉음)·중간(주홍)·심지(금색)가
// **각자 불꽃 모양 실루엣**이고, 흔들리는 위상이 서로 달라 경계가 평행하게 붙어 다니지 않는다.
//
// 유지되는 카툰 문법: 8fps 스텝 타임 / 하드 컷 / 바깥 실루엣에만 잉크 림.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform vec4 col_core : source_color = vec4(0.992, 0.820, 0.475, 1.0); // #fdd179 심지
uniform vec4 col_mid : source_color = vec4(0.922, 0.588, 0.380, 1.0);  // #eb9661
uniform vec4 col_out : source_color = vec4(0.710, 0.349, 0.271, 1.0);  // #b55945 바깥
uniform vec4 ink : source_color = vec4(0.451, 0.298, 0.267, 1.0);      // #734c44 외곽 테
uniform float seed = 0.0;        // 불꽃마다 다른 위상
uniform float intensity = 1.3;   // 심지만 살짝 bloom 문턱(1.1)을 넘는다
uniform float alpha_mul = 0.0;   // 스크립트가 페이드 — 하드 컷이라 "줄어들며 꺼진다"
uniform float fps = 8.0;         // 스텝 타임 프레임률

// 불꽃 실루엣 하나. wm/hm = 폭/높이 배율, ph = 흔들림 위상 오프셋.
// 안쪽 불꽃일수록 작고(wm·hm↓) 위상이 달라(ph) 경계가 따로 논다.
float flame(float x, float up, float wm, float hm, float ph, float t) {
	float u = clamp(up / hm, 0.0, 1.0);
	// 위로 갈수록 크게 휜다. 층마다 주파수도 살짝 다르게(+ph*0.3) — 평행 경계 방지의 핵심
	float wob = sin(t * (9.0 + ph * 0.3) + seed + ph + u * 7.0) * 0.14 * u;
	float hw = mix(0.46, 0.10, u) * wm;
	return (1.0 - smoothstep(hw * 0.5, hw, abs(x - wob))) * step(up, hm);
}

void fragment() {
	float t = floor(TIME * fps) / fps;
	float up = 1.0 - UV.y;          // 뿌리 0 -> 끝 1
	float x = UV.x - 0.5;
	float flick = 0.85 + 0.15 * sin(t * 16.0 + seed * 3.1);

	float a_out = flame(x, up, 1.0, 1.0, 0.0, t) * flick * alpha_mul;
	float a_mid = flame(x, up, 0.64, 0.72, 3.7, t) * alpha_mul;
	float a_core = flame(x, up, 0.36, 0.44, 8.1, t) * alpha_mul;

	float cut = step(0.30, a_out);
	float rim = cut - step(0.48, a_out);   // 바깥 실루엣에만 잉크 테

	vec3 c = col_out.rgb;
	if (a_mid > 0.5) { c = col_mid.rgb; }
	if (a_core > 0.5) { c = col_core.rgb * intensity; }

	ALBEDO = mix(c, ink.rgb, rim);
	ALPHA = cut;
}
