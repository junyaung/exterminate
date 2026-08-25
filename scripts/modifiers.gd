class_name Modifiers
extends RefCounted

## 모디파이어 — PoE 의 **서포트 젬** 역할. 태그가 맞는 오브젝트의 스펙을 고친다.
## 카드로 노출하기 전 단계라 지금은 데이터 + 디버그 키로만 켠다 (HammerStrike.active_mods).
##
## ⚠️ 효과는 **데이터**로만 적는다 (Callable 금지). 그래야 적용 순서를 ObjectSpec.apply()
##    한 곳이 정할 수 있다. 함수로 적으면 순서가 카드 목록 순서를 타서, 같은 카드 조합인데
##    먹은 순서에 따라 결과가 달라진다.
##
## tags 가 비어 있으면 **모든 오브젝트**에 걸린다.
## excludes 에 오브젝트 id 를 적으면 태그가 맞아도 그 오브젝트는 제외된다 —
## "발사체인데 이 하나만 예외" 를 위해 태그를 새로 파는 것보다 싸다.
## 필드: count_add(합) / radius_mul / speed_mul / lifetime_mul / damage_mul(곱)
##       repeat_add / split_add

const MODS: Array[Dictionary] = [
	{
		# 거대화와 다중화는 **정반대 축**이다. 둘을 같이 넣어야 선택이 생긴다 —
		# 하나만 있으면 "먹으면 좋은 것"이지 빌드가 아니다.
		# ⚠️ **발사체 전용**이다 (유저 지시 2026-08-18). 날아가는 물체가 커지는 것과
		#    면적이 넓어지는 것은 다른 축이라, 면적 쪽은 '광역화'가 따로 맡는다.
		#    한 카드가 둘 다 하면 면적 오브젝트가 다섯 종이라 그 카드만 압도적으로 세진다.
		id = &"giant", mname = "거대화", desc = "발사체 크기 +100%\n수량 -1, 피해 +25%",
		tags = [ObjectSpec.TAG_PROJECTILE],
		count_add = -1, radius_mul = 2.0, damage_mul = 1.25,
	},
	{
		# 거대화의 면적판. 대상이 겹치지 않는다 — 거대화는 발사체(불덩이·분출바위),
		# 광역화는 면적(충격파·균열·분화구·폭연·특수).
		# ⚠️ 피해 감소는 **없다** (유저 지시 2026-08-18). 순수하게 넓어지기만 한다 —
		#    대가를 붙이지 않기로 한 것이니 밸런스를 이유로 다시 깎지 말 것.
		id = &"wide", mname = "광역화", desc = "범위 +100%",
		tags = [ObjectSpec.TAG_AREA],
		radius_mul = 2.0,
	},
	{
		id = &"multi", mname = "다중화", desc = "수량 +2, 크기 -30%, 피해 -40%",
		tags = [ObjectSpec.TAG_PROJECTILE],
		count_add = 2, radius_mul = 0.7, damage_mul = 0.6,
	},
	{
		id = &"swift", mname = "질주", desc = "이동 속도 +40%, 수명 -15%",
		tags = [ObjectSpec.TAG_PROJECTILE],
		speed_mul = 1.4, lifetime_mul = 0.85,
	},
	{
		# ⚠️ 재귀 위험. 반복 시전은 **자식이 또 반복하지 않도록** 부르는 쪽에서
		#    DamageSource.can_spawn() 을 확인해야 한다.
		id = &"echo", mname = "메아리", desc = "0.35초 뒤 한 번 더 (세기 60%)",
		tags = [],
		repeat_add = 1,
	},
	{
		id = &"linger", mname = "잔류", desc = "바닥에 남는 것의 지속 ×2",
		tags = [ObjectSpec.TAG_GROUND],
		lifetime_mul = 2.0,
	},
	{
		# ⚠️ 재귀 위험. 분열체는 depth+1 이라 MAX_DEPTH 에서 자연히 멈춘다.
		# ⚠️ 분출 바위는 **뺀다** (유저 지시 2026-08-18). 바위는 연출 전용이라
		#    쪼개져도 피해가 없다 — 화면만 시끄러워지고 효과는 0 이 된다.
		id = &"split", mname = "분열", desc = "발사체가 사라질 때\n작은 것 2개로 쪼개진다",
		tags = [ObjectSpec.TAG_PROJECTILE], excludes = [&"erupt_rock"],
		split_add = 2,
	},
]

static func by_id(id: StringName) -> Dictionary:
	for m in MODS:
		if m.id == id:
			return m
	return {}

## tags 가 비어 있으면 전부에 걸린다. 아니면 **하나라도 겹치면** 걸린다.
static func matches(mod: Dictionary, spec: ObjectSpec) -> bool:
	if spec.id in mod.get("excludes", []):
		return false
	var tags: Array = mod.get("tags", [])
	if tags.is_empty():
		return true
	for t in tags:
		if spec.has(t):
			return true
	return false
