// 망치 충격파. 2026-08-10 영상 학습 노트의 결론을 그대로 구현한 것이다
// (gamedev/video_study_notes_2026-08-10.md 참고):
//   ① "애니 에너지 구체" 편 — Mask 임계값을 올려서 형태를 **부순다**.
//      영상은 모디파이어로 굽지만, 우리는 굽지 않고 프래그먼트에서 문턱을 올린다.
//   ② "VFX 텍스처" 편의 Godot NoiseTexture2D(Cellular) — 부서지는 **단위**가
//      셀 하나가 되게 한다. 텍스처를 굽지 않고 셰이더 안에서 셀을 만든다.
// 매끈하게 옅어지는 링은 CG 티가 난다. 조각으로 흩어져야 "땅이 밀려났다"로 읽힌다.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

// ⚠️ 메시 UV 규약: U = 중심에서의 거리(0..1), V = 각도(0..1 한 바퀴).
//    hammer_strike._shockwave_mesh() 가 그렇게 구워 준다. PlaneMesh 를 끼우면 안 된다.
uniform float t = 0.0;            // 진행도 0 → 1. 스크립트가 트윈한다.
uniform vec4 core_col : source_color = vec4(0.992, 0.820, 0.475, 1.0); // #fdd179 링 심지
uniform vec4 edge_col : source_color = vec4(0.949, 0.722, 0.533, 1.0); // #f2b888 링 몸통
uniform vec4 dust_col : source_color = vec4(0.922, 0.588, 0.380, 1.0); // #eb9661 흩어지는 꼬리
uniform vec4 hot_col : source_color = vec4(0.996, 0.882, 0.722, 1.0);  // #fee1b8 앞머리 심지
uniform float cells_a = 44.0;     // 둘레 방향 셀 수. **정수여야** 이음매가 안 보인다.
uniform float cells_r = 5.0;      // 반경 방향 셀 수
uniform float break_from = 0.22;  // 이 진행도부터 부서지기 시작한다
uniform float w_start = 0.18;     // 처음 링 두께 (반경 비율)
uniform float w_end = 0.05;       // 끝날 때 링 두께
uniform float edge_hard = 0.10;   // 앞머리 경사. 작을수록 칼같이 선다.
uniform float wobble = 0.45;      // 원을 찌그러뜨리는 정도. 0 이면 정원.
uniform float streaks = 16.0;     // 방사형 힘줄 개수. **정수여야** 이음매가 안 보인다.
uniform float streak_push = 0.05; // 힘줄이 고리를 앞으로 밀어내는 정도
uniform float wash_alpha = 0.38;  // 고리 안쪽에 남는 흙먼지 장막의 진하기
uniform float boost = 2.4;        // 앞머리 밝기. 1.1 을 넘겨야 블룸(main.tscn)에 걸린다.
uniform float seed = 0.0;
// 위 기본값은 2026-08-18 A/B 렌더 비교에서 유저가 고른 값이다 (tools/preview_shockwave.gd).
// 두껍고 흐물한 A 안은 감자 모양으로 읽혔다 — 얇고 앞머리가 선 쪽이 '밀려나간다'로 읽힌다.

vec2 cell_hash(vec2 c) {
	// 둘레 방향은 감긴다 — mod 를 걸지 않으면 0도와 360도 셀이 달라져 이음매가 선으로 보인다
	c.x = mod(c.x, cells_a);
	vec2 p = vec2(dot(c, vec2(127.1, 311.7)), dot(c, vec2(269.5, 183.3)));
	return fract(sin(p + seed) * 43758.5453);
}

// F1 보로노이. 반환값 대신 **어느 셀에 속했는지**가 필요하다 —
// 조각이 픽셀 단위로 스러지면 노이즈로 보이고, 셀 단위로 통째로 사라져야 파편으로 보인다.
vec2 voronoi_cell(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	vec2 best = n;
	float md = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = cell_hash(n + g);
			float d = length(g + o - f);
			if (d < md) {
				md = d;
				best = n + g;
			}
		}
	}
	return best;
}

void fragment() {
	float r = UV.x;
	float ang = UV.y * TAU;

	// 링 반경: 튀어나갔다가 느려진다 (Tween 의 QUAD/EASE_OUT 과 같은 곡선)
	float rad = 1.0 - (1.0 - t) * (1.0 - t);
	// 완전한 동심원은 도장 찍은 티가 난다 — 각도에 따라 살짝 찌그러뜨린다
	rad *= 1.0 + wobble * (-0.06 + 0.06 * sin(ang * 3.0 + seed)
		+ 0.03 * sin(ang * 5.0 - seed * 1.7));

	// 방사형 힘줄. 각도마다 고리가 삐죽 앞서 나가고 그 자리가 더 두껍고 밝게 탄다 —
	// 균일한 고리는 아무리 밝혀도 도넛으로 읽힌다. 밀어내는 힘은 결이 있어야 보인다.
	float sp = pow(0.5 + 0.5 * sin(ang * streaks + seed * 2.0), 3.0);
	rad *= 1.0 + streak_push * sp;

	// 폭은 퍼질수록 좁아진다. 처음엔 두껍게 밀려나고 끝엔 실처럼 남는다.
	float w = mix(w_start, w_end, t) * (1.0 + 0.20 * sp);

	// d: -1 꼬리 .. 0 링 중심 .. +1 앞머리
	float d = (r - rad) / w;
	float lead = 1.0 - smoothstep(0.0, edge_hard, d);   // 앞머리는 칼같이 선다
	float tail = smoothstep(-1.0, -0.10, d);            // 뒤는 길게 끌린다
	float band = lead * tail;

	// --- 부수기 ---
	vec2 cell = voronoi_cell(vec2(UV.y * cells_a, r * cells_r));
	float cv = cell_hash(cell + 7.0).x;            // 셀마다 고정된 0..1 값
	float thr = smoothstep(break_from, 1.05, t);
	// 꼬리 쪽이 먼저 무너진다 — 앞머리가 마지막까지 남아야 '밀고 나간다'로 읽힌다
	thr *= 1.0 + max(0.0, -d) * 0.6;
	float alive = step(thr, cv);

	float fade = 1.0 - smoothstep(0.78, 1.0, t);
	float ring_a = band * alive * fade;

	// 밀려난 흙 장막. 고리 **바로 뒤**에 깔렸다가 중심 쪽으로 갈수록 옅어진다.
	// ⚠️ 안쪽 전체를 덮으면 안 된다 — 처음엔 그렇게 짰다가 고리 안이 통째로 허연
	//    원판이 돼서 정작 고리가 안 보였다 (2026-08-18 렌더로 확인). d<0 쪽으로만,
	//    지수로 빠르게 떨군다. 셀로 부수지도 않는다 — 통째로 걷혀야 '지나간 자리'다.
	float veil = d < 0.0 ? exp(d * 0.30) : 0.0;
	float wash = veil * wash_alpha * (1.0 - t) * fade;

	float a = max(ring_a, wash);
	if (a < 0.01) {
		discard;
	}

	vec3 c = mix(edge_col.rgb, core_col.rgb, smoothstep(0.45, 1.0, band));
	c = mix(c, dust_col.rgb, clamp(-d, 0.0, 1.0));  // 흩어지는 꼬리는 흙먼지 색
	// 앞머리 심지만 1 을 넘긴다 — 여기만 블룸에 걸려서 고리가 "탄다"로 보인다
	float rim = smoothstep(-0.30, -0.02, d) * lead * alive;
	c = mix(c, hot_col.rgb * boost, rim * (0.55 + 0.45 * sp));
	c = ring_a >= wash ? c : dust_col.rgb;

	ALBEDO = c;
	ALPHA = a;
}
