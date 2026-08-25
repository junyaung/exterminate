class_name Fireball
extends Node3D

## 분화구가 뿜는 불덩이.
##   1단계 — 균열에서 짧게 솟아오른다 (포물선)
##   2단계 — 착지 후 **정해진 방향으로 3초간 일직선으로 굴러간다**. 스치는 적을 태운다.
##
## 왜 굴리나: 한 점에 떨어지는 방식은 명중률이 밀도에 갇힌다(실측 10%).
## 굴리면 원(면적 πr²)이 아니라 **띠(길이×지름)** 를 쓸어서, 성긴 전장에서도 뭔가에 닿는다.
## 적 하나당 한 번만 태운다 — 같은 적을 계속 밀며 지나가도 중복 피해는 없다.

const GRAVITY := 30.0
const ARC_VY := 7.0          ## 솟는 높이 — 낮게 뿜어 바로 구르기 시작한다
const ARC_DIST := 2.2        ## 솟아 나가는 수평 거리
const ROLL_TIME := 3.0       ## 구르는 시간
const ROLL_SPEED := 6.0      ## 구르는 속도 (3초 = 18유닛, 화면 폭의 절반쯤)
const COL := Color(0.922, 0.588, 0.38)       # nice31 #eb9661
const COL_CORE := Color(0.992, 0.82, 0.475)  # nice31 #fdd179
const COL_CHAR := Color(0.239, 0.2, 0.2)     # nice31 #3d3333 다 타고 남은 재

## 불타는 궤적: 구르며 일정 간격으로 **재 한 겹만** 떨군다.
## 예전엔 그 위에 밝은 불 웅덩이(fire_trail.gdshader)를 한 겹 더 얹었는데,
## step 으로 딱 잘린 5~8갈래 실루엣이 **별모양 도장**으로 읽혀서 뺐다 (유저 지시 2026-08-18).
## 떨구던 함수(_fire_decal)는 지웠지만 **셰이더 파일은 남겨뒀다** — 되살리고 싶으면
## _char_decal 을 본떠 fire_trail.gdshader 를 물린 데칼을 다시 만들면 된다.
## 세로 불혀(_flame_tongue)와 마지막 화염 버스트도 앞서 같은 이유로 빠졌다.
## 분열체 규격. 원본보다 작고 약하고 짧게 산다 — 같은 크기면 개수만 는 것으로 보인다.
const SPLIT_SIZE := 0.6
const SPLIT_DAMAGE := 0.5
const SPLIT_COEFF := 0.6     ## 자식에게 물려주는 proc 계수 (RoR2 방식 감쇠)

const SCORCH_STEP := 0.16    ## 떨구는 간격(초)
const SCORCH_LIFE := 1.3     ## 재가 사라지기까지

const ScorchShader := preload("res://shaders/scorch.gdshader")

var _mesh: MeshInstance3D
var _r := 1.0
var _vel := Vector3.ZERO
var _dir := Vector3.FORWARD
var _damage := 0.0
var _radius := 2.0
var _rolling := false
var _roll_left := 0.0
var _trail := 0.0
var _done := false
## 구르는 내내 주변을 물들인다 (유저 요청 2026-08-17). -1 = 슬롯을 못 잡음.
var _fire_slot := -1
# 누적 통계 (구르는 내내 쌓아 마지막에 한 번 보고한다)
var _hit_ids := {}
var _dealt := 0.0
var _wasted := 0.0
var _kills := 0

## dir 방향으로 솟았다가 그 방향으로 굴러간다.
## spec 은 오브젝트 스펙(ObjectSpec). 모디파이어가 이미 적용된 **완성품**이 들어온다 —
## 여기서 태그를 보거나 모디파이어를 뒤지지 않는다.
## null 이면 예전 그대로 (배율 1.0, 출처 없음, 분열 없음).
static func spawn_roll(parent: Node, origin: Vector3, dir: Vector2,
		damage: float, radius: float, spec: ObjectSpec = null) -> Fireball:
	var f := Fireball.new()
	parent.add_child(f)
	f.global_position = origin + Vector3(0.0, 0.4, 0.0)
	f._dir = Vector3(dir.x, 0.0, dir.y).normalized()
	var flight := 2.0 * ARC_VY / GRAVITY
	f._vel = f._dir * (ARC_DIST / flight) + Vector3.UP * ARC_VY
	f._damage = damage
	f._radius = radius
	if spec != null:
		f._scale = spec.scale
		f._speed = spec.speed
		f._life = spec.lifetime
		f._split = spec.split
		f._src = spec.src
	ProjectileStats.spawned(&"fire")
	return f

# --- 오브젝트 스펙에서 받은 값. 기본은 전부 '예전 그대로' ---
var _scale := 1.0
var _speed := 1.0
var _life := 1.0
var _split := 0
var _src: DamageSource

func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	_r = randf_range(0.9, 1.26) * _scale   # 기본 몹(반지름 0.6)보다 큰 화산탄
	sphere.radius = _r
	sphere.height = _r * 2.0
	sphere.radial_segments = 8    # 로우폴리 각짐
	sphere.rings = 4
	var m := StandardMaterial3D.new()
	m.albedo_color = COL
	# HDR 발광 — bloom 문턱(1.1)을 넘겨 불덩이가 빛나며 굴러간다
	m.emission_enabled = true
	m.emission = COL_CORE
	m.emission_energy_multiplier = 2.2
	sphere.material = m
	_mesh.mesh = sphere
	# 스스로 빛나는 물체지만 그림자는 켠다 — 굴러오는 위치가 읽힌다.
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_mesh)

	# 먹선 껍질 — 살짝 키운 같은 구 + 앞면 컬링. 불 계열이라 잉크는 검정이 아니라
	# 어두운 갈적색(#734c44): 카툰 불꽃의 외곽선 문법이고, bloom 이 살짝 덮어도 죽지 않는다.
	var ink := MeshInstance3D.new()
	ink.mesh = sphere
	ink.scale = Vector3.ONE * ((_r + 0.05) / _r)
	var ink_m := StandardMaterial3D.new()
	ink_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink_m.cull_mode = BaseMaterial3D.CULL_FRONT
	ink_m.albedo_color = Color(0.451, 0.298, 0.267)   # nice31 #734c44
	ink.material_override = ink_m
	ink.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.add_child(ink)

## ⚠️ 슬롯은 반드시 돌려준다 (_finish 로 끝나든 중간에 지워지든).
func _exit_tree() -> void:
	FireLights.release(_fire_slot)
	_fire_slot = -1

func _physics_process(delta: float) -> void:
	if _done:
		return
	# 불덩이는 **움직이는 불**이라 매 프레임 위치를 갱신한다. 반경은 불덩이 크기(_r)에
	# 비례시킨다 — 큰 화산탄이 더 넓게 물들어야 크기가 거짓말을 안 한다.
	# 굴러가는 불이라 넓게 잡는다 (9.0+_r*4.0 = 12.6~14.0). 감쇠가 제곱이라 가운데가 밝고
	# 바깥은 옅게 깔린다. ⚠️ 세기는 0.9 -> 0.65 로 내렸다 — 밴딩을 없애고 나니
	# 가운데가 하얗게 타서(유저 스크린샷) 굴러가는 불이 스포트라이트로 보였다.
	if _fire_slot < 0:
		_fire_slot = FireLights.acquire()
	FireLights.put(_fire_slot, global_position, 9.0 + _r * 4.0, COL_CORE, 0.65)
	if _rolling:
		_roll_left -= delta
		global_position += _dir * ROLL_SPEED * _speed * delta
		# 구르는 회전: 진행 방향과 직각인 수평축으로, 각속도 = 속도/반지름
		_mesh.rotate(Vector3.UP.cross(_dir).normalized(), ROLL_SPEED * _speed / _r * delta)
		_burn_touching()
		_trail -= delta
		if _trail <= 0.0:
			_trail = SCORCH_STEP
			_scorch()
		if _roll_left <= 0.0:
			_finish()
		return
	# 솟아오르는 중
	_vel.y -= GRAVITY * delta
	global_position += _vel * delta
	if _vel.y < 0.0 and global_position.y <= Terrain.h(global_position) + _r:
		global_position.y = Terrain.h(global_position) + _r
		_rolling = true
		_roll_left = ROLL_TIME * _life
		ImpactDust.burst(get_parent(), Vector3(global_position.x, 0.0, global_position.z),
			8, 0.6, COL_CORE)

## 지금 닿아 있는 적을 태운다. 같은 적은 한 번만.
func _burn_touching() -> void:
	var ground := Terrain.on(global_position)
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		var id := e.get_instance_id()
		if _hit_ids.has(id):
			continue
		var d := e.global_position - ground
		d.y = 0.0
		if d.length() <= _radius + e.hit_radius:
			_hit_ids[id] = true
			var before := e.health
			e.flash_burn()     # 폭연과 같은 신호 — 불에 데면 주홍으로 번쩍인다
			e.take_damage(_damage, ground, _src)
			_dealt += minf(_damage, before)
			_wasted += maxf(_damage - before, 0.0)
			if e.dying:
				_kills += 1
				# 불에 죽었으면 **불에 어울리는 죽음**을 준다 (유저 지시 2026-08-14):
				# 납작해지는 대신 종이처럼 타들어가며 재가 되어 날아간다.
				# ⚠️ 보스는 뺀다 — 자기 사망 연출(조각 분해)이 따로 있고, 거기에
				#    끼어들면 조각이 안 나오거나 두 연출이 겹친다.
				if not (e is Boss):
					e.burn_away()

func _finish() -> void:
	_done = true
	set_physics_process(false)
	var ground := Terrain.on(global_position)
	_do_split(ground)
	ProjectileStats.landed(&"fire", _hit_ids.size(), _dealt, _wasted, _kills)
	# 마지막 화염 버스트(_flame_burst)는 유저 지시로 제거 — 끝은 불똥 먼지 한 줌으로만
	ImpactDust.burst(get_parent(), ground, 12, 0.7, COL_CORE)
	queue_free()

## 분열 — 다 굴러간 자리에서 작은 불덩이로 쪼개진다.
## ⚠️ **반드시 child_src 로 깊이를 확인한다.** 안 그러면 쪼개진 게 또 쪼개져서 무한히 는다.
##    MAX_DEPTH 를 넘으면 child_src 가 null 을 주고, 여기서 조용히 멈춘다.
func _do_split(ground: Vector3) -> void:
	if _split <= 0 or _src == null:
		return
	if not _src.can_spawn():
		return
	var kid_src := _src.child(&"fireball_split", SPLIT_COEFF)
	for i in _split:
		var a := TAU * float(i) / float(_split) + randf() * 0.4
		var kid := spawn_roll(get_parent(), ground, Vector2(cos(a), sin(a)),
			_damage * SPLIT_DAMAGE, _radius * SPLIT_SIZE)
		kid._scale = _scale * SPLIT_SIZE
		kid._life = _life * 0.6
		kid._src = kid_src
		# ⚠️ 분열체는 **다시 분열하지 않는다** — _split 을 물려주지 않는 게 1차 방어,
		#    깊이 상한이 2차 방어다. 둘 다 둔 건 나중에 "분열 강화" 카드가 생겼을 때
		#    깊이만으로 막히게 하기 위해서다.

## 지나간 자리에 불을 떨군다. 뒤쪽부터 차례로 사그라지며 궤적처럼 보인다.
## 불덩이는 3초 뒤 사라지므로 자국은 부모(HammerStrike)에 붙여 따로 살게 한다.
## 세로 불꽃 혀(_flame_tongue)는 유저 지시로 뺐다 — 굴러가는 동안은 바닥 자국만 남긴다.
func _scorch() -> void:
	# 공 한가운데가 아니라 살짝 뒤에 떨궈야 "끌고 가는 꼬리"가 된다
	var at := global_position - _dir * _r * 0.55
	_char_decal(at)

## 재 — 다 타고 남은 검은 자국. 넓게, 어둡게, 오래.
func _char_decal(at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()          # PlaneMesh 는 XZ 평면 — 바닥에 그대로 눕는다
	# 쿼드는 사각형이지만 셰이더가 가장자리를 깎아 울퉁불퉁한 자국만 남긴다
	plane.size = Vector2(_radius * randf_range(1.5, 1.9), _radius * randf_range(1.5, 1.9))
	var m := ShaderMaterial.new()
	m.shader = ScorchShader
	m.set_shader_parameter("col", Color(COL_CHAR.r, COL_CHAR.g, COL_CHAR.b, 0.45))
	m.set_shader_parameter("glow_col", COL_CHAR)
	m.set_shader_parameter("seed", randf() * 30.0)
	# ⚠️ 트윈할 유니폼은 **반드시 먼저 set_shader_parameter 로 심어야** 한다.
	# 셰이더 기본값에 맡기면 tween_property("shader_parameter/alpha_mul") 가
	# "그런 프로퍼티 없음"으로 실패하고 트윈 전체가 죽는다(자국이 안 사라진다).
	m.set_shader_parameter("glow", 0.0)   # 벌건 속은 불 레이어가 담당한다
	m.set_shader_parameter("alpha_mul", 1.0)
	plane.material = m
	mi.mesh = plane
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(mi)
	# y 를 미세하게 흩어 같은 높이에서 겹칠 때 생기는 정렬 깜빡임을 피한다
	mi.global_position = Vector3(at.x, randf_range(0.02, 0.05), at.z)
	mi.rotation.y = randf_range(0.0, TAU)
	var tw := mi.create_tween()
	tw.tween_property(m, "shader_parameter/alpha_mul", 0.0, SCORCH_LIFE) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)

# 세로 불꽃(궤적의 혀, 마지막 버스트)은 전부 유저 지시로 제거됐다.
# 불덩이의 불은 이제 **공 자체의 발광 + 바닥의 검은 재** 두 가지로만 말한다.
