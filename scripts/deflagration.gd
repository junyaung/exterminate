class_name Deflagration
extends Node3D

## 폭연 — 불 속성 + 기본 공격.
## 망치에 **직접** 맞아 죽은 적이 잠깐 뒤 그 자리에서 터진다.
##
## 정체성 정리 (다른 속성/카드와 겹치지 않게):
##   불(폭연) — 적이 **죽는 순간** 발생하는 즉발 범위 공격. 지속시간·스택·상태 아이콘이 없다.
##   독        — 오래 누적되는 지속 피해
##   전염(상태이상 카드) — **살아 있는** 적에게 상태를 복사
## 연달아 터지는 것처럼 보여도 시스템상 전염이 아니다: 상태가 옮겨가는 게 아니라
## 이미 정해진 시체 목록이 순서대로 터질 뿐이다.
##
## ⚠️ **폭연 피해로 죽은 적은 다시 터지지 않는다** (무한 연쇄·화면 혼잡 방지).
## 플래그로 막지 않는다 — 터뜨릴 대상이 HammerStrike 의 **직접 타격 사망자 목록**에서만
## 오기 때문에 구조적으로 불가능하다. 아래 _burn() 의 사망자는 아무도 수집하지 않는다.

## 아직 안 터진 폭연이 들어있는 그룹. CardUI 가 카드 창을 늦출지 판단하는 데 쓴다.
const BLAST_PENDING := &"blast_pending"
const DELAY := 1.0         ## 처치 후 터지기까지 — 이 시간 내내 시체가 부풀어 오른다
## 시체마다 조금씩 어긋나게 터뜨린다. 동시에 터지면 작은 원 여러 개가 아니라
## 하나의 큰 원으로 뭉쳐 보여서 "곳곳에서 연쇄적으로" 라는 인상이 사라진다.
const STAGGER := 0.05

## 충격파 링이 퍼지는 최대 배율. **링이 닿는 곳이 곧 피해 범위**다 —
## 링만 커지고 판정은 중심에 머물면 "왜 저기 있는 놈은 멀쩡하지"가 된다.
const RING_REACH := 1.75
const RING_TIME := 0.32

const COL_CORE := Color(0.992, 0.82, 0.475)   # nice31 #fdd179
const COL_MID := Color(0.922, 0.588, 0.38)    # nice31 #eb9661

## ⚠️ 폭발 연출은 **카툰화 이전 상태로 전면 복원**됐다 (2026-08-12 유저:
## "카툰해달라고 하기 전의 폭연 이펙트가 딱 마음에 들었는데 손보다가 더 이상해졌다").
## 그 사이 시도했다 버린 것: 스텝 링, 스텝/돔 섬광, 겹불꽃 셰이더, 버스트 별, 뭉게구름,
## 0.75초 잔향 링. 남긴 것: 링이 피해를 싣는 구조(카툰 전에 확정된 스펙).
## 화염 셰이더는 flame_jet 이 카툰판으로 덮어써졌으므로 **원본과 동일한 lava_flame** 을 쓴다.
const FlameShader := preload("res://shaders/lava_flame.gdshader")

## 터지는 순간 주변(벌레·바닥·성)을 물들이는 시간 (유저 요청 2026-08-17).
## ⚠️ **짧아야 한다.** 폭발은 번쩍하고 끝나는 사건이다 — 길게 끌면 화면에 주황 등이 켜진 꼴이 된다.
## 섬광 메시(_flash)보다 조금만 길게 둬서, 섬광이 꺼진 뒤에도 잔광이 남는 것처럼 보이게 한다.
## (유저 지시 2026-08-17: "더 먼 거리까지". 0.45 -> 0.55 로 아주 조금만 늘렸다 —
##  더 끌면 번쩍임이 아니라 등불이 된다.)
const LIGHT_TIME := 0.55

## 빛 반경 = 폭발 반경 × 이 값. 폭발 반경 4 기준 20, 퍼지면서 27 까지 간다.
## 폭발 자체(반경 4)보다 빛이 훨씬 넓은 게 맞다 — 불빛은 피해 범위가 아니라
## "번쩍했다"는 사건의 크기다. 감쇠가 제곱이라 바깥쪽은 알아서 옅게 깔린다.
const LIGHT_REACH := 5.0

var _fire_slot := -1
var _light_left := 0.0
var _light_r := 0.0

## ⚠️ 슬롯은 반드시 돌려준다 — 폭연은 한 판에 수십 번 터지므로 새면 금방 8칸이 다 막힌다.
func _exit_tree() -> void:
	FireLights.release(_fire_slot)
	_fire_slot = -1

func _process(delta: float) -> void:
	if _light_left <= 0.0:
		return
	_light_left -= delta
	if _light_left <= 0.0:
		FireLights.release(_fire_slot)
		_fire_slot = -1
		return
	var k := _light_left / LIGHT_TIME          # 1 -> 0
	# 사그라들며 **넓어진다** — 빛이 퍼져 나가다 옅어지는 인상.
	# 세기는 k^1.5 로 떨군다(제곱보다 완만) — 제곱이면 넓어지기도 전에 다 식어서
	# 멀리 있는 것들은 물들 틈이 없다.
	FireLights.put(_fire_slot, global_position + Vector3(0.0, 0.6, 0.0),
		_light_r * (1.35 - k * 0.55), COL_CORE, 1.7 * pow(k, 1.5))

## 시체 하나를 터뜨린다. order 는 몇 번째 시체인지(어긋나게 터뜨리는 용도).
## spec 은 오브젝트 스펙 — 모디파이어가 이미 먹은 완성품이다. 출처(src)를 싣는 게 주 목적이다.
## ⚠️ 반경·피해는 **부르는 쪽이 시체마다 다르게** 계산해서 넘긴다(큰 시체는 크게 터진다).
##    여기서 spec.radius 를 읽으면 그 차이가 뭉개진다.
static func detonate(parent: Node, at: Vector3, radius: float, damage: float,
		knock: float, order := 0, spec: ObjectSpec = null) -> void:
	var d := Deflagration.new()
	if spec != null:
		d._src = spec.src
	parent.add_child(d)
	d.global_position = Vector3(at.x, 0.0, at.z)
	ProjectileStats.spawned(&"blast")
	# 부풀고 있는 동안은 이 그룹에 있다. CardUI 가 이걸 보고 **터지는 걸 본 뒤에** 카드를 연다
	# — 카드 화면은 트리를 멈추므로 퓨즈 도중에 열면 폭발이 통째로 얼어붙는다.
	d.add_to_group(BLAST_PENDING)
	var tw := d.create_tween()
	tw.tween_interval(DELAY + STAGGER * float(order))
	tw.tween_callback(d._fire.bind(radius, damage, knock))

var _src: DamageSource     ## 이 폭발의 출처 (오브젝트 시스템)

func _fire(radius: float, damage: float, knock: float) -> void:
	remove_from_group(BLAST_PENDING)     # 터졌다 — 더는 기다릴 이유가 없다
	# 주변 물들이기. 자리가 없으면 -1 이 오고 그냥 안 물든다 (동시에 수십 개가 터지는 연쇄에선
	# 먼저 터진 몇 개만 빛난다 — 어차피 겹쳐 보여서 티가 안 난다).
	_fire_slot = FireLights.acquire()
	_light_r = radius * LIGHT_REACH
	_light_left = LIGHT_TIME
	_flash(radius)
	_shockwave(radius, damage, knock)   # 링이 퍼지며 피해를 준다
	_fx(radius)
	# 1초를 부풀며 기다린 폭발이다 — 화면이 한 번 울려야 "뻥"이 된다
	var hs := get_tree().get_first_node_in_group("hammer")
	if hs != null:
		hs._shake = maxf(hs._shake, 0.55)
	# 불꽃이 사그라들 때까지 살려둔다 (이펙트는 이 노드의 자식이다)
	var tw := create_tween()
	tw.tween_interval(0.9)
	tw.tween_callback(queue_free)

## 섬광 — 터지는 순간 하얗게 차오르는 구. 아주 짧아야 한다(길면 전구가 된다).
func _flash(radius: float) -> void:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
	# unshaded 는 emission 을 안 쓴다 — albedo 검정 + emission 만으로 HDR 발광을 만든다
	m.emission_enabled = true
	m.emission = Color(0.996, 0.882, 0.722)   # nice31 #fee1b8
	m.emission_energy_multiplier = 2.6        # bloom 문턱(1.1) 위로
	sphere.material = m
	mi.mesh = sphere
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.position.y = 0.4
	mi.scale = Vector3.ONE * radius * 0.2
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius * 0.85, 0.09) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.22) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)

## 충격파 — 바닥을 훑으며 퍼지는 납작한 고리. 폭발의 "크기"를 말하고, **실제로 때린다**.
## 크기와 판정을 **같은 tween_method 한 곳**에서 굴린다 — 둘을 따로 두면
## 이징이나 시간을 한쪽만 고쳤을 때 소리 없이 어긋난다.
func _shockwave(radius: float, damage: float, knock: float) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.82
	torus.outer_radius = 1.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.949, 0.722, 0.533)   # nice31 #f2b888
	torus.material = mat
	ring.mesh = torus
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.position.y = 0.06
	ring.scale = Vector3(radius * 0.25, 0.16, radius * 0.25)
	var tw := create_tween()
	tw.set_parallel(true)
	# front = 링의 현재 반경. 이 값 하나가 크기와 판정을 동시에 정한다.
	tw.tween_method(func(front: float) -> void:
		ring.scale = Vector3(front, lerpf(0.16, 0.05, front / (radius * RING_REACH)), front)
		_sweep(front, damage, knock),
		radius * 0.25, radius * RING_REACH, RING_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, RING_TIME)
	tw.chain().tween_callback(ring.queue_free)
	tw.chain().tween_callback(func() -> void:
		ProjectileStats.landed(&"blast", _hits, _dealt, _wasted, _kills))

# 링이 퍼지는 동안의 누적치. 다 퍼진 뒤 한 번에 보고한다.
var _hit_ids := {}
var _hits := 0
var _dealt := 0.0
var _wasted := 0.0
var _kills := 0

## 지금 링 반경 안에 들어온 적을 태우고 바깥으로 민다. 한 적은 **한 번만** —
## 링이 지나가며 매 프레임 때리면 가까운 적일수록 여러 대 맞는다.
## ⚠️ 여기서 죽은 적은 **수집하지 않는다** — 폭연이 폭연을 낳지 않는 지점이 여기다.
func _sweep(front: float, damage: float, knock: float) -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		var id := e.get_instance_id()
		if _hit_ids.has(id):
			continue
		var flat := e.global_position - global_position
		flat.y = 0.0
		if flat.length() > front + e.hit_radius:
			continue
		_hit_ids[id] = true
		_hits += 1
		var before := e.health
		e.flash_burn()     # 데었다는 신호. take_damage 보다 먼저 — 죽어도 한 번은 번쩍인다
		e.take_damage(damage, global_position, _src)
		_dealt += minf(damage, before)
		_wasted += maxf(damage - before, 0.0)
		if e.dying:
			_kills += 1
		elif knock > 0.0:
			e.knockback(global_position, knock)

## 낮고 넓게 확 피었다 꺼지는 불. 섬광(순간)과 링(크기) 사이에서 "불"을 담당한다.
func _fx(radius: float) -> void:
	var count := clampi(roundi(radius * 2.5), 3, 7)
	for i in count:
		var mi := MeshInstance3D.new()
		var quad := QuadMesh.new()
		var h := randf_range(0.5, 0.95) * radius
		quad.size = Vector2(randf_range(0.5, 0.85) * radius, h)
		var mat := ShaderMaterial.new()
		mat.shader = FlameShader
		mat.set_shader_parameter("seed", randf() * 100.0)
		mat.set_shader_parameter("alpha_mul", 0.0)
		quad.material = mat
		mi.mesh = quad
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.rotation.y = randf_range(0.0, TAU)
		# 중심에서 바깥으로 흩어 놓는다 — 한 점에서 솟으면 판때기로 보인다
		var a := TAU * (float(i) + randf()) / float(count)
		var r := radius * randf_range(0.15, 0.62)
		mi.position = Vector3(cos(a) * r, h * 0.5 * 0.3, sin(a) * r)
		mi.scale.y = 0.3
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(mat, "shader_parameter/alpha_mul", 1.0, 0.04)
		tw.tween_property(mi, "scale:y", 1.0, 0.1) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "position:y", h * 0.5, 0.1) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.chain().tween_property(mat, "shader_parameter/alpha_mul", 0.0,
			randf_range(0.16, 0.3)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# 불똥은 두 층: 밝은 심지가 빠르게, 주홍 파편이 굵직하게
	ImpactDust.burst(get_parent(), global_position,
		clampi(roundi(radius * 8.0), 10, 22), 0.7, COL_CORE)
	ImpactDust.burst(get_parent(), global_position,
		clampi(roundi(radius * 5.0), 6, 14), 1.0, COL_MID)
