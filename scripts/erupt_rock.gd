class_name EruptRock
extends Node3D

## 지면 분출로 솟아오른 돌덩이. 포물선을 그리며 날아가 **떨어진 자리에서** 범위 피해를 준다.
## 공중에서는 아무 판정도 없다 — 착지 순간에만 한 번 터진다.

const GRAVITY := 30.0
## 수직 초속. 정점 높이 = vy^2 / (2*GRAVITY) -> 15~21 이면 3.8~7.4 유닛까지 솟는다.
## 착지 지점은 spawn() 이 수평속도로 보정하므로 이 값만 올려도 낙하 위치는 그대로다.
const LAUNCH_VY := Vector2(15.0, 21.0)
const COL_ROCK := Color(0.529, 0.522, 0.486)   # nice31 #87857c (잔해 통계용 폴백)
const COL_ROCK_LIGHT := Color(0.737, 0.678, 0.624)  # nice31 #bcad9f 윗면

const LINGER := 1.5       ## 착지 후 바닥에 남아있는 시간
const FADE := 0.35        ## 그 뒤 사라지는 시간
## 지면에 박히는 비율 (전체 높이 대비).
## ⚠️ **피해를 주는 바위만** 깊게 박힌다 (유저 지시 2026-08-14: 15~25%).
##    잔해까지 깊게 박으면 작은 조각이 땅에 반쯤 잠겨 "떨어진 돌"이 아니라 얼룩이 된다.
const BURY := Vector2(0.30, 0.40)     ## 본체 — 조각마다 무작위 (0.10 -> 0.15~0.25 -> 0.30~0.40)
const BURY_DEBRIS := 0.08             ## 잔해 — 살짝 얹힌 정도

## --- 파헤쳐진 흙 (유저 지시 2026-08-14) --------------------------------------
## ⚠️ 묻는 것만으로는 화면에서 **아무 일도 일어나지 않는다.** 카메라가 직교 pitch -50 이라
##    윗면을 보는데 묻히는 건 밑면이라, 원래 안 보이던 부분이 사라질 뿐이다.
##    박혔다는 걸 알려줄 수 있는 자리는 **땅과 바위가 만나는 경계선** 하나뿐이라,
##    거기에 밀려난 흙 자국을 그린다.
##
## 셰이더는 불덩이 그을음(scorch)을 그대로 쓴다 — 가장자리를 울퉁불퉁하게 깎아 주므로
## 색만 흙색으로 바꾸면 된다. 원형 판때기로 깔면 접시가 얹힌 것처럼 보인다.
## ⚠️ glow 는 반드시 0 이다. 기본값(1.6)이면 자국이 벌겋게 타올라 '불에 그을린 자리'가 된다.
const ScorchShader := preload("res://shaders/scorch.gdshader")
## 색을 한 단계 어둡게 + 불투명하게 (유저 지시 2026-08-14).
## #734c44(62%) 는 초록 지면 위에서 옅게 떠서 "젖은 자국" 정도로만 읽혔다.
## 한 단계 내린 #593e47 을 85% 로 깔면 **파헤쳐진 구멍**으로 읽힌다.
const DIRT_COL := Color(0.349, 0.243, 0.278, 0.85)   ## nice31 #593e47 파헤쳐진 흙
const DIRT_DARK := Color(0.239, 0.2, 0.2)            ## nice31 #3d3333 가장자리 그늘
const DIRT_FIT := Vector2(1.9, 2.4)   ## 바위 발자국 대비 자국 크기 — 바위보다 넓어야 밀려난 게 읽힌다
const DIRT_Y := 0.03                  ## 지면 z-fighting 회피



const DUST_AMOUNT := 16   ## 착지 먼지 (망치 임팩트는 26 — 돌이라 조금 적게)

## 먹선 두께 (월드 유닛). 개미(0.006~0.012)보다 굵게 — 바위가 커서 가는 선은 안 보인다.
const OUTLINE := 0.045
const COL_ROCK_DARK := Color(0.388, 0.4, 0.388)   # nice31 #636663 어두운 면
const COL_INK := Color(0.239, 0.2, 0.2)           # nice31 #3d3333 (망치 돌 테두리와 동일)

## ⚠️ 살아 있는 동안은 **불투명 cel** 을 쓴다. cel_fade 는 ALPHA 를 쓰므로 투명 파이프라인으로
## 넘어가고, Godot 은 투명 재질에 **그림자를 만들지 않는다** — 처음부터 cel_fade 로 깔았더니
## 바위 그림자가 통째로 사라져 있었다 (유저 지적 2026-08-13).
## 그림자는 이 바위에 특히 중요하다: 공중에 있는 동안 낙하 지점을 미리 알려주는 유일한 단서다.
## 사라질 때만 cel_fade 사본으로 갈아끼운다 (보스 시체가 쓰는 것과 같은 수법).
const CelShader := preload("res://shaders/cel.gdshader")
const CelFadeShader := preload("res://shaders/cel_fade.gdshader")

## 기본 몹(지름 1.2)보다 큰 덩어리. 축마다 다르게 뽑아 정육면체를 피한다.
const SIZE_MIN := Vector3(1.44, 1.2, 1.44)
const SIZE_MAX := Vector3(1.92, 1.68, 1.92)

## --- 바위 asset (rocks.glb, 2026-08-14) ------------------------------------
## 예전엔 BoxMesh 였다. 이제 블렌더에서 구운 로우폴리 조각 24종에서 무작위로 뽑는다.
## ⚠️ **피해를 주는 것과 안 주는 것을 이름으로 가른다** (유저 지시 2026-08-14):
##    BOULDER/ROCK = 실제 피해. PEBBLE/CHIP/SHARD = 순수 이펙트(잔해).
##    잔해까지 판정에 넣으면 화면에 보이는 파편 수만큼 피해가 늘어 밸런스가 통째로 흔들린다.
const RocksScene := preload("res://assets/models/rocks.glb")
const DAMAGE_KINDS := ["BOULDER", "ROCK"]
const DEBRIS_KINDS := ["PEBBLE", "CHIP", "SHARD"]

## 잔해: 본체 하나가 터질 때 같이 튀는 조각 수와 크기(지름).
const DEBRIS_COUNT := Vector2i(4, 7)
const DEBRIS_SIZE := Vector2(0.18, 0.46)

## 분열체 규격. 원본보다 작고 약하다 — 같은 크기면 개수만 는 것으로 보인다.
const SPLIT_SIZE := 0.6
const SPLIT_DAMAGE := 0.5
const SPLIT_COEFF := 0.6
const DEBRIS_LINGER := Vector2(0.7, 1.4)   ## 본체(1.5)보다 짧게 — 잔해가 오래 남으면 지저분하다

## 이름 -> {mesh, ink}. glb 를 매번 instantiate 하면 분출마다 씬을 통째로 만든다.
static var _lib := {}
static var _lib_damage: Array[String] = []
static var _lib_debris: Array[String] = []

static func lib() -> Dictionary:
	if _lib.is_empty():
		var sc := RocksScene.instantiate()
		for mi in _collect(sc):
			var nm := String(mi.name)
			if nm.ends_with("Ink"):
				var base := nm.substr(0, nm.length() - 3)
				_lib.get_or_add(base, {})["ink"] = mi.mesh
			else:
				_lib.get_or_add(nm, {})["mesh"] = mi.mesh
		sc.free()
		for nm in _lib:
			var kind: String = String(nm).split("_")[0]
			if kind in DAMAGE_KINDS:
				_lib_damage.append(String(nm))
			elif kind in DEBRIS_KINDS:
				_lib_debris.append(String(nm))
		_lib_damage.sort()
		_lib_debris.sort()
	return _lib

static func _collect(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_collect(c))
	return out

## 바위 몸통 셀 재질. 블렌더는 3밴드지만 게임 셰이더는 2밴드라, 대비가 큰 쌍을 골라
## 3밴드의 인상을 흉내낸다 (밑동 재질이 3~4번째 톤을 맡는다).
static var _rock_mats := {}

static func rock_material(mat_name: String) -> ShaderMaterial:
	if not _rock_mats.has(mat_name):
		var m := ShaderMaterial.new()
		m.shader = CelShader
		if mat_name.begins_with("Cel_RockBase"):
			m.set_shader_parameter("light_tone", Color(0.451, 0.298, 0.267))  # #734c44
			m.set_shader_parameter("dark_tone", Color(0.239, 0.2, 0.2))       # #3d3333
		else:
			m.set_shader_parameter("light_tone", COL_ROCK_LIGHT)
			m.set_shader_parameter("dark_tone", COL_ROCK_DARK)
		m.set_shader_parameter("threshold", 0.42)
		_rock_mats[mat_name] = m
	return _rock_mats[mat_name]

## 사라질 때 갈아끼울 투명 사본. 색·경계는 살아 있을 때와 같아야 룩이 안 튄다.
##
## ⚠️ 예전엔 재질이 하나뿐이라(_mat) 그걸 베꼈다. 지금 바위는 서피스가 여러 개고
##    (몸통 / 흙 밑동) 재질도 서피스마다 다르다 — **그 서피스의 현재 재질**을 베껴야
##    사라지는 동안 밑동 색이 몸통 색으로 바뀌는 일이 없다.
func _fade_material_for(surface: int) -> ShaderMaterial:
	var src := _mesh.get_surface_override_material(surface) as ShaderMaterial
	var m := ShaderMaterial.new()
	m.shader = CelFadeShader
	if src != null:
		for k in ["light_tone", "dark_tone", "threshold"]:
			m.set_shader_parameter(k, src.get_shader_parameter(k))
	m.set_shader_parameter("alpha_mul", 1.0)
	return m

## 아무렇게나 회전해도 중심에서 이 거리를 넘지 않는다 (반대각선).
## 기지 회피 여유를 이 값으로 잡아야 모서리가 성을 파고들지 않는다.
static func max_half_extent() -> float:
	return (SIZE_MAX * 0.5).length()

var _ink_mat: StandardMaterial3D
var _mesh: MeshInstance3D
var _half := Vector3.ONE   ## 박스 반크기
var _vel := Vector3.ZERO
var _spin := Vector3.ZERO
var _damage := 0.0
var _radius := 1.6
var _landed := false
var _dirt: MeshInstance3D      ## 파헤쳐진 흙 자국 (본체만)
var _debris := false   ## 피해 없는 잔해인가 (이름이 PEBBLE/CHIP/SHARD 인 조각)
## 뽑힌 조각 이름 (BOULDER_A 등). ⚠️ 메시의 resource_name 은 임포터가 'rocks_EXP_' 를
## 앞에 붙여 놔서 분류에 못 쓴다 — 뽑을 때의 이름을 그대로 들고 있는다.
var _pick := ""

# --- 오브젝트 스펙에서 받은 값. 기본은 전부 '예전 그대로' ---
var _scale := 1.0
var _speed := 1.0
var _life := 1.0
var _split := 0
var _src: DamageSource
## 연출 전용인가. true 면 **착지해도 아무도 안 때린다** (유저 지시 2026-08-18) —
## 분출의 실제 판정은 도넛 면적이 맡는다. 바위가 하나하나 때리면 돌 사이 빈틈이
## 그대로 판정 구멍이 되어, 같은 자리에 서 있어도 운에 따라 맞고 안 맞고가 갈렸다.
var visual_only := false
## 이 바위가 솟았다 떨어지기까지 걸리는 **계산상** 시간(초). 참고용이다 —
## ⚠️ 실제 착지는 이보다 빠르다. 바위는 중심이 아니라 **최저점**이 지면에 닿는 순간 멈추고,
##    그 최저점은 조각 모양·회전·크기마다 다르다. 계수로 보정하려다 실측에서 어긋났다
##    (2026-08-18: 계산 평균으로 잡은 판정이 첫 착지보다 130ms 빨랐다).
##    그래서 타이밍이 필요한 쪽은 이 값이 아니라 **landed 시그널**을 쓴다.
var flight_time := 0.0

## 지면에 닿았다. 분출 판정이 이 순간에 맞춰 들어간다.
signal landed_on_ground

## land(월드 착지 지점)에 떨어지도록 속도를 역산해서 쏜다.
## spec 은 오브젝트 스펙 — 모디파이어가 이미 먹은 완성품이다. null 이면 예전 그대로.
## ⚠️ spec.count 는 여기서 안 본다. 몇 개를 쏠지는 **부르는 쪽**(HammerStrike._erupt_rocks)이
##    착지점을 고르며 정한다 — 여기서 세면 착지점 분배가 어긋난다.
static func spawn_at(parent: Node, origin: Vector3, land: Vector3,
		damage: float, radius: float, spec: ObjectSpec = null,
		debris_mul := 1.0) -> EruptRock:
	var r := EruptRock.new()
	if spec != null:
		r.visual_only = spec.visual_only
		r._scale = spec.scale
		r._speed = spec.speed
		r._life = spec.lifetime
		r._split = spec.split
		r._src = spec.src
	parent.add_child(r)
	r.global_position = origin + Vector3(0.0, 0.9, 0.0)   # 노드 y = 박스 중심
	# 질주: 초속을 낮추면 체공이 짧아지고 궤적이 눕는다 — "빠르게 날아간다"로 읽힌다
	var vy := randf_range(LAUNCH_VY.x, LAUNCH_VY.y) / maxf(r._speed, 0.01)
	var flight := 2.0 * vy / GRAVITY          # 올라갔다 같은 높이로 돌아오는 시간
	# ⚠️ **실제** 착지는 이보다 조금 빠르다 — 바위의 최저점이 지면에 닿는 순간 멈추기
	#    때문이다(_lowest_drop). 판정 타이밍을 여기에 맞추는 쪽에서 그 차이를 감안한다.
	r.flight_time = flight
	var delta := land - origin
	delta.y = 0.0
	r._vel = delta / flight + Vector3.UP * vy
	r._spin = Vector3(randf_range(-9.0, 9.0), randf_range(-9.0, 9.0), randf_range(-9.0, 9.0))
	r._damage = damage
	r._radius = radius
	ProjectileStats.spawned(&"rock")
	# 잔해를 같이 뿌린다 (유저 지시 2026-08-14). 본체와 **같은 자리에서** 솟아야
	# "한 번의 분출"로 읽힌다 — 따로 뿌리면 두 번 터진 것처럼 보인다.
	# ⚠️ debris_mul 로 줄일 수 있게 해 뒀다. 바위 개수가 수십 개로 늘면서 바위 하나당
	#    잔해 4~7 개를 그대로 붙이면 노드가 수백 개가 된다 — 이건 밸런스가 아니라
	#    성능 장치다 (이미 성능 작업을 한 프로젝트다).
	var deb := roundi(randf_range(DEBRIS_COUNT.x, DEBRIS_COUNT.y) * debris_mul)
	for i in deb:
		spawn_debris(parent, origin, land)
	return r

## 분열 — 떨어진 자리에서 작은 바위로 쪼개진다. 잔해(피해 0)와 달리 **피해가 있다.**
## ⚠️ 깊이를 먼저 확인한다. 안 그러면 쪼개진 게 또 쪼개져 무한히 는다 —
##    _split 을 자식에게 물려주지 않는 게 1차 방어, MAX_DEPTH 가 2차 방어다.
func _do_split(ground: Vector3) -> void:
	if _split <= 0 or _src == null or not _src.can_spawn():
		return
	var kid_src := _src.child(&"erupt_rock_split", SPLIT_COEFF)
	for i in _split:
		var a := TAU * float(i) / float(_split) + randf() * 0.5
		var land := ground + Vector3(cos(a), 0.0, sin(a)) * randf_range(1.6, 3.2)
		var kid := spawn_at(get_parent(), ground, land,
			_damage * SPLIT_DAMAGE, _radius * SPLIT_SIZE)
		kid._scale = _scale * SPLIT_SIZE
		kid._src = kid_src
		kid.visual_only = visual_only    # 연출 전용이 쪼개져도 연출 전용이다

## 피해 없는 잔해 한 조각. 본체보다 넓게 흩어지고 빨리 사라진다.
## airtime > 0 이면 그 체공시간이 나오도록 초속을 역산한다 (v = g·t/2).
## 우클릭 망치 착탄처럼 "하늘 높이 튀었다 떨어지는" 연출에 쓴다.
static func spawn_debris(parent: Node, origin: Vector3, land: Vector3,
		airtime := 0.0, spread_range := Vector2(0.8, 3.2)) -> EruptRock:
	var r := EruptRock.new()
	r._debris = true
	parent.add_child(r)
	r.global_position = origin + Vector3(0.0, 0.5, 0.0)
	var vy: float = airtime * GRAVITY * 0.5 if airtime > 0.0 \
		else randf_range(LAUNCH_VY.x * 0.55, LAUNCH_VY.y * 0.85)
	var flight := 2.0 * vy / GRAVITY
	# 착지점을 본체 주변으로 흩는다 — 같은 점에 모이면 무더기로 쌓여 한 덩어리가 된다
	var spread := randf_range(spread_range.x, spread_range.y)
	var a := randf_range(0.0, TAU)
	var delta := land - origin + Vector3(cos(a), 0.0, sin(a)) * spread
	delta.y = 0.0
	r._vel = delta / flight + Vector3.UP * vy
	r._spin = Vector3(randf_range(-16.0, 16.0), randf_range(-16.0, 16.0),
		randf_range(-16.0, 16.0))          # 작아서 본체보다 빨리 돈다
	r._damage = 0.0
	r._radius = 0.0
	return r

func _ready() -> void:
	var L := lib()
	var pool: Array[String] = _lib_debris if _debris else _lib_damage
	_pick = pool[randi() % pool.size()]
	var src: Mesh = L[_pick]["mesh"]

	# 크기: 메시의 실제 지름을 재서 목표 지름으로 맞춘다. 조각마다 원본 크기가 달라
	# 배율을 그냥 곱하면 BOULDER 와 ROCK 이 제각각이 된다.
	var ab := src.get_aabb()
	var raw: float = maxf(ab.size.x, maxf(ab.size.y, ab.size.z))
	# 가장 긴 축을 목표 지름에 맞춘다. 본체는 예전 박스의 **가로 범위**(1.44~1.92)를 쓴다 —
	# 세로 범위(1.2~1.68)로 맞추면 새 조각이 전체적으로 예전 바위보다 작아진다.
	var want: float = (randf_range(DEBRIS_SIZE.x, DEBRIS_SIZE.y) if _debris \
		else randf_range(SIZE_MIN.x, SIZE_MAX.x)) * _scale
	var k: float = want / maxf(raw, 0.001)

	var mi := MeshInstance3D.new()
	mi.mesh = src
	mi.scale = Vector3.ONE * k
	for i in src.get_surface_count():
		var sm: Material = src.surface_get_material(i)
		# ⚠️ 재질은 **이름으로** 고른다. glTF 는 그 조각이 실제로 쓰는 재질만 서피스로 만들어서
		#    번호로 꽂으면 밑동 색이 몸통에 칠해진다 (장수풍뎅이에서 겪은 함정).
		mi.set_surface_override_material(i,
			rock_material(sm.resource_name if sm != null else ""))
	# 그림자를 켠다. 공중에서는 낙하 지점을 미리 알려주고, 착지 후엔 접지 그림자가 된다.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	# **회전은 노드가 아니라 메시가 갖는다.** 노드에 걸면 회전축이 노드 원점이라,
	# 뒤집힌 바위가 통째로 땅속으로 들어가 그림자까지 사라진다.
	mi.rotation = Vector3(randf_range(0.0, TAU), randf_range(0.0, TAU), randf_range(0.0, TAU))
	_mesh = mi
	_half = ab.size * 0.5 * k

	# 먹선 = 블렌더에서 구운 역헐(법선이 뒤집힌 껍질). 박스 시절엔 스케일로 만들었지만
	# 임의 형상은 그렇게 못 한다 — 면마다 필요한 두께가 달라 모서리가 벌어진다.
	# ⚠️ cull_mode 를 건드리지 않는다. 껍질에 이미 뒤집힌 법선이 구워져 있어서
	#    기본 후면 컬링이 그대로 윤곽을 만든다. CULL_FRONT 를 주면 도로 뒤집힌다.
	var ink_mesh: Mesh = L[_pick].get("ink")
	if ink_mesh != null:
		var ink := MeshInstance3D.new()
		ink.mesh = ink_mesh
		_ink_mat = StandardMaterial3D.new()
		_ink_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ink_mat.albedo_color = COL_INK
		# 본체보다 나중에 그려야 본체가 써둔 깊이에 껍질 안쪽이 걸러진다.
		_ink_mat.render_priority = 1
		ink.material_override = _ink_mat
		ink.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.add_child(ink)

## 무언가 박힌 자리에 밀려난 흙 자국. **분출 바위와 우클릭 망치가 공유한다** —
## 같은 "땅에 박혔다"를 그리는 것이므로 문법이 갈리면 안 된다 (유저 지시 2026-08-14).
## radius = 자국의 반경(월드 유닛). 부르는 쪽이 제 몸 크기에 맞춰 정한다.
static func dirt_patch(parent: Node, at: Vector3, radius: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()          # PlaneMesh 는 XZ 평면 — 바닥에 그대로 눕는다
	plane.size = Vector2(radius * 2.0, radius * 2.0)
	var m := ShaderMaterial.new()
	m.shader = ScorchShader
	m.set_shader_parameter("col", DIRT_COL)
	m.set_shader_parameter("glow_col", DIRT_DARK)
	# ⚠️ 트윈할 유니폼은 **미리 심어 둬야** 한다. 셰이더 기본값에 맡기면
	#    tween 이 "그런 프로퍼티 없음"으로 실패해 자국이 영영 안 사라진다
	#    (불덩이 자국에서 겪은 것과 같은 함정 — fireball.gd 주석 참고).
	# ⚠️ glow 는 반드시 0. 기본값(1.6)이면 자국이 벌겋게 타올라 '그을린 자리'가 된다.
	m.set_shader_parameter("glow", 0.0)
	m.set_shader_parameter("alpha_mul", 1.0)
	m.set_shader_parameter("seed", randf() * 40.0)
	plane.material = m
	mi.mesh = plane
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = Vector3(at.x, DIRT_Y, at.z)
	mi.rotation.y = randf_range(0.0, TAU)   # 자국이 매번 다른 모양으로 읽히게
	return mi

## 바위가 박힌 자리의 흙 자국. **바위의 자식이지만 변환은 끊는다**(top_level) —
## 바위는 아무렇게나 기울어 박히는데 자국이 따라 기울면 지면에서 떠서 판때기가 된다.
## 자식으로 두는 이유는 바위가 사라질 때 같이 없어지게 하려는 것뿐이다.
func _dirt_patch() -> void:
	var r: float = maxf(_half.x, _half.z) * randf_range(DIRT_FIT.x, DIRT_FIT.y)
	_dirt = dirt_patch(self, global_position, r)
	_dirt.top_level = true

## 회전한 박스가 세로로 차지하는 반높이. 최저점 = 중심 y - 이 값.
## 회전한 상태에서 메시가 중심보다 얼마나 아래로 내려가는가 (월드 유닛).
##
## ⚠️ **AABB 로 재면 안 된다.** 울퉁불퉁한 바위는 AABB 모서리가 빈 공간이라, 박스로 재면
##    실제 최저점보다 낮은 값이 나오고 그만큼 바위가 **공중에 뜬다**. 크기 배율이 붙으면
##    뜨는 높이도 같이 배가 되어, 거대화(×2)에서는 눈에 띄게 떠 보였다 (유저 지적 2026-08-18).
##    실제 정점을 전부 훑어서 최저점을 찾는다 — 로우폴리라 착지 한 번에 수백 개 수준이다.
static var _verts_cache := {}

static func _verts(pick: String) -> PackedVector3Array:
	if not _verts_cache.has(pick):
		_verts_cache[pick] = (lib()[pick]["mesh"] as Mesh).get_faces()
	return _verts_cache[pick]

func _lowest_drop() -> float:
	var b := _mesh.transform.basis      # 회전 + 크기(k)가 함께 들어 있다
	var lo := 0.0
	for v in _verts(_pick):
		lo = minf(lo, (b * v).y)
	return -lo

func _physics_process(delta: float) -> void:
	if _landed:
		return
	_vel.y -= GRAVITY * delta
	global_position += _vel * delta
	_mesh.rotation += _spin * delta
	# 내려가는 중일 때만 착지 판정 (솟아오르는 첫 프레임에 걸리지 않게)
	# 착지 기준은 y=0 이 아니라 **그 자리 지면**이다 (지형에 높이가 생긴 뒤로).
	if _vel.y < 0.0 and global_position.y - _lowest_drop() <= Terrain.h(global_position):
		_land()

func _land() -> void:
	_landed = true
	landed_on_ground.emit()
	set_physics_process(false)
	# 날아오던 모습 **그대로** 멈춘다 — 회전도 크기도 건드리지 않는다.
	# 전체 높이의 bury 만큼만 땅에 박히도록 중심 높이를 맞춘다:
	#   최저점 = 중심 - 반높이 = -(2*반높이) * bury  ->  중심 = 반높이 * (1 - 2*bury)
	var hh := _lowest_drop()
	var bury: float = BURY_DEBRIS if _debris else randf_range(BURY.x, BURY.y)
	global_position.y = Terrain.h(global_position) + hh * (1.0 - 2.0 * bury)
	if not _debris:
		_dirt_patch()


	# 피해와 먼지는 바위 중심이 아니라 지면 접지점 기준
	var ground := Vector3(global_position.x, 0.0, global_position.z)
	# ⚠️ 잔해는 **판정도 통계도 없다** — 순수 이펙트다 (유저 지시 2026-08-14).
	#    화면에 보이는 파편마다 피해가 들어가면 분출 한 번의 위력이 몇 배가 된다.
	if _debris:
		ImpactDust.burst(get_parent(), ground, 3, 0.5)   # 톡 튀는 흙먼지만
		_start_fade(randf_range(DEBRIS_LINGER.x, DEBRIS_LINGER.y))
		return
	if visual_only:
		# 판정은 도넛이 이미 했다. 흙먼지와 자국만 남기고 물러난다.
		ImpactDust.burst(get_parent(), ground, DUST_AMOUNT)
		_do_split(ground)
		_start_fade(LINGER * _life)
		return
	var hits := 0
	var dealt := 0.0
	var wasted := 0.0
	var kills := 0
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		var d := e.global_position - ground
		d.y = 0.0
		if d.length() <= _radius + e.hit_radius:
			var before := e.health
			e.flash_hit()      # 물리 타격이라 흰색 — 불 계열(주홍)과 색으로 구분된다
			e.take_damage(_damage, ground, _src)
			hits += 1
			dealt += minf(_damage, before)
			wasted += maxf(_damage - before, 0.0)
			if e.dying:
				kills += 1
	ProjectileStats.landed(&"rock", hits, dealt, wasted, kills)

	# 망치 임팩트와 같은 흙먼지. 돌은 곧 사라지므로 부모에 붙여 따로 살게 한다.
	ImpactDust.burst(get_parent(), ground, DUST_AMOUNT)
	_do_split(ground)
	_start_fade(LINGER * _life)

## 박힌 모습 그대로 버티다가 스르르 사라진다. 본체와 잔해가 같은 코드를 쓴다 —
## 사라지는 문법이 갈리면 같은 분출에서 튀어나온 것들이 따로 노는 것처럼 보인다.
func _start_fade(linger: float) -> void:
	var tw := create_tween()
	tw.tween_interval(linger)
	# 스르르 사라진다 (크기를 줄이면 땅에 빨려드는 것처럼 보여서 알파로 뺀다)
	tw.tween_callback(func() -> void:
		if _ink_mat != null:
			_ink_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# 여기서부터만 투명해진다. 이 순간 그림자는 사라지지만, 어차피 사라지는 중이다.
		# ⚠️ 서피스 **전부**를 갈아야 한다. 0번만 갈면 흙 밑동이 불투명하게 남아
		#    몸통이 사라진 뒤에도 밑동 조각만 떠 있다.
		for i in _mesh.mesh.get_surface_count():
			_mesh.set_surface_override_material(i, _fade_material_for(i)))
	if _dirt != null:
		# 흙 자국도 같이 옅어진다 — 바위가 사라졌는데 자국만 남으면 그게 얼룩이다
		tw.parallel().tween_method(func(a: float) -> void:
			if is_instance_valid(_dirt):
				(_dirt.mesh as PlaneMesh).material.set_shader_parameter("alpha_mul", a),
			1.0, 0.0, FADE)
	tw.tween_method(func(a: float) -> void:
		for i in _mesh.mesh.get_surface_count():
			var m := _mesh.get_surface_override_material(i)
			if m is ShaderMaterial:
				(m as ShaderMaterial).set_shader_parameter("alpha_mul", a),
		1.0, 0.0, FADE)
	# 테두리는 조금 앞서 빠진다 — 깊이로 걸러도 실루엣 가장자리엔 껍질이 남기 때문에,
	# 끝까지 같이 가면 마지막에 윤곽선만 떠 있는 순간이 생긴다.
	if _ink_mat != null:
		tw.parallel().tween_property(_ink_mat, "albedo_color:a", 0.0, FADE * 0.7)
	tw.tween_callback(queue_free)
