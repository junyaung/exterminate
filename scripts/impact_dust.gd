class_name ImpactDust
extends RefCounted

## 무언가가 땅을 때렸을 때의 흙먼지. 망치 임팩트와 낙석 착지가 같은 먼지를 쓴다.
## 한 곳에 모아둔 이유: 두 곳에 복사해두면 한쪽만 손봐서 룩이 어긋난다.

const COL := Color(0.737, 0.678, 0.624)   # nice31 #bcad9f
## 압축 고리가 목표 반경까지 퍼지는 시간.
## ⚠️ 0.5 는 너무 빨랐다 — 반경 8 을 0.5 초에 훑으면 평균 16유닛/초라 눈이 못 따라간다.
const RING_LIFE := 0.75

## amount = 알갱이 수, scale = 크기·속도 배율, color = 기본은 흙색 (불꽃 등은 바꿔 쓴다).
static func burst(parent: Node, pos: Vector3, amount := 26, scale := 1.0,
		color := COL) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	# CPUParticles3D 는 emitting 기본값이 true 라, 끄지 않으면 add_child 되는 순간
	# 아직 transform 이 원점인 상태로 터진다. local_coords=false 라 그 파티클은
	# 월드 원점에 박혀버린다 — 반드시 자리를 잡은 뒤에 켤 것.
	p.emitting = false
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.55
	p.direction = Vector3.UP
	p.spread = 75.0
	p.initial_velocity_min = 7.0 * scale
	p.initial_velocity_max = 15.0 * scale
	p.gravity = Vector3(0.0, -38.0, 0.0)
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE * 0.35 * scale
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	cube.material = m
	p.mesh = cube
	parent.add_child(p)
	p.global_position = pos + Vector3(0.0, 0.3, 0.0)
	p.emitting = true      # 자리를 잡은 뒤에 터뜨린다
	parent.get_tree().create_timer(1.2).timeout.connect(p.queue_free)
	return p


## 바닥을 훑으며 바깥으로 쓸려나가는 압축 고리 (풀차징 임팩트 전용).
##
## burst() 와 **방향이 정반대**인 게 핵심이다: 평타는 위로 터지고, 풀차징은 옆으로 깔린다.
## 실루엣만 봐도 어느 쪽을 쳤는지 알 수 있어야 한다는 게 이 이펙트의 존재 이유다.
##
## 덤으로 정보도 준다 — 고리가 퍼지는 거리를 그 스윙의 **실제 타격 반경**에 맞췄으므로,
## 풀차징 범위가 얼마나 넓은지를 눈이 바로 읽는다.
##
## radial_accel 로 미는 이유: CPUParticles3D 의 velocity 는 direction+spread 라 방사형이
## 안 나온다. 링 위에 뿌리고 원점에서 바깥으로 가속하면 납작하게 퍼진다.
static func ground_ring(parent: Node, pos: Vector3, radius: float,
		amount := 44, color := COL) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false          # burst() 와 같은 함정 — 자리를 잡기 전엔 켜지 않는다
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = RING_LIFE
	# 링 위에서 시작 — 한 점에서 뿜으면 가운데가 뭉쳐 고리로 안 읽힌다
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = radius * 0.22
	p.emission_ring_inner_radius = radius * 0.10
	p.emission_ring_height = 0.12
	p.direction = Vector3.UP
	p.spread = 12.0             # 거의 수평 — 위로 솟으면 평타 먼지와 구분이 안 된다
	# 위로 뜨는 성분은 최소로 — 이 이펙트의 정체성은 '바닥에 깔린다' 이다.
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.8
	# 등가속으로 목표 반경까지: r = 0.5·a·t²  ->  a = 2r/t²
	var accel := 2.0 * radius / (RING_LIFE * RING_LIFE)
	p.radial_accel_min = accel * 0.75
	p.radial_accel_max = accel * 1.15
	# ⚠️ 중력을 세게 주면 수명이 끝나기 전에 **지면 아래로 가라앉아** 사라진 것처럼 보인다.
	#    RING_LIFE 0.75 / 초기 상승 0.2~0.8 기준으로 -3.0 이면 0.5 초에 y<0 이었다.
	#    -0.8 이면 수명 내내 지면 위에 남고, 크기 커브가 알아서 줄여 없앤다.
	p.gravity = Vector3(0.0, -0.8, 0.0)
	p.damping_min = 1.0
	p.damping_max = 3.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	# ⚠️ CPUParticles3D.scale_curve 는 Curve 를 그대로 받는다. CurveTexture 를 넣으면
	#    (GPUParticles 의 ParticleProcessMaterial 과 헷갈리기 쉽다) 대입에서 터진다.
	var curve := Curve.new()              # 끝에서 작아지며 사라진다
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	var cube := BoxMesh.new()
	# ⚠️ 0.42 는 안 보였다 (유저 지적). 고리는 반경 8 까지 퍼지므로 둘레가 50유닛이다 —
	#    알갱이가 작으면 그 둘레에 흩어져 사라진 것처럼 보인다. 넉넉히 키운다.
	cube.size = Vector3(0.7, 0.22, 0.7)     # 납작한 판 — 흙이 깔려 밀리는 느낌
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	cube.material = m
	p.mesh = cube
	parent.add_child(p)
	p.global_position = pos + Vector3(0.0, 0.12, 0.0)
	p.emitting = true
	parent.get_tree().create_timer(RING_LIFE + 0.6).timeout.connect(p.queue_free)
	return p
