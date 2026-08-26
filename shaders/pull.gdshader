// 회오리 = 충격파 + 인력 조합 전용 셰이더. (인력 단독은 magnet.gdshader 로 갈라졌다 —
// 둘이 같은 그림이면 조합이 합쳐졌다는 게 안 읽힌다.)
// 원래는 인력의 "빨려드는 나선"이었다. 충격파가 밖으로 부서져 나간다면
// 이건 밖에서 안으로 빨려 들어온다. HoN 의 Flux(자성 히어로, pull 폴라리티)를
// 벤치마킹했다 (유저 지시 2026-08-25).
//
// 셰이더 문법은 shockwave.gdshader 의 형제다 — 같은 메시(_shockwave_mesh),
// 같은 UV 규약, 같은 셀 파괴 방식. 다른 것은 **방향과 색** 둘뿐이다:
//   · 방향: 링이 1.0 → 0.0 으로 오므라들고, 힘줄이 안쪽으로 흐른다
//   · 색: 따뜻한 주황(충격파) ↔ 차가운 청록·보라(자성). 카드가 다른 걸 색으로 먼저 읽는다
//
// ⚠️ 메시 UV 규약: U = 중심에서의 거리(0..1), V = 각도(0..1 한 바퀴).
//    hammer_strike._shockwave_mesh() 가 그렇게 구워 준다. PlaneMesh 를 끼우면 안 된다.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled;

uniform float t = 0.0;            // 진행도 0 → 1. 스크립트가 트윈한다.
// 자성 색. 충격파와 겹치지 않게 **한랭 계열**로만 고른다 (endesga32).
uniform vec4 core_col : source_color = vec4(0.173, 0.910, 0.961, 1.0); // #2ce8f5 심지
uniform vec4 body_col : source_color = vec4(0.000, 0.600, 0.859, 1.0); // #0099db 몸통
uniform vec4 tail_col : source_color = vec4(0.408, 0.220, 0.424, 1.0); // #68386c 꼬리

uniform float streaks = 22.0;     // 힘줄이 날 수 있는 **자리** 수. 매 순간 다 나지는 않는다.
uniform float density = 0.88;     // 그중 실제로 나는 비율. 1.0 이면 전부 = 바퀴살이 된다.
uniform float dash_len = 0.32;    // 힘줄 하나의 길이 (반경 비율). 짧아야 '쇳가루'로 읽힌다.
uniform float dash_w = 0.46;      // 힘줄 굵기 (각도 방향)
uniform float spread_t = 0.28;    // 출발 시점을 흩는 정도. 0 이면 전부 동시에 출발한다.
uniform float speed_var = 0.55;   // 힘줄마다 속도 차이
uniform float core_r = 0.22;      // 가운데 모임 불빛의 크기
uniform float core_gain = 1.15;    // 그 불빛의 세기
uniform float rim_w = 0.05;       // 오므라드는 테두리 두께 (얇게 — 주역은 힘줄이다)
uniform float rim_alpha = 0.22;
uniform float boost = 1.9;        // 심지 밝기. 1.1 을 넘겨야 블룸(main.tscn)에 걸린다.
uniform float alpha_mul = 1.0;
uniform float swirl = 0.16;      // 안쪽으로 갈수록 감기는 정도. 0 이면 순수 방사형(별 모양)
uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.7, 289.1))) * 43758.5453 + seed);
}

void fragment() {
	float u = UV.x;               // 중심에서의 거리
	float v = UV.y;               // 각도

	// --- 힘줄: 각자 다른 시점에 출발해 각자 다른 속도로 안으로 빨려든다 -----------
	// ⚠️ 각도를 반경에 따라 비튼 좌표로 힘줄을 뜬다 — 그래야 직선이 아니라 **나선**으로 온다.
	float vc = v + swirl * (1.0 - u);
	float si = floor(vc * streaks);
	// 이 자리에 힘줄이 나는가. 안 나는 자리가 있어야 바퀴살이 아니라 흩어진 쇳가루가 된다.
	float live = step(hash(vec2(si, 11.0)), density);
	float phase = hash(vec2(si, 3.0));                    // 출발 시점
	float speed = 1.0 + (hash(vec2(si, 7.0)) - 0.5) * 2.0 * speed_var;
	// 자기 시계. 음수면 아직 출발 전이다.
	float lt = (t - phase * spread_t) * speed / max(1.0 - phase * spread_t * 0.5, 0.2);
	// 머리 위치: 바깥(1.05)에서 중심(-0.1)까지. 중심을 지나면 사라진다.
	// ⚠️ 1.0 에서 출발한다. 이보다 밖에서 시작하면 머리가 메시 바깥에 있어서
	//    착탄 직후 몇 프레임이 **빈 화면**이 된다 (t=0.25 까지 아무것도 안 보였다).
	float head = 1.0 - clamp(lt, 0.0, 1.5) * 1.35;
	float behind = u - head;                              // 머리 **바깥쪽**이면 양수 = 꼬리
	float along = smoothstep(dash_len, 0.0, behind) * step(0.0, behind + 0.02);
	// 각도 방향 굵기 — 안쪽으로 갈수록 좁아져 한 점으로 모이는 게 읽힌다
	float across = abs(fract(vc * streaks) - 0.5) * 2.0;
	float line = smoothstep(dash_w * mix(0.45, 1.0, u), 0.0, across);
	// 출발 전/도착 후에는 안 보인다
	float alive = step(0.0, lt) * (1.0 - smoothstep(1.15, 1.4, lt));
	float streak = along * line * live * alive;

	// --- 가운데로 모여드는 불빛: 힘줄이 도착할수록 밝아진다 ----------------------
	float core = smoothstep(core_r, 0.0, u) * smoothstep(0.15, 0.7, t)
		* (1.0 - smoothstep(0.85, 1.0, t)) * core_gain;

	// --- 오므라드는 테두리 (얇게, 시작을 알리는 정도) ---------------------------
	float rim = smoothstep(rim_w, 0.0, abs(u - (1.0 - t * 0.9))) * rim_alpha
		* (1.0 - smoothstep(0.6, 1.0, t));

	float a = streak + core + rim;
	if (a <= 0.004) discard;

	// --- 색: **반경으로** 두 카드를 가른다 -------------------------------------
	// ⚠️ 예전엔 밝기(hot)로 갈랐는데, 밝은 곳이 곧 머리라서 금색이 머리를 전부 덮고
	//    청록은 알파가 0에 가까운 꼬리 끝에만 남았다 — 실측 금 74~81% / 청록 4~7% 로
	//    "두 색을 섞었다"가 화면에서 거짓말이 됐다. 밝기가 아니라 **자리**로 갈라야
	//    둘 다 밝은 부분을 갖는다: 바깥은 인력의 청록, 중심으로 갈수록 충격파의 금.
	//    빨려들며 색이 달아오르는 것으로도 읽힌다.
	vec3 tint = mix(core_col.rgb, body_col.rgb, smoothstep(0.10, 0.62, u));
	float hot = clamp(smoothstep(dash_len * 0.55, 0.0, max(behind, 0.0)) * streak + core, 0.0, 1.0);
	vec3 col = mix(tail_col.rgb, tint, clamp(streak * 1.6, 0.0, 1.0));
	col = mix(col, tint * boost, hot);

	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0) * alpha_mul;
}
