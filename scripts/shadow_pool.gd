class_name ShadowPool
extends MultiMeshInstance3D

## 개미 발밑 접지 타원을 **한 덩어리**로 그린다.
##
## 왜: 타원 하나가 MeshInstance3D 하나였다. 개미가 동시 생존 590마리 중 ~410마리라
## 그것만으로 씬 인스턴스의 **약 25%** 였고, 렌더러가 그걸 전부 컬링·제출하는 비용이
## 웨이브 8~10 의 병목이었다 (2026-08-26 실측: 590마리에서 process 26ms).
## 전부 같은 메시에 위치·크기만 다르므로 MultiMesh 가 정확히 맞는 자리다.
##
## ⚠️ 등록만 받고 **해제는 받지 않는다.** 몹은 사망 연출 뒤 queue_free 되는데, 그때마다
##    풀에 알리게 하면 해제 지점이 여러 곳(사망·웨이브 정리·씬 전환)으로 흩어진다.
##    매 프레임 is_instance_valid 로 걸러내는 편이 싸고 새지 않는다.

## ⚠️ 이 스크립트는 Enemy 를 **참조하지 않는다.** 서로 참조하면 GDScript 가 두 클래스를
##    모두 못 푼다 (실제로 밟았다: "Could not find type ShadowPool"). 그래서 그림자
##    생김새 상수는 여기가 갖고, Enemy 는 발자국 크기만 넘긴다.
const DropShadowShader := preload("res://shaders/drop_shadow.gdshader")
## nice31 최암부 #14233a. 지면 위에 까는 것이니 팔레트 규칙대로 nice31 쪽을 쓴다.
const SHADOW_COL := Color(0.078, 0.137, 0.227)
const SHADOW_STRENGTH := 0.30
const SHADOW_Y := 0.02        ## 지면과의 z-fighting 을 피하는 최소 높이

## 등록된 몹과 그 발자국 크기(가로, 세로). 인덱스가 서로 짝이다.
var _users: Array[Node3D] = []
var _foot: Array[Vector2] = []

func _ready() -> void:
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	# ⚠️ PlaneMesh 기본 크기는 (2,2) 다 — 그대로 두면 그림자가 정확히 두 배로 나온다.
	#    실제 크기는 인스턴스 배율이 내므로 여기서는 1×1 이어야 한다.
	var unit := PlaneMesh.new()
	unit.size = Vector2.ONE
	multimesh.mesh = unit
	multimesh.instance_count = 0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = DropShadowShader
	m.set_shader_parameter("col", SHADOW_COL)
	m.set_shader_parameter("strength", SHADOW_STRENGTH)
	material_override = m

func add(who: Node3D, width: float, length: float) -> void:
	_users.append(who)
	_foot.append(Vector2(width, length))

## ⚠️ **물리 프레임이 아니라 매 프레임 갱신한다.** 몹은 물리에서 움직이지만 화면은
##    그보다 자주 그려지므로, 물리에 맞추면 빠른 몹(러너)의 그림자가 몸에서 떨어져 끌린다.
func _process(_delta: float) -> void:
	var n := _users.size()
	var write := 0
	# 죽은 몹을 앞으로 당겨 메우면서 한 번에 훑는다 — 별도 정리 패스가 필요 없다.
	for i in n:
		var who := _users[i]
		if not is_instance_valid(who) or not who.is_inside_tree():
			continue
		if write != i:
			_users[write] = who
			_foot[write] = _foot[i]
		write += 1
	if write != n:
		_users.resize(write)
		_foot.resize(write)
	if multimesh.instance_count != write:
		multimesh.instance_count = write
	for i in write:
		var who := _users[i]
		var f := _foot[i]
		# 몹의 회전·기울기·크기를 그대로 물려받되, 발자국 비율로 눕힌다.
		var b := who.global_transform.basis.scaled(Vector3(f.x, 1.0, f.y))
		multimesh.set_instance_transform(i, Transform3D(b,
			who.global_position + Vector3(0.0, SHADOW_Y, 0.0)))
