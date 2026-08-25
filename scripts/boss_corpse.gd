class_name BossCorpse
extends Node3D

## 보스 시체 조각 (머리/가슴/배). 포물선으로 흩어져 회전하며 날아가고,
## 착지하면 날아오던 자세 그대로 바닥에 박혀 잠깐 남았다가 알파로 사라진다.
##
## - 회전 중심이 조각의 무게중심이 되도록 spawn() 이 메시를 -centroid 로 옮겨 담는다
##   (조각 메시의 원점은 셋 다 보스 발밑이라, 노드째 돌리면 궤도를 돈다).
## - 착지 판정/묻힘은 EruptRock 과 같은 문법: 회전한 자세의 실제 세로 반높이
##   `hh = |b.x.y|*hx + |b.y.y|*hy + |b.z.y|*hz` 로 계산하고, 하강 중일 때만 판정.
## - 착지 시 회전·크기를 건드리지 않는다 (바위 규칙: 시체는 찌그러지지 않는다).
## - 소멸은 반드시 알파 페이드 — 크기를 줄이면 땅에 빨려드는 것처럼 보인다.
##   투명 파이프라인 비용이 있으므로 페이드 직전에만 머티리얼을 fade 판으로 바꾼다.

const FadeShader := preload("res://shaders/cel_fade.gdshader")

const GRAVITY := 30.0
const LINGER := 1.3          ## 착지 후 남아있는 시간 (기본값 — opts.linger 로 덮어쓴다)
const FADE := 0.45           ## 알파 페이드 시간
const BURY := 0.12           ## 착지 시 묻히는 비율 (기본값 — opts.bury 로 덮어쓴다)

var vel := Vector3.ZERO
var _spin_axis := Vector3.UP
var _spin_speed := 0.0
var _landed := false
var _meshes: Array[MeshInstance3D] = []
var _half := Vector3.ZERO    ## 로컬 AABB 반크기 (본체+먹선 합)

## 사망 종류별 연출 옵션 (spawn 의 opts):
##   bury: 묻히는 비율(폭연 낙하는 깊게 박힌다) / linger: 잔류 시간 / squash: 착지 시 납작
##   dust: 착지 먼지 개수 / dust_scale: 먼지 크기
var _opts := {}


## sources: [{mesh: Mesh, mats: Array[Material], shadow: bool}] — 본체와 먹선 헐.
## xform 은 살아있던 모델(Stag 노드)의 global_transform — 스케일·방향을 그대로 물려받는다.
static func spawn(parent: Node, xform: Transform3D, centroid: Vector3,
		sources: Array, velocity: Vector3, spin_axis: Vector3, spin_speed: float,
		opts := {}) -> BossCorpse:
	var c := BossCorpse.new()
	c.vel = velocity
	c._spin_axis = spin_axis.normalized()
	c._spin_speed = spin_speed
	c._opts = opts
	parent.add_child(c)
	c.global_transform = Transform3D(xform.basis, xform * centroid)
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for s in sources:
		var mi := MeshInstance3D.new()
		mi.mesh = s.mesh
		for i in mini(s.mats.size(), s.mesh.get_surface_count()):
			mi.set_surface_override_material(i, s.mats[i])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if s.shadow \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = -centroid
		c.add_child(mi)
		c._meshes.append(mi)
		var ab: AABB = s.mesh.get_aabb()
		lo = lo.min(ab.position - centroid)
		hi = hi.max(ab.position + ab.size - centroid)
	c._half = (hi - lo) * 0.5
	return c


func _physics_process(delta: float) -> void:
	if _landed:
		return
	vel.y -= GRAVITY * delta
	global_position += vel * delta
	if _spin_speed > 0.0:
		global_rotate(_spin_axis, _spin_speed * delta)
	# 회전한 자세의 실제 세로 반높이. basis 에 스케일이 들어있으므로 로컬 반크기와 곱하면 월드값.
	var b := global_basis
	var hh := absf(b.x.y) * _half.x + absf(b.y.y) * _half.y + absf(b.z.y) * _half.z
	if vel.y < 0.0 and global_position.y - hh <= 0.0:
		_land(hh)


func _land(hh: float) -> void:
	_landed = true
	var bury: float = _opts.get("bury", BURY)
	var rest_y := hh * (1.0 - 2.0 * bury)
	global_position.y = rest_y
	ImpactDust.burst(get_parent(), Vector3(global_position.x, 0.0, global_position.z),
		_opts.get("dust", 14), _opts.get("dust_scale", 1.4))
	var tw := create_tween()
	# 납작해지기(일반 사망): 위아래로 눌리고 옆으로 살짝 퍼진다.
	# ⚠️ scale 은 절대값이 아니라 **현재 스케일에 곱해야** 한다 — 베이시스에 모델 스케일(≈5)이
	# 들어있어서 절대값을 넣으면 조각이 1유닛짜리로 쪼그라든다.
	# 회전 피벗이 무게중심이라 그냥 눌리면 바닥에서 뜨므로 높이도 같은 비율로 내린다.
	if _opts.get("squash", false):
		var s0 := scale
		tw.set_parallel(true)
		tw.tween_property(self, "scale", s0 * Vector3(1.09, 0.7, 1.09), 0.13) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "position:y", rest_y * 0.7, 0.13) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw = create_tween()
	tw.tween_interval(_opts.get("linger", LINGER))
	tw.tween_callback(_begin_fade)
	tw.tween_interval(FADE)
	tw.tween_callback(queue_free)


## 페이드 직전에만 투명 가능한 머티리얼로 갈아끼운다.
## 셀 ShaderMaterial -> cel_fade 사본, Standard(먹선·눈) -> transparency 켠 사본.
func _begin_fade() -> void:
	for mi in _meshes:
		for i in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(i)
			if m is ShaderMaterial:
				var sm := ShaderMaterial.new()
				sm.shader = FadeShader
				sm.set_shader_parameter("light_tone", (m as ShaderMaterial).get_shader_parameter("light_tone"))
				sm.set_shader_parameter("dark_tone", (m as ShaderMaterial).get_shader_parameter("dark_tone"))
				sm.set_shader_parameter("threshold", (m as ShaderMaterial).get_shader_parameter("threshold"))
				sm.set_shader_parameter("alpha_mul", 1.0)
				mi.set_surface_override_material(i, sm)
			elif m is StandardMaterial3D:
				var d := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
				d.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				# 먹선 껍질은 본체보다 나중에. 분출 바위와 같은 이유 —
				# 순서가 뒤집히면 페이드 중에 검은 실루엣이 뜬다 (cel_fade.gdshader 주석).
				d.render_priority = 1
				mi.set_surface_override_material(i, d)
	var tw := create_tween()
	tw.tween_method(_set_alpha, 1.0, 0.0, FADE)


func _set_alpha(a: float) -> void:
	for mi in _meshes:
		for i in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(i)
			if m is ShaderMaterial:
				(m as ShaderMaterial).set_shader_parameter("alpha_mul", a)
			elif m is StandardMaterial3D:
				(m as StandardMaterial3D).albedo_color.a = a
