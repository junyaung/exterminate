class_name HammerStrike
extends Node3D

## 신의 망치. 평소엔 카메라 밖(하늘)에 숨어 있고, 지면에는 오렌지색
## 점선 원(공격 범위)만 마우스를 따라다닌다. 좌클릭하면 그 자리에
## 하늘에서 망치가 내리꽂힌다 — 분노한 신이 세상을 내려치는 힘.

# --- 업그레이드로 바뀌는 값 (기본치). 실제 사용은 항상 stats.get_v() 를 거친다 ---
@export var base_damage := 100.0
@export var base_cooldown := 0.65          ## 평타 쿨타임
@export var base_cooldown_charged := 0.65  ## 풀차징 쿨타임 (평타와 따로 논다)
@export var base_radius := 4.0

# --- 연출용. 업그레이드 대상이 아니다 ---
@export var hammer_scale := 6.0     ## 망치 총 길이 (모델이 1.0 유닛으로 정규화되어 있음)
@export var cock_angle := 150.0     ## 임팩트 자세 기준 뒤로 젖히는 각도
@export var swing_time := 0.13      ## 내리치는 시간. 짧을수록 격렬하다.
## 평타 전용 스윙 시간. 평타는 **누르는 순간** 맞아야 해서 예비 동작을 건너뛰고
## 이 시간만에 내리꽂는다 (유저 지시 2026-08-15: 평타 입력 지연 제거).
@export var tap_swing_time := 0.045
@export var embed := 0.06           ## 타격면이 지면에 파고드는 깊이 (scale 비율)
@export var entry_height := 26.0    ## 스윙 시작 시 그립 높이 — 신의 팔은 하늘에서 내려온다
@export var entry_back := 9.0       ## 스윙 시작 시 타깃 반대쪽으로 물러난 거리
# --- 오브젝트 시스템 (2026-08-18) ---------------------------------------------
## 지금 켜져 있는 모디파이어. 카드로 노출하기 전 단계라 디버그 키(F5~F10)로 켠다.
## ⚠️ 여기에 카드 로직을 넣지 마라. 카드가 붙을 땐 이 배열을 채우는 주체만 바뀐다.
@export var active_mods: Array[StringName] = []

## 이번 스윙의 출처. 스윙마다 새로 만들어 그 스윙에서 나온 오브젝트 전부가 공유한다.
var _swing_src: DamageSource

## 오브젝트 스펙을 만들고 **활성 모디파이어를 먹인 뒤** 돌려준다.
## 생성 함수는 완성된 스펙만 받는다 — 태그 매칭은 전부 여기서 끝난다.
## ⚠️ count 는 **apply 전에** 넣어야 한다. 모디파이어의 수량 가감이 여기에 얹히기 때문이다.
##    apply 를 두 번 부르면 배율이 두 번 곱해진다 — 스펙은 한 번만 굽는다.
## ⚠️ 오브젝트의 출처는 스윙 출처 **그 자체가 아니라 그 자식**이다. 그래야
##    "망치가 직접 때린 것(depth 0, direct)" 과 "카드가 만든 것(depth 1, secondary)" 이
##    구분된다 — 폭연이 직격 사망자만 노리는 규칙이 이 구분 위에 서 있다.
func object_spec(id: StringName, tags: Array[StringName], damage: float, radius: float,
		count := 1, src: DamageSource = null) -> ObjectSpec:
	var base: DamageSource = src if src != null else _swing_src
	if base == null:
		base = DamageSource.root(&"normal")
	var spec := ObjectSpec.make(id, tags, base.child(id))
	spec.damage = damage
	spec.radius = radius
	spec.count = maxi(1, count)
	return spec.apply(active_mods)

## 분화구가 뿜는 불덩이. 발수(balls)를 수량으로 넣어 다중화·거대화가 발수를 직접 건드린다.
func fireball_spec(damage: float, radius: float, balls: int) -> ObjectSpec:
	return object_spec(&"fireball", PROJECTILE_TAGS, damage, radius, balls)

## 분화구 자신. 바닥에 남는 발사대라 ground+area — 잔류가 수명을 늘린다.
func crater_spec(radius: float) -> ObjectSpec:
	return object_spec(&"crater", GROUND_AREA_TAGS, 0.0, radius)

## 분출 바위. 날아가 떨어지는 물체라 projectile.
## ⚠️ radius 인자는 **분출 판 전체의 반경**이다 (바위 하나 크기가 아니다) — _erupt_rocks 주석 참고.
func rock_spec(damage: float, radius: float, count: int) -> ObjectSpec:
	return object_spec(&"erupt_rock", PROJECTILE_TAGS, damage, radius, count)

## 폭연. 시체 자리에서 터지는 범위라 area — 바닥에 남지 않으니 ground 는 아니다.
## count 는 **몇 구를 터뜨리는가**. 거대화가 여기서 "적게, 대신 크게"로 읽힌다.
func deflag_spec(damage: float, radius: float, count: int) -> ObjectSpec:
	return object_spec(&"deflagration", AREA_TAGS, damage, radius, count)

## 우클릭 충격파가 퍼지는 반경. **맥스 차징 충격파와 같은 크기**다 (유저 지시 2026-08-18).
## ⚠️ 특수 직격 반경(6.0)에 곱하지 않는다 — 그러면 14.4 가 되어 맥스 차징(19.2)보다 작다.
##    "특수가 궁극기인데 차징보다 좁다" 를 피하려고 차징 쪽 배율에서 파생시킨다.
func special_shock_spread() -> float:
	return base_radius * stats.get_v(Stats.CHARGE_RADIUS) * shock_spread \
		* stats.get_v(Stats.RADIUS_ALL)

## 끌어당김. 바닥에 깔려 잠깐 남는 흡입이라 **area + ground** 다 —
## '광역화'(area)가 흡입 반경을, '잔류'(ground)가 흡입 시간을 늘린다.
## ⚠️ 피해 0 이라 '거대화' 계열의 피해 배율은 의미가 없다. 그게 정상이다 (순수 유틸).
func pull_spec(radius: float) -> ObjectSpec:
	return object_spec(&"pull_field", GROUND_AREA_TAGS, 0.0, radius)

## 우클릭 끌어당김이 미치는 반경. **맥스 차징 끌어당김과 같은 크기**다 (유저 지시 2026-08-25).
## ⚠️ special_shock_spread() 와 같은 이유로 특수 직격 반경(6.0)에 곱하지 않는다 —
##    그러면 차징보다 좁아져서 "궁극기가 더 좁다" 가 된다.
func special_pull_spread() -> float:
	return base_radius * stats.get_v(Stats.CHARGE_RADIUS) * pull_spread \
		* stats.get_v(Stats.RADIUS_ALL)

## 우클릭 특수 자체. 하늘에서 꽂히는 범위 타격이라 area.
## ⚠️ 메아리 망치는 **이 스펙의 repeat** 로 나온다 (모디파이어 '메아리').
##    예전엔 '천벌의 메아리' 카드가 echo_level 을 올렸는데, 같은 일을 하는 통로가
##    둘이 되므로 카드를 없애고 모디파이어 하나로 합쳤다 (유저 지시 2026-08-18).
func special_spec(damage: float, radius: float) -> ObjectSpec:
	return object_spec(&"special_slam", AREA_TAGS, damage, radius)

## 균열 지대. 바닥에 남는 범위라 area + ground — 잔류가 수명을 늘린다.
func crack_spec(radius: float) -> ObjectSpec:
	return object_spec(&"crack_field", GROUND_AREA_TAGS, 0.0, radius)

## ⚠️ 타입 있는 배열이라 호출부에서 리터럴로 못 넘긴다 — 상수로 한 번만 만든다.
const PROJECTILE_TAGS: Array[StringName] = [&"projectile"]
const GROUND_AREA_TAGS: Array[StringName] = [&"area", &"ground"]
const AREA_TAGS: Array[StringName] = [&"area"]

# --- 공격 패턴 카드: 충격파 (Shockwave) ---
## 평타가 때린 자리에서 고리가 퍼져나가 **바깥쪽 적을 밀어내며 깎는다.**
## 직격은 그대로고, 그 바깥 고리가 추가로 붙는 형태다 — 우클릭 특수의 문법과 같다.
## ⚠️ 이름이 has_* 인 건 규약이다. card_ui 가 flag 카드를 이 프로퍼티로 켠다.
@export var has_shockwave := false
## 고리가 퍼지는 배율 (직격 반경 기준).
## 2026-08-18 에 2.64 로 10% 키웠다가 되돌렸다 — 기본값은 작게 두고 **업그레이드로
## 키우는 여지**를 남기는 쪽이 낫다는 판단(유저). 반경 카드가 이미 여기에 곱해진다.
@export var shock_spread := 2.4
@export var shock_damage := 0.35     ## 고리 피해 = 그 스윙 직격의 35%
@export var shock_knockback := 14.0  ## 대강타(9)보다 세고 특수(22)보다는 약하게

# --- 끌어당김(집결) 카드 -------------------------------------------------------
## 망치가 지면을 가격하는 **그 순간** 범위 안의 적을 중심으로 끌어온다.
## 피해는 0 — 순수 유틸이다 (유저 지시 2026-08-25).
##
## 왜 착탄 시점인가 (유저 결정): 충격파와 **같은 문법**이 되어야
##   · '메아리' 가 끌어당김을 그대로 한 번 더 일으키고
##   · 나중에 슬로우 패턴이 붙으면 끌어당김과 **동시에** 터진다
## 흡입을 예고/차징 중에 돌리면 저 둘이 어긋나고, '신속한 천벌'(착탄 대기 -0.3초)과도
## 충돌한다. 착탄 한 점에 모으면 그 충돌이 아예 없어진다.
@export var has_pull := false
## 끌어당김 반경 = 그 스윙의 직격 반경 × 이 값. 평타(4)→9.6, 맥스 차징(8)→19.2.
## 충격파와 같은 배수라 두 카드의 "미치는 범위"가 화면에서 같게 읽힌다.
@export var pull_spread := 2.4
## 한 번에 끌려오는 **거리**. 반경이 아니다 — 멀리 있던 적일수록 중심 근처까지 오진 않는다.
## 장수풍뎅이 같은 무거운 몹은 knockback_resist 만큼 깎여 절반만 온다 (Enemy.pull).
@export var pull_distance := 6.0

# --- 회오리 = 충격파 + 인력 (조합 자동 발동) -----------------------------------
## 두 카드를 다 가지면 **밀지도 당기지도 않는다.** 남는 건 접선 방향 — 적이 착탄점 주위를 돈다.
## 조합이 제3의 효과가 되는 건 이 게임의 규약이다 (여진 + 불 = 분화구와 같은 자리).
##
## ⚠️ 이건 취향이 아니라 **버그 수정이기도 하다.** 그냥 두면 넉백이 적을 띄우는 동안
##    인력이 통째로 버려져서, 잡졸에겐 인력이 없는 것과 같고 탱커에겐 약해진다 —
##    몹 종류에 따라 결과가 정반대다 (2026-08-25 실측). 힘 하나로 대체하면 그 문제가 사라진다.
@export var vortex_arc := 5.0        ## 한 번에 도는 호의 길이. 클수록 빠르게 돈다.
@export var vortex_inward := 0.12    ## 그중 안쪽으로 감기는 비율. 0 이면 궤도가 벌어진다.

func has_vortex() -> bool:
	return has_shockwave and has_pull

## 고리가 실제로 미는 세기. 회오리일 땐 0 — 미는 힘은 접선으로 **변환됐다**.
## ⚠️ 고리의 피해는 그대로 남는다. 사라지는 건 넉백뿐이다.
func shock_knock() -> float:
	return 0.0 if has_vortex() else shock_knockback

# --- 공격 변화 카드: 여진 (Aftershock) ---
## 첫 카드 시험용. UI 가 없으므로 이 체크박스 또는 F1 키로 켠다.
@export var has_aftershock := false
@export var aftershock_delay := 0.35     ## 충돌 후 재공격까지
@export var aftershock_damage := 0.5     ## 원래 공격 피해의 50%
@export var aftershock_radius := 1.2     ## 원래 공격 범위의 120%
@export var aftershock_shake := 0.3      ## 최초 충돌 대비 화면 흔들림 (훨씬 약하게)
@export var aftershock_strength := 0.55  ## 시각적 세기 (최초 충돌 = 1.0)

# --- 속성 카드: 불 (Fire) ---
## 2번 카드. 여진과 조합하면: 균열에 잔열(ember)이 흐르고, 재타격 시 분출 대신
## **분화구**가 생긴다 — 5초간 2초 간격으로 불덩이 8개를 사방에 뿜는다.
@export var has_fire := false
@export var fire_ball_damage := 0.4      ## 불덩이 하나당 그 스윙 피해의 40%
## 불덩이 시각 크기가 0.9~1.26(지름 1.8~2.5) 이라 판정도 그에 맞춘다
@export var fire_ball_radius := 2.0

## --- 폭연: 불 속성 단독일 때 기본 공격이 바뀌는 방식 ---
## 망치에 직접 맞아 죽은 적이 0.15초 뒤 터진다. 큰 원 하나가 아니라
## 타격 범위 곳곳에서 작은 원 여럿이 연쇄적으로 터지는 형태가 된다.
@export var deflag_count := 3             ## 평타 한 번에 터뜨릴 시체 수
@export var deflag_count_charged := 6     ## 풀차징
@export var deflag_damage := 0.20         ## 그 스윙 피해의 20%
## 반경은 **차징 배율을 뺀** 기본 타격 반경 기준이다. 차징 반경(×2)에 곱하면
## 폭연이 통째로 두 배가 되어 "약간 더 넓게" 라는 의도를 넘어선다.
## 0.45 -> 0.52: 유저 지시로 폭발 반경 15% 확대 (반경 1.80 -> 2.08).
@export var deflag_radius := 0.52
@export var deflag_radius_charged := 1.3  ## 풀차징이면 폭연 반경 ×1.3
## **시체가 클수록 크게 터진다.** 폭연 반경이 고정이면 보스(몸 반경 8.4)가 터질 때
## 반경 2 짜리 폭발이 몸속에 파묻혀 "터졌다"로 안 읽힌다. 몸 반경에 이 비율만큼 더한다.
@export var deflag_body_scale := 0.75
@export var deflag_knock := 4.0           ## 약한 바깥쪽 넉백
@export var deflag_knock_charged := 6.0

# --- 분출: 갈라진 땅을 다시 내려치면 지면이 터진다 ---
@export var erupt_damage := 0.8          ## 그 스윙 피해의 80% 를 추가로
@export var erupt_knockback := 11.0      ## 넉백 세기 (무거운 적은 뜨지 않고 밀리기만)
@export var erupt_shake := 1.3
## 분출로 튀어나오는 돌덩이. 착지한 자리에서 범위 피해를 준다.
@export var erupt_rocks := 8
## ⚠️ **더 이상 안 쓴다** (2026-08-18). "돌 하나당 50%" 는 돌마다 판정이 있던 시절의 값이다.
##    지금은 판정이 도넛 하나뿐이라, 여기에 또 곱하면 "여러 발 맞을 수 있으니 한 발은 약하게"
##    라는 전제가 사라진 채 약해지기만 한다 — 실제로 개미(체력 100)가 25 를 맞고 살아남아
##    "바위에 깔렸는데 안 죽는" 그림이 나왔다 (유저 제보). 손잡이는 남겨 두되 곱하지 않는다.
@export var erupt_rock_damage := 0.5
## 바위 크기가 1.44~1.92 라 판정 1.6 은 "맞은 것 같은데 안 맞는" 구간이 생겼다 -> 2.0
@export var erupt_rock_radius := 2.0

# --- 차징 ---
## 이 시간 안에 떼면 차징 0 = 평타. 짧게 톡톡 치는 플레이를 막지 않기 위한 구간.
@export var charge_deadzone := 0.2
## 최대 차징까지 누르고 있어야 하는 시간 (유저 지시 2026-08-13: 1.0 -> 2.0).
## ⚠️ '응축' 카드의 감소는 **가산**이라 4장이면 -80% 다. 1.0 이던 시절엔 0.2 초로 떨어져
##    데드존 하한(0.25)에 걸렸고, 풀차징이 사실상 공짜가 됐다. 2.0 이면 4장에도 0.4 초다.
@export var charge_max_time := 2.0
## 최대 차징 시 배율. 전부 stats 값에 곱해지므로 업그레이드와 자연히 합성된다.
@export var charge_damage_mult := 2.5   ## 피해 100 -> 250
@export var charge_radius_mult := 2.0   ## 반경 4 -> 8
@export var charge_scale_mult := 1.35   ## 망치 크기 6 -> 8.1
## 지면 분출 돌 개수 배율 (8 -> 12). 차징은 "한 방이 세진다"만이 아니라
## "터지는 게 많아진다"로도 보여야 한다.
## 불덩이 쪽은 발리당 개수가 작아 배율이 안 맞는다 — Crater.CHARGE_BONUS 로 따로 더한다.
@export var charge_count_mult := 1.5

# --- 풀차징 임팩트 연출 (유저 지시 2026-08-13) --------------------------------
# 예전엔 평타와 **양적 차이뿐**이었다 (먼지 26->60, 흔들림 1.0->1.8). 같은 걸 더 많이
# 뿌리면 '더 세다'는 읽히지만 '다른 공격'으로는 안 읽힌다. 그래서 두 축을 새로 쓴다:
#   공간 — 위로 터지는 먼지 대신 **바닥을 훑는 압축 고리** (평타와 방향이 정반대)
#   시간 — 임팩트 순간 **히트스톱** (파티클 없이 무게를 전달)
## 이 비율 이상이면 풀차징 연출로 친다. 1.0 을 요구하면 살짝 일찍 뗀 스윙이 매번
## 밋밋해져서 "됐다/안 됐다"가 운처럼 느껴진다 — 조금 너그럽게 잡는다.
@export var charge_fx_min_ratio := 0.8
@export var charge_ring_amount := 110      ## 압축 고리 알갱이 수 (둘레가 길어 넉넉해야 한다)
@export var charge_dust_kick := 22         ## 고리와 함께 터지는 작은 수직 먼지
@export var charge_hitstop := 0.07         ## 멈추는 시간 (실시간 초)
@export var charge_hitstop_scale := 0.12   ## 멈춘 동안의 시간 배속

# --- 우클릭 특수: 하늘에서 수직 낙하 (유저 스펙 2026-08-13) -------------------
# 좌클릭 스윙과 **다른 문법**이다: 저건 비스듬히 휘둘러 꽂히고, 이건 그냥 떨어진다.
# 예고(그림자) 2초가 있어서 적을 끌어모아 놓고 쓰는 배치 기술이 된다.
@export var special_cooldown := 7.0        ## 우클릭 쿨타임 (3 -> 5 -> 7, 유저 지시 2026-08-14)
@export var special_telegraph := 2.0       ## 그림자가 뜬 뒤 떨어질 때까지
@export var special_scale_mult := 2.0      ## 평타 망치의 2배 크기
@export var special_radius_mult := 1.5     ## 직격 반경 = 평타 반경 × 이 값
## ⚠️ 자리표시자 — 밸런스는 카드가 다 모인 뒤에 (health 와 같은 취급).
@export var special_damage_mult := 2.5     ## 직격 피해 = 기본 피해 × 이 값
@export var special_fall_height := 26.0    ## 낙하 시작 높이
## 예고가 끝나고 **내리꽂히는** 시간. 길면 '내려온다', 짧아야 '꽂힌다'.
## 2초 내내 망치가 보이면 긴장이 풀린다 — 그림자만 커지다가 순간적으로 나타나야
## 강력함이 전달된다 (유저 지시 2026-08-13).
## 0.09 -> 0.05 (유저 지시 2026-08-14). 26유닛을 0.05초에 내려오므로 초속 520 —
## 60fps 에서 프레임당 8.7유닛이라 **낙하 중 망치가 보이는 프레임은 서너 장뿐**이다.
## 그게 노림수다: 보이는 게 아니라 '박혔다'로 읽힌다.
## ⚠️ 이 값은 예고의 하한도 정한다 (telegraph_time = max(설정값, slam × 3)).
##    0.27 -> 0.15 로 내려가므로 '신속한 천벌'을 더 쌓을 수 있게 된다.
@export var special_slam_time := 0.05
## 꽂힌 뒤 망치 길이의 몇 할이 땅에 박히는가 (유저 스펙: 10%).
@export var special_embed := 0.10
## 8방위(동·북동·북·북서·서·남서·남·남동) 중 하나로 이만큼 기운 채 꽂힌다.
## 똑바로 꽂히면 도장 찍은 것처럼 심심하다 — 기울어야 '내리꽂혔다'가 된다.
@export var special_tilt_deg := 15.0
## 박힌 채 남아있는 시간. 1.0 은 너무 빨리 치워져서 '꽂혔다'가 눈에 안 남았다 (유저 지적).
## 쿨타임(5초) 안에 증발까지 끝나야 다음 발동 때 이전 망치가 겹쳐 보이지 않는다.
@export var special_linger := 2.0
## 소각(종이 타기)에 걸리는 시간. 0.45 는 디졸브가 너무 빨라 '탄다'가 안 읽혔다.
## ⚠️ 예산: 예고 2.0 + 강타 0.09 + 유지 2.0 + 소각 0.9 = 4.99 ≤ 쿨타임 5.0.
##    이보다 늘리려면 쿨타임도 같이 늘려야 이전 망치가 겹치지 않는다.
@export var special_evaporate := 0.9
@export var special_shake := 2.0
## --- 착탄 파편 (유저 지시 2026-08-14: 먼지 대신 돌 파편) ---
## 피해는 **없다** — 순수 이펙트다. 분출 바위의 잔해(EruptRock 의 debris)를 그대로 쓴다.
@export var special_debris := 48          ## 튀어오르는 조각 수 (16 -> 48, 유저 지시 2026-08-14)
@export var special_debris_airtime := 1.8 ## 체공 시간(초). 초속은 여기서 역산된다
@export var special_debris_spread := Vector2(2.0, 9.0)  ## 착지 산포 반경
## 흙 자국 크기 = 직격 반경 × 이 값. 망치 머리가 판 구멍이라 피해 반경 전체보다 훨씬 작다.
@export var special_dirt_fit := 0.42
## 특수가 만드는 균열 지대의 반경 = 직격 반경 × 이 값.
## 평타는 2차 효과 반경(≈ 평타 반경)을 그대로 쓰는데, 특수 직격 반경은 평타의 1.5배라
## 그대로 쓰면 균열이 화면을 덮는다. 0.8 이면 평타 균열의 약 1.2배로 "더 넓게 갈라졌다"가 읽힌다.
@export var special_crack_fit := 0.8
## 특수는 **재타격 없이도** 여진과 함께 바위가 솟는다 (유저 지시 2026-08-16).
## 평타는 갈라진 땅을 한 번 더 쳐야 뒤집히지만, 특수는 한 방이 그만큼 무거우니
## 떨어지는 것만으로 지면이 뒤집힌다. 바위 위력 = 특수 직격 피해 × 이 값
## (그 뒤 바위 하나당 erupt_rock_damage 가 또 곱해진다 — 평타 분출과 같은 문법).
@export var special_erupt_damage := 0.5
## ⚠️ **개수 배율은 이제 의미가 거의 없다** (2026-08-18). 바위 수는 도넛 넓이에서 나오는데
##    (ERUPT_FILL) 특수는 판 자체가 이미 넓어서 개수가 자동으로 는다. 여기에 배율을 또
##    곱하면 이중 계산이라 특수 한 방에 400개가 넘게 나왔다. 1.0 으로 두고, 남겨 둔 이유는
##    "특수만 유독 성글다/빽빽하다" 가 나올 때 돌릴 손잡이가 필요해서다.
@export var special_erupt_rocks_mul := 1.0
## 특수 분출의 **산개 반경 배수** (유저 지시 2026-08-18: "범위 20% 늘려줘").
## 개수(special_erupt_rocks_mul)와 따로 둔다 — 같은 개수를 더 넓게 뿌리면 밀도가 떨어지고
## 좁히면 한 점에 뭉친다. 서로 다른 축이라 한 값으로 묶으면 조절이 안 된다.
@export var special_erupt_spread := 1.2

## --- 평타 여진: 재타격 없이 바로 분출 (유저 지시 2026-08-18) -----------------
## 예전 규칙은 "균열을 만들고 → 그 자리를 한 번 더 쳐야 뒤집힌다" 였다. 이제 **첫 방에 바로**
## 바위가 솟는다. 특수와의 차별점은 **산개 반경**이고, 개수는 그 반경에서 자동으로 따라온다
## (넓이 기준 — ERUPT_FILL). 개수 배율은 1.0 이 기본이다.
## ⚠️ 균열은 **그대로 남긴다.** 밟고 지나가기(stumble)와 균열 계열 카드가 균열의 존재를
##    전제로 돌아간다. 남은 균열을 다시 치면 예전처럼 소모되며 더 크게 분출한다(8개 + 범위 피해).
## 평타 분출 개수 배율. 1.0 -> 0.9 (유저 지시 2026-08-18: "거대화+여진 평타만 10% 줄여줘").
## ⚠️ 상한을 먼저 걸고 **그 뒤에** 곱하기 때문에, 상한에 걸린 거대화 평타에도 그대로 먹는다.
@export var normal_erupt_rocks_mul := 0.9
@export var normal_erupt_spread := 0.75   ## 평타 산개 반경 = 균열 반경 × 이 값
@export var normal_erupt_damage := 0.5    ## 바위 위력 = 그 스윙 피해 × 이 값 (특수와 같은 문법)

## 분화구 불덩이 개수 (유저 지시 2026-08-18: "평타 2발 / 특수 3발, 후속 추가 없음").
## ⚠️ 예전엔 분화구가 2초 간격으로 두 번 뿜어 총 6~10발이었다. 지금은 **한 번에 끝**이다.
##    개수를 늘리고 싶으면 발리를 되살리지 말고 이 숫자만 올릴 것 — 후속 발리는
##    "언제 끝났는지 모르겠다"는 인상을 만든다.
@export var crater_balls_normal := 2      ## 평타(무차징)
@export var crater_balls_charged := 3     ## 평타 풀차징
@export var crater_balls_special := 4     ## 우클릭 특수

## 차징 비율에 따른 평타 분화구 발수.
## ⚠️ **내림**이다 — 반올림하면 차징 0.5 에서 이미 3발이 되어 "덜 모았는데 늘었다"로 보인다
##    (분화구가 차징 보너스를 갖고 있던 시절에 같은 이유로 내림을 썼다).
##    즉 3발은 **꽉 채웠을 때만** 나온다.
func crater_balls_for(ratio: float) -> int:
	return crater_balls_normal \
		+ int(clampf(ratio, 0.0, 1.0) * float(crater_balls_charged - crater_balls_normal))

# --- 카드로 켜지는 것들 (유저 스펙 2026-08-13) --------------------------------
## 본체에서 메아리까지의 거리. ⚠️ 스펙 초안은 1.5~4.5 였는데, 그건 망치가 2배(scale 12)로
## 커지기 전 기준이었다. 망치 반폭이 4.33 유닛(모델 0.361 × 12)이라 그 범위에선 두 망치가
## **항상 48~83% 겹쳐** 한 덩어리로 뭉친다 — '쾅—쾅' 이 '쾅' 하나가 된다 (실측 후 유저 승인).
@export var echo_dist_min := 6.0
@export var echo_dist_max := 11.0
## 망치 **낙하 시차** — 본체가 떨어지고 이만큼 뒤에 메아리가 떨어진다 (유저 지시 2026-08-14).
## ⚠️ 예전엔 "본체 착탄 뒤 메아리 발사까지"였다. 지금은 메아리도 본체와 같은 길이의 예고를
##    받으므로, 예고 **시작**을 이만큼 밀면 착탄도 그대로 이만큼 밀린다.
##    즉 이 값이 곧 화면에서 보이는 '쾅 — 쾅' 사이의 간격이다.
@export var echo_gap := 0.5
@export var echo_radius_ratio := 0.85  ## 직격·쇼크웨이브 반경 모두 본체의 85%
## 메아리 예고는 **본체와 같은 길이**(telegraph_time)를 쓴다. 같은 일이 한 번 더
## 일어나는 것이므로 예고도 같아야 한다 (유저 지적 2026-08-14).

## '몰아치는 신격' 레벨. 스택은 **평타가 한 마리라도 맞혔을 때만** 오른다.
var combo_level := 0
const COMBO_PER_STACK := [0.0, 0.06, 0.09, 0.09]   ## 레벨별 스택당 피해 증가
const COMBO_MAX := [0, 5, 5, 7]                    ## 레벨별 최대 스택
@export var combo_window := 1.2        ## 마지막 명중 후 이 시간이 지나면 초기화

## '파괴의 박자' — 4회째 명중하는 평타가 대강타가 된다.
var has_beat := false
const BEAT_EVERY := 4
@export var beat_damage_mult := 1.75
@export var beat_radius_mult := 1.35
@export var beat_scale_mult := 1.25
## ⚠️ 스펙은 "밀쳐내는 거리 +50%" 인데 평타에는 원래 넉백이 **없다**(_damage_area 에 knock=0).
##    0 의 150% 는 0 이라 배율로는 의미가 없어서, 대강타 전용 절대값으로 잡았다.
##    지면 분출(11)보다 약하고 우클릭(22)보다 훨씬 약한 선.
@export var beat_knockback := 9.0

# 돌 머리 실측값 (모델 로컬 좌표, glb에서 잰 것)
const HEAD_CENTER_Y := 0.685   ## 자루 방향 머리 중심
const HEAD_FACE_X := 0.34      ## 타격면까지의 절반 폭
## 그립(모델 원점)에서 **머리 끝**까지. 모델이 길이 1.0 으로 정규화되어 있어 실측 1.000.
## 우클릭 특수는 망치를 세워 머리부터 꽂으므로 이 값이 접지 높이가 된다.
const HEAD_TIP_Y := 1.0
const PREP_TIME := 0.08        ## 하늘에서 치켜드는 예비 동작

## ⚠️ range_indicator.gdshader 의 aim_r 과 **같은 값**이어야 한다. 조준 원(=실제 사거리)이
##    쿼드의 이 지점에 그려지고, 그 바깥 여백에 우클릭 쿨 고리가 들어간다.
const AIM_R := 0.86

@onready var _indicator: MeshInstance3D = $Indicator
@onready var _hammer: Node3D = $WeaponHammer
@onready var _cam: Camera3D = get_viewport().get_camera_3d()

var stats: Stats

# 공격 횟수 — RunLog 가 판이 끝날 때 읽는다. 카드가 어느 공격을 밀어줬는지는
# 스탯만 봐서는 모르고, 실제로 몇 번 썼는지와 같이 봐야 읽힌다.
var tap_swings := 0
var charged_swings := 0
var special_swings := 0

var _cd := 0.0
var _cd_total := 1.0   ## 마지막으로 걸린 쿨의 총량 — 쿨타임 HUD 가 진행도(0~1)로 나누는 분모
var _shake := 0.0
var _tw: Tween

# 차징 상태
var _charging := false
var _charge := 0.0
# 버튼을 뗀 뒤 임팩트까지 — 조준 원/그림자를 낙하 지점에 묶어두는 구간
var _striking := false
var _strike_at := Vector3.ZERO
var _strike_ratio := 0.0

## 현재 차징 비율 0~1. 데드존 안에서는 0(평타).
## 풀차징까지 걸리는 시간. '응축' 카드가 이 값을 줄인다.
## 데드존(클릭과 홀드를 가르는 구간)은 줄이지 않는다 — 줄이면 평타가 차징으로 새기 시작한다.
func charge_time() -> float:
	return maxf(stats.get_v(Stats.CHARGE_TIME), charge_deadzone + 0.05)

func charge_ratio() -> float:
	return clampf((_charge - charge_deadzone) / maxf(charge_time() - charge_deadzone, 0.001), 0.0, 1.0)

## ratio 에 해당하는 **직격** 반경. 2차 효과(여진)는 secondary_radius() 를 쓸 것.
## ⚠️ 범위 카드(넓은 울림=RADIUS)는 **평타에만** 통한다 (유저 지시). 차징 범위는
##    기본 반경 × 과충전 배율로만 큰다. 다만 살짝만 눌러 ratio 가 0 에 가까울 때
##    평타보다 작아지면 안 되므로 평타 반경을 하한으로 깐다.
## RADIUS_ALL('확장된 권능')은 평타·차징 양쪽에 곱한다.
func strike_radius(ratio: float) -> float:
	return secondary_radius(ratio) * stats.get_v(Stats.RADIUS_ALL)

## 여진처럼 **2차로 파생되는** 효과의 반경. RADIUS_ALL 이 빠져 있는 게 유일한 차이다
## (유저 스펙: '확장된 권능'은 2차 공격 범위에는 적용하지 않음).
func secondary_radius(ratio: float) -> float:
	var normal := stats.get_v(Stats.RADIUS)
	if ratio <= 0.0:
		return normal
	return maxf(normal, base_radius * lerpf(1.0, stats.get_v(Stats.CHARGE_RADIUS), ratio))

## 모디파이어 디버그 토글. 카드로 노출하기 전까지의 임시 통로다.
## ⚠️ 숫자 5~0 을 쓴다. macOS 에서 F1~F12 는 밝기/볼륨 미디어 키라 못 쓴다
##    (이 파일 위쪽 디버그 키 주석과 같은 이유).
func _toggle_mod(idx: int) -> void:
	if idx < 0 or idx >= Modifiers.MODS.size():
		return
	var id: StringName = Modifiers.MODS[idx].id
	if active_mods.has(id):
		active_mods.erase(id)
	else:
		active_mods.append(id)
	var names := []
	for m in active_mods:
		names.append(Modifiers.by_id(m).mname)
	print("[mod] %s %s -> 활성: %s" % [
		Modifiers.MODS[idx].mname,
		"OFF" if not active_mods.has(id) else "ON",
		"없음" if names.is_empty() else ", ".join(names)])

func _ready() -> void:
	print("[디버그 키] 1 여진  2 불  4 우클릭쿨 초기화  O 분출 판정범위 표시")
	print("[모디파이어] 5 거대화(발사체)  6 광역화(면적)  7 다중화  8 질주  9 메아리  - 잔류  = 분열")
	add_to_group(&"hammer")   # CardUI 가 카드 효과를 꽂을 곳을 찾는 통로
	stats = Stats.new({
		Stats.DAMAGE: base_damage,
		Stats.COOLDOWN: base_cooldown,
		Stats.RADIUS: base_radius,
		# 차징은 평타와 **다른 스탯**을 본다 — 카드로 둘의 템포를 따로 키우기 위해서다.
		Stats.COOLDOWN_CHARGED: base_cooldown_charged,
		Stats.COOLDOWN_SPECIAL: special_cooldown,
		Stats.TELEGRAPH_SPECIAL: special_telegraph,
		Stats.SPECIAL_RADIUS: 1.0,
		Stats.RADIUS_ALL: 1.0,
		Stats.DAMAGE_NORMAL: 1.0,
		Stats.CHARGE_TIME: charge_max_time,
		Stats.CHARGE_DAMAGE: charge_damage_mult,
		Stats.CHARGE_RADIUS: charge_radius_mult,
		Stats.XP_GAIN: 1.0,
		Stats.SPAWN_RATE: 1.0,
	})
	_hammer.visible = false
	_setup_indicator.call_deferred()

func _process(delta: float) -> void:
	_cd = maxf(_cd - delta, 0.0)
	_special_cd = maxf(_special_cd - delta, 0.0)
	# 연격은 **쉬면 풀린다**. 차징하느라 1.2초 넘게 안 때려도 자연히 초기화된다 (스펙).
	if _combo > 0:
		_combo_left = maxf(_combo_left - delta, 0.0)
		if _combo_left <= 0.0:
			_combo = 0
	if _charging:
		_charge += delta

	# 조준 원은 차징 중엔 커서를 따라다니고, 버튼을 뗀 뒤 임팩트까지는 낙하 지점에 고정된다.
	var ratio := charge_ratio() if _charging else (_strike_ratio if _striking else 0.0)
	var ground := _strike_at if _striking else _mouse_ground()

	# 반경을 매 프레임 읽어서 업그레이드가 즉시 반영되게 한다.
	var r := strike_radius(ratio)
	# ⚠️ 사각형을 사거리보다 **키운다.** 조준 원 바깥에 우클릭 쿨 고리를 그리려면 여백이
	#    필요한데, 쿼드 밖에는 못 그린다. 셰이더가 aim_r 지점을 실제 사거리로 삼으므로
	#    여기서 그만큼 나눠 키운다 — 두 값은 짝이라 한쪽만 바꾸면 원이 사거리와 어긋난다.
	_indicator.scale = Vector3(r / AIM_R, 1.0, r / AIM_R)
	# ⚠️ y 는 0 으로 둔다 — 높이는 셰이더가 정점마다 지형에서 읽어 올린다.
	#    노드를 지면 높이에 올려놓으면 경사에서 한쪽이 파묻힌다 (유저 지적).
	_indicator.global_position = Vector3(ground.x, 0.0, ground.z)
	var mat := _indicator.material_override as ShaderMaterial
	mat.set_shader_parameter("alpha_mul", 1.0 if (_cd <= 0.0 or _striking) else 0.35)
	# 우클릭 쿨 — 0(방금 씀) ~ 1(준비 완료). 예고/낙하 중에는 이미 쓰는 중이므로 0 으로 둔다.
	var cdmax: float = maxf(stats.get_v(Stats.COOLDOWN_SPECIAL), 0.001)
	# ⚠️ 이름을 `ready` 로 두면 Node 의 `ready` **시그널을 가린다** (GDScript 경고).
	var cd_ready: float = 0.0 if _special_active else clampf(1.0 - _special_cd / cdmax, 0.0, 1.0)
	mat.set_shader_parameter("cd_ratio", cd_ready)

	# 카메라 셰이크: h/v offset만 흔들어서 원래 transform은 건드리지 않는다
	if _shake > 0.0:
		_shake = maxf(_shake - delta * 3.2, 0.0)
		var a := _shake * _shake * 0.55
		_cam.h_offset = randf_range(-a, a)
		_cam.v_offset = randf_range(-a, a)

func _unhandled_input(event: InputEvent) -> void:
	# 개발용 즉시 토글 (정식 획득은 3 키 -> CardUI 카드 선택).
	# (macOS 에서 F1~F12 는 밝기/볼륨 미디어 키라 쓰면 안 된다)
	# --- 디버그 키 -----------------------------------------------------------
	#   1 여진 토글 / 2 불 토글 / 3 인력 토글 / 4 우클릭 쿨 초기화
	# 카드가 무작위로 나오게 바뀐 뒤(2026-08-14)로 특정 카드를 기다려서 시험하는 게
	# 사실상 불가능해졌다. 시험용 통로를 열어 둔다 — 시작할 때 한 번 찍어 준다.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1:
			has_aftershock = not has_aftershock
			print("[card 1] 여진(Aftershock): ", "ON" if has_aftershock else "OFF")
			return
		if event.keycode == KEY_2:
			has_fire = not has_fire
			print("[card 2] 불 속성(Fire): ", "ON" if has_fire else "OFF")
			return
		if event.keycode == KEY_3:
			has_pull = not has_pull
			print("[card 3] 인력(Pull): ", "ON" if has_pull else "OFF")
			return
		if event.keycode == KEY_4:
			# 우클릭 쿨타임을 즉시 0 으로 — 예고를 반복해서 보려면 이게 제일 답답한 벽이다.
			_special_cd = 0.0
			print("[debug 4] 우클릭 쿨타임 초기화")
			return
		if event.keycode == KEY_O:
			show_erupt_area = not show_erupt_area
			print("[debug O] 분출 판정 범위 표시: ",
				"ON (도넛 %.0f%%~%.0f%%)" % [ERUPT_NEAR * 100.0, ERUPT_FAR * 100.0]
				if show_erupt_area else "OFF")
			return
		# 5~9 와 - : 모디파이어 토글. ⚠️ 0 은 쓰면 안 된다 — main.gd 의 투사체 리포트가 이미 쓴다.
		var mod_keys := [KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_MINUS, KEY_EQUAL]
		var mi := mod_keys.find(event.keycode)
		if mi >= 0:
			_toggle_mod(mi)
			return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT \
			and event.pressed:
		if _special_cd <= 0.0 and not _special_active:
			_special_strike(_mouse_ground())
		return
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if event.pressed:
		# 쿨다운 중엔 차징 자체를 시작하지 않는다 — 눌러둔 채 쿨이 도는 꼼수 방지.
		if _cd <= 0.0 and not _charging and not _striking:
			_charging = true
			_charge = 0.0
	elif _charging:
		# 한 번의 클릭 = 한 방. 짧게 떼면 평타, 데드존을 넘겼으면 차징만 나간다
		# (유저 지시 2026-08-15). 누를 때 미리 칠 수는 없다 — 그러면 꾹 누를 때
		# 평타 + 차징 두 방이 되어 버린다.
		_charging = false
		_strike(_mouse_ground(), charge_ratio())

## --- 우클릭 특수: 하늘에서 수직 낙하 ------------------------------------------
##
## 좌클릭 스윙과 노드를 **공유하지 않는다.** 예고 2초 동안 평타를 계속 칠 수 있어야 하는데,
## 같은 $WeaponHammer 를 쓰면 두 트윈이 한 노드의 position/rotation 을 두고 싸운다.
## 그래서 낙하용 망치를 따로 복제해 쓰고 임팩트 뒤에 버린다.
func _special_strike(target: Vector3) -> void:
	special_swings += 1
	_special_active = true
	_special_cd = stats.get_v(Stats.COOLDOWN_SPECIAL)
	target = Terrain.on(target)
	var radius := special_radius()

	# 낙하 그림자 — 떨어질수록 커진다. 시작을 0 으로 두면 '생겼다'가 안 읽히므로 35% 에서 시작.
	_special_shadow = _make_drop_shadow(target, radius)

	# 낙하 망치 — 좌클릭 망치의 복제본. 좌클릭과 자세가 **다르다**:
	# 저건 z=-90° 로 눕혀 옆면으로 치고, 이건 z=180° 로 **세워서 머리부터 꽂는다**.
	#   z=180° 는 모델 +Y(그립->머리)를 월드 아래로 돌린다 -> 머리가 밑, 손잡이가 위.
	# 세웠으므로 접지 높이는 그립에서 머리 끝까지 = HEAD_TIP_Y. 수평 오프셋은 없다
	# (좌클릭은 자루가 눕는 만큼 target 에서 뒤로 물러나야 했다).
	var s := hammer_scale * radius_scale() * special_scale_mult
	# 8방위 중 하나로 기운다. 0 = 동, 45° 씩 (화면 기준 — Main.to_world 규약).
	# ⚠️ randi() 를 cos/sin 에 따로 부르면 두 각이 섞여 8방위가 아니게 된다. 한 번만 뽑는다.
	var dir_a := TAU * float(randi() % 8) / 8.0
	var lean := Main.to_world(cos(dir_a), sin(dir_a))
	var basis_stand := Basis.from_euler(Vector3(0.0, randf_range(0.0, TAU), PI))
	var tilt := Basis(Vector3.UP.cross(lean).normalized(), deg_to_rad(special_tilt_deg))
	var basis_final := tilt * basis_stand
	# ⚠️ 기울면 머리 끝이 그립 **바로 아래**가 아니게 된다. 회전된 그립->머리끝 벡터를
	#    빼야 촉이 target 에 꽂힌다. 안 그러면 기운 만큼 옆으로 어긋난 자리에 박힌다.
	var tip_off := basis_final * (Vector3.UP * HEAD_TIP_Y * s)
	var grip_impact := target - Vector3.UP * (special_embed * s) - tip_off
	var from_sky := grip_impact + Vector3.UP * special_fall_height
	_special_hammer = _hammer.duplicate() as Node3D
	# 이름을 안 주면 add_child 가 @Node3D@23 식으로 자동 개명해서 디버깅 때 못 알아본다.
	_special_hammer.name = "SpecialHammer"
	add_child(_special_hammer)
	# basis 로 주면 scale 이 덮여버리므로 스케일을 먹인 basis 를 통째로 넣는다.
	_special_hammer.transform = Transform3D(basis_final.scaled(Vector3.ONE * s), from_sky)
	_special_hammer.visible = false        # 예고 동안엔 없다. 그림자만 보인다.
	# ⚠️ 떨어지는 동안 **직사광 그림자를 끈다.** 직교 카메라라 26유닛 상공의 물체는 지면
	#    위치에서 한참 떨어진 곳에 그림자를 드리운다 — 거대한 검은 덩어리가 화면을 가로질러
	#    쓸려 들어온다 (녹화해서 확인). 예고는 발밑 원형 그림자 하나로 충분하다.
	#    임팩트 뒤엔 다시 켜서 박힌 망치가 땅에 붙어 보이게 한다.
	for node in _special_hammer.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var tw := create_tween()
	# 1) 예고 — 그림자만 자란다. 가속 커브라 마지막에 급격히 커지며 착지를 알린다.
	tw.tween_property(_special_shadow, "scale", Vector3(radius, 1.0, radius), telegraph_time()) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# 2) 내리꽂기 — 나타나자마자 등속으로 내리꽂는다. 이징을 넣으면 속도가 죽어 무게가 빠진다.
	tw.tween_callback(func() -> void:
		if _special_hammer != null:
			_special_hammer.visible = true)
	tw.tween_property(_special_hammer, "global_position", grip_impact, special_slam_time) \
		.set_trans(Tween.TRANS_LINEAR)
	tw.tween_callback(_special_impact.bind(target, radius))

	# 메아리도 **지금** 예약한다. 본체 예고가 시작되는 이 순간부터 시차를 재야
	# 두 망치가 정확히 echo_gap 만큼 벌어져 떨어진다.
	var slam := special_spec(stats.get_v(Stats.DAMAGE) * special_damage_mult, radius)
	if slam.repeat > 0:
		_spawn_echoes(target, radius, slam)

## 낙하 지점에 까는 원형 예고 그림자. 본체 특수와 **메아리가 같이 쓴다**.
## 반경 35% 에서 시작해 착탄 반경까지 자라는 것도 공통 — 자라는 속도만 호출 쪽이 정한다
## (본체는 예고 2초 동안, 메아리는 예고가 없어 낙하 시간 동안).
func _make_drop_shadow(at: Vector3, radius: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2(2.0, 2.0)          # 반경 1 짜리 원판 — scale 로 실제 크기를 준다
	var smat := ShaderMaterial.new()
	smat.shader = ShadowShader
	quad.material = smat
	mi.mesh = quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = Terrain.on(at, 0.04)
	mi.scale = Vector3(radius * 0.35, 1.0, radius * 0.35)
	return mi

## 착탄 파편 — 하늘로 높이 튀었다 떨어진다. 피해는 없다.
## ⚠️ 체공 1.8초는 **먼지보다 훨씬 오래 화면에 남는다**. 그게 노림수다: 임팩트가 끝난 뒤에도
##    파편이 떨어지는 동안 여운이 이어진다. 다만 그만큼 오래 사니 개수를 늘리면 금방 지저분해진다.
func _special_debris(target: Vector3, fx_scale: float) -> void:
	var n := maxi(1, int(float(special_debris) * fx_scale))
	for i in n:
		EruptRock.spawn_debris(self, target, target,
			special_debris_airtime * randf_range(0.8, 1.15),
			special_debris_spread * fx_scale)

## 클릭 후 착탄까지 걸리는 시간. '신속한 천벌' 이 스택당 0.2초씩 깎는다.
## ⚠️ 하한을 둔다 — 0 이 되면 그림자가 뜨자마자 꽂혀서 '예고' 자체가 사라진다.
##    낙하 연출(special_slam_time)보다는 확실히 길어야 두 단계로 읽힌다.
func telegraph_time() -> float:
	return maxf(stats.get_v(Stats.TELEGRAPH_SPECIAL), special_slam_time * 3.0)

## 우클릭 직격 반경. 망치가 2배라 자국도 커야 한다.
## ⚠️ stats.RADIUS 가 아니라 **base_radius** 를 쓴다. RADIUS 는 평타 전용인데 여기서 읽으면
##    '넓은 울림'(평타 범위)이 우클릭까지 새어 들어간다 (기존 버그).
func special_radius() -> float:
	return base_radius * special_radius_mult \
		* stats.get_v(Stats.RADIUS_ALL) * stats.get_v(Stats.SPECIAL_RADIUS)

func _special_impact(target: Vector3, radius: float) -> void:
	_swing_src = DamageSource.root(&"special")
	# 꽂혔으니 그림자를 되돌린다 — 이제 지면에 닿아 있어 그림자가 자리를 알려준다.
	if _special_hammer != null:
		for node in _special_hammer.find_children("*", "MeshInstance3D", true, false):
			if node.name != "Outline":     # 먹선 껍질은 원래 그림자를 안 만든다
				(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_special_blast(target, radius,
		stats.get_v(Stats.DAMAGE) * special_damage_mult, 1.0)

	if _special_shadow != null:
		_special_shadow.queue_free()
		_special_shadow = null
	# 박힌 채 2초 버티다가 타서 사라진다 (하늘로 되감아 올리면 '회수'로 읽혀 무게가 빠진다)
	var h := _special_hammer
	_special_hammer = null
	if h != null:
		_evaporate(h)
	_special_active = false

	# ⚠️ 메아리는 여기서 부르지 않는다. **예고를 겹쳐서 돌려야** 두 망치의 낙하 시차가
	#    0.5초가 된다 (유저 지시 2026-08-14) — _special_strike 가 예고를 시작할 때 같이 건다.

## 우클릭 계열 착탄 한 번의 공통 처리 — 본체와 메아리가 같은 문법으로 터지게 모아뒀다.
## scale 은 연출 강도(흔들림·먼지). 메아리는 본체보다 작게 울려야 '곁다리'로 읽힌다.
## ⚠️ 우클릭에 **기본 쇼크웨이브는 없다** (유저 지시 2026-08-18). 그림자 진 자리만 때린다.
##    단, '충격파' 카드를 가지면 이야기가 다르다 — 패턴 카드는 클릭 버튼이 아니라
##    **무기의 성질**이라 평타·차징·특수 전부에 걸린다 (여진·불과 같은 문법).
##    카드 없이 나가던 예전 고리를 걷어낼 때 이 통로까지 같이 막혔던 걸 되살린 것이다.
func _special_blast(target: Vector3, radius: float,
		direct: float, fx_scale: float) -> void:
	_shake = maxf(_shake, special_shake * fx_scale)
	if fx_scale >= 1.0:
		_hitstop(charge_hitstop, charge_hitstop_scale)
	# ⚠️ 먼지(burst + ground_ring)는 **뺐다** (유저 지시 2026-08-14). 대신 돌 파편이
	#    하늘 높이 튀었다 떨어진다 — 먼지는 퍼지고 사라지지만 파편은 날아가는 궤적이
	#    남아서, 같은 임팩트라도 "땅을 부쉈다"가 훨씬 세게 읽힌다.
	#    범위는 낙하 전 예고 그림자가 알려준다.
	_special_debris(target, fx_scale)
	# 망치가 박힌 자리에 밀려난 흙 — 분출 바위와 **같은 함수**를 쓴다.
	var dirt := EruptRock.dirt_patch(self, target, radius * special_dirt_fit * fx_scale)
	var dtw := create_tween()
	dtw.tween_interval(special_linger)
	dtw.tween_method(func(a: float) -> void:
		if is_instance_valid(dirt):
			(dirt.mesh as PlaneMesh).material.set_shader_parameter("alpha_mul", a),
		1.0, 0.0, 0.5)
	dtw.tween_callback(dirt.queue_free)

	# 충격파 카드 — 그림자 바깥으로 고리가 퍼진다. 평타와 **같은 문법**이다.
	# ⚠️ 직격보다 **먼저** 부른다. _damage_area 가 안쪽을 때린 뒤 고리는 바깥만 치는데,
	#    순서가 뒤집혀도 결과는 같지만 읽는 사람이 "고리가 두 번 때리나" 를 매번 확인하게 된다.
	if has_shockwave:
		var spec := object_spec(&"shockwave", GROUND_AREA_TAGS,
			direct * shock_damage * fx_scale, special_shock_spread())
		_shockwave_object(target, radius, spec)

	# 끌어당김 — 반경은 **맥스 차징과 같다**(유저 지시). 메아리 망치는 fx_scale 만큼
	# 약하게 끈다 — 충격파가 피해를 그렇게 깎는 것과 같은 이유로 곁다리로 읽혀야 한다.
	if has_vortex():
		_vortex_object(target, pull_spec(special_pull_spread()), fx_scale)
	elif has_pull:
		_pull_object(target, pull_spec(special_pull_spread()), fx_scale)

	# 직격 — 그림자 안. 여기 있던 적은 그대로 맞는다.
	var killed := _damage_area(target, radius, direct, false, 0.0)
	if has_fire:
		_deflagrate(killed, 1.0)
	# --- 여진: 평타와 **같은 문법** (유저 지시 2026-08-14) ---------------------
	# 예전엔 특수에 여진이 아예 안 걸렸다. 불은 걸리는데 여진만 빠져 있으니
	# 플레이어가 보기엔 버그다 — 속성·패턴 카드는 클릭 버튼이 아니라 **무기의 성질**이다.
	# 균열 위를 치면 소모해서 분출하고, 아니면 새로 만든다. 무한 연쇄를 막는 이 규칙도
	# 평타에서 그대로 가져온다 (분출 자리에 또 균열이 생기면 같은 곳을 계속 치게 된다).
	var field := _crack_field_at(target)
	if field != null:
		if has_fire and has_aftershock:
			field.ignite()
		field.erupt()
		_shake = maxf(_shake, erupt_shake * fx_scale)
		_damage_area(field.global_position, field.field_radius,
			direct * erupt_damage, false, erupt_knockback)
		if has_fire and has_aftershock:
			Crater.spawn(self, field, crater_spec(field.field_radius),
				fireball_spec(direct * fire_ball_damage, fire_ball_radius,
					crater_balls_special))
		else:
			# 재타격 경로도 같은 배수로 넓힌다 — 특수의 분출은 어느 경로로 나오든
			# 같은 크기여야 한다 (한쪽만 넓히면 "왜 이번엔 좁지"가 된다).
			_erupt_rocks(field.global_position, field.field_radius * special_erupt_spread,
				direct, 1.0)
	elif has_aftershock:
		# ⚠️ 균열 크기가 **그 공격의 범위에 비례**한다. radius 는 메아리면 이미 85% 로
		#    줄어 있으므로, 메아리가 만드는 균열도 자동으로 작아진다.
		# ⚠️ 마지막 인자가 평타와의 차이다 — 특수는 균열을 남기는 동시에 **바로 바위를
		#    뒤집는다**. 메아리는 fx_scale(0.6) 만큼 적게 솟아 곁다리로 읽힌다.
		_aftershock_at(target, direct, radius * special_crack_fit, fx_scale)

## '천벌의 메아리' — 본체가 꽂힌 뒤 곁에 한두 발 더 떨어진다.
## 0.2초를 띄우는 이유: 동시에 터지면 두 방이 한 방으로 뭉개진다. '쾅—쾅' 으로 갈려야 한다.
func _spawn_echoes(target: Vector3, main_radius: float, spec: ObjectSpec) -> void:
	# 개수·세기는 모디파이어가 정한다 ('메아리' 한 장 = repeat 1).
	# ⚠️ 깊이를 확인한다 — 메아리가 만든 착탄이 또 메아리를 부르면 무한히 는다.
	var count := spec.repeat if spec.child_src(&"special_echo") != null else 0
	var dmg_ratio := spec.repeat_power
	var stagger := echo_gap
	var far := echo_dist_max
	var radius := main_radius * echo_radius_ratio
	for i in count:
		var a := randf_range(0.0, TAU)
		var d := randf_range(echo_dist_min, far)
		var at := _clamp_to_arena(target + Vector3(cos(a), 0.0, sin(a)) * d)
		# 시차만큼 기다렸다가 **그때** 그림자를 깐다 — 본체 그림자가 먼저 뜨고,
		# stagger 뒤에 두 번째 그림자가 뜬다. 예고 길이는 본체와 같으므로
		# 낙하 시차도 정확히 stagger 가 된다.
		var tw := create_tween()
		tw.tween_interval(stagger * float(i + 1))
		tw.tween_callback(_echo_telegraph.bind(at, main_radius, dmg_ratio, radius))

## 메아리 한 발의 예고 -> 낙하. 본체(_special_strike)와 같은 순서를 탄다.
func _echo_telegraph(at: Vector3, main_radius: float, dmg_ratio: float,
		radius: float) -> void:
	var sh := _make_drop_shadow(at, radius)
	var tw := create_tween()
	tw.tween_property(sh, "scale", Vector3(radius, 1.0, radius), telegraph_time()) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_echo_drop.bind(at, main_radius, dmg_ratio, sh))

## 전투 가능 지역 보정 — 성 상자(5×5) 안쪽에 찍히면 밖으로 밀어낸다.
## 성 안에 망치가 박히면 벽을 뚫고 들어간 것처럼 보인다.
func _clamp_to_arena(at: Vector3) -> Vector3:
	var base := get_tree().get_first_node_in_group("base") as Node3D
	if base == null:
		return at
	var flat := Vector3(at.x - base.global_position.x, 0.0, at.z - base.global_position.z)
	# 성 반폭은 Enemy 가 콩벌레 정지거리 계산에 쓰려고 이미 상수로 갖고 있다 (5×5 상자 -> 2.5).
	var keep: float = Enemy.PILL_BASE_HALF + special_radius() * 0.5
	if flat.length() < keep:
		if flat.length() < 0.01:
			flat = Vector3(1, 0, 0)
		flat = flat.normalized() * keep
		return Vector3(base.global_position.x + flat.x, 0.0, base.global_position.z + flat.z)
	return at

## 메아리 망치 한 발. 본체와 같은 낙하·소각을 쓰되 수치만 줄인다.
## sh = 예고 동안 이미 깔려 있던 낙하 그림자. null 이면(직접 호출·테스트) 여기서 만든다.
func _echo_drop(target: Vector3, main_radius: float, dmg_ratio: float,
		sh: MeshInstance3D = null) -> void:
	var radius := main_radius * echo_radius_ratio
	var s := hammer_scale * radius_scale() * special_scale_mult
	var dir_a := TAU * float(randi() % 8) / 8.0
	var lean := Main.to_world(cos(dir_a), sin(dir_a))
	var basis_stand := Basis.from_euler(Vector3(0.0, randf_range(0.0, TAU), PI))
	var tilt := Basis(Vector3.UP.cross(lean).normalized(), deg_to_rad(special_tilt_deg))
	var basis_final := tilt * basis_stand
	var tip_off := basis_final * (Vector3.UP * HEAD_TIP_Y * s)
	var grip := target - Vector3.UP * (special_embed * s) - tip_off
	var h := _hammer.duplicate() as Node3D
	h.name = "EchoHammer"
	add_child(h)
	# ⚠️ 원본 $WeaponHammer 는 평소 visible=false 다 (스윙할 때만 켠다). 복제본도 숨은 채로
	#    태어나므로 **반드시 켜야 한다** — 안 켜면 메아리가 보이지 않게 떨어져서 피해만 들어가고
	#    화면엔 아무 일도 안 일어난 것처럼 보인다 (유저 제보 2026-08-13).
	#    본체 특수는 예고 동안 일부러 끄고 낙하 직전에 켜지만, 메아리는 예고가 없다.
	h.visible = true
	h.transform = Transform3D(basis_final.scaled(Vector3.ONE * s),
		grip + Vector3.UP * special_fall_height)
	for node in h.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 그림자는 _spawn_echoes 가 예고 내내 키워 놓은 것을 그대로 물려받는다.
	if sh == null:
		sh = _make_drop_shadow(target, radius)
		sh.scale = Vector3(radius, 1.0, radius)
	var tw := create_tween()
	tw.tween_property(h, "global_position", grip, special_slam_time) \
		.set_trans(Tween.TRANS_LINEAR)
	tw.tween_callback(func() -> void:
		if is_instance_valid(sh):
			sh.queue_free()      # 임팩트와 동시에 걷는다 — 남으면 자국처럼 보인다
		for node in h.find_children("*", "MeshInstance3D", true, false):
			if node.name != "Outline":
				(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_special_blast(target, radius,
			stats.get_v(Stats.DAMAGE) * special_damage_mult * dmg_ratio, 0.6)
		_evaporate(h))

## 박힌 망치가 스르르 증발한다 — 위로 옅게 떠오르며 투명해진다.
##
## ⚠️ 복제된 망치는 원본 $WeaponHammer 와 **머티리얼 리소스를 공유한다.** 그대로 알파를
##    건드리면 좌클릭 망치까지 같이 사라진다. 그래서 사본을 만들어 서피스 오버라이드로 덮는다.
## ⚠️ 먹선(Outline)은 역헐이라 본체보다 **나중에** 그려야 한다 — 순서가 뒤집히면 투명해지는
##    동안 검은 실루엣이 뜬다 (분출 바위에서 겪은 것과 같은 문제, cel_fade.gdshader 주석).
## ⚠️ 재질 교체는 **소각이 실제로 시작될 때** 해야 한다. 임팩트 즉시 바꾸면 박혀 있는 2초의
##    연출이 달라진다 (그림자 문제로 이미 한 번 데였다 — 다만 burn 은 discard 기반이라
##    불투명 파이프라인에 남고, 타는 동안에도 그림자가 유지되며 구멍도 같이 뚫린다).
##    Array 는 참조라 여기서 채우면 아래 트윈의 클로저가 그대로 본다.
func _swap_to_burn(h: Node3D, burns: Array) -> void:
	for node in h.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var src := mi.get_surface_override_material(i)
			if src == null:
				src = mi.mesh.surface_get_material(i)
			var bm := ShaderMaterial.new()
			if src is ShaderMaterial:
				# 본체 셀 서피스 — 색·경계를 그대로 물려받아 타기 전과 룩이 같다
				bm.shader = CelBurnShader
				for k in ["light_tone", "dark_tone", "threshold"]:
					bm.set_shader_parameter(k, (src as ShaderMaterial).get_shader_parameter(k))
			elif src is StandardMaterial3D:
				# 먹선 껍질 — 서피스마다 색이 다르다 (나무 테두리/돌 테두리/먹선)
				bm.shader = InkBurnShader
				bm.set_shader_parameter("col", (src as StandardMaterial3D).albedo_color)
			else:
				continue
			bm.set_shader_parameter("dissolve", 0.0)
			mi.set_surface_override_material(i, bm)
			burns.append(bm)

func _evaporate(h: Node3D) -> void:
	var burns: Array[ShaderMaterial] = []
	# ⚠️ set_parallel(true) 를 쓰면 안 된다. 그 뒤에 붙는 트위너가 **직전 단계에 합쳐져서**
	#    대기(interval)와 소각이 동시에 시작한다 — 2초 버티는 게 아니라 곧바로 타기 시작했다
	#    (알파 페이드 시절 유저가 "너무 빨리 사라진다"고 두 번 지적한 원인). 기본이 순차다.
	# 망치를 위로 띄우는 트윈은 뺐다 — 종이는 타면서 떠오르지 않는다. 위로 가는 건 재뿐이다.
	var tw := create_tween()
	tw.tween_interval(special_linger)
	# 여기까지는 불투명 cel 그대로 — 박힌 채 그림자를 드리운다.
	tw.tween_callback(func() -> void:
		_swap_to_burn(h, burns)
		_spawn_ash(h))
	tw.tween_method(func(d: float) -> void:
		for m in burns:
			m.set_shader_parameter("dissolve", d),
		0.0, 1.0, special_evaporate)
	tw.tween_callback(h.queue_free)

## 타는 경계에서 피어오르는 재. 소각 마스크가 위(손잡이 끝)에서 아래로 쓸고 내려가므로,
## 방출구(얇은 슬랩)도 같은 속도로 따라 내려간다 — 재가 항상 타는 자리에서 나온다.
func _spawn_ash(h: Node3D) -> void:
	var s := h.scale.x
	var p := CPUParticles3D.new()
	p.name = "SpecialAsh"
	p.emitting = false          # ImpactDust 와 같은 함정 — 자리 잡기 전 켜면 원점에서 터진다
	p.amount = 280
	p.lifetime = 1.5
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	# ⚠️ 고정값 1.6 이었을 땐 망치 폭(모델 반폭 0.36 × 스케일 12 ≈ 4.3)의 3분의 1 밖에 안 돼서
	#    재가 가운데 좁은 기둥에서만 올라왔다. 타는 단면 전체에서 나와야 양이 산다.
	#    y 는 얇게 — 소각 경계는 두께 없는 판이다.
	p.emission_box_extents = Vector3(0.36 * s, 0.05 * s, 0.28 * s)
	p.direction = Vector3.UP
	p.spread = 40.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.4
	# 위로 + 옆으로 살짝 — 재가 곧게 오르면 연기 기둥이지 나부끼는 재가 아니다
	p.gravity = Vector3(0.45, 2.2, 0.45)
	p.damping_min = 0.2
	p.damping_max = 0.8
	var curve := Curve.new()               # 날아가며 작아진다 (scale_amount_curve 는 Curve 직접)
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.25))
	p.scale_amount_curve = curve
	# 갓 태어난 재는 잉걸빛, 식으며 회색, 끝에서 투명 — '식는다'까지 색으로 말한다
	var g := Gradient.new()
	g.set_color(0, Color(0.922, 0.588, 0.38, 0.95))   # #eb9661
	g.set_color(1, Color(0.529, 0.522, 0.486, 0.0))   # #87857c -> 투명
	g.add_point(0.18, Color(0.529, 0.522, 0.486, 0.9))
	g.add_point(0.65, Color(0.388, 0.4, 0.388, 0.7))  # #636663
	p.color_ramp = g
	var flake := BoxMesh.new()
	flake.size = Vector3(0.16, 0.04, 0.16)             # 납작한 조각 — 재는 부피가 없다
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true                # color_ramp 를 받으려면 필수
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flake.material = m
	p.mesh = flake
	add_child(p)
	p.global_position = h.global_position              # 그립 = 뒤집힌 망치의 꼭대기
	p.emitting = true
	var tw := create_tween()
	tw.tween_property(p, "global_position",
		h.global_position + Vector3.DOWN * (HEAD_TIP_Y * s), special_evaporate)
	tw.tween_callback(func() -> void: p.emitting = false)
	tw.tween_interval(p.lifetime)                      # 마지막 재가 다 날아갈 때까지
	tw.tween_callback(p.queue_free)

## 도넛 판정 — inner 밖 ~ outer 안. 특수 공격에서 직격과 쇼크웨이브가 겹쳐 맞는 걸 막는다.
## 맞힌 결과를 돌려준다 {hits, dealt, wasted, kills} — 도넛 분출이 이걸 리포트에 싣는다.
func _damage_ring(center: Vector3, inner: float, outer: float,
		damage: float, knock: float, src: DamageSource = null) -> Dictionary:
	var out := {hits = 0, dealt = 0.0, wasted = 0.0, kills = 0}
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		var flat := enemy.global_position - center
		flat.y = 0.0
		var d := flat.length()
		if d <= inner + enemy.hit_radius or d > outer + enemy.hit_radius:
			continue
		var before := enemy.health
		enemy.take_damage(damage, center, src)
		out.hits += 1
		out.dealt += minf(damage, before)
		out.wasted += maxf(damage - before, 0.0)
		if enemy.dying:
			out.kills += 1
		if not enemy.dying and knock > 0.0:
			enemy.knockback(center, knock)
	return out

## 직교 카메라 기준 마우스 -> y=0 지면 교점.
## 조준 원이 지형을 타게 준비한다 — 쿼드를 잘게 쪼개고 높이 텍스처를 물린다.
## ⚠️ 지면이 아직 안 구워졌을 수 있어 한 프레임 미뤄서 부른다.
func _setup_indicator() -> void:
	var quad := _indicator.mesh as PlaneMesh
	if quad != null:
		# 경사를 따라 휘려면 정점이 있어야 한다. 32×32 면 4유닛 격자를 충분히 담는다.
		quad.subdivide_width = 32
		quad.subdivide_depth = 32
	var mat := _indicator.material_override as ShaderMaterial
	var g := Terrain.ground()
	if mat == null or g == null:
		return
	mat.set_shader_parameter("height_tex", g.height_texture())
	mat.set_shader_parameter("terrain_half", Ground.HALF)
	mat.set_shader_parameter("conform", true)

## 마우스가 가리키는 **지면 위** 지점.
## ⚠️ 예전엔 y=0 평면과의 교차였다. 지형에 높이가 생긴 뒤로는 고원을 겨눠도 y=0 평면의
##    엉뚱한 자리(화면상 한참 어긋난 곳)를 때린다. 광선을 따라 걸어가며 지면을 뚫는
##    지점을 찾는다 — 지형이 격자라 촘촘히 걸으면 충분히 정확하다.
func _mouse_ground() -> Vector3:
	var mp := get_viewport().get_mouse_position()
	var o := _cam.project_ray_origin(mp)
	var d := _cam.project_ray_normal(mp)
	if absf(d.y) < 0.001:
		return Vector3.ZERO
	var flat := o - d * (o.y / d.y)      # y=0 평면 교차 — 여기서부터 앞뒤로 훑는다
	var g := Terrain.ground()
	if g == null:
		return flat
	# 카메라에서 멀어지는 순으로 걸으며 지면 위 -> 아래로 바뀌는 순간을 잡는다.
	var t0 := (o.distance_to(flat)) - 60.0
	var prev := 1.0
	var step := 1.0
	var t := maxf(t0, 0.0)
	while t < o.distance_to(flat) + 60.0:
		var p := o + d * t
		var diff := p.y - g.height_at(p)
		if diff <= 0.0 and prev > 0.0:
			# 두 표본 사이를 선형 보간해 교차점을 다듬는다
			var a := o + d * (t - step)
			var f := prev / maxf(prev - diff, 0.0001)
			return a.lerp(p, f)
		prev = diff
		t += step
	return flat

## ratio = 차징 비율 0~1. 0 이면 평타. 피해/반경/망치 크기가 이 값으로 보간된다.
func _strike(target: Vector3, ratio := 0.0) -> void:
	# 평타와 차징은 쿨타임이 다르다 — 어느 쪽을 쳤는지로 고른다.
	var cd := stats.get_v(Stats.COOLDOWN_CHARGED) if ratio > 0.0 \
		else stats.get_v(Stats.COOLDOWN)
	if ratio > 0.0:
		charged_swings += 1
	else:
		tap_swings += 1
	_cd = cd
	_cd_total = maxf(cd, 0.001)
	# 조준 원/그림자를 임팩트까지 이 자리에 묶어둔다
	_striking = true
	_strike_at = target
	_strike_ratio = ratio
	var s := hammer_scale * radius_scale() * lerpf(1.0, charge_scale_mult, ratio)
	if is_beat_strike(ratio):
		s *= beat_scale_mult          # 대강타는 눈에도 커야 한다 (예고 없는 강타라 더 그렇다)
	# 손잡이는 항상 화면 동(오른쪽)~남(아래) 사분면에서 내려온다.
	# 그 90도 안에서만 랜덤 — 왼쪽/위에서 치는 일은 없다.
	var a := randf_range(0.0, PI / 2.0)          # 0 = 동, PI/2 = 남 (화면 기준)
	var handle_dir := Main.to_world(cos(a), sin(a))
	var forward := -handle_dir                    # 그립은 target - forward 쪽에 놓인다
	var yaw := atan2(-forward.z, forward.x)

	_hammer.visible = true
	_hammer.scale = Vector3.ONE * s
	# 못질 스윙: 그립(모델 원점)이 회전축. 임팩트 자세는 z=-90°,
	# 그때 자루(+Y)는 수평 forward, 타격면(+X)은 정확히 아래를 향한다.
	# 그립 위치는 임팩트 순간 타격면 중심이 target에 닿도록 역산.
	var grip_impact := target - forward * (HEAD_CENTER_Y * s) \
		+ Vector3.UP * ((HEAD_FACE_X - embed) * s)
	# 신의 팔은 하늘에서 내려온다: 그립이 높은 뒤쪽에서 출발해
	# 스윙 회전과 "동시에" 낙하 — 어깨가 내려오며 손목이 도는 궤적.
	var grip_start := grip_impact - forward * entry_back + Vector3.UP * entry_height
	var cocked := deg_to_rad(-90.0 + cock_angle)
	_hammer.position = grip_start
	_hammer.rotation = Vector3(0.0, yaw, cocked)

	# 유지/회수 시간은 쿨다운에서 남는 만큼으로 맞추되, 15% 는 남겨 둔다.
	# 진입 지점(grip_start)은 스윙 방향이 랜덤이라 매번 다른 자리이고 화면 안에 잡히기도 해서,
	# 망치가 숨어 있는 틈이 없으면 최대 연사 때 그 자리 이동이 점프로 보인다.
	# 평타는 예비 동작 없이 곧장 떨어진다 — 누른 순간과 임팩트 사이를 최대한 붙인다.
	var prep := PREP_TIME if ratio > 0.0 else 0.0
	var fall := swing_time if ratio > 0.0 else tap_swing_time
	var budget := maxf((cd - prep - fall) * 0.85, 0.14)
	var hold := budget * 0.54
	var retract := budget * 0.46

	# 이전 스윙이 어떤 이유로든 아직 살아 있으면 끊는다 (트윈 겹침 방지)
	if _tw and _tw.is_valid():
		_tw.kill()
	var tw := create_tween()
	_tw = tw
	tw.set_parallel(true)
	# 예비 동작: 하늘에서 한 번 더 치켜든다 (차징 전용 — 평타는 건너뛴다)
	if prep > 0.0:
		tw.tween_property(_hammer, "position:y", grip_start.y + 1.5, prep) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(_hammer, "rotation:z", cocked + deg_to_rad(10.0), prep) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.chain()
	# 내리침: 낙하와 스윙이 같은 가속 커브로 함께 떨어져 임팩트 자세에 동시 도달
	tw.tween_property(_hammer, "position", grip_impact, fall) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_hammer, "rotation:z", deg_to_rad(-90.0), fall) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(_impact.bind(target, ratio))
	# 박힌 채 잠깐 머물렀다가 하늘로 되감아 올리며 회수
	tw.chain().tween_interval(hold)
	tw.chain().tween_property(_hammer, "position", grip_start, retract) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_hammer, "rotation:z", cocked, retract) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func() -> void: _hammer.visible = false)

func _impact(target: Vector3, ratio := 0.0) -> void:
	_striking = false
	# 이 스윙에서 파생되는 오브젝트 전부가 이 출처를 공유한다 (깊이 0 = 망치가 직접).
	_swing_src = DamageSource.root(&"charge" if ratio > 0.0 else &"normal")
	# 차징이 셀수록 화면이 더 크게 흔들린다
	_shake = lerpf(1.0, 1.8, ratio)
	_dust(target, ratio)
	if ratio >= charge_fx_min_ratio:
		_hitstop(charge_hitstop, charge_hitstop_scale)

	# 타격 반동: 못을 때린 망치처럼 튕겨 올라왔다가 낮게 가라앉는다
	var kick := create_tween()
	kick.tween_property(_hammer, "rotation:z", deg_to_rad(-76.0), 0.05) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	kick.tween_property(_hammer, "rotation:z", deg_to_rad(-86.0), 0.1)

	# 직접 타격. **이 사망자만** 폭연 대상이 된다 — 분출·여진·폭연으로 죽은 적은 터지지 않는다.
	# ratio 를 넘겨야 보스가 풀차징 여부를 알 수 있다 (예고 취소 판정).
	#
	# 연격(몰아치는 신격)과 대강타(파괴의 박자)는 **직격 한 방에만** 얹는다. 대강타를 별도
	# 공격으로 한 번 더 발생시키면 폭연·여진이 이중으로 터지므로, 강해진 1회로 처리한다(스펙).
	var beat := is_beat_strike(ratio)
	var dmg := strike_damage(ratio)
	var rad := strike_radius(ratio)
	var knock := 0.0
	if ratio <= 0.0:
		dmg *= combo_mult()
	if beat:
		dmg *= beat_damage_mult
		rad *= beat_radius_mult
		knock = beat_knockback
	var killed := _damage_area(target, rad, dmg, false, knock, ratio)
	if ratio <= 0.0:
		_tally_normal_hit(killed.size() > 0 or _hit_anyone(target, rad), beat)
	# 충격파 — 직격 바깥으로 퍼지는 고리. **연출과 판정이 같은 반경**을 쓴다.
	# ⚠️ 여기가 beat(대강타)로 rad 가 커진 뒤라서 고리도 같이 커진다 — 의도한 것이다.
	# ⚠️ _damage_area 가 이미 안쪽을 때렸으므로 고리는 _damage_ring 으로 **바깥만** 친다.
	#    (직격 대상이 두 번 맞는 건 특수에서 이미 겪은 함정이다.)
	if has_shockwave:
		# 충격파는 **바닥에 눕는 범위**라 area + ground 둘 다다 —
		# 잔류(ground)가 고리 지속을, 거대화(area)가 고리 크기를 건드린다.
		var spec := object_spec(&"shockwave", GROUND_AREA_TAGS,
			dmg * shock_damage, rad * shock_spread)
		_shockwave_object(target, rad, spec)
	# 끌어당김 — 충격파와 **같은 자리, 같은 문법**이다. 착탄 순간 안쪽으로 끈다.
	# ⚠️ 직격보다 뒤에 있어도 이번 타격에는 영향이 없다 — pull 은 _slide 를 얹을 뿐이라
	#    실제로 움직이는 건 다음 프레임부터다. 모아둔 값은 **다음 공격과 메아리**가 받는다.
	if has_vortex():
		_vortex_object(target, pull_spec(rad * pull_spread))
	elif has_pull:
		_pull_object(target, pull_spec(rad * pull_spread))
	if has_fire:
		_deflagrate(killed, ratio)

	# 여기가 분기점이다. 균열 위를 치면 분출하고 **새 균열은 만들지 않는다** —
	# 안 그러면 분출 자리에 또 균열이 생겨서 같은 곳을 계속 치는 무한 연쇄가 된다.
	var field := _crack_field_at(target)
	if field != null:
		# 있음: 균열 소모 -> 지면 분출
		# 균열이 불 획득 "전"에 만들어졌어도, 분출 시점에 불을 갖고 있으면 용암 분출이다
		if has_fire and has_aftershock:
			field.ignite()
		field.erupt()
		_shake = maxf(_shake, erupt_shake)
		_damage_area(field.global_position, field.field_radius,
			strike_damage(ratio) * erupt_damage, false, erupt_knockback)
		if has_fire and has_aftershock:
			# 여진+불 조합: 바위 대신 분화구 — 갈라진 땅 자체에서 불덩이가 솟는다
			Crater.spawn(self, field, crater_spec(field.field_radius),
				fireball_spec(strike_damage(ratio) * fire_ball_damage, fire_ball_radius,
					crater_balls_for(ratio)))
		else:
			# 평타 경로라 평타 상한을 쓴다 (특수는 자기 상한 ERUPT_MAX)
			_erupt_rocks(field.global_position, field.field_radius,
				strike_damage(ratio), ratio, 1.0, normal_erupt_cap_for(ratio))
	elif has_aftershock:
		# 없음: 일반 피해에 이어 새 균열 생성
		_aftershock(target, ratio)

## 폭연: 직접 타격으로 죽은 적 중 최대 N 구를 골라 부풀렸다 터뜨린다.
## 많이 죽였을 때 **무작위로** 고르는 이유 — 중심부터 순서대로 고르면 폭발이 한 점에 뭉쳐
## 큰 원 하나로 보인다. 흩어서 골라야 "범위 곳곳에서 터진다"가 된다.
func _deflagrate(killed: Array[Enemy], ratio: float) -> void:
	if killed.is_empty():
		return
	var n := mini(killed.size(),
		int(lerpf(float(deflag_count), float(deflag_count_charged), ratio)))
	killed.shuffle()
	# 반경만 기본 반경 기준. 피해는 그 스윙의 실제 위력을 따라간다(차징하면 같이 세진다).
	# 이름을 deflag_base 로 둔다 — base_radius 는 **망치의 기본 반경**(@export)이라
	# 같은 이름을 쓰면 어느 쪽을 읽는 건지 읽는 사람이 매번 헷갈린다.
	var deflag_base := stats.get_v(Stats.RADIUS) * deflag_radius \
		* lerpf(1.0, deflag_radius_charged, ratio)
	var damage := strike_damage(ratio) * deflag_damage
	var knock := lerpf(deflag_knock, deflag_knock_charged, ratio)
	# 오브젝트 스펙 — 터뜨릴 시체 수(count), 반경, 피해가 여기서 정해진다.
	# ⚠️ n 은 **살아있는 시체 수로 다시 자른다.** 다중화로 5구를 터뜨리라 해도
	#    시체가 3구뿐이면 3구다 — 안 자르면 배열 밖을 읽는다.
	var spec := deflag_spec(damage, deflag_base, n)
	n = mini(killed.size(), spec.count)
	deflag_base = spec.radius
	damage = spec.damage
	for i in n:
		var t := Deflagration.DELAY + Deflagration.STAGGER * float(i)
		# 큰 시체는 크게 터진다 — 잡졸(hit_radius 0)은 지금 그대로다.
		var radius := deflag_base + killed[i].hit_radius * deflag_body_scale
		# 시체가 직접 부풀어 오르고(combust), 같은 순간 폭발이 피해와 불꽃을 맡는다.
		# 죽는 순간의 자리를 박아둔다 — 사망 슬라이드는 pivot(로컬)만 움직여서 이 값은 안 변한다.
		killed[i].combust(t)
		Deflagration.detonate(self, killed[i].global_position, radius, damage, knock, i, spec)

## 분출 도넛 판정 범위를 화면에 그린다 (개발용, O 키로 토글).
## ⚠️ 표시는 판정과 **같은 값**에서 나와야 한다 — 따로 계산하면 디버그 표시 자체가 거짓말을 한다.
@export var show_erupt_area := false
const DebugRingShader := preload("res://shaders/debug_ring.gdshader")
const ERUPT_AREA_HOLD := 1.6     ## 표시가 머무는 시간(초)

## 분출 도넛의 안팎 반경 (산개 범위 대비). 바위 착지 범위와 **반드시 같은 값**이다.
const ERUPT_NEAR := 0.3
const ERUPT_FAR := 1.05

## 분출 판 반경 전체 배율 (유저 지시 2026-08-18: "기본 범위를 모두 10% 증가").
## ⚠️ 호출부가 아니라 _erupt_rocks 안에서 곱한다 — 평타·특수·메아리 어느 경로로 와도
##    같은 배율을 받아야 "모두" 가 된다.
@export var erupt_field_mul := 1.1

## 바위는 연출이라 개수가 판정을 안 바꾼다. 그래서 **도넛을 채우는 밀도**로 정한다.
##   count = ERUPT_FILL × 도넛 넓이 / (기준 바위 넓이)
## ⚠️ 기준 바위 크기는 **고정**이다 (spec.scale 을 안 본다). 실제 바위 크기로 나누면
##    거대화에서 바위가 커진 만큼 개수가 줄어 개수가 그대로가 된다 — 유저가 원한 건
##    "거대화하면 바위도 크고 개수도 많아서 도넛을 꽉 채우는" 그림이다.
const ERUPT_FILL := 1.10
const ERUPT_REF_ROCK := 0.84       ## 기준 바위 반지름 (SIZE_MIN~MAX 평균의 절반)
## 성능 상한. 넘어가면 로그로 알린다 — 조용히 자르면 "다 채웠다" 로 읽힌다.
const ERUPT_MAX := 48
## 평타 전용 상한. 특수보다 낮다 — 평타는 0.65초마다 나가서 바위가 겹쳐 쌓이는데
## 특수는 쿨이 7초라 한 번에 많이 솟아도 누적이 없다.
## ⚠️ **상한에 걸리는 건 사실상 거대화 평타뿐**이다 (거대화 없으면 요청이 24개라 안 걸린다).
##    그래서 이 값을 내리면 "거대화 평타만" 줄어든다 (유저 지시 2026-08-18).
## 33 × 평타 배율 0.9 = **30개** (유저 지시 2026-08-18: "30개로 줄여봐").
@export var normal_erupt_cap := 33
## 맥스 차징 전용 상한. 44 × 0.9 = **40개** (유저 지시 2026-08-18).
## ⚠️ 상한을 하나만 두면 차징이 상한에 걸리는 순간 평타와 개수가 같아진다 —
##    "모아 쳤는데 그대로다" 가 된다. 차징 비율로 두 값 사이를 섞는다.
@export var normal_erupt_cap_charged := 44
## 잔해를 온전히 붙일 바위 수. 그 뒤 바위는 잔해 없이 몸통만 솟는다.
const ERUPT_DEBRIS_HEADS := 8
## 분출로 솟는 돌덩이들. 사방으로 흩어져 떨어진다 — **연출이다.**
## 피해는 바위가 아니라 같은 범위에 깔리는 **도넛 면적**이 낸다.
## 차징한 만큼 개수가 는다 — 범위(strike_radius)도 같이 커지므로 밀도는 유지된다.
## count_mul 은 개수만 줄인다 — 메아리처럼 "같은 분출이되 작게" 를 표현할 때 쓴다.
func _erupt_rocks(center: Vector3, radius: float, rock_damage: float, ratio := 0.0,
		count_mul := 1.0, cap := ERUPT_MAX) -> void:
	radius *= erupt_field_mul
	# 오브젝트 스펙을 굽는다 — 수량·크기·피해·분열이 여기서 정해진다.
	# ⚠️ count 를 **스펙에 넣어서** 모디파이어가 개수를 바꾸게 한다. 착지점은 그 뒤에 고른다 —
	#    순서가 바뀌면 다중화로 개수만 늘고 착지점은 원래 개수만큼만 잡힌다.
	# ⚠️ spec.radius 는 바위 하나의 판정 반경이 **아니라 분출 판 전체의 반경**이다
	#    (유저 지시 2026-08-18). 바위는 연출이라 개별 판정이 없어졌고, 그러면 남는 반경은
	#    "어디까지 튀는가" 하나뿐이다. 이렇게 묶어두면 거대화 한 장이
	#      · 바위를 2배로 키우고(spec.scale)
	#      · 튀는 범위를 2배로 넓히고(spec.radius)
	#      · 그래서 **도넛 판정도 2배**가 된다
	#    — 유저가 느끼는 건 "광역화" 인데 실제로 커진 건 연출과 판이다. 의도된 속임수다.
	# ⚠️ 스펙을 **먼저** 굽는다. 개수를 도넛 넓이에서 뽑는데, 그 넓이는 거대화가 반경을
	#    바꾼 **뒤**라야 정해진다. 순서를 뒤집으면 거대화가 개수에 반영되지 않는다
	#    (2026-08-18 실제로 이렇게 틀렸다 — 거대화가 8개에서 7개로 줄었다).
	#    count 자리에는 1 을 넣고, 모디파이어가 더한 몫만 따로 떼어 나중에 얹는다.
	var spec := rock_spec(rock_damage, radius, 1)
	var count_bonus := spec.count - 1
	spec.visual_only = true
	# ⚠️ 성능 상한을 **개수 배율보다 먼저** 건다. 순서를 뒤집으면 상한에 걸린 경우
	#    (거대화처럼 요청이 상한을 훌쩍 넘길 때) 배율이 아무 효과가 없다 —
	#    "평타만 10% 줄여줘" 가 정작 거대화 평타에서 안 먹는다 (2026-08-18).
	#    메아리가 본체보다 적게 솟는 규칙도 같은 이유로 이 순서라야 지켜진다.
	var raw := _erupt_fill_count(spec.radius) * strike_count_mult(ratio)
	var fill := minf(raw, float(cap))
	if raw > float(cap):
		print("[erupt] 넓이 기준 %d개 -> %d개로 제한 (성능 상한)" % [roundi(raw), cap])
	spec.count = maxi(1, roundi(fill * count_mul) + count_bonus)
	# ⚠️ 겹침은 **일부러 막지 않는다**. 겹쳐 보이는 건 문제가 아니고,
	#    문제였던 "겹친 바위가 공중에 뜬다" 는 착지 높이 쪽에서 고쳤다.
	var spots := LandPicker.pick(center, spec.radius, spec.count,
		ERUPT_NEAR, ERUPT_FAR, _base_keepout())
	var rocks: Array[EruptRock] = []
	var slowest := 0.0
	for i in spots.size():
		# 잔해는 앞쪽 몇 개만 온전히 — 전부 붙이면 노드가 수백 개가 된다
		var rock := EruptRock.spawn_at(self, center, spots[i], 0.0, 0.0, spec,
			1.0 if i < ERUPT_DEBRIS_HEADS else 0.0)
		rocks.append(rock)
		slowest = maxf(slowest, rock.flight_time)

	# ⚠️ **실제 공격은 여기 도넛 하나뿐이다** (유저 지시 2026-08-18). 바위는 연출이다.
	#    바위 하나하나가 때리면 돌 사이 빈틈이 그대로 판정 구멍이 되어, 같은 자리에
	#    서 있어도 운에 따라 맞고 안 맞고가 갈렸다.
	# ⚠️ 안팎 반경은 **바위가 떨어지는 범위와 같은 상수**를 쓴다 (ERUPT_NEAR/FAR).
	#    따로 두면 "돌이 떨어졌는데 안 아픈" 자리가 생긴다.
	if show_erupt_area:
		_show_erupt_area(center, spec.radius)
	ProjectileStats.spawned(&"rock")
	# ⚠️ 판정을 **착지 시각까지 미룬다** (유저 지시 2026-08-18). 예전엔 생성과 같은 프레임에
	#    때려서, 몹이 죽고 난 **뒤에** 바위가 떨어졌다 — "바위에 깔려 죽었다" 가 안 읽혔다.
	#    바위는 연출이고 판정은 도넛이라, 둘의 시각만 맞추면 인과가 눈에 보인다.
	var fired := [false]
	var fire_ring := func() -> void:
		if fired[0] or not is_inside_tree():
			return
		fired[0] = true
		var hit := _damage_ring(center, spec.radius * ERUPT_NEAR, spec.radius * ERUPT_FAR,
			spec.damage, 0.0, spec.src)
		ProjectileStats.landed(&"rock", hit.hits, hit.dealt, hit.wasted, hit.kills)
	if rocks.is_empty():
		fire_ring.call()
		return
	# **첫 바위가 땅에 닿는 순간** 때린다. 계산한 체공 시간으로 맞추면 어긋난다 —
	# 바위는 최저점이 닿을 때 멈추고 그 높이가 조각마다 달라서다 (EruptRock.flight_time 주석).
	for r in rocks:
		r.landed_on_ground.connect(fire_ring, CONNECT_ONE_SHOT)
	# ⚠️ 안전망: 바위가 전부 조기 제거되면(웨이브 정리·검증 스크립트) 시그널이 안 온다.
	#    그러면 판정이 영영 안 들어가므로, 가장 느린 바위의 계산 체공 + 여유만큼 기다렸다가 쏜다.
	var tw := create_tween()
	tw.tween_interval(slowest + 0.5)
	tw.tween_callback(fire_ring)

## 분출 도넛 판정 범위 표시. 지형을 타고 눕는다 (충격파와 **같은 메시**를 쓴다).
func _show_erupt_area(center: Vector3, field: float) -> void:
	var mi := MeshInstance3D.new()
	# 디스크를 도넛 **바깥 반경**으로 구우면 U=1 이 곧 바깥 경계가 된다
	mi.mesh = _shockwave_mesh(center, field * ERUPT_FAR)
	var m := ShaderMaterial.new()
	m.shader = DebugRingShader
	m.set_shader_parameter("inner", ERUPT_NEAR / ERUPT_FAR)
	# ⚠️ 트윈할 유니폼은 미리 심어 둔다 — 이 프로젝트의 단골 함정이다
	m.set_shader_parameter("alpha_mul", 1.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# 충격파(0.06)·흙자국(0.03)보다 위 — 겹쳐도 판정 표시가 가려지면 안 된다
	mi.global_position = Terrain.on(center, 0.08)
	var tw := create_tween()
	tw.tween_interval(ERUPT_AREA_HOLD)
	tw.tween_property(m, "shader_parameter/alpha_mul", 0.0, 0.4)
	tw.tween_callback(mi.queue_free)

## 차징 비율에 따른 평타 분출 상한. 무차징 30개 -> 맥스 차징 40개.
func normal_erupt_cap_for(ratio: float) -> int:
	return roundi(lerpf(float(normal_erupt_cap), float(normal_erupt_cap_charged),
		clampf(ratio, 0.0, 1.0)))

## 도넛을 채우는 데 필요한 바위 수. 반경이 커지면 넓이가 제곱으로 커지므로
## 개수도 제곱으로 는다 — 거대화(반경 ×2)면 개수 ×4 다.
func _erupt_fill_count(field: float) -> float:
	var band := field * field * (ERUPT_FAR * ERUPT_FAR - ERUPT_NEAR * ERUPT_NEAR)
	return ERUPT_FILL * band / (ERUPT_REF_ROCK * ERUPT_REF_ROCK)

## 낙석이 피해야 할 기지 영역.
## 여유는 **바위가 회전했을 때의 최대 반경**이어야 한다 — 중심만 밖에 두면
## 모서리가 성을 파고든다. 착지 판정이 목표보다 살짝 앞에서 걸리므로 여기에 0.4 를 더 준다.
func _base_keepout() -> Rect2:
	var b := get_tree().get_first_node_in_group("base") as BaseBlock
	if b == null:
		return Rect2()
	return b.footprint().grow(EruptRock.max_half_extent() + 0.4)

## 이 지점을 덮고 있는 살아있는 균열 지대. 없으면 null.
func _crack_field_at(pos: Vector3) -> AftershockFX:
	for node in get_tree().get_nodes_in_group("crack_fields"):
		var fx := node as AftershockFX
		if not fx.active:
			continue
		var d := fx.global_position - pos
		d.y = 0.0
		if d.length() <= fx.field_radius:
			return fx
	return null

## 이번 스윙의 실효 피해. 반경은 위쪽 strike_radius() 담당 (평타/차징 규칙이 달라서 분리).
## 피해 카드(담금질)는 **모든 공격**에 통한다 (유저 지시) — 여기서 갈라내지 않는다.
## 풀차징 배율만 '과충전' 카드가 키운다.
## ratio 에 해당하는 직격 피해.
## ⚠️ 피해 카드(담금질=DAMAGE_NORMAL)는 **평타에만** 통한다. 반경과 같은 구조이고,
##    같은 이유로 하한을 깐다 — 살짝만 눌러 ratio 가 0 에 가까울 때 평타보다 약해지면
##    "차징했더니 더 약하다" 가 된다.
func strike_damage(ratio: float) -> float:
	var base := stats.get_v(Stats.DAMAGE)
	var normal := base * stats.get_v(Stats.DAMAGE_NORMAL)
	if ratio <= 0.0:
		return normal
	return maxf(normal, base * lerpf(1.0, stats.get_v(Stats.CHARGE_DAMAGE), ratio))

## 현재 연격 스택으로 붙는 평타 피해 배율. 차징·우클릭은 이걸 안 본다 (스펙).
func combo_mult() -> float:
	if combo_level <= 0:
		return 1.0
	return 1.0 + float(_combo) * COMBO_PER_STACK[mini(combo_level, 3)]

func combo_max() -> int:
	return COMBO_MAX[mini(combo_level, 3)] if combo_level > 0 else 0

## 이번 평타가 대강타인가. **때리기 전에** 정해야 반경·망치 크기를 미리 키울 수 있다.
## 스펙: 네 번째로 '명중하는' 평타가 대강타 -> 3회 쌓였으면 다음 타가 그 네 번째다.
## 빗나가면 _beat 가 그대로 3 이라 다음 타도 대강타로 남는다 ("횟수는 사라지지 않는다").
func is_beat_strike(ratio: float) -> bool:
	return has_beat and ratio <= 0.0 and _beat >= BEAT_EVERY - 1

## 업그레이드로 늘어난 범위만큼 망치도 커진다 — 범위 카드를 먹으면 무기가 눈에 띄게 자란다.
##
## ⚠️ 차징분(charge_radius_mult ×2)은 **일부러 뺀다.** strike_radius(ratio) 를 쓰면
## 풀차징 때 여기서 2배가 되고 아래에서 charge_scale_mult(1.35)가 또 곱해져 2.7배가 된다.
## 차징의 크기 연출은 charge_scale_mult 담당이고, 이 함수는 **영구 성장분만** 맡는다.
func radius_scale() -> float:
	return stats.get_v(Stats.RADIUS) / maxf(base_radius, 0.001)

## 이번 스윙이 뿜을 돌 개수 배율.
func strike_count_mult(ratio: float) -> float:
	return lerpf(1.0, charge_count_mult, ratio)

## 한 지점 반경 안의 적에게 피해. 최초 충돌·여진·분출이 공유한다.
## knock > 0 이면 살아남은 적을 튕겨낸다 (무거운 적은 뜨지 않고 뒤로 밀린다).
##
## **죽은 적 노드**를 돌려준다 — 폭연이 그 시체를 가로채(combust) 부풀렸다 터뜨린다.
## _deflagrate 는 이 목록을 같은 프레임에 소비하므로 노드 수명 걱정은 없다
## (combust 가 걸리는 순간 시체 수명은 폭발 시점까지로 다시 정해진다).
## ratio 는 그 스윙의 차징 비율. 맞은 적에게 그대로 전달된다 —
## 보스가 "풀차징으로 예고를 끊는" 규칙을 판정하려면 **얼마나 모아 쳤는지**를 알아야 한다.
func _damage_area(center: Vector3, radius: float, damage: float,
		nudge := false, knock := 0.0, ratio := 0.0,
		src: DamageSource = null) -> Array[Enemy]:
	var killed: Array[Enemy] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		var flat := enemy.global_position - center
		flat.y = 0.0
		# hit_radius 를 더한다 — 보스처럼 망치보다 큰 몸은 중심이 아니라 **몸에** 맞아야 한다
		if flat.length() <= radius + enemy.hit_radius:
			if nudge:
				enemy.hop()      # 살아남으면 짧게 들썩인다
			enemy.take_damage(damage, center, src if src != null else _swing_src)
			enemy.on_hammer(ratio)
			if enemy.dying:
				killed.append(enemy)
			elif knock > 0.0:
				enemy.knockback(center, knock)
	return killed

## 이 반경 안에 (죽지 않은 적 포함) 누군가 있었는가. killed 만 보면 **살아남은 적을 때린 것**이
## 빗나감으로 집계되어 연격이 안 쌓인다 — 스펙은 "한 마리 이상에게 명중" 이다.
func _hit_anyone(center: Vector3, radius: float) -> bool:
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		var flat := enemy.global_position - center
		flat.y = 0.0
		if flat.length() <= radius + enemy.hit_radius:
			return true
	return false

## 평타 한 방의 결과를 연격·대강타 카운터에 반영한다.
func _tally_normal_hit(hit: bool, was_beat: bool) -> void:
	if combo_level > 0:
		if hit:
			_combo = mini(_combo + 1, combo_max())
			_combo_left = combo_window
		else:
			_combo = 0            # 빗나가면 즉시 초기화 (스펙)
	if has_beat:
		if was_beat:
			if hit:
				_beat = 0         # 대강타가 실제로 맞았을 때만 리셋
		elif hit:
			_beat = mini(_beat + 1, BEAT_EVERY - 1)
		# 빗나간 평타는 증가도 감소도 없다 (스펙)

## 여진: 망치는 다시 떨어지지 않고, 눌렸던 땅이 뒤늦게 반발한다.
## 여진이 또 다른 여진을 낳지 않도록 _impact 가 아니라 _damage_area 를 직접 부른다.
func _aftershock(target: Vector3, ratio: float) -> void:
	# 평타·차징: 2차 효과 반경(RADIUS_ALL 이 빠진 값)과 그 스윙의 피해를 그대로 쓴다.
	# 불이 있으면 같은 한 방에 **분화구**가 열린다 (유저 지시 2026-08-18) — 바위 대신.
	# ⚠️ ratio 를 **끝까지** 넘긴다. 예전엔 _erupt_rocks 가 ratio 0 으로 불려서
	#    맥스 차징이든 살짝 눌렀든 바위 개수가 똑같이 4개였다 (유저 지적 2026-08-18).
	_aftershock_at(target, strike_damage(ratio), secondary_radius(ratio), 1.0,
		normal_erupt_rocks_mul, normal_erupt_damage, normal_erupt_spread,
		crater_balls_for(ratio), ratio, normal_erupt_cap_for(ratio))

## 균열 지대를 만든다. **반경과 피해를 부르는 쪽이 정한다** — 평타는 2차 효과 반경을,
## 우클릭 특수는 자기 직격 반경에 비례한 값을 넘긴다 (유저 지시 2026-08-14:
## "특수가 만드는 균열은 공격 범위에 비례하게").
## erupt_scale > 0 이면 여진과 **같은 순간에 바위가 솟는다** — 재타격을 기다리지 않는다
## (특수 전용. 평타는 0 으로 둬서 "갈라진 땅을 한 번 더 친다"는 규칙을 지킨다).
## 균열은 그대로 남는다 — 재타격하면 원래대로 소모돼 분출/분화구가 된다.
## ratio 는 그 스윙의 차징 비율. 분출 바위 **개수**가 여기에 비례한다
## (평타 4개 → 맥스 차징 7개 → 우클릭 16개 순서가 되도록). 우클릭 호출부는
## 자기 배율(special_erupt_rocks_mul)로 이미 개수를 정하므로 0 을 그대로 쓴다.
func _aftershock_at(target: Vector3, dmg_base: float, radius: float,
		erupt_scale := 0.0, rocks_mul := -1.0, dmg_mul := -1.0, spread := -1.0,
		crater_balls := -1, ratio := 0.0, cap := -1) -> void:
	if cap < 0:
		cap = ERUPT_MAX          # 음수면 특수 기본값 (rocks_mul 등과 같은 규약)
	if crater_balls < 0:
		crater_balls = crater_balls_special
	# 음수면 **특수 기본값**을 쓴다 — 특수 쪽 호출부를 안 건드리려고.
	if rocks_mul < 0.0:
		rocks_mul = special_erupt_rocks_mul
	if dmg_mul < 0.0:
		dmg_mul = special_erupt_damage
	if spread < 0.0:
		spread = special_erupt_spread
	# 균열 지대의 오브젝트 스펙. 반경·수명이 여기서 정해진다 —
	# ⚠️ 아래에서 여진 피해 범위도 **같은 crack.radius** 를 쓴다. 따로 계산하면
	#    "빛나는 균열은 넓은데 안 아픈" 거짓말이 생긴다.
	var crack := crack_spec(radius * aftershock_radius)
	var fx := AftershockFX.new()
	fx.spec = crack
	add_child(fx)
	fx.global_position = Terrain.on(target)
	fx.begin(radius, 1.0)               # 0.00 최초 충돌 자국 — 바닥에 남는다
	if has_fire:
		fx.ignite()                     # 불 조합: 균열에 잔열이 흐른다 (분화구 예고)

	# 특수 즉시 분출 — **충돌과 같은 프레임**이다 (유저 지시 2026-08-16: "딜레이 없이").
	# ⚠️ 처음엔 0.35초 여진 박자에 얹었는데, 망치가 꽂히고 한 박자 쉰 뒤 바위가 나와서
	#    같은 한 방으로 안 읽혔다. 여진(고리·피해)은 그대로 0.35초에 오고, 바위만 앞으로 뺀다.
	#    반경은 여진 지대 크기를 그대로 쓴다 — 나중에 갈라질 범위에서 미리 솟는 셈이다.
	if erupt_scale > 0.0:
		_shake = maxf(_shake, erupt_shake * erupt_scale)
		# ⚠️ **첫 가격에 두 번째 가격의 그림을 보여준다** (유저 지시 2026-08-18):
		#    갈라진 틈이 안에서부터 빛나고, 빛줄기·돌조각이 솟는다.
		#    flare() 는 연출만 한다 — 균열은 살아남아 밟기·재타격이 그대로 동작한다.
		fx.flare()
		if has_fire:
			# 불 조합은 **바위 대신 분화구** — 평타가 균열을 재타격했을 때와 같은 규칙이다
			# (유저 지시 2026-08-16: "첫 방에 분화구, 불덩이까지"). 균열은 위에서 이미
			# ignite 됐고, 분화구 수명(5초)과 잔열 수명(LAVA_LINGER)이 같아서 맞아떨어진다.
			# charge 에 erupt_scale 을 넘긴다 — 본체는 풀차징급(발리당 5발),
			# 메아리는 0.6 이라 한 발 적게 뿜어 곁다리로 읽힌다.
			# ⚠️ 메아리는 erupt_scale(0.6) 만큼 **적게** 뿜어 곁다리로 읽힌다 —
			#    본체와 같은 개수면 두 분화구가 같은 무게로 보인다.
			Crater.spawn(self, fx, crater_spec(radius * aftershock_radius),
				fireball_spec(dmg_base * fire_ball_damage, fire_ball_radius,
					maxi(1, roundi(float(crater_balls) * erupt_scale))))
		else:
			_erupt_rocks(target, radius * aftershock_radius * spread,
				dmg_base * dmg_mul, ratio, erupt_scale * rocks_mul, cap)

	var tw := create_tween()
	tw.tween_interval(AftershockFX.TELL_START)
	tw.tween_callback(fx.tell)          # 0.15 예고
	tw.tween_interval(aftershock_delay - AftershockFX.TELL_START)
	tw.tween_callback(func() -> void:   # 0.35 여진
		# 예고 0.35초 사이에 균열이 사라졌을 수 있다 (웨이브 정리·검증 스크립트 등).
		# 트윈은 그 사실을 모르고 그대로 호출해서 Nil 에러를 낸다.
		if not is_instance_valid(fx):
			return
		fx.fire(crack.radius, aftershock_strength)
		_shake = maxf(_shake, aftershock_shake)
		_damage_area(target, crack.radius,
			dmg_base * aftershock_damage, true))
	# 정리는 AftershockFX 가 스스로 한다 — fire() 시점부터 LINGER(3초) 동안
	# 균열 지대로 살아있다가 만료되거나, 그 전에 다시 얻어맞으면 분출하며 사라진다.

## 충격파 오브젝트 한 발. 스펙의 수량·반복·수명을 여기서 푼다.
## ⚠️ 연출과 판정은 **같은 spec.radius** 를 쓴다. 따로 계산하면 어긋난다.
func _shockwave_object(target: Vector3, inner: float, spec: ObjectSpec) -> void:
	for i in spec.count:
		# 수량이 2 이상이면 동심원으로 시차를 두고 나간다 — 같은 순간 겹쳐 쏘면 한 겹으로 보인다
		var delay := float(i) * 0.08
		var r := spec.radius * lerpf(1.0, 0.72, float(i) / maxf(float(spec.count), 1.0))
		_shockwave_shot(target, inner, r, spec, delay, 1.0)
	# 메아리 — 0.35초 뒤 한 번 더, 약하게. 깊이 상한을 넘으면 안 나간다.
	for e in spec.repeat:
		if spec.child_src(&"shockwave_echo", spec.repeat_power) == null:
			break
		_shockwave_shot(target, inner, spec.radius, spec,
			spec.repeat_delay * float(e + 1), spec.repeat_power)

## 끌어당김 — 착탄 순간 범위 안의 적을 중심으로 끈다. 충격파와 **같은 구조**다.
## count 는 쓰지 않는다: '다중화'가 발사체 전용이라 면적 오브젝트의 count 는 항상 1 이고,
## 흡입을 여러 겹으로 쪼개면 한 번에 모이는 그림이 흐려진다.
func _pull_object(target: Vector3, spec: ObjectSpec, power := 1.0) -> void:
	_pull_shot(target, spec, 0.0, power)
	# 메아리 — 0.35초 뒤 한 번 더 끈다. 이게 이 카드를 고른 이유의 절반이다(유저).
	# ⚠️ 깊이 상한을 넘으면 안 나간다. 끌어당김이 끌어당김을 부르면 무한이다.
	for e in spec.repeat:
		if spec.child_src(&"pull_echo", spec.repeat_power) == null:
			break
		_pull_shot(target, spec, spec.repeat_delay * float(e + 1), spec.repeat_power * power)

## 회오리 — 인력과 **같은 구조**다. 끄는 대신 돌린다.
func _vortex_object(target: Vector3, spec: ObjectSpec, power := 1.0) -> void:
	_vortex_shot(target, spec, 0.0, power)
	for e in spec.repeat:
		if spec.child_src(&"vortex_echo", spec.repeat_power) == null:
			break
		_vortex_shot(target, spec, spec.repeat_delay * float(e + 1), spec.repeat_power * power)

func _vortex_shot(target: Vector3, spec: ObjectSpec, delay: float, power: float) -> void:
	var fire := func() -> void:
		if not is_inside_tree():
			return
		_pull_vfx(target, spec.radius, spec.lifetime, true)
		for node in get_tree().get_nodes_in_group("enemies"):
			var enemy := node as Enemy
			var flat := enemy.global_position - target
			flat.y = 0.0
			if flat.length() > spec.radius + enemy.hit_radius:
				continue
			enemy.swirl(target, vortex_arc * power, vortex_inward)
	if delay <= 0.0:
		fire.call()
		return
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(fire)

func _pull_shot(target: Vector3, spec: ObjectSpec, delay: float, power: float) -> void:
	var fire := func() -> void:
		if not is_inside_tree():
			return
		_pull_vfx(target, spec.radius, spec.lifetime)
		for node in get_tree().get_nodes_in_group("enemies"):
			var enemy := node as Enemy
			var flat := enemy.global_position - target
			flat.y = 0.0
			# hit_radius 를 더해 주는 건 _damage_ring 과 같은 이유다 —
			# 몸이 큰 적은 중심이 범위 밖이어도 몸통이 걸쳐 있으면 걸려야 한다.
			if flat.length() > spec.radius + enemy.hit_radius:
				continue
			enemy.pull(target, pull_distance * power)
	if delay <= 0.0:
		fire.call()
		return
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(fire)

## 빨려드는 힘줄 연출. 충격파와 **같은 메시**를 쓴다 (지형을 타는 원판, U=거리 V=각도) —
## 셰이더만 pull.gdshader 로 갈아 끼운 형제다.
func _pull_vfx(target: Vector3, radius: float, life_mul := 1.0, vortex := false) -> void:
	var disc := MeshInstance3D.new()
	disc.mesh = _shockwave_mesh(target, radius)
	var mat := ShaderMaterial.new()
	mat.shader = PullShader if vortex else MagnetShader
	# ⚠️ 트윈할 유니폼은 미리 심어 둔다 (shockwave 와 같은 함정).
	mat.set_shader_parameter("t", 0.0)
	mat.set_shader_parameter("seed", randf() * 40.0)
	if vortex:
		# 조합의 색은 **두 카드의 색을 섞은 것**이다 — 충격파의 주황이 인력의 청록에 물든다.
		# 새 카드가 아니라 "두 개가 합쳐졌다"를 색으로 먼저 읽게 하려는 것이다.
		mat.set_shader_parameter("swirl", 0.62)      # 확실히 감긴다
		# ⚠️ boost 를 같이 낮춰야 한다. 1.9 로 두면 심지가 **흰색으로 타서** 색조가 사라지고
		#    충격파와 구분이 안 된다 (2026-08-25 렌더에서 확인). 조합의 정체성은 색이다.
		mat.set_shader_parameter("boost", 1.3)
		mat.set_shader_parameter("core_col", Color(0.992, 0.820, 0.475))  # #fdd179 충격파 심지
		mat.set_shader_parameter("body_col", Color(0.173, 0.910, 0.961))  # #2ce8f5 인력 몸통
		mat.set_shader_parameter("tail_col", Color(0.922, 0.588, 0.380))  # #eb9661 충격파 꼬리
	disc.material_override = mat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	disc.global_position = Terrain.on(target, SHOCK_LIFT)
	if not vortex and magnet_random_axis:
		# 판은 **땅과 평행**하게 눕혀 둔다 (유저 지시 2026-08-25) — 세웠더니 방향에 따라
		# 카메라에 옆면으로 서서 선 하나로 뭉개졌다. 눕히면 어느 방향이든 같은 기울기로 보인다.
		mat.set_shader_parameter("axis_v", randf())
	var tw := create_tween()
	tw.tween_property(mat, "shader_parameter/t", 1.0,
		(PULL_TIME if vortex else MAGNET_TIME) * life_mul)
	tw.tween_callback(disc.queue_free)

## 흡입 연출 길이. 충격파(SHOCK_TIME)보다 짧다 — 끌림은 한 번에 훅 들어와야 읽힌다.
const PULL_TIME := 0.42
## 자기장(인력 단독)은 **고리가 하나씩 차례로** 빨려들어야 해서 나선보다 길어야 한다.
## 0.42 로 두면 마지막 고리가 출발하기도 전에 끝난다.
const MAGNET_TIME := 0.62
## 자기장 축 방향을 매 시전마다 무작위로 돌린다. 항상 같은 축이면 스킬이 한 장면으로 굳는다.
## ⚠️ 노드를 돌리지 않고 **셰이더의 axis_v** 로 돌린다 — 지형 높이가 구워진 메시를 회전시키면
##    높이가 엉뚱한 자리에 얹혀 판이 뒤틀린다.
@export var magnet_random_axis := true
const PullShader := preload("res://shaders/pull.gdshader")
## 인력 단독은 **뿜어져 나오는 쌍극자 자기장**이다 (유저 지시 2026-08-25).
## 빨려드는 나선(PullShader)은 회오리 조합이 가져갔다 — 둘이 같은 그림이면 조합이 안 읽힌다.
const MagnetShader := preload("res://shaders/magnet.gdshader")

func _shockwave_shot(target: Vector3, inner: float, outer: float, spec: ObjectSpec,
		delay: float, power: float) -> void:
	var fire := func() -> void:
		if not is_inside_tree():
			return
		_shockwave(target, 0.0, outer, spec.lifetime)
		_damage_ring(target, inner, outer, spec.damage * power, shock_knock() * power,
			spec.src)
	if delay <= 0.0:
		fire.call()
		return
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(fire)

## 퍼져나가는 충격파 링 (nice31 #f2b888 계열).
## 평타는 '충격파' 카드(has_shockwave)로 해금되고, 우클릭 특수는 카드와 무관하게 항상 부른다.
## ⚠️ radius_override 는 **필수로 넘겨라.** 두 호출부 모두 자기 판정 반경을 그대로 넘겨서
##    연출과 판정이 어긋나지 않게 한다 — 링이 판정보다 넓으면 "닿았는데 안 맞는" 거짓말이 된다.
##
## 링을 **토러스 스케일 트윈**으로 하던 걸 2026-08-18 에 셰이더로 갈아치웠다.
## 매끈한 고리가 통째로 옅어지는 건 CG 티가 났다 — 지금은 셀 단위로 부서져 흩어진다
## (근거: gamedev/video_study_notes_2026-08-10.md, shaders/shockwave.gdshader 머리말).
const ShockwaveShader := preload("res://shaders/shockwave.gdshader")
const SHOCK_TIME := 0.45      ## 퍼져서 다 부서질 때까지
const SHOCK_LIFT := 0.06      ## 지면 z-fighting 회피
const SHOCK_SEG := 48         ## 둘레 분할. 셰이더 셀(34)보다 촘촘해야 파편이 각지지 않는다.
const SHOCK_RINGS := 10       ## 반경 분할. 지형을 타고 넘는 해상도이기도 하다.

func _shockwave(target: Vector3, ratio := 0.0, radius_override := -1.0,
		life_mul := 1.0) -> void:
	var spread := (strike_radius(ratio) * shock_spread) if radius_override < 0.0 else radius_override
	var ring := MeshInstance3D.new()
	ring.mesh = _shockwave_mesh(target, spread)
	var mat := ShaderMaterial.new()
	mat.shader = ShockwaveShader
	# ⚠️ 트윈할 유니폼은 미리 심어 둔다 — 셰이더 기본값에 맡기면 tween 이 조용히 실패한다
	#    (erupt_rock.dirt_patch 주석과 같은 함정).
	mat.set_shader_parameter("t", 0.0)
	mat.set_shader_parameter("seed", randf() * 40.0)
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.global_position = Terrain.on(target, SHOCK_LIFT)

	var tw := create_tween()
	tw.tween_property(mat, "shader_parameter/t", 1.0, SHOCK_TIME * life_mul)
	tw.tween_callback(ring.queue_free)

## 충격파가 깔릴 원판. **지형 높이를 따라간다** — 평평한 PlaneMesh 를 깔면
## 언덕이 링을 뚫고 나와 판때기가 지면에 박힌 게 보인다. 링이 반경 6~7 유닛까지
## 퍼지는 데다 유저가 지형을 직접 깎는 게임이라 그냥 넘길 수 없다.
## UV 규약: U = 중심에서의 거리(0..1), V = 각도(0..1). 셰이더가 이걸 전제로 짜여 있다.
static func _shockwave_mesh(center: Vector3, radius: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var base_y := Terrain.h(center)
	for ri in SHOCK_RINGS + 1:
		var fr := float(ri) / float(SHOCK_RINGS)
		for si in SHOCK_SEG + 1:
			var fa := float(si) / float(SHOCK_SEG)
			var ang := fa * TAU
			var lx := cos(ang) * fr * radius
			var lz := sin(ang) * fr * radius
			verts.append(Vector3(lx,
				Terrain.h(center + Vector3(lx, 0.0, lz)) - base_y, lz))
			uvs.append(Vector2(fr, fa))
	for ri in SHOCK_RINGS:
		for si in SHOCK_SEG:
			var a := ri * (SHOCK_SEG + 1) + si
			var b := a + SHOCK_SEG + 1
			idx.append_array([a, b, a + 1, a + 1, b, b + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh

## 흙먼지 파편 (nice31 #bcad9f)
## 히트스톱 — 임팩트 순간 세상을 잠깐 멈춘다.
##
## ⚠️ Engine.time_scale 은 **전역**이라 복구를 못 하면 게임이 저속으로 굳는다. 함정 둘:
##   1) 복구 타이머가 트리 정지에 걸리면 안 된다. 히트스톱 도중 레벨업이 겹치면 카드 화면이
##      get_tree().paused 를 걸어버린다 -> process_always=true.
##   2) 타이머 자체가 time_scale 을 타면 0.07 초가 0.58 초로 늘어난다 -> ignore_time_scale=true.
## 겹쳐 들어오면 먼저 걸린 타이머가 나중 히트스톱을 조기 해제하므로 토큰으로 막는다.
var _hitstop_id := 0

## 우클릭 특수 상태. 쿨(3초) > 예고(2초) 라 동시에 두 개가 뜰 일은 없지만,
## 예고 도중 또 눌리는 것만은 막아야 한다.
var _combo := 0            ## 현재 연격 스택
var _combo_left := 0.0     ## 남은 유지 시간
var _beat := 0             ## 대강타까지 쌓인 명중 수 (0..BEAT_EVERY-1)

var _special_cd := 0.0
var _special_active := false
var _special_hammer: Node3D
var _special_shadow: MeshInstance3D
const ShadowShader := preload("res://shaders/drop_shadow.gdshader")
const CelBurnShader := preload("res://shaders/cel_burn.gdshader")
const InkBurnShader := preload("res://shaders/ink_burn.gdshader")

## ⚠️ 인자 이름이 scale 이면 Node3D.scale 을 가린다 — 이 함수 안에서 실수로
##    노드 크기를 건드리려 하면 조용히 이 인자를 읽는다.
## ⚠️ 함정 3) 복구값을 **1.0 으로 박으면 안 된다.** 배속이 걸린 환경에서 히트스톱 한 번에
##    배속이 영영 1.0 으로 주저앉는다 — 밸런스 시뮬(tools/sim_run.gd)이 10배속으로 도는데
##    봇이 첫 풀차징을 치는 순간 1배속이 돼서 20분 런을 끝낼 수가 없었다 (2026-08-14 실측:
##    30분을 돌려도 UPGRADE 로그가 한 줄도 안 나왔다). 히트스톱 **들어가기 직전의 배속**을
##    기억했다가 그 값으로 되돌린다.
##    겹쳐 들어올 땐 이미 느려진 값(0.12)을 기억하면 안 되므로, 진행 중이 아닐 때만 기록한다.
var _hitstop_prev := 1.0
var _hitstop_active := false

func _hitstop(duration: float, time_scale: float) -> void:
	_hitstop_id += 1
	var id := _hitstop_id
	if not _hitstop_active:
		_hitstop_prev = Engine.time_scale
		_hitstop_active = true
	Engine.time_scale = time_scale
	get_tree().create_timer(duration, true, false, true).timeout.connect(
		func() -> void:
			if id == _hitstop_id:      # 그 사이 새 히트스톱이 걸렸으면 그쪽에 맡긴다
				Engine.time_scale = _hitstop_prev
				_hitstop_active = false)

func _dust(target: Vector3, ratio := 0.0) -> void:
	if ratio >= charge_fx_min_ratio:
		# 풀차징: 수직 먼지는 작은 킥만 남기고, 주인공은 바닥을 훑는 압축 고리다.
		# 고리 반경 = 그 스윙의 실제 타격 반경 — 연출이 곧 범위 표시가 된다.
		ImpactDust.burst(self, target, charge_dust_kick)
		ImpactDust.ground_ring(self, target, strike_radius(ratio), charge_ring_amount)
		return
	# 낙석 착지도 같은 먼지를 쓴다 (ImpactDust 에 모아둠)
	ImpactDust.burst(self, target, int(lerpf(26.0, 60.0, ratio)))
