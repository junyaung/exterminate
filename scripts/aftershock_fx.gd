class_name AftershockFX
extends Node3D

## 여진 연출 전담. 로직(피해 판정)은 HammerStrike 가 갖고, 여기는 보이는 것만 담당한다.
##
## 컨셉(유저): "망치가 한 번 더 떨어지는 게 아니라, 첫 충돌로 눌렸던 땅이 뒤늦게 반발한다."
## 그래서 망치는 재등장하지 않고 지면 이펙트만 쓴다.
##
## 균열은 직선 방사형이 아니라 **재귀 분기**로 만든다 — 잎맥·모세혈관처럼.
## 실제 지면 파괴는 직선으로 갈라지지 않는다.
##
## 타임라인
##   0.00  최초 충돌 — 분기 균열 + 중앙 눌린 자국 + 돌조각 (바닥에 남는다)
##   0.15~0.35  예고 — 빛이 중심에서 바깥으로 번짐, 돌조각이 미세하게 떨림
##   0.35  여진 — 각진 고리가 납작하게 퍼짐 + 돌조각이 바닥을 따라 튐
##   0.55  전부 제거

const TELL_START := 0.15
const LINGER := 3.0           ## 여진 후 균열이 바닥에 남아있는 시간
const LAVA_LINGER := 5.0      ## 불 조합에서 분화구로 남는 시간 (= Crater.LIFETIME)
const FADE_OUT := 0.4

## 균열 지대로서의 상태. active 인 동안 망치로 다시 치면 분출하고,
## 그 위를 처음 지나가는 적은 한 번 휘청인다.
var active := false
var field_radius := 0.0
## 이 균열 지대의 오브젝트 스펙 (area + ground). 잔류가 수명을, 거대화가 반경을 건드린다.
## null 이면 예전 그대로 (배율 1.0).
var spec: ObjectSpec
var _stumbled := {}           ## 이미 휘청인 적 (instance_id) — 한 번만 반응한다

# --- 균열 분기 파라미터 ---
## 자연의 "갈라지는 방식"만 빌려오고 밀도는 땅답게 굵고 성글게 잡는다.
## 잎맥·모세혈관처럼 세밀하게 갈라지면 흙바닥이 아니라 유기체로 보인다.
const TRUNK_MIN := 4          ## 중심에서 뻗는 주간(主幹) 개수
const TRUNK_MAX := 6
const MAX_DEPTH := 1          ## 주간 + 갈래 하나까지만. 잔가지·실핏줄은 만들지 않는다.
const BRANCHES_PER_TRUNK := 1 ## 주간 하나당 갈래 최대 1개 — 덤불이 되는 걸 막는다
const SEG_LEN := 0.9          ## 길고 각진 마디. 짧게 쪼개면 곡선이 되어 유기적으로 보인다.
const WANDER := 0.22          ## 마디마다 꺾이는 정도(rad)
const TAPER := 0.86           ## 마디마다 가늘어지는 비율
const TRUNK_WIDTH := 0.30     ## 굵어야 흙이 갈라진 것처럼 보인다
const BRANCH_CHANCE := 0.5    ## 갈래가 생길 확률 (주간당 1회 한정)
const BRANCH_ANGLE_MIN := 0.4
const BRANCH_ANGLE_MAX := 0.8
const CHILD_LEN := Vector2(0.3, 0.5)     ## 부모 대비 자식 길이 비율
const CHILD_WIDTH := 0.6
## 충돌 지점 바로 주변은 가장 크게 부서진다 — 중심부 마디를 굵게 부풀린다.
const HUB_BOOST := 2.0        ## 중심에서의 굵기 배율
const HUB_FALLOFF := 0.4      ## 반경의 이 비율까지가 "중심부"

# --- 중심 파쇄부 (유리창이 깨진 듯 — 유저 레퍼런스 이미지) ---
## 짧은 잔금 여러 개 + 거미줄 연결 고리 + 눌려 부서진 중앙 구멍.
## 바깥의 큰 분기 균열과 달리, 여기는 촘촘하고 잘게 부서져야 한다.
const CORE_R := 0.5           ## 파쇄부 크기 (지대 반경 대비) — 거미줄이 지대의 절반을 차지한다
const CORE_SPOKES_MIN := 6    ## 잔금 개수 (10~13 은 너무 촘촘했다)
const CORE_SPOKES_MAX := 8
const CORE_RINGS: Array[float] = [0.5, 0.95]  ## 연결 고리 위치 (잔금 끝 대비)
const CORE_W := 0.12          ## 잔금 굵기 — 바깥 주간(0.30)보다 가늘다
## 균열 먹선 굵기(월드, 가장자리에서 안쪽으로). 0 이면 꺼진다 — 되돌리기 쉬우라고 상수로 뺐다.
## 균열 반폭은 중심 0.25 ~ 끝 0.06 이라, 0.022 면 굵은 데선 얇고 가는 갈래에선 도톰해진다
## (펜으로 그은 선에 잉크가 고이는 느낌).
const CRACK_INK := 0.022
## 분출 화염 먹선 (UV 단위 — 불꽃 반폭이 뿌리 0.46 ~ 끝 0.10).
## ⚠️ **폭연(Deflagration)도 같은 lava_flame 셰이더를 쓴다.** 유저가 폭연 룩은 그대로
## 두라고 했으므로 셰이더 기본값은 0(꺼짐)이고, 여기 분출 불꽃에만 켠다.
const FLAME_INK := 0.045
const CORE_RING_GAP := 0.5    ## 고리가 군데군데 끊길 확률

# nice31
const COL_CRACK := Color(0.239, 0.2, 0.2)      # #3d3333
const COL_GLOW := Color(0.949, 0.722, 0.533)   # #f2b888
const COL_RING := Color(0.737, 0.678, 0.624)   # #bcad9f
const COL_DEBRIS := Color(0.737, 0.678, 0.624)

# 불 조합(분화구 예정)일 때의 용암 팔레트 — 빛이 아니라 불이어야 한다
const COL_LAVA := Color(0.922, 0.588, 0.38)    # #eb9661
const COL_LAVA_DEEP := Color(0.71, 0.349, 0.271)  # #b55945
const COL_LAVA_GOLD := Color(0.871, 0.624, 0.278) # #de9f47

const CrackShader := preload("res://shaders/crack.gdshader")
const RayShader := preload("res://shaders/light_ray.gdshader")
## 용암 불길은 카툰 겹불꽃(flame_jet)이 아니라 부드러운 VFX 판을 쓴다 (유저 지시).
const FlameShader := preload("res://shaders/lava_flame.gdshader")

var _crack_mat: ShaderMaterial
var _pebbles: Array[MeshInstance3D] = []
## 실제로 그려진 균열 선분들(로컬 XZ). 밟기 판정은 이 선에 닿았는지로 한다 —
## 지대 반경(원)으로 판정하면 보이지 않는 경계에서 밀려서 이상하다.
var _segments: Array = []      ## {a: Vector2, b: Vector2, w: float(반폭)}

## 최초 충돌 시점에 호출. radius = 최초 공격 반경, strength = 연출 세기 배율.
func begin(radius: float, strength := 1.0) -> void:
	_cracks(radius, strength)
	_pebble_field(radius)

# ---------------------------------------------------------------- 균열 (분기)

func _cracks(radius: float, strength: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_shatter_core(st, radius)
	var n := randi_range(TRUNK_MIN, TRUNK_MAX)
	var base_ang := randf_range(0.0, TAU)
	for i in n:
		# 균등 분포에 각도 흔들기 — 완벽한 대칭은 인공적이다
		var ang := base_ang + TAU * i / n + randf_range(-0.3, 0.3)
		var dir := Vector2(cos(ang), sin(ang))
		var seg_len := radius * randf_range(0.6, 1.05) * strength
		_branch(st, Vector2.ZERO, dir, seg_len, TRUNK_WIDTH, 0, radius, BRANCHES_PER_TRUNK)

	_crack_mat = ShaderMaterial.new()
	_crack_mat.shader = CrackShader
	_crack_mat.set_shader_parameter("base_col", Color(COL_CRACK.r, COL_CRACK.g, COL_CRACK.b, 0.9))
	_crack_mat.set_shader_parameter("glow_col", COL_GLOW)
	_crack_mat.set_shader_parameter("wave_pos", -1.0)
	_crack_mat.set_shader_parameter("fade", 1.0)
	_crack_mat.set_shader_parameter("ink_width", CRACK_INK)
	# 평상시 균열은 그냥 검다. 불 속성 카드가 여진과 결합하면 여기서 잔열을 켠다:
	#   _crack_mat.set_shader_parameter("ember", 0.9)

	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _crack_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.position.y = 0.025

## 중심 파쇄부: 유리창이 깨진 것처럼 — 짧은 잔금들 + 거미줄 연결 고리 + 눌린 구멍.
func _shatter_core(st: SurfaceTool, radius: float) -> void:
	var core_r := radius * CORE_R
	var n := randi_range(CORE_SPOKES_MIN, CORE_SPOKES_MAX)
	var tips: Array[Vector2] = []
	var base_ang := randf_range(0.0, TAU)
	# 잔금: 한 번 꺾인 두 마디짜리 가는 금
	for i in n:
		var ang := base_ang + TAU * i / n + randf_range(-0.18, 0.18)
		var dir := Vector2(cos(ang), sin(ang))
		var seg_len := core_r * randf_range(0.75, 1.15)
		var mid := dir * seg_len * randf_range(0.45, 0.6) \
			+ dir.orthogonal() * seg_len * randf_range(-0.12, 0.12)
		var tip := dir * seg_len
		_quad(st, Vector2.ZERO, mid, CORE_W, CORE_W * 0.7, radius)
		_quad(st, mid, tip, CORE_W * 0.7, CORE_W * 0.45, radius)
		tips.append(tip)
	# 연결 고리: 이웃 잔금끼리 이어 거미줄처럼. 군데군데 끊겨야 자연스럽다.
	for ring_t in CORE_RINGS:
		for i in n:
			if randf() < CORE_RING_GAP:
				continue
			var a: Vector2 = tips[i] * ring_t * randf_range(0.85, 1.1)
			var b: Vector2 = tips[(i + 1) % n] * ring_t * randf_range(0.85, 1.1)
			_quad(st, a, b, CORE_W * 0.55, CORE_W * 0.55, radius)
	# 중앙 구멍: 눌려 부서진 자국 — 울퉁불퉁한 부채꼴 채움
	var hole_r := core_r * 0.3
	var m := 8
	var pts: Array[Vector2] = []
	for i in m:
		var ang := TAU * i / m
		pts.append(Vector2(cos(ang), sin(ang)) * hole_r * randf_range(0.6, 1.15))
	for i in m:
		# 가운데 구멍은 꼭짓점이 중심(가로 0)이고 테두리가 바깥(가로 1)이라,
		# 같은 공식으로 바깥 둘레에만 먹선이 돈다. UV2.x = 그 꼭짓점까지의 거리.
		for v: Vector2 in [Vector2.ZERO, pts[i], pts[(i + 1) % m]]:
			var edge := v.length()
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(clampf(edge / radius, 0.0, 1.0), 0.0 if edge < 0.001 else 1.0))
			st.set_uv2(Vector2(maxf(edge, hole_r), 0.0))
			st.add_vertex(Vector3(v.x, 0.0, v.y))

## 한 갈래를 재귀적으로 그린다. 마디마다 꺾이고, 주간당 최대 한 번 갈라진다.
func _branch(st: SurfaceTool, pos: Vector2, dir: Vector2, length: float,
		width: float, depth: int, radius: float, branches_left: int) -> void:
	if depth > MAX_DEPTH or length < 0.2 or width < 0.02:
		return
	var segs := maxi(2, int(ceil(length / SEG_LEN)))
	var seg_len := length / segs
	var p := pos
	var d := dir.normalized()
	var w := width
	for s in segs:
		d = d.rotated(randf_range(-WANDER, WANDER)).normalized()
		var p2 := p + d * seg_len
		var w2 := w * TAPER
		_quad(st, p, p2, w, w2, radius)
		# 가지치기 — **바깥쪽 절반에서만** 갈라진다. 중심은 파쇄부가 담당하고,
		# 밖으로 뻗을수록 갈라지는 인상을 주기 위해서다 (유저 지시).
		# 갈래는 주간당 최대 BRANCHES_PER_TRUNK 개 (자식에게는 0을 넘겨 더 못 갈라지게 한다).
		if depth < MAX_DEPTH and branches_left > 0 \
				and float(s + 1) / segs > 0.45 and randf() < BRANCH_CHANCE:
			branches_left -= 1
			var side := 1.0 if randf() < 0.5 else -1.0
			var ba := d.rotated(side * randf_range(BRANCH_ANGLE_MIN, BRANCH_ANGLE_MAX))
			_branch(st, p2, ba, length * randf_range(CHILD_LEN.x, CHILD_LEN.y),
				w2 * CHILD_WIDTH, depth + 1, radius, 0)
		p = p2
		w = w2

## 마디 하나를 사다리꼴 판으로. UV.x 에 중심으로부터의 거리를 구워 넣는다(발광 파동용).
func _quad(st: SurfaceTool, a: Vector2, b: Vector2, wa: float, wb: float, radius: float) -> void:
	var perp := (b - a).orthogonal().normalized()
	var da := a.length()
	var db := b.length()
	var ua := clampf(da / radius, 0.0, 1.0)
	var ub := clampf(db / radius, 0.0, 1.0)
	# 중심에 가까울수록 굵게. 갈래도 중심 근처면 같이 굵어진다.
	var ka := wa * _hub(da, radius) * 0.5
	var kb := wb * _hub(db, radius) * 0.5
	var a0 := a - perp * ka
	var a1 := a + perp * ka
	var b0 := b - perp * kb
	var b1 := b + perp * kb
	_segments.append({a = a, b = b, w = maxf(ka, kb)})
	# UV = (중심에서의 거리, 가로 위치 -1~1), UV2.x = 그 지점의 반폭.
	# 셰이더가 이 둘로 "가장자리까지 남은 월드 거리"를 복원해 먹선을 긋는다.
	for v in [[a0, ua, -1.0, ka], [b0, ub, -1.0, kb], [b1, ub, 1.0, kb],
			[a0, ua, -1.0, ka], [b1, ub, 1.0, kb], [a1, ua, 1.0, ka]]:
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(v[1], v[2]))
		st.set_uv2(Vector2(v[3], 0.0))
		st.add_vertex(Vector3(v[0].x, 0.0, v[0].y))

# ---------------------------------------------------------------- 나머지 요소

## 중심부 굵기 배율. 중심에서 HUB_BOOST 배, HUB_FALLOFF 지점부터 1배.
func _hub(dist: float, radius: float) -> float:
	return 1.0 + (HUB_BOOST - 1.0) * (1.0 - smoothstep(0.0, radius * HUB_FALLOFF, dist))

## 바닥에 흩어진 작은 돌조각. 예고 구간에 떨고, 여진에 튄다.
func _pebble_field(radius: float) -> void:
	var mat := _flat_mat(COL_DEBRIS, 1.0)
	for i in randi_range(4, 7):
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3.ONE * randf_range(0.14, 0.24)
		box.material = mat
		mi.mesh = box
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var ang := randf_range(0.0, TAU)
		var d := radius * randf_range(0.25, 0.85)
		mi.position = Vector3(cos(ang) * d, 0.09, sin(ang) * d)
		mi.rotation.y = randf_range(0.0, TAU)
		_pebbles.append(mi)

## 불 속성 카드 조합 여부. 분출 연출이 빛(금색)에서 불/용암(주홍)으로 바뀐다.
var lava := false
var _lava_pulse: Tween   ## 분화구로 있는 동안 벌겋게 맥동시키는 루프
var _life: Tween         ## fire() 가 건 LINGER 수명 타이머. erupt() 가 수명을 다시 정한다.

## 불 속성 카드 조합: 균열에 잔열이 흐른다 — 이 자리를 다시 치면 분화구가 된다는 예고.
func ignite() -> void:
	lava = true
	if _crack_mat:
		_crack_mat.set_shader_parameter("ember", 0.9)
		# 잔열·분출 발광을 용암색으로 (기본은 옅은 금색 #f2b888)
		_crack_mat.set_shader_parameter("glow_col", COL_LAVA)

## 예고: 빛이 중심에서 바깥으로 번지고, 돌조각이 미세하게 떤다.
func tell() -> void:
	if _crack_mat:
		var tw := create_tween()
		tw.tween_method(
			func(v: float) -> void: _crack_mat.set_shader_parameter("wave_pos", v),
			-0.2, 1.25, 0.2).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(func() -> void: _crack_mat.set_shader_parameter("wave_pos", -1.0))
	for p in _pebbles:
		var base: Vector3 = p.position
		var tw2 := create_tween().set_loops(4)
		tw2.tween_property(p, "position", base + Vector3(
			randf_range(-0.04, 0.04), randf_range(0.0, 0.05), randf_range(-0.04, 0.04)), 0.025)
		tw2.tween_property(p, "position", base, 0.025)

## 여진 발생. 고리 + 바닥을 따라 퍼지는 돌조각.
## 이 시점부터 균열 지대가 LINGER 초 동안 살아있다.
func fire(radius: float, strength := 0.55) -> void:
	field_radius = radius
	active = true
	add_to_group("crack_fields")
	set_physics_process(true)
	# 수명이 다하면 스스로 사라진다 (erupt() 가 이 타이머를 갈아끼운다)
	_life = create_tween()
	# ⚠️ 불이 붙은 균열은 **분화구 수명만큼** 남는다. 첫 방에 분화구가 열리는 지금 구조에서
	#    LINGER(3초)로 두면 분화구(5초)보다 먼저 균열이 꺼져 "빛나던 틈이 갑자기 사라진다".
	_life.tween_interval((LAVA_LINGER if lava else LINGER) \
		* (spec.lifetime if spec != null else 1.0))
	_life.tween_callback(expire)

	_debris(radius, strength)
	# 바닥에 있던 돌조각도 같이 튀어오른다
	for p in _pebbles:
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(p, "position:y", randf_range(0.4, 0.8), 0.12) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(p, "rotation", p.rotation + Vector3(
			randf_range(-3.0, 3.0), randf_range(-3.0, 3.0), 0.0), 0.3)
		tw.chain().tween_property(p, "position:y", 0.05, 0.18) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
## 바닥을 따라 낮게 퍼지는 먼지. 최초 충돌 먼지와 달리 높이 솟지 않는다.
func _debris(radius: float, strength: float) -> void:
	var p := CPUParticles3D.new()
	p.emitting = false          # add_child 순간 원점에서 터지는 것 방지
	p.amount = int(14.0 * strength / 0.55)
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.35
	p.direction = Vector3.UP
	p.spread = 88.0             # 거의 수평 — 바닥을 따라 퍼진다
	p.initial_velocity_min = radius * 1.2
	p.initial_velocity_max = radius * 2.2
	p.gravity = Vector3(0.0, -26.0, 0.0)
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE * 0.22
	cube.material = _flat_mat(COL_DEBRIS, 1.0)
	p.mesh = cube
	add_child(p)
	p.position = Vector3(0.0, 0.12, 0.0)
	p.emitting = true

func _ready() -> void:
	set_physics_process(false)   # fire() 전까지는 감지할 필요가 없다

## 균열 "선"을 밟은 적 감지. 적마다 딱 한 번만 반응하고, 그 뒤론 그냥 걸어간다.
func _physics_process(_delta: float) -> void:
	if not active:
		return
	var r2 := field_radius * field_radius
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		var id := e.get_instance_id()
		if _stumbled.has(id):
			continue
		var d := e.global_position - global_position
		d.y = 0.0
		if d.length_squared() > r2:
			continue                       # 지대 밖 — 선분 검사도 생략(빠른 제외)
		if _touches_crack(Vector2(d.x, d.z), e.scale.x * 0.5):
			_stumbled[id] = true
			e.stumble(global_position)

## 균열 선 위의 임의 지점 (월드 좌표). 분화구가 여기서 불덩이를 뿜는다.
func random_crack_point() -> Vector3:
	if _segments.is_empty():
		return global_position
	var s: Dictionary = _segments.pick_random()
	var p: Vector2 = s.a.lerp(s.b, randf())
	return global_position + Vector3(p.x, 0.0, p.y)

## 로컬 XZ 좌표 p 가 균열 선분에 닿는가. touch = 적의 접촉 반경.
func _touches_crack(p: Vector2, touch: float) -> bool:
	for s in _segments:
		if _dist_to_seg(p, s.a, s.b) <= s.w + touch:
			return true
	return false

static func _dist_to_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 <= 0.0:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)

## 갈라진 땅을 망치로 다시 내려쳤을 때 — 지면이 분출한다.
## 피해/넉백은 HammerStrike 가 처리하고 여기서는 보이는 것만 맡는다.
## 분출 **연출만** 재생한다 — `active`(지대 상태)와 수명은 건드리지 않는다.
## ⚠️ erupt() 에서 갈라냈다 (유저 지시 2026-08-18: "첫 가격에 두 번째 가격의 이펙트가 나오게").
##    첫 방에 이 그림을 보여주면서도 균열은 살려둬야 한다 — 밟고 지나가기와 균열 계열 카드가
##    균열의 존재를 전제로 돌아가기 때문이다. 소모(consume)는 erupt() 만 한다.
func flare() -> void:
	# 균열이 안에서부터 확 밝아진다 + HDR 부스트로 bloom 이 번진다
	if _crack_mat:
		var tw := create_tween()
		tw.tween_method(
			func(v: float) -> void: _crack_mat.set_shader_parameter("wave_width", v),
			0.28, 2.0, 0.08)
		tw.parallel().tween_method(
			func(v: float) -> void: _crack_mat.set_shader_parameter("wave_pos", v),
			0.0, 0.6, 0.08)
		# 용암 모드는 부스트를 낮춘다 — 3.5 는 주홍색도 하얗게 태워서 "빛"으로 보인다
		tw.parallel().tween_method(
			func(v: float) -> void: _crack_mat.set_shader_parameter("boost", v),
			1.0, 2.0 if lava else 3.5, 0.06)

	_light_rays()
	_erupt_chunks()
	# 바닥 돌조각도 같이 솟구친다
	for p in _pebbles:
		var tw2 := create_tween()
		tw2.tween_property(p, "position:y", randf_range(1.2, 2.2), 0.16) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw2.parallel().tween_property(p, "rotation", p.rotation + Vector3(
			randf_range(-6.0, 6.0), randf_range(-6.0, 6.0), 0.0), 0.45)
		tw2.tween_property(p, "position:y", 0.05, 0.28) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# 불 조합: 균열이 곧 분화구다 — 분화구 수명 동안 벌겋게 맥동한다.
	# ⚠️ 이미 맥동 중이면 새로 걸지 않는다 (첫 방 flare + 재타격 erupt 로 두 번 불릴 수 있다).
	if lava and not (_lava_pulse and _lava_pulse.is_valid()):
		var pulse := create_tween().set_loops()
		pulse.tween_method(
			func(v: float) -> void: _crack_mat.set_shader_parameter("boost", v),
			1.5, 2.3, 0.6).set_trans(Tween.TRANS_SINE)
		pulse.tween_method(
			func(v: float) -> void: _crack_mat.set_shader_parameter("boost", v),
			2.3, 1.5, 0.6).set_trans(Tween.TRANS_SINE)
		_lava_pulse = pulse

## 균열 지대를 **소모**한다 — 연출(flare)에 더해 지대를 끄고 수명을 다시 잡는다.
func erupt() -> void:
	if not active:
		return
	active = false
	remove_from_group("crack_fields")
	set_physics_process(false)
	flare()
	# 원래 존속 타이머를 반드시 끈다 — 안 끄면 분화구(5초)보다 먼저 균열이 사라진다
	if _life and _life.is_valid():
		_life.kill()
	var t := create_tween()
	# 분화구 수명(Crater.LIFETIME)과 같은 값. 상수를 직접 참조하면
	# Crater <-> AftershockFX 순환 참조가 되어 스크립트 로드가 멈춘다.
	t.tween_interval(LAVA_LINGER if lava else 0.35)
	t.tween_callback(expire)

## 균열 틈새에서 솟는 빛줄기 — 분출의 하이라이트.
## 실제 균열 선분 위의 점에서만 나온다 (빈 땅에서 솟으면 어색하다).
func _light_rays() -> void:
	if _segments.is_empty():
		return
	for i in randi_range(14, 24):
		var s: Dictionary = _segments.pick_random()
		var p2: Vector2 = s.a.lerp(s.b, randf())
		# 불 모드: 빛기둥이 아니라 화염 혀 — 크고 굵게, 전용 불꽃 셰이더
		var h := randf_range(2.8, 5.4) if lava else randf_range(2.5, 5.0)
		var mi := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(randf_range(0.9, 1.7) if lava else randf_range(0.25, 0.6), h)
		var mat := ShaderMaterial.new()
		# 같은 색이라도 additive 로 겹치면 하얗게 날아가 "빛"으로 보인다 —
		# 불은 blend_mix + 실루엣 + 흔들림이 있는 전용 셰이더를 쓴다.
		mat.shader = FlameShader if lava else RayShader
		mat.set_shader_parameter("alpha_mul", 0.0)
		if lava:
			mat.set_shader_parameter("seed", randf() * 100.0)
			mat.set_shader_parameter("ink_width", FLAME_INK)   # 폭연은 0 그대로
		quad.material = mat
		mi.mesh = quad
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.rotation.y = randf_range(0.0, TAU)
		# 뿌리를 지면에 붙인 채 위로 자라나게: 스케일과 중심 높이를 같이 올린다
		mi.scale = Vector3(1.0, 0.35, 1.0)
		mi.position = Vector3(p2.x, h * 0.5 * 0.35, p2.y)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(mat, "shader_parameter/alpha_mul", 1.0, 0.05)
		tw.tween_property(mi, "scale:y", 1.0, 0.12) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "position:y", h * 0.5, 0.12) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if lava:
			# 불길은 ~1.5초 남아 핥다가, 서서히 오그라들며 꺼진다 (유저 스펙).
			# 뿌리를 바닥에 붙인 채 줄어들도록 scale.y 와 position.y 를 같이 내린다.
			tw.chain().tween_interval(randf_range(1.3, 1.7))
			var dur := randf_range(0.5, 0.8)
			tw.chain().tween_property(mi, "scale:y", 0.04, dur) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_property(mi, "position:y", h * 0.5 * 0.04, dur) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_property(mat, "shader_parameter/alpha_mul", 0.0, dur) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		else:
			tw.chain().tween_property(mat, "shader_parameter/alpha_mul", 0.0,
				randf_range(0.25, 0.4)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(mi.queue_free)

## 위로 솟구치는 흙먼지 — 여진의 바닥 먼지와 달리 수직으로 뿜는다.
## 실제 돌덩이(EruptRock)는 HammerStrike 가 따로 쏘므로, 여기는 잔먼지만 맡는다.
## 불 모드에선 흙 대신 **불똥(ember)**: 천천히 떠오르며 빛나는 알갱이.
func _erupt_chunks() -> void:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	var cube := BoxMesh.new()
	if lava:
		p.amount = 22
		p.lifetime = 1.1
		p.spread = 24.0
		p.initial_velocity_min = 4.0
		p.initial_velocity_max = 9.0
		p.gravity = Vector3(0.0, -4.0, 0.0)   # 거의 안 떨어진다 — 불똥은 떠오른다
		cube.size = Vector3.ONE * 0.14
		var m := StandardMaterial3D.new()
		m.albedo_color = COL_LAVA
		m.emission_enabled = true
		m.emission = COL_LAVA_GOLD
		m.emission_energy_multiplier = 1.8    # bloom 문턱(1.1)을 넘겨 반짝인다
		cube.material = m
	else:
		p.amount = 12
		p.lifetime = 0.6
		p.spread = 28.0
		p.initial_velocity_min = 9.0
		p.initial_velocity_max = 17.0
		p.gravity = Vector3(0.0, -30.0, 0.0)
		cube.size = Vector3.ONE * 0.18
		cube.material = _flat_mat(COL_RING, 1.0)
	p.mesh = cube
	add_child(p)
	p.position = Vector3(0.0, 0.15, 0.0)
	p.emitting = true

## 균열/자국을 서서히 지우고 스스로 사라진다.
func expire() -> void:
	if not is_inside_tree():
		return
	if _lava_pulse and _lava_pulse.is_valid():
		_lava_pulse.kill()
	active = false
	if is_in_group("crack_fields"):
		remove_from_group("crack_fields")
	set_physics_process(false)
	var tw := create_tween()
	tw.set_parallel(true)
	if _crack_mat:
		tw.tween_method(
			func(v: float) -> void: _crack_mat.set_shader_parameter("fade", v), 1.0, 0.0, FADE_OUT)
	for p in _pebbles:
		tw.tween_property(p, "scale", Vector3.ZERO, FADE_OUT)
	tw.chain().tween_callback(queue_free)

func _flat_mat(c: Color, a: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(c.r, c.g, c.b, a)
	return m
