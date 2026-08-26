// 인력 — **쌍극자 자기장**이 순간적으로 뿜어져 나온다 (유저 지시 2026-08-25,
// 지구 자기장 레퍼런스). 이전의 빨려드는 나선은 회오리(조합)가 가져갔다.
//
// 자기력선 방정식: 극좌표에서 r = L·sin²θ (θ = 축에서 잰 각).
// 그래서 어떤 점 (r, θ) 가 속한 자기력선은 L = r / sin²θ 하나로 정해진다.
// L 을 일정 간격으로 끊으면 레퍼런스의 그 동심 고리 다발이 그대로 나온다 —
// 극에서 모이고 적도에서 가장 벌어지는 것도 공짜로 따라온다.
//
// ⚠️ 메시 UV 규약: U = 중심에서의 거리(0..1), V = 각도(0..1 한 바퀴).
//    hammer_strike._shockwave_mesh() 가 그렇게 구워 준다.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled;

uniform float t = 0.0;            // 진행도 0 → 1

// 청록 발광. 심지는 블룸 문턱(1.1)을 넘겨야 실제로 빛나 보인다.
uniform vec4 line_col : source_color = vec4(0.173, 0.910, 0.961, 1.0); // #2ce8f5
uniform vec4 glow_col : source_color = vec4(0.000, 0.600, 0.859, 1.0); // #0099db 번짐
uniform float boost = 2.4;        // 심지 밝기

// 축 방향 (0..1 바퀴). 시전마다 스크립트가 무작위로 넣는다.
// 기본 0.625 = 카메라 yaw 45 기준 **화면 위쪽** — 레퍼런스와 같은 방향이다.
uniform float axis_v = 0.625;

uniform float lines = 4.0;        // 자기력선 개수 (최대 8)
// ⚠️ **1.0 을 넘기면 안 된다.** 가장 바깥 고리가 적도에서 u=span 까지 가는데, 메시는 u=1 에서
//    끝나므로 넘는 만큼 잘려서 고리가 끊겨 보인다 (1.25 로 뒀다가 실제로 끊겼다).
uniform float span = 0.94;        // 가장 바깥 고리가 적도에서 닿는 반경 (1.0 = 원판 가장자리)
uniform float width = 0.024;      // 선 굵기 (반경 비율)
uniform float glow_w = 0.095;     // 선 주변 번짐 폭
uniform float pole_fade = 0.10;   // 극 근처에서 선이 뭉치는 걸 눌러 주는 정도
// ⚠️ **코어 반경.** 이게 없으면 자기력선이 전부 중심 한 점으로 빨려들어 물방울 모양이 된다.
//    레퍼런스(지구 자기장)는 몸통이 있어서 선이 **극에서 나온다** — 안쪽을 도려내면 그 그림이 된다.
uniform float core_r = 0.13;

// --- 시간 구성 (유저 지시 2026-08-25) ---------------------------------------
// "모든 고리가 **먼저 나타난 다음**, **가장 바깥 고리부터 차례로** 중심으로 빨려든다."
// 끌어당기는 카드라 뿜는 게 아니라 거둬들이는 순서여야 한다.
uniform float appear = 0.12;      // 이때까지 전부 나타난다
uniform float stagger = 0.19;     // 고리 하나가 다음 고리보다 먼저 출발하는 간격
uniform float suck = 0.32;        // 고리 하나가 중심까지 빨려드는 데 걸리는 시간
uniform float alpha_mul = 1.0;

const int MAX_LINES = 8;

void fragment() {
	float u = UV.x;
	if (u < core_r) discard;                   // 코어 안쪽 — 선은 여기서 '나온다'

	// 축에서 잰 각. 축은 화면-위 방향이다.
	float ang = (UV.y - axis_v) * TAU;
	float sn = sin(ang);
	// 극에 가까울수록 sin² 이 0 이라 L 이 폭발하므로 바닥을 깐다.
	float denom = max(sn * sn, pole_fade);

	// 자기력선 방정식 r = L·sin²θ → 이 픽셀이 놓인 선의 L
	float L = u / denom;
	float spacing = span / lines;

	// --- 고리마다 지금 어디까지 빨려들었는지 계산해 가장 가까운 것을 고른다 --------
	// ⚠️ 예전처럼 픽셀의 L 을 반올림해 고리를 찾는 방식은 **고리가 고정일 때만** 쓸 수 있다.
	//    고리가 각자 다른 속도로 움직이므로, 고리 쪽에서 현재 L 을 내고 비교해야 한다.
	float core_a = 0.0;
	float halo_a = 0.0;
	float hot = 0.0;
	for (int i = 1; i <= MAX_LINES; i++) {
		if (float(i) > lines) { break; }
		float base = float(i) * spacing;
		// 바깥 고리(i 가 큰 쪽)가 **먼저** 출발한다
		// ⚠️ appear 뒤에 틈을 둔다 — 안쪽 고리가 아직 켜지는 중에 바깥이 출발하면
		//    "전부 나타난 다음 차례로 빨려든다" 가 아니라 그냥 뒤섞여 보인다.
		float start = appear + 0.05 + (lines - float(i)) * stagger;
		float k = clamp((t - start) / suck, 0.0, 1.0);
		// 부드럽게 가속해 빨려든다 — 등속이면 기계적으로 보인다
		float pulled = k * k * (3.0 - 2.0 * k);
		float ln = base * (1.0 - pulled);
		if (ln <= 0.0005) { continue; }        // 다 빨려들었다

		// 나타나는 단계: 바깥부터 순서대로 켜진다 (빨려들 때와 같은 순서)
		float lit = smoothstep(0.0, appear * 0.7, t - (lines - float(i)) * appear * 0.12);

		float dr = abs(L - ln) * denom;        // 반경 단위 거리
		float c = smoothstep(width, 0.0, dr) * lit;
		core_a = max(core_a, c);
		halo_a = max(halo_a, smoothstep(glow_w, 0.0, dr) * 0.45 * lit);
		// 중심에 가까워질수록 밝아진다 — 에너지가 모이는 인상
		hot = max(hot, c * pulled);
	}

	float a = core_a + halo_a;
	if (a <= 0.004) discard;

	vec3 col = mix(glow_col.rgb, line_col.rgb * boost, clamp(core_a + hot * 0.6, 0.0, 1.0));
	float fade = 1.0 - smoothstep(0.93, 1.0, t);

	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0) * fade * alpha_mul;
}
