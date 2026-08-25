// 불덩이가 굴러가며 남기는 그을린 자국.
// PlaneMesh 에 단색을 칠하면 사각형 도장이 찍힌 것처럼 보인다 —
// 가장자리를 울퉁불퉁하게 깎아내고 부드럽게 사라지게 해야 탄 자국으로 읽힌다.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform vec4 col : source_color = vec4(0.710, 0.349, 0.271, 1.0);       // #b55945 그을림
uniform vec4 glow_col : source_color = vec4(0.922, 0.588, 0.380, 1.0);  // #eb9661 아직 타는 중
uniform float glow = 1.6;        // 갓 지나간 자국은 벌겋다. 식으면서 0 으로.
uniform float alpha_mul = 1.0;
uniform float seed = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	// 가장자리 반경을 각도에 따라 흔든다 — 완전한 원도, 사각형도 아니게
	float wob = 0.84 + 0.13 * sin(a * 4.0 + seed) + 0.06 * sin(a * 7.0 + seed * 1.7);
	float edge = 1.0 - smoothstep(wob * 0.45, wob, r);
	// 가운데가 더 뜨겁다
	float hot = 1.0 - smoothstep(0.0, wob * 0.75, r);
	ALBEDO = mix(col.rgb, glow_col.rgb * glow, hot * clamp(glow, 0.0, 1.0));
	ALPHA = edge * alpha_mul * col.a;
}
