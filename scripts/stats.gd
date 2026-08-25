class_name Stats
extends RefCounted

## 업그레이드로 바뀌는 모든 수치의 단일 통로.
## 최종값 = (기본 + flat 합) * (1 + pct 합)
##
## 새 스탯을 추가할 때 이 클래스는 건드릴 필요 없다 — 키 상수 한 줄만 늘리고,
## 소유자가 _init 에 기본값을 넣으면 끝. 값을 읽을 땐 항상 get_v() 를 거칠 것.
## 캐시해두면 업그레이드가 반영되지 않는다.

# --- 스탯 키 ---------------------------------------------------------------
# 오타를 런타임 침묵 대신 에러로 만들려고 상수로 둔다.
const HEALTH := &"health"
const DAMAGE := &"damage"              ## 세 공격 공통 기반 피해
## ⚠️ 평타 **전용** 피해 배율 (기본 1.0). 담금질이 여기 붙는다 — DAMAGE 에 붙이면
##    차징·우클릭까지 같이 오른다 (유저 지시 2026-08-13: 담금질은 평타만).
const DAMAGE_NORMAL := &"damage_normal"
## ⚠️ 쿨타임·범위는 **평타 전용**이다 (유저 지시 2026-08-13). 차징은 아래 CHARGE_* 를 쓴다.
## 평타와 차징의 템포를 카드로 따로 키우려면 둘이 같은 스탯을 보면 안 된다.
const COOLDOWN := &"cooldown"
const RADIUS := &"radius"
const SPEED := &"speed"
const ATTACK_RANGE := &"attack_range"
## --- 차징 전용 ---
const COOLDOWN_CHARGED := &"cooldown_charged"  ## 풀차징 후 쿨타임 (평타 쿨감이 안 먹는다)
## --- 우클릭 특수 (하늘에서 수직 낙하) ---
const COOLDOWN_SPECIAL := &"cooldown_special"
## 클릭 후 착탄까지의 예고 시간(초). '신속한 천벌' 이 **고정값**으로 깎는다 —
## 배율이 아니라 초 단위라 add_flat 을 쓴다 (스펙: 0.2초 감소).
const TELEGRAPH_SPECIAL := &"telegraph_special"
const SPECIAL_RADIUS := &"special_radius"            ## 우클릭 **직격** 반경 배율 (기본 1.0)
## --- 세 공격 공통 ---
## ⚠️ RADIUS 와 다르다. RADIUS 는 **평타 전용**이고 이건 평타·차징·우클릭 직격에 전부 곱한다.
##    여진·폭연·불덩이 같은 2차 공격 범위에는 **적용하지 않는다** (유저 스펙: '확장된 권능').
##    그래서 2차 효과는 strike_radius() 가 아니라 secondary_radius() 를 봐야 한다.
const RADIUS_ALL := &"radius_all"
const CHARGE_TIME := &"charge_time"            ## 풀차징까지 눌러야 하는 시간
const CHARGE_DAMAGE := &"charge_damage"        ## 풀차징 피해 배율
const CHARGE_RADIUS := &"charge_radius"        ## 풀차징 범위 배율
## --- 성장 ---
const XP_GAIN := &"xp_gain"                    ## 경험치 획득 배율 (기본 1.0)
## 일반 적 출현량 배율 (기본 1.0). 보스는 이걸 안 본다 — 카드 문구가 '일반 적' 이다.
## ⚠️ 가산이라 '전쟁의 부름 3 + 신의 억제 1' 이 자동으로 +20% 가 된다 (유저 스펙의 상쇄 규칙).
##    다만 지금은 한쪽을 고르면 반대쪽이 풀에서 빠지므로 실제로 섞이진 않는다.
const SPAWN_RATE := &"spawn_rate"
# 예정: ARMOR_PEN, BURN, FREEZE ... 필요할 때 여기에 추가한다.

var _base: Dictionary
var _flat: Dictionary = {}
var _pct: Dictionary = {}

func _init(base: Dictionary) -> void:
	_base = base.duplicate()

## 업그레이드가 반영된 현재값.
func get_v(key: StringName) -> float:
	var b: float = float(_base.get(key, 0.0)) + float(_flat.get(key, 0.0))
	return b * (1.0 + float(_pct.get(key, 0.0)))

## 고정 수치 가감. 예: 피해 +25
func add_flat(key: StringName, amount: float) -> void:
	_flat[key] = float(_flat.get(key, 0.0)) + amount

## 비율 가감. 0.2 = +20%, -0.2 = -20%.
## 쿨감(cooldown reduction)은 별도 스탯이 아니라 add_pct(COOLDOWN, -0.2) 로 표현한다.
func add_pct(key: StringName, ratio: float) -> void:
	_pct[key] = float(_pct.get(key, 0.0)) + ratio

## 기본값 자체를 갈아끼운다 (등급업 등). 업그레이드 보정치는 그대로 유지된다.
func set_base(key: StringName, value: float) -> void:
	_base[key] = value

## 디버그/HUD 용.
func describe() -> String:
	var out := PackedStringArray()
	for key in _base:
		out.append("%s=%.2f" % [key, get_v(key)])
	return ", ".join(out)
