// 3D 값 노이즈 + 소각 마스크. cel_burn(본체)과 ink_burn(먹선 껍질)이 **같은 마스크**를
// 써야 두 메시의 타들어간 구멍이 정확히 겹친다 — 한쪽만 타면 검은 껍데기가 남는다.
float burn_hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float burn_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float n000 = burn_hash(i);
	float n100 = burn_hash(i + vec3(1.0, 0.0, 0.0));
	float n010 = burn_hash(i + vec3(0.0, 1.0, 0.0));
	float n110 = burn_hash(i + vec3(1.0, 1.0, 0.0));
	float n001 = burn_hash(i + vec3(0.0, 0.0, 1.0));
	float n101 = burn_hash(i + vec3(1.0, 0.0, 1.0));
	float n011 = burn_hash(i + vec3(0.0, 1.0, 1.0));
	float n111 = burn_hash(i + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, u.x);
	float nx10 = mix(n010, n110, u.x);
	float nx01 = mix(n001, n101, u.x);
	float nx11 = mix(n011, n111, u.x);
	return mix(mix(nx00, nx10, u.y), mix(nx01, nx11, u.y), u.z);
}

// 모델 로컬 좌표 기준 마스크. 망치 모델은 그립 y=0, 머리끝 y=1 로 정규화되어 있고,
// 특수 망치는 뒤집혀 박히므로 **그립(y=0)이 하늘을 본다** — y 가중치를 섞으면
// 위(손잡이 끝)부터 타 내려간다. 재는 위로 나부끼니 방향이 맞는다.
float burn_mask(vec3 lp, float noise_scale) {
	return burn_noise(lp * noise_scale) * 0.6 + clamp(lp.y, 0.0, 1.0) * 0.4;
}
