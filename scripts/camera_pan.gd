class_name CameraPan
extends Node

## 카메라를 좌우·위아래로 움직인다 (유저 요청 2026-08-16).
##
## 조작: **WASD** 또는 **방향키**. 마우스는 조준에 쓰므로 이동은 키보드가 맞다.
## 화면 가장자리 밀기(edge scroll)는 넣지 않았다 — 조준하다 커서가 가장자리에 닿으면
## 의도치 않게 화면이 흐른다.
##
## ⚠️ 이동은 **화면 기준**이다. 카메라가 45도 돌아가 있어서 월드 축으로 밀면 W 를 눌렀을 때
##    화면이 비스듬히 흐른다. Main.to_world 로 화면축을 월드축으로 바꿔서 민다.
## ⚠️ 지도 밖으로 나가지 못하게 묶는다. 안 묶으면 허공(배경색)만 보이는 데서 길을 잃는다.

## 초당 이동 거리 (화면 유닛). 줌 아웃하면 화면이 넓어지므로 비례해서 빨라진다.
const SPEED := 55.0
## 감속/가속 — 딱 끊기면 손맛이 딱딱하다.
const ACCEL := 12.0
## 카메라가 바라볼 수 있는 범위 (화면 기준). 지형이 ±120 이라 그 안쪽으로 묶는다.
const LIMIT_X := 70.0
const LIMIT_Z := 60.0

var cam: Camera3D
var _vel := Vector2.ZERO
## 시작 위치 = 화면 원점을 보는 자리. 여기서 얼마나 밀렸는지를 들고 다닌다.
var _home := Vector3.ZERO
var _offset := Vector2.ZERO

func _ready() -> void:
	if cam != null:
		_home = cam.global_position
	print("[camera] WASD / 방향키로 화면 이동")

## 지금 눌린 키에서 이동 방향(화면 기준)을 읽는다.
func _input_dir() -> Vector2:
	var d := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		d.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		d.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		d.y -= 1.0     # 화면 위 = -z
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		d.y += 1.0
	return d.normalized() if d.length() > 1.0 else d

func _process(delta: float) -> void:
	if cam == null:
		return
	# 스컬프트 모드에서는 S 가 '다듬기' 라 카메라가 같이 움직이면 안 된다.
	var editor := get_parent().get_node_or_null("TerrainEditor") as TerrainEditor
	var want := Vector2.ZERO if (editor != null and editor.active) else _input_dir()
	_vel = _vel.lerp(want, clampf(ACCEL * delta, 0.0, 1.0))
	if _vel.length() < 0.001 and want == Vector2.ZERO:
		return
	# 줌에 비례해 속도를 맞춘다 — 넓게 볼수록 같은 시간에 더 많이 움직여야 답답하지 않다.
	var zoom: float = cam.size / 75.5 if cam.projection == Camera3D.PROJECTION_ORTHOGONAL else 1.0
	pan(_vel * SPEED * zoom * delta)

## 화면 기준으로 이만큼 민다. 범위 밖으로는 안 나간다.
func pan(screen_delta: Vector2) -> void:
	if cam == null:
		return
	_offset.x = clampf(_offset.x + screen_delta.x, -LIMIT_X, LIMIT_X)
	_offset.y = clampf(_offset.y + screen_delta.y, -LIMIT_Z, LIMIT_Z)
	cam.global_position = _home + Main.to_world(_offset.x, _offset.y)

## 화면 원점으로 되돌린다.
func recenter() -> void:
	_offset = Vector2.ZERO
	_vel = Vector2.ZERO
	if cam != null:
		cam.global_position = _home

func _unhandled_input(event: InputEvent) -> void:
	# HOME 키: 성이 보이는 처음 자리로. 길 잃었을 때의 탈출구다.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_HOME:
		recenter()
		print("[camera] 처음 자리로")
