class_name TerrainEditor
extends Node3D

## 게임 안에서 지형을 직접 깎는 툴 (유저 요청 2026-08-16: "Astroneer 처럼 좌클릭으로 깎고
## 우클릭으로 채워서 대충 만들면 네가 다듬는" 방식).
##
## 흐름: **F 로 스컬프트 모드** -> 마우스로 깎는다 -> **K 로 저장** -> 내가 그 파일을 읽고
## 다듬는다. 저장은 `res://layout/terrain_edit.json` 이라 프로젝트 폴더에 그대로 남는다.
##
## ⚠️ 스컬프트 모드에서는 **망치 입력을 끈다.** 좌클릭이 겹치기 때문이다 —
##    안 끄면 지형을 깎으면서 망치가 같이 떨어진다.
## ⚠️ 지형을 바꾸면 그 위의 프롭도 다시 앉혀야 한다 (나뭇가지가 공중에 뜬다).
##    붓질 중에는 메시만 다시 굽고, 프롭은 붓을 뗄 때 한 번만 다시 앉힌다 — 매 붓질마다
##    다시 뿌리면 잎사귀가 매번 다른 자리로 튀어서 뭘 깎고 있는지 안 보인다.
##
## 키
##   F          스컬프트 모드 켜기/끄기 (끌 때 자동 저장)
##   좌클릭     판다 (drag)
##   우클릭     채운다 (drag)
##   S + 드래그  다듬는다 — 울퉁불퉁한 자국과 붓 자국을 편다
##              (가운데 클릭도 같은 동작이지만 랩탑엔 없어서 키를 기본으로 둔다)
##   휠         붓 크기
##   Shift      약하게 (섬세한 경사용)
##
## ⚠️ 랩탑 트랙패드 기준으로 고른 조작이다 — 가운데 버튼처럼 **없을 수도 있는 입력은
##    기본 조작으로 쓰지 않는다** (유저 지적 2026-08-16). 두 손가락 탭=우클릭,
##    두 손가락 스크롤=휠은 트랙패드에서 그대로 된다.
##   K          저장   /   R 되돌리기(전부 지움)

const RADIUS_MIN := 4.0
const RADIUS_MAX := 40.0
## 초당 파는 깊이(유닛). 계단 한 칸(Ground.STEP = 2.0)을 0.5초 안에 내려가야
## "파고 있다"가 손에 느껴진다. Shift 를 누르면 1/4 로 느려져 한 단씩 조절할 수 있다.
const RATE := 4.5
const REBUILD_GAP := 0.12     ## 메시 다시 굽는 최소 간격(초). 매 프레임 구우면 붓이 끊긴다.

var active := false
var radius := 14.0

var _ground: Ground
var _hammer: Node
var _cam: Camera3D
var _ring: MeshInstance3D
var _dig := 0                 ## -1 판다 / +1 채운다 / 0 안 누름
var _smoothing := false       ## 가운데 버튼 — 다듬기
var _since_build := 0.0
var _dirty := false

func _ready() -> void:
	_ground = get_parent().get_node_or_null("Ground") as Ground
	_hammer = get_tree().get_first_node_in_group(&"hammer")
	_cam = get_viewport().get_camera_3d()
	_ring = _make_ring()
	_ring.visible = false
	print("[terrain] F 스컬프트 — 좌클릭 파기 / 우클릭 채우기 / S+드래그 다듬기")
	print("[terrain]   휠 붓크기 / Shift 약하게 / K 저장 / R 초기화")

## 붓 표시. ⚠️ 처음엔 PlaneMesh 를 썼는데 그건 **사각형**이라 붓이 어디까지 닿는지
## 전혀 안 맞았다 (유저 지적 2026-08-16). 붓은 원형이므로 표시도 원이어야 한다.
## 원판(반투명) + 테두리 링 두 겹 — 테두리가 있어야 경계가 정확히 읽힌다.
func _make_ring() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.02
	disc.radial_segments = 48        # 48각형이면 이 크기에서 원으로 읽힌다
	disc.rings = 0
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.99, 0.88, 0.47, 0.22)     # #fdd179
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material = m
	mi.mesh = disc
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	var edge := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.965
	ring.outer_radius = 1.0
	ring.rings = 48
	ring.ring_segments = 6
	var em := StandardMaterial3D.new()
	em.albedo_color = Color(0.99, 0.88, 0.47, 0.95)
	em.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material = em
	edge.mesh = ring
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_child(edge)               # 원판의 자식이라 크기·위치를 같이 따라간다
	return mi

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F:
				_toggle()
				get_viewport().set_input_as_handled()
			KEY_K:
				if active and _ground != null:
					_ground.save_edits()
			KEY_R:
				if active and _ground != null:
					_ground.clear_edits()
					_rebuild(true)
					print("[terrain] 깎은 것 전부 지움")
		return
	if not active:
		return
	# 스컬프트 모드에서는 마우스 입력을 **여기서 전부 먹는다** — 안 그러면 망치가 같이 나간다.
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_dig = -1 if event.pressed else 0
			MOUSE_BUTTON_RIGHT:
				_dig = 1 if event.pressed else 0
			MOUSE_BUTTON_MIDDLE:
				_smoothing = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				radius = minf(radius * 1.12, RADIUS_MAX)
			MOUSE_BUTTON_WHEEL_DOWN:
				radius = maxf(radius / 1.12, RADIUS_MIN)
		if not event.pressed and event.button_index in [MOUSE_BUTTON_LEFT,
				MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_reseat_props()          # 붓을 뗄 때 한 번만 프롭을 다시 앉힌다
		get_viewport().set_input_as_handled()

func _toggle() -> void:
	active = not active
	_ring.visible = active
	_dig = 0
	if _hammer != null:
		# 망치 노드의 입력만 끈다 — 카메라 튜너·스캐터 단축키는 그대로 살려둔다.
		_hammer.set_process_unhandled_input(not active)
		_hammer.set_process_input(not active)
	if not active and _ground != null:
		_ground.save_edits()         # 모드를 끄면 자동 저장 — 깎아놓고 날리는 사고 방지
		_reseat_props()
	print("[terrain] 스컬프트 모드 ",
		"ON — 좌클릭 파기 / 우클릭 채우기 / S+드래그 다듬기" if active else "OFF")

func _process(delta: float) -> void:
	if not active or _ground == null:
		return
	var at := _mouse_ground()
	# 계단 지형이라 붓이 놓인 단 위에 정확히 얹혀야 한다 — 안 그러면 절벽에 파묻힌다.
	_ring.global_position = Vector3(at.x, _ground.height_at(at) + 0.15, at.z)
	_ring.scale = Vector3(radius, 1.0, radius)
	_since_build += delta
	# S 를 누른 채 드래그하면 파는 대신 다듬는다 (가운데 버튼 없는 랩탑용).
	var smooth_now: bool = _smoothing or (_dig != 0 and Input.is_key_pressed(KEY_S))
	if smooth_now:
		# 다듬기는 세게 걸면 지형이 통째로 녹아버린다 — 문지르는 만큼 서서히.
		_ground.smooth_brush(at, radius, 3.0 * delta)
		_dirty = true
	elif _dig != 0:
		var rate: float = RATE * (0.25 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
		_ground.sculpt(at, radius, float(_dig) * rate * delta)
		_dirty = true
	if _dirty and _since_build >= REBUILD_GAP:
		_rebuild(false)

func _rebuild(reseat: bool) -> void:
	_since_build = 0.0
	_dirty = false
	_ground.build()
	if reseat:
		_reseat_props()

## 지형이 바뀌었으니 프롭을 다시 앉힌다.
func _reseat_props() -> void:
	var sc := get_parent().get_node_or_null("Scatter") as Scatter
	if sc != null:
		sc.rebuild()

## 마우스 아래 지면 좌표. 망치와 같은 방식(광선 대 y=0 평면)이라 깎인 자리에서는
## 실제 지면보다 살짝 어긋나지만, 붓 반경이 크므로 손맛에는 영향이 없다.
func _mouse_ground() -> Vector3:
	if _cam == null:
		_cam = get_viewport().get_camera_3d()
	var mp := get_viewport().get_mouse_position()
	var o := _cam.project_ray_origin(mp)
	var d := _cam.project_ray_normal(mp)
	if absf(d.y) < 0.001:
		return Vector3.ZERO
	return o - d * (o.y / d.y)
