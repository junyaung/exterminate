// 불덩이가 지나간 자리에서 아직 타고 있는 바닥 불 — 카툰판 v2: **겹웅덩이**.
//
// v1 은 같은 외곽선(wob)을 축소해 동심원 띠를 만들었다가 경계가 평행하게 붙어 다녀
// "명확한 레이어층"으로 읽혔다(유저 지적). 이제 바깥/중간/심지가 **각자 다른 위상·주파수로
// 날름거리는 웅덩이**라 경계가 따로 논다 — 불꽃 안에 작은 불꽃, 바닥판.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform vec4 col_hot : source_color = vec4(0.996, 0.882, 0.722, 1.0);   // #fee1b8 심지
uniform vec4 col_mid : source_color = vec4(0.992, 0.820, 0.475, 1.0);   // #fdd179
uniform vec4 col_edge : source_color = vec4(0.871, 0.624, 0.278, 1.0);  // #de9f47 바깥 혀
uniform vec4 ink : source_color = vec4(0.710, 0.349, 0.271, 1.0);       // #b55945 바닥 불의 테
uniform float alpha_mul = 1.0;
uniform float seed = 0.0;
uniform float fps = 8.0;

// 날름거리는 웅덩이 실루엣. sc = 크기, ph = 위상 — 층마다 다르게 줘서 경계가 평행해지지 않는다.
float pool(float r, float a, float sc, float ph, float t) {
	float w = 0.80 + 0.17 * sin(a * 5.0 + ph + t * 3.4)
	               + 0.10 * sin(a * (8.0 + ph * 0.7) - t * 5.8 - ph)
	               + 0.06 * sin(a * 3.0 + t * 1.9 + ph * 2.2);
	w *= sc;
	return 1.0 - smoothstep(w * 0.25, w, r);
}

void fragment() {
	float t = floor(TIME * fps) / fps;
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float flick = 0.82 + 0.18 * sin(t * 15.0 + seed * 2.3);

	float a_edge = pool(r, a, 1.0, seed, t) * flick * alpha_mul;
	float a_mid = pool(r, a, 0.60, seed + 2.3, t) * alpha_mul;
	float a_hot = pool(r, a, 0.32, seed + 5.1, t) * alpha_mul;

	float cut = step(0.34, a_edge);
	float rim = cut - step(0.52, a_edge);

	vec3 c = col_edge.rgb;
	if (a_mid > 0.5) { c = col_mid.rgb; }
	if (a_hot > 0.5) { c = col_hot.rgb * 1.25; }   // 심지만 살짝 bloom

	ALBEDO = mix(c, ink.rgb, rim);
	ALPHA = cut * 0.96;
}
