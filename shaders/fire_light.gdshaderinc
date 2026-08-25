// 불빛 물들이기 — 횃불·폭연·불덩이가 **주변 사물과 벌레를 밝힌다**.
//
// 왜 진짜 광원이 아니라 이걸 쓰나 (2026-08-17):
//   이 게임의 색은 셰이더 light() 가 `DIFFUSE_LIGHT = ...` 로 **확정한다**. 씬에 광원을
//   하나 더 넣으면 그 전제가 무너져 화면의 색이 통째로 날아간다 (OmniLight3D 로 실제로 겪었다).
//   그래서 불빛은 조명 계산에 끼어들지 않고, fragment() 에서 EMISSION 에 **더하기만** 한다.
//   → light() 는 손대지 않는다 = 기존 2톤 셀 룩이 그대로 유지된다.
//
// 슬롯은 8개 고정이다. 전역 유니폼은 배열이 안 되므로 이름을 나눠 두고 펼쳐서 더한다.
//   fire_pN = vec4(월드 위치 xyz, 반경 w).  ⚠️ **w <= 0 이면 꺼진 슬롯**이다.
//   fire_cN = vec4(색 rgb, 세기 a).
// 슬롯 관리는 scripts/fire_lights.gd 가 한다. 다 차면 새 불은 그냥 안 물들인다 —
// 화면에 불이 8개 넘게 있을 땐 하나쯤 빠져도 아무도 모른다.
global uniform vec4 fire_p0;
global uniform vec4 fire_p1;
global uniform vec4 fire_p2;
global uniform vec4 fire_p3;
global uniform vec4 fire_p4;
global uniform vec4 fire_p5;
global uniform vec4 fire_p6;
global uniform vec4 fire_p7;
global uniform vec4 fire_c0;
global uniform vec4 fire_c1;
global uniform vec4 fire_c2;
global uniform vec4 fire_c3;
global uniform vec4 fire_c4;
global uniform vec4 fire_c5;
global uniform vec4 fire_c6;
global uniform vec4 fire_c7;
/// 시간대 배수 (Mood). 밤에 1.0, 낮엔 약하게 — 불빛은 어두울수록 세게 읽힌다.
global uniform float mood_fire_mul;

vec3 fire_one(vec4 p, vec4 c, vec3 wp, vec3 wn) {
	if (p.w <= 0.0) {
		return vec3(0.0);
	}
	vec3 d = p.xyz - wp;
	float dist = length(d);
	// 제곱으로 떨어뜨린다 — 선형이면 반경 끝까지 희미하게 묻어 "안개 낀 주황"이 된다.
	float f = clamp(1.0 - dist / p.w, 0.0, 1.0);
	f *= f;
	// ⚠️ 순수 램버트(max(dot,0))로 하면 뒷면이 딱 잘려 검게 남는다. 벌레 몸이 이미
	//    거의 검정이라 그 경계가 칼로 자른 것처럼 보인다. 감싸는 램버트로 뒷면도 절반은 받는다.
	f *= dot(normalize(wn), d / max(dist, 0.001)) * 0.5 + 0.5;
	// ⚠️ **계단화(밴딩)를 하지 않는다.** 처음엔 셀 룩을 맞추려고 3단으로 끊었는데,
	//    폭연·불덩이 반경을 키우자 그 계단이 그대로 **동심원 링**이 되어 화면에 떴다
	//    (유저 스크린샷 2026-08-17: "불덩이 주변에 링이 생겼어").
	//    빛은 면이 아니라 **번짐**이라, 벌레 몸의 2톤 밴딩과 같은 문법을 쓰면 안 된다.
	//    지면처럼 넓고 평평한 곳에서는 밴드 경계가 숨을 데가 없다 — 매끈해야 빛으로 읽힌다.
	//    (횃불의 가짜 빛웅덩이도 같은 이유로 매끈한 원형 감쇠를 쓴다.)
	return c.rgb * (f * c.a);
}

vec3 fire_light(vec3 wp, vec3 wn) {
	vec3 a = vec3(0.0);
	a += fire_one(fire_p0, fire_c0, wp, wn);
	a += fire_one(fire_p1, fire_c1, wp, wn);
	a += fire_one(fire_p2, fire_c2, wp, wn);
	a += fire_one(fire_p3, fire_c3, wp, wn);
	a += fire_one(fire_p4, fire_c4, wp, wn);
	a += fire_one(fire_p5, fire_c5, wp, wn);
	a += fire_one(fire_p6, fire_c6, wp, wn);
	a += fire_one(fire_p7, fire_c7, wp, wn);
	return a * mood_fire_mul;
}
