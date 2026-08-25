class_name Torch
extends Node3D

## 성 옆 횃불 (유저 요청 2026-08-17). 무드 조명이 어떻게 읽히는지 확인하는 용도이기도 하다.
##
## ⚠️ **진짜 광원(OmniLight3D)을 쓰지 않는다.** 지금 셀/지면 셰이더는 `light()` 에서
##    DIFFUSE_LIGHT 를 **덮어쓴다**(`=`). 광원이 둘이면 마지막 것만 남아서, 횃불을 켜는 순간
##    그 주변만 태양 조명이 사라지거나 반대가 된다 (지면이 통째로 까매졌던 것과 같은 계열의 사고).
##    그래서 여기서는 **발광 지오메트리 + 바닥 빛웅덩이 + 불티**로 같은 인상을 만든다.
##
##    ⚠️ 2026-08-17 에 진짜 광원을 한 번 시도했다가 되돌렸다. 방향광/점광원을 분기해서
##       (`LIGHT_IS_DIRECTIONAL`) 태양은 `=`, 횃불은 `+=` 로 갈랐는데 **화면의 색이 전부 날아갔다.**
##       이 게임의 색은 light() 가 확정하는 구조라, 광원이 하나 더 끼는 순간 그 전제가 무너진다.
##       다시 시도할 거면 셰이더 색 결정 방식부터 새로 설계해야 한다 — 분기만으로는 안 된다.
##
## 흔들림이 핵심이다 — 불은 밝기와 크기가 **불규칙하게** 떨려야 불로 읽힌다.

const POLE_H := 3.2
const FLAME_COL := Color("#feae34")     ## 불꽃 (endesga 주황)
const FLAME_CORE := Color("#fee761")    ## 심지 쪽 밝은 노랑
const POOL_COL := Color("#f77622")      ## 바닥 빛웅덩이
const POOL_R := 11.0
## 주변을 물들이는 반경. 가짜 빛웅덩이(POOL_R)와 **같은 값으로 두지 않는다** —
## 바닥 웅덩이는 넓게 깔려야 예쁘고, 물드는 건 좁아야 "닿는다"로 읽힌다.
const FIRE_R := 8.0
const FIRE_ENERGY := 0.55

var _flame: MeshInstance3D
var _core: MeshInstance3D
var _pool: MeshInstance3D
var _t := 0.0
var _seed := 0.0
## 불빛 슬롯. -1 = 못 잡았음(그냥 안 물들인다).
var _fire_slot := -1

func _ready() -> void:
	_seed = randf() * 10.0
	_build()
	_fire_slot = FireLights.acquire()

## ⚠️ 슬롯은 반드시 돌려준다 — 안 돌려주면 8칸이 새서 나중 판의 불이 아무것도 못 잡는다.
func _exit_tree() -> void:
	FireLights.release(_fire_slot)
	_fire_slot = -1

func _build() -> void:
	# 기둥
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.16
	cyl.bottom_radius = 0.22
	cyl.height = POLE_H
	cyl.radial_segments = 6
	pole.mesh = cyl
	pole.position.y = POLE_H * 0.5
	pole.material_override = _solid(Color("#734c44"))
	add_child(pole)

	# 불꽃 — 위로 갈수록 좁아지는 두 겹 (겉불 + 심지)
	# ⚠️ 크기는 기둥 굵기(0.16)가 아니라 **멀리서 읽히는가**로 정한다. 직교 카메라라
	#    작은 불은 몇 픽셀로 뭉개져 그냥 주황 점이 된다 (유저 지적: 더 키울 것).
	_flame = MeshInstance3D.new()
	var f := SphereMesh.new()
	f.radius = 0.95
	f.height = 2.8
	f.radial_segments = 7
	f.rings = 4
	_flame.mesh = f
	# 불꽃 아랫동이 기둥 끝을 물게 올린다 — 사이가 뜨면 공중에 뜬 구슬로 보인다.
	_flame.position.y = POLE_H + 0.85
	_flame.material_override = _glow(FLAME_COL, 2.2)
	add_child(_flame)

	_core = MeshInstance3D.new()
	var c := SphereMesh.new()
	c.radius = 0.48
	c.height = 1.5
	c.radial_segments = 6
	c.rings = 3
	_core.mesh = c
	_core.position.y = POLE_H + 0.68
	_core.material_override = _glow(FLAME_CORE, 3.2)
	add_child(_core)

	# 바닥 빛웅덩이 — 가짜 조명. 가산 혼합이라 어두운 밤일수록 도드라진다.
	# 불꽃을 키운 만큼 웅덩이도 같이 키운다 — 불만 커지고 바닥이 그대로면 비율이 어긋난다.
	_pool = MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(POOL_R * 2.0, POOL_R * 2.0)
	_pool.mesh = q
	_pool.position.y = 0.05
	_pool.material_override = _pool_mat()
	_pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pool)

	# 불티
	var p := CPUParticles3D.new()
	p.emitting = false          # ⚠️ 자리 잡기 전에 켜면 원점에서 터진다 (이 프로젝트의 단골 함정)
	p.amount = 22
	p.lifetime = 1.2
	p.position.y = POLE_H + 1.1
	p.direction = Vector3.UP
	p.spread = 18.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.8
	p.gravity = Vector3(0.2, 1.4, 0.2)
	p.scale_amount_min = 0.07
	p.scale_amount_max = 0.16
	p.mesh = SphereMesh.new()
	p.material_override = _glow(FLAME_CORE, 2.6)
	add_child(p)
	p.emitting = true

func _process(delta: float) -> void:
	_t += delta
	# 두 개의 다른 주기를 겹쳐 **불규칙하게** 떨리게 한다. 한 주기만 쓰면 기계적으로 뛴다.
	var a := sin((_t + _seed) * 11.0) * 0.5 + sin((_t + _seed) * 6.3) * 0.5
	var flick := 1.0 + a * 0.14
	if _flame != null:
		_flame.scale = Vector3(flick, 1.0 + a * 0.22, flick)
	if _core != null:
		_core.scale = Vector3.ONE * (1.0 + a * 0.18)
	if _pool != null:
		var mat := _pool.material_override as ShaderMaterial
		mat.set_shader_parameter("strength", 0.34 + a * 0.07)
		_pool.scale = Vector3.ONE * (1.0 + a * 0.05)
	# 주변 물들이기 — 불꽃과 **같은 리듬**으로 떤다. 불은 떠는데 물든 바닥이 가만히 있으면
	# 둘이 따로 논다. 세기만 떨고 반경은 고정한다 (반경이 떨면 경계가 출렁여 어지럽다).
	FireLights.put(_fire_slot, global_position + Vector3(0.0, POLE_H + 0.5, 0.0),
		FIRE_R, FLAME_COL, FIRE_ENERGY * (1.0 + a * 0.18))

func _solid(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	return m

## 발광 재질 — glow 문턱(1.1)을 넘겨 블룸이 걸리게 한다. 무드가 밤일수록 세게 번진다.
func _glow(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m

## 바닥 빛웅덩이 재질. ⚠️ 사각 판에 단색 알파를 주면 **네모난 빛**이 보인다 —
## 가운데가 밝고 가장자리로 사라지는 원형이어야 빛으로 읽힌다. 작은 셰이더로 처리한다.
func _pool_mat() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 col : source_color = vec4(0.969, 0.463, 0.133, 1.0);
uniform float strength = 0.34;
void fragment() {
	float r = length(UV * 2.0 - 1.0);
	// 가운데가 밝고 가장자리에서 0 — 제곱으로 떨어뜨려야 불빛처럼 뭉친다.
	float a = pow(clamp(1.0 - r, 0.0, 1.0), 2.2);
	ALBEDO = col.rgb;
	ALPHA = a * strength;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("col", POOL_COL)
	m.set_shader_parameter("strength", 0.34)
	return m
