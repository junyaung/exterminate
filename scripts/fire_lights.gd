class_name FireLights
extends Object

## 불빛 슬롯 관리자 — 횃불·폭연·불덩이가 주변을 물들이게 한다 (유저 요청 2026-08-17:
## "밤에 불 공격이 일어날 때 주변 사물이나 벌레도 밝아져야 세심하다").
##
## ⚠️ **진짜 광원(OmniLight3D)은 쓸 수 없다.** 셀/지면 셰이더가 light() 에서 색을 확정해서,
##    광원을 하나 더 넣으면 화면 색이 통째로 날아간다 (같은 날 실제로 겪고 되돌렸다).
##    그래서 위치·반경·색을 전역 유니폼으로 넘기고, 셰이더는 fragment() 에서 EMISSION 에
##    더하기만 한다. 자세한 건 shaders/fire_light.gdshaderinc 주석에.
##
## 노드가 아니라 정적 함수 묶음이다 — 불은 게임 어디서든(투사체·시체·성 옆) 생기므로
## 트리에서 관리자를 찾아다니게 만들면 매번 null 검사가 붙는다.

const SLOTS := 8

## 슬롯 점유 여부. 인덱스 = 슬롯 번호.
static var _used := []
static var _registered := false

## 슬롯을 전부 꺼진 상태로 되돌린다 (판을 새로 시작할 때 전 판의 불이 남지 않게).
## ⚠️ **전역 유니폼 등록은 여기서 하지 않는다** — 선언은 project.godot 의 `[shader_globals]` 에
##    있다. 예전엔 여기서 `global_shader_parameter_add` 를 불렀는데, 정식 선언 후엔 중복이라
##    에러가 나고, 존재 확인에 쓰던 `global_shader_parameter_get_list()` 는 에디터 전용이라
##    성능 경고까지 났다 (2026-08-18). 새 전역 유니폼을 만들 땐 **project.godot 에 적을 것.**
## 멱등이다 — 늦게 불려도 안전하다.
static func reset_slots() -> void:
	if _registered:
		return
	_registered = true
	_used.resize(SLOTS)
	for i in SLOTS:
		_used[i] = false
		# 씬을 다시 로드해도 전 판의 불이 남아 있지 않도록 항상 끈다 (w = 0).
		RenderingServer.global_shader_parameter_set(StringName("fire_p%d" % i), Vector4.ZERO)

## 슬롯 하나를 잡는다. 반환 -1 = 자리가 없음 (그냥 안 물들이면 된다 — 불이 8개 넘게
## 켜져 있는 화면에서 하나 빠진 걸 알아채는 사람은 없다).
static func acquire() -> int:
	reset_slots()
	for i in SLOTS:
		if not _used[i]:
			_used[i] = true
			return i
	return -1

## 슬롯 갱신. radius <= 0 이면 셰이더가 이 슬롯을 건너뛴다.
static func put(slot: int, pos: Vector3, radius: float, col: Color, energy: float) -> void:
	if slot < 0:
		return
	RenderingServer.global_shader_parameter_set(StringName("fire_p%d" % slot),
		Vector4(pos.x, pos.y, pos.z, radius))
	RenderingServer.global_shader_parameter_set(StringName("fire_c%d" % slot),
		Vector4(col.r, col.g, col.b, energy))

## 슬롯을 돌려준다. ⚠️ **불이 사라질 때 반드시 부를 것.** 안 부르면 슬롯이 새서
## 몇 판 지나면 새 불이 아무것도 못 잡는다 (증상: 나중 판일수록 불빛이 안 물든다).
static func release(slot: int) -> void:
	if slot < 0:
		return
	RenderingServer.global_shader_parameter_set(StringName("fire_p%d" % slot), Vector4.ZERO)
	_used[slot] = false
