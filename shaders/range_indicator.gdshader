// 공격 범위 표시 — 오렌지(endesga #f77622) 원, 외곽선은 점선.
// ⚠️ 지면(#89a477)과 **명도가 거의 같다**(상대휘도 0.329 vs 0.332). 색상·채도로만 갈리므로
//    점선을 더 얇게 하거나 배경이 밝아지면 경계가 무르게 보인다 — 그땐 먹선을 한 겹 두를 것.
// 점선이 천천히 회전해서 "조준 중" 이라는 게 살아 보인다.
//
// 바깥 고리 = **우클릭 쿨타임** (유저 아이디어 2026-08-14). 화면 구석의 도넛은 전투 중에
// 눈이 안 가지만, 조준 원은 커서를 따라다니므로 항상 시야 안에 있다. 거기에 얹으면
// "지금 우클릭 되나?"를 곁눈으로 안다.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform vec4 col : source_color = vec4(0.969, 0.463, 0.133, 1.0); // #f77622
uniform float dash_count = 28.0;   // 점선 개수
uniform float ring_width = 0.07;   // 외곽선 두께 (반지름 비율)
uniform float fill_alpha = 0.10;   // 안쪽 채움 투명도
uniform float spin_speed = 0.05;   // 점선 회전 속도 (rev/s)
uniform float alpha_mul = 1.0;     // 쿨다운 중 어둡게 (스크립트에서 조절)

// ⚠️ **아래 세 값은 스크립트와 짝이다.** 쿨 고리를 그리려면 사각형이 사거리보다 커야 하므로,
//    실제 사거리는 쿼드의 aim_r 지점이다. HammerStrike 가 scale = 사거리 / AIM_R 로 키운다 —
//    한쪽만 바꾸면 조준 원이 실제 사거리와 어긋난다.
uniform float aim_r = 0.86;        // 이 반지름이 곧 실제 공격 사거리
uniform float cd_gap = 0.05;       // 점선 고리와 쿨 고리 사이 틈
uniform float cd_width = 0.06;     // 쿨 고리 두께

uniform vec4 cd_col : source_color = vec4(0.710, 0.349, 0.271, 1.0); // #b55945 (쿨다운 HUD 의 R 과 같은 색)
uniform float cd_ratio = 1.0;      // 0 = 방금 씀, 1 = 준비 완료
uniform float cd_ready_alpha = 0.5;// 다 찼을 때 고리 진하기 — 차는 동안(0.9)보다 낮춰 '대기 중'으로 읽힌다

// --- 지면에 붙이기 (유저 지시 2026-08-16: "커서가 기울어진 면적에 맞춰서") ---
// 평평한 쿼드는 경사에서 절반이 땅에 파묻힌다. 정점마다 **그 자리 지면 높이**를 읽어
// 올려주면 조준 원이 지형을 타고 흐른다.
// ⚠️ 노드의 세로 스케일이 1 이어야 한다 (HammerStrike 가 xz 만 키운다). 그래야 로컬에서
//    더한 값이 월드에서 그대로 같은 높이가 된다.
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform float terrain_half = 160.0;   // 높이 격자가 덮는 범위 (Ground.HALF)
uniform float lift = 0.06;            // 지면에서 살짝 띄우기 (z-파이팅 방지)
uniform bool conform = false;         // 지형이 없을 땐 끈다

void vertex() {
	if (conform) {
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec2 uv = (wp.xz + vec2(terrain_half)) / (terrain_half * 2.0);
		float h = texture(height_tex, uv).r;
		// 모델 원점의 높이를 빼야 "지면 높이 + lift" 에 정확히 놓인다.
		VERTEX.y += h + lift - MODEL_MATRIX[3].y;
	}
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float outer = aim_r;
	float inner = outer - ring_width * aim_r;

	// 점선 외곽선
	float ring = smoothstep(inner - 0.015, inner, r) * (1.0 - smoothstep(outer, outer + 0.015, r));
	float ang = atan(p.y, p.x) / TAU + 0.5 + TIME * spin_speed;
	float dash = step(fract(ang * dash_count), 0.55);

	// 안쪽 옅은 채움
	float fill = (1.0 - smoothstep(inner - 0.03, inner, r)) * fill_alpha;

	// 바깥 쿨타임 고리 — 12시에서 시계방향으로 찬다.
	// atan 은 +x 에서 반시계로 도므로, 12시 시작·시계방향으로 바꾸려면 부호를 뒤집고 1/4 돌린다.
	float ci = outer + cd_gap;
	float co = ci + cd_width;
	float band = smoothstep(ci - 0.012, ci, r) * (1.0 - smoothstep(co, co + 0.012, r));
	float t = fract((-atan(p.x, p.y)) / TAU + 1.0);   // 0 = 12시, 시계방향으로 1 까지
	float filled = step(t, cd_ratio);
	float ready = step(0.999, cd_ratio);
	// 다 찼으면 고리 전체를 옅게, 차는 중이면 채워진 호만 진하게
	float cd_a = band * mix(filled * 0.9, cd_ready_alpha, ready);

	// 쿨 고리는 alpha_mul(좌클릭 쿨다운으로 흐려지는 것)에 **휘둘리지 않는다** —
	// 좌클릭이 쿨이라고 우클릭 정보까지 흐려지면 이걸 여기 붙인 의미가 없다.
	vec3 c = mix(col.rgb, cd_col.rgb, step(ci - 0.012, r));
	ALBEDO = c;
	ALPHA = max(max(ring * dash, fill) * col.a * alpha_mul, cd_a * cd_col.a);
}
