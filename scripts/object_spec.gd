class_name ObjectSpec
extends RefCounted

## **오브젝트** — 공격 패턴 카드가 만들어내는 생성물(불덩이, 충격파, 분출 바위 …)의
## 생성 파라미터를 한 덩어리로 모은 것. 모디파이어(서포트 젬 역할)는 생성 **직전에**
## 이 객체를 고친다. 생성 함수는 완성된 스펙만 읽는다.
##
## 왜 이렇게 하나: 예전엔 `spawn_roll(parent, origin, dir, damage, radius)` 처럼 인자가
## 흩어져 있어서 "이 값을 카드가 바꾼다"를 끼워 넣을 자리가 없었다. 스펙 하나로 모으면
## 모디파이어는 그냥 필드를 고치면 된다 — 생성 함수는 아무것도 몰라도 된다.

# --- 태그 --------------------------------------------------------------------
# ⚠️ **필요한 것만 만든다.** 모디파이어가 실제로 쓰는 태그만 여기 있어야 한다.
#    태그를 미리 잔뜩 만들면 카드보다 프레임워크가 커진다
#    (근거: gamedev/poe_gem_system_build_variety_study.md 위험 항목 2).
## **발사체** — 쏘아져 날아가는 물체. 불덩이, 분출 바위.
## 크기가 커지면 물체 자체가 커진다 ('거대화').
const TAG_PROJECTILE := &"projectile"
## **면적** — 한 자리에서 퍼지는 범위. 충격파, 균열, 분화구, 폭연, 우클릭 특수.
## 크기가 커지면 덮는 넓이가 커진다 ('광역화'). 발사체와 **다른 축**이라 카드가 따로다.
const TAG_AREA := &"area"
## **지속** — 바닥에 눕고 자리에 남는다. 충격파, 균열, 분화구. ('잔류'가 수명을 늘린다)
const TAG_GROUND := &"ground"

var id := &""
var tags: Array[StringName] = []
var src: DamageSource

var count := 1          ## 몇 개 만드는가
var damage := 0.0
var radius := 0.0       ## 판정 반경. **시각 크기와 같은 배율로만 움직인다** (아래 참고)
var scale := 1.0        ## 시각 배율. radius 와 항상 함께 움직인다.
var speed := 1.0        ## 이동 속도 배율
var lifetime := 1.0     ## 수명 배율
var repeat := 0         ## 추가 시전 횟수 (메아리)
var repeat_delay := 0.35
var repeat_power := 0.6 ## 추가 시전의 세기 (1.0 = 본체와 동일)
var split := 0          ## 소멸 시 쪼개질 개수 (분열)
## 생성물이 **연출만** 맡는가. 분출 바위가 그렇다 — 판정은 도넛 면적이 따로 낸다.
var visual_only := false

static func make(id_: StringName, tags_: Array[StringName], src_: DamageSource) -> ObjectSpec:
	var s := ObjectSpec.new()
	s.id = id_
	s.tags = tags_
	s.src = src_
	return s

func has(tag: StringName) -> bool:
	return tags.has(tag)

## 모디파이어 목록을 적용한다. **순서는 카드 순서가 아니라 여기 적힌 단계 순서**다 —
## 카드 순서가 결과를 바꾸면 "어떤 순서로 먹었더라"를 플레이어가 추적해야 한다.
##
## ⚠️ **수량(count)만 합이고 나머지는 곱**이다. 곱으로 하면 다중화 2장이 3 → 5 → 8.3 이
##    된다. 3 → 5 → 7 이어야 한다 (PoE 도 발사체 수는 가산이다).
## ⚠️ radius 와 scale 은 **같은 배율로만** 움직인다. 따로 두면 연출이 판정보다 넓어지는
##    거짓말이 생긴다 — 충격파에서 실제로 겪었다 (2026-08-18).
func apply(mods: Array[StringName]) -> ObjectSpec:
	var live: Array[Dictionary] = []
	for m in mods:
		var d := Modifiers.by_id(m)
		if not d.is_empty() and Modifiers.matches(d, self):
			live.append(d)

	# 1) 수량 — 합
	for d in live:
		count += int(d.get("count_add", 0))
	count = maxi(1, count)
	# 2) 크기·속도 — 곱
	for d in live:
		var rm: float = d.get("radius_mul", 1.0)
		radius *= rm
		scale *= rm
		speed *= float(d.get("speed_mul", 1.0))
	# 3) 시간 — 수명, 반복
	for d in live:
		lifetime *= float(d.get("lifetime_mul", 1.0))
		repeat += int(d.get("repeat_add", 0))
	# 4) 충돌 시 행동
	for d in live:
		split += int(d.get("split_add", 0))
	# 5) 최종 수치 보정
	for d in live:
		damage *= float(d.get("damage_mul", 1.0))
	return self

## 이 스펙에서 파생되는 자식 오브젝트의 출처. 깊이 상한을 넘으면 null —
## 부르는 쪽은 **null 이면 만들지 않는다.**
func child_src(child_id: StringName, coeff := 1.0) -> DamageSource:
	if src == null or not src.can_spawn():
		return null
	return src.child(child_id, coeff)

func _to_string() -> String:
	return "%s x%d dmg=%.1f r=%.2f spd=%.2f life=%.2f rep=%d split=%d" % [
		id, count, damage, radius, speed, lifetime, repeat, split]
