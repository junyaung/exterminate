class_name Terrain
extends RefCounted

## 지형 높이를 **어디서나 한 줄로** 물어보는 통로.
##
## 지형에 높이가 생기면서(2026-08-16) 코드 곳곳의 `y = 0.0` 가 전부 틀린 값이 됐다 —
## 균열·분화구·먼지·피웅덩이·낙석 착지가 죄다 지면 아래나 공중에 뜬다.
## 그 자리들을 `Terrain.h(pos)` 로 바꾸면 지형이 바뀌어도 따라온다.
##
## ⚠️ Ground 노드를 매번 찾지 않고 캐시한다. 씬을 다시 로드하면(검증 스크립트가 그런다)
##    캐시가 죽은 노드를 가리키므로 `is_instance_valid` 로 확인하고 다시 찾는다.

static var _ground: Ground

static func ground() -> Ground:
	if _ground != null and is_instance_valid(_ground):
		return _ground
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	_ground = tree.get_first_node_in_group(&"ground") as Ground
	return _ground

## 이 자리의 지면 높이. 지형이 없으면 0 — 지형을 안 쓰는 검증 씬에서도 안전하다.
static func h(at: Vector3) -> float:
	var g := ground()
	# ⚠️ 평지에서는 즉시 0. 몹 600마리 × 프레임당 수십 번 샘플링이라, 이 한 줄이
	#    프레임 시간을 좌우한다 (벤치: 한 마리 72us -> 아래 참고).
	return 0.0 if g == null or g.is_flat else g.height_at(at)

## 이 자리의 지면 법선 (경사에 맞춰 눕힐 때). 지형이 없으면 위쪽.
static func normal(at: Vector3) -> Vector3:
	var g := ground()
	return Vector3.UP if g == null or g.is_flat else g.normal_at(at)

## 같은 자리를 지면에 붙인 좌표.
static func on(at: Vector3, lift := 0.0) -> Vector3:
	return Vector3(at.x, h(at) + lift, at.z)
