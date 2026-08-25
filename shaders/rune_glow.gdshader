// 보스 등의 룬 문양 — 조명과 무관한 평면 발광.
//
// ⚠️ unshaded 를 쓰면 안 된다. Godot 은 unshaded 에서 EMISSION 을 버리고 ALBEDO 만 출력한다
//    (deflagration.gd 에 같은 메모가 있다 — 프로젝트 안에서 이미 한 번 부딪힌 함정이다).
//    대신 ALBEDO 를 0 으로 두고 EMISSION 만 쓴다. 검은 albedo 라 확산광이 0 이 되고,
//    ambient_light_disabled 로 환경광도 끄면 결과는 EMISSION 하나뿐 — 각도와 무관하게
//    같은 밝기다. 그러면서 HDR 값이라 bloom 문턱(main.tscn 1.1)을 넘길 수 있다.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert,
			specular_disabled, ambient_light_disabled;

// source_color 힌트가 붙은 값은 sRGB 로 넣는다 (Godot 이 linear 로 변환해 준다).
uniform vec4 col : source_color = vec4(0.173, 0.910, 0.961, 1.0);
// 발광 배율. **1.1(bloom 문턱) 위**여야 번진다 — 아래로 내리면 그냥 밝은 청록이 된다.
uniform float glow = 2.0;

void fragment() {
	ALBEDO = vec3(0.0);
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
	EMISSION = col.rgb * glow;
}
