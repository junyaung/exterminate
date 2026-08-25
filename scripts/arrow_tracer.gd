class_name ArrowTracer
extends Node3D

## 성이 쏜 화살의 궤적선 (유저 지시 2026-08-17). 화살 자체는 안 그린다 — **선만 그린다.**
##
## 왜 직선이 아니라 포물선인가 (유저 지적): 직선 + 즉시 명중은 **저격총**으로 읽힌다.
## 화살은 ① 위로 살짝 뜨는 호를 그리고 ② 도달까지 아주 짧은 시간이 걸린다. 둘 다 있어야
## "쐈다 → 날아갔다 → 맞았다" 세 박자가 생긴다. 대신 시간은 **미세하게만** 준다 —
## 길어지면 성이 곡사포가 되고 명중 타이밍이 뭉갠다.
##
## 카툰(셀) 처리 (유저 제안): **알파로 흐리지 않는다.**
##   · 양 끝 가늘어짐 = **폭(지오메트리)** 으로 만든다. 알파로 흐리면 수채처럼 번져서
##     셀 룩(경계가 딱 떨어지는 면)이 깨진다. 폭으로 줄이면 끝이 뾰족해도 경계는 선명하다.
##   · 먹선은 **가운데에만** 넣는다. 굵기 0.07 짜리 선에 외곽선을 통째로 두르면 먹선이
##     선을 삼킨다. 두꺼운 구간에서만 나타나고 양 끝에서 빠지게 알파 프로파일을 준다.
##
## 매 프레임 리본을 다시 굽는다. 정점 34개짜리라 비용은 없다시피 하고, 그래야
## **지금 보이는 구간의 양 끝**이 정확히 뾰족해진다 (전체 호를 미리 구워두면
## 날아가는 도중의 잘린 끝이 뭉툭하게 남는다).

signal arrived   ## 화살 머리가 표적에 닿은 순간. 피해는 여기서 확정한다.

const SEG := 16                       ## 리본 분할 수
const WIDTH := 0.16                   ## 가운데 최대 폭
## 먹선이 궤적선 밖으로 삐져나오는 양. ⚠️ 0.055 는 화면에서 **안 보였다**(유저 지적) —
## 궤적선 자체가 얇아서 먹선도 같이 얇아지면 그냥 사라진다. 0.11 도 아직 약했다 —
## **선 폭(0.16)만큼** 줘서 흰 심지 양옆에 같은 두께의 먹선이 붙는 꼴로 맞췄다.
## ⚠️ 여기서 더 올리면 먹선이 심지를 삼켜 그냥 검은 선이 된다.
const INK_PAD := 0.16
const INK_COL := Color("#14233a")     ## 게임 공통 먹선색 (nice31)
## 궤적선 색. **순백**으로 되돌렸다 (유저 결정 2026-08-17 — 차가운 톤 #bbc3d0 을 대보고
## 순백을 골랐다). 순백이 제일 눈에 띄고, 화면의 불(횃불·폭연·불덩이)이 전부 따뜻한 색이라
## 오히려 무채색이 그 사이에서 갈라진다. 팔레트 안의 흰색이라 튀지도 않는다.
const LINE_COL := Color("#f7f2ef")
## 꼬리가 머리를 따라오기까지의 지연 = 화면에 보이는 선의 길이(비행시간 대비 비율).
## 1.0 이면 도착할 때까지 호 전체가 남고, 0 이면 점 하나가 날아간다.
const TAIL_FRAC := 0.55
const FADE := 0.07                    ## 꼬리가 다 따라온 뒤 사그라지는 시간

var _from := Vector3.ZERO
var _target: Node3D = null
var _to := Vector3.ZERO               ## 표적이 사라지면 마지막 위치를 쓴다
var _arc := 1.0                       ## 호의 높이
var _flight := 0.2
var _t := 0.0
var _hit := false
var _fade_left := FADE

var _line: MeshInstance3D
var _ink: MeshInstance3D

static func shoot(parent: Node, from: Vector3, target: Node3D, flight: float) -> ArrowTracer:
	var a := ArrowTracer.new()
	a._from = from
	a._target = target
	a._to = target.global_position + Vector3.UP * 0.4
	a._flight = maxf(flight, 0.02)
	# 호의 높이는 거리에 비례하되 상한을 둔다 — 멀리 쏠수록 더 뜨지만 곡사포가 되진 않는다.
	a._arc = clampf(from.distance_to(a._to) * 0.14, 0.7, 3.2)
	a.name = "Tracer"
	# ⚠️ 성이 아니라 **씬 루트 쪽**에 붙인다. 성이 부서질 때 궤적이 같이 사라지면 안 된다.
	parent.add_child(a)
	return a

func _ready() -> void:
	# ⚠️ 정점을 **월드 좌표로** 굽는다. 노드는 원점에 두어야 좌표가 두 번 변환되지 않는다.
	global_position = Vector3.ZERO
	# 먹선이 뒤(카메라에서 먼 쪽)에 깔린다 — 투명 재질은 거리순으로 정렬되므로
	# 따로 렌더 순서를 지정하지 않아도 흰 선이 위에 온다.
	# 색·알파는 전부 **정점 색**으로 넣는다 (머티리얼을 만지지 않는다) — 매 프레임 리본을
	# 다시 굽는 구조라, 굽는 곳 한 군데에서 폭과 알파를 같이 정하는 편이 어긋날 여지가 없다.
	_ink = _make_layer(INK_COL, false)
	_line = _make_layer(LINE_COL, true)

func _make_layer(col: Color, glow: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ImmediateMesh.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # 선은 명암을 받지 않는다 (셀 문법)
	m.albedo_color = col
	m.cull_mode = BaseMaterial3D.CULL_DISABLED              # 리본이라 뒤에서도 보여야 한다
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# 정점 알파로 **먹선을 부분적으로** 넣고, 사라질 때 전체를 같이 뺀다.
	m.vertex_color_use_as_albedo = true
	if glow:
		# glow 문턱(1.1) 위 — 얇은 선이라 살짝 번져야 눈에 걸린다. 가산이 아니라 일반 혼합이라
		# 색은 평면 그대로다(셀), 번짐만 후처리로 얹힌다.
		m.emission_enabled = true
		m.emission = col
		# 1.6 이면 총 밝기가 glow 문턱(1.1)을 넘어 살짝 번진다 — 색은 차갑게 두되 존재감은 남긴다.
		m.emission_energy_multiplier = 1.6
	mi.material_override = m
	add_child(mi)
	return mi

func _process(delta: float) -> void:
	_t += delta
	if _target != null and is_instance_valid(_target):
		# 표적을 계속 따라간다 — 명중률 100% 라 선이 표적을 벗어나면 거짓말이 된다.
		_to = _target.global_position + Vector3.UP * 0.4
	var head := clampf(_t / _flight, 0.0, 1.0)
	var tail := clampf((_t - _flight * TAIL_FRAC) / (_flight * (1.0 - TAIL_FRAC)), 0.0, 1.0)
	if head >= 1.0 and not _hit:
		_hit = true
		arrived.emit()
	var alpha := 1.0
	if tail >= 1.0:
		_fade_left -= delta
		if _fade_left <= 0.0:
			queue_free()
			return
		alpha = _fade_left / FADE
		# 꼬리가 다 따라온 뒤엔 머리 끝에 짧게 남은 잔상만 사그라진다.
		tail = 1.0 - 0.12 * alpha
	_build(_line, tail, head, WIDTH, alpha, false)
	_build(_ink, tail, head, WIDTH + INK_PAD, alpha, true)

## 포물선 위의 점. t 0=총구, 1=표적. 4t(1-t) 는 양 끝 0, 가운데 1 인 종 모양이다.
func _point(t: float) -> Vector3:
	return _from.lerp(_to, t) + Vector3.UP * (_arc * 4.0 * t * (1.0 - t))

## [tail, head] 구간을 카메라를 향한 리본으로 굽는다.
## ink=true 면 가운데에서만 나타나는 알파 프로파일을 쓴다.
func _build(mi: MeshInstance3D, tail: float, head: float, width: float,
		alpha: float, ink: bool) -> void:
	var mesh := mi.mesh as ImmediateMesh
	mesh.clear_surfaces()
	if head - tail <= 0.0005:
		return
	var cam := get_viewport().get_camera_3d()
	# 카메라가 보는 방향. 이걸로 리본을 화면 쪽으로 세운다 — 안 그러면 각도에 따라
	# 선이 종잇장처럼 사라진다.
	var view := -cam.global_basis.z if cam != null else Vector3.FORWARD
	# 먹선은 흰 선보다 카메라에서 **멀리** 둔다. 같은 평면에 겹치면 z-파이팅으로 지글거린다.
	var depth_push := view * (0.05 if ink else 0.0)
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in SEG + 1:
		var s := float(i) / float(SEG)          # 보이는 구간 안에서의 위치 0~1
		var t := lerpf(tail, head, s)
		var p := _point(t)
		# 접선 — 끝점에서는 안쪽 이웃과의 차이로 대신한다.
		var t2 := clampf(t + 0.01, 0.0, 1.0)
		var t1 := clampf(t - 0.01, 0.0, 1.0)
		var tangent := (_point(t2) - _point(t1))
		if tangent.length_squared() < 1e-8:
			tangent = _to - _from
		var side := tangent.normalized().cross(view).normalized() * 0.5
		# **양 끝이 얇아지는 폭 프로파일.** sin 은 양 끝 0, 가운데 1 — 지수를 1 보다 작게 두어
		# 가운데를 넓게 유지하고 끝에서만 빠르게 뾰족해지게 한다.
		var w: float = width * pow(sin(PI * s), 0.65)
		var col := INK_COL if ink else LINE_COL
		if ink:
			# 먹선은 **두꺼운 가운데 구간에만** 있다. 끝까지 두르면 뾰족한 끝이 먹선에 먹힌다.
			col.a = alpha * smoothstep(0.35, 0.62, sin(PI * s))
		else:
			col.a = alpha
		mesh.surface_set_color(col)
		mesh.surface_add_vertex(p + side * w + depth_push)
		mesh.surface_set_color(col)
		mesh.surface_add_vertex(p - side * w + depth_push)
	mesh.surface_end()
