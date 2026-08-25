class_name CardCatalog
extends RefCounted

## 업그레이드 카드 정의. 카드를 추가할 땐 여기에 한 줄이면 된다.
##   stat + pct  : 일반 강화 — hammer.stats.add_pct(stat, pct). 반복 획득 가능.
##   flag        : 패턴/속성 — hammer 의 bool 프로퍼티를 켠다. 한 번만.
## 조합(여진+불=분화구)은 카드가 아니다 — 두 flag 를 보유하면 자동 발동한다(기획 원칙).
##
## stat + flat : 배율이 아니라 **고정값** 가감 (초·거리처럼 단위가 있는 값).
## excludes: 이 id 를 한 장이라도 가지고 있으면 이 카드는 안 나온다 (상반된 계약 방지).
## max_stacks: 이 카드를 몇 장까지 먹을 수 있는가. 다 채우면 풀에서 빠진다.
##   repeat 카드엔 **반드시** 적어라 — 빠뜨리면 무한 중첩이라 한 장으로 런이 무너진다.
##   flag 카드는 repeat=false 라 자동으로 1 회다.
##
## ⚠️ 평타와 차징은 **다른 스탯**을 본다 (유저 지시 2026-08-13):
##   COOLDOWN / RADIUS       = 평타 전용
##   COOLDOWN_CHARGED / CHARGE_TIME / CHARGE_DAMAGE / CHARGE_RADIUS = 차징 전용
##   COOLDOWN_SPECIAL / SPECIAL_* = 특수(우클릭) 전용
##   DAMAGE_NORMAL           = 평타 전용 피해 (담금질)
##   DAMAGE                  = 세 공격 공통 기반 (거인의 힘)
##
## rarity: &"common"(일반, 흰 종이) / &"rare"(희귀, 금박). 등급이 늘면 여기에 추가.

## id 로 카드 정의 찾기. 없으면 빈 딕셔너리.
static func by_id(id: StringName) -> Dictionary:
	for c in CARDS:
		if c.id == id:
			return c
	return {}

const CARDS: Array[Dictionary] = [
	{
		id = &"damage", cname = "담금질", desc = "평타 피해 +20%",
		cat = "평타 강화", rarity = &"common", repeat = true, max_stacks = 3,
		stat = Stats.DAMAGE_NORMAL, pct = 0.20,   # 평타 전용 (거인의 힘이 세 공격 담당)
	},
	{
		id = &"radius", cname = "넓은 울림", desc = "평타 범위 +15%",
		cat = "일반 강화", rarity = &"common", repeat = true, max_stacks = 3,
		stat = Stats.RADIUS, pct = 0.15,          # 차징 범위는 '과충전' 담당
	},
	{
		id = &"swift", cname = "신속한 강타", desc = "평타 쿨타임 -10%",
		cat = "일반 강화", rarity = &"common", repeat = true, max_stacks = 5,
		stat = Stats.COOLDOWN, pct = -0.10,
	},
	{
		id = &"condense", cname = "응축", desc = "최대 차징 도달 시간 -20%",
		cat = "차징 강화", rarity = &"common", repeat = true, max_stacks = 4,
		stat = Stats.CHARGE_TIME, pct = -0.20,
	},
	{
		id = &"overcharge", cname = "과충전", desc = "풀차징 피해 +30%\n풀차징 범위 +10%",
		cat = "차징 강화", rarity = &"rare", repeat = true, max_stacks = 3,
		# 스탯 두 개를 건드리는 첫 카드 — 단일 stat/pct 대신 목록으로 적는다.
		stats = [
			{stat = Stats.CHARGE_DAMAGE, pct = 0.30},
			{stat = Stats.CHARGE_RADIUS, pct = 0.10},
		],
	},
	{
		id = &"blessing", cname = "성장의 축복", desc = "경험치 획득량 +25%",
		cat = "성장", rarity = &"rare", repeat = true, max_stacks = 2,
		stat = Stats.XP_GAIN, pct = 0.25,
	},
	# --- 공용 (세 공격 전부에 통한다) -------------------------------------------
	{
		id = &"giant", cname = "거인의 힘", desc = "평타·차징·특수\n직접 피해 +10%",
		cat = "일반 강화", rarity = &"common", repeat = true, max_stacks = 3,
		stat = Stats.DAMAGE, pct = 0.10,
	},
	{
		# ⚠️ RADIUS(넓은 울림)가 아니라 RADIUS_ALL 이다. RADIUS 는 평타 전용이고,
		# 이 카드는 세 공격의 **직격**에 전부 걸리되 여진·폭연·불덩이 같은 2차 범위는 건드리지
		# 않는다 (유저 스펙). 그래서 2차 효과는 secondary_radius() 를 따로 본다.
		id = &"reach", cname = "확장된 권능", desc = "평타·차징·특수\n직접 타격 반경 +10%",
		cat = "일반 강화", rarity = &"common", repeat = true, max_stacks = 3,
		stat = Stats.RADIUS_ALL, pct = 0.10,
	},
	# --- 물량 계약 (서로 배타) ---------------------------------------------------
	# ⚠️ 한쪽을 고르면 반대쪽은 풀에서 빠진다 (excludes). 유저 판단: 상쇄를 허용하면
	#    "이전 선택을 뒤집는다" 는 의미는 있지만, **상반된 계약을 동시에 맺는 모순**이 된다.
	#    스탯 자체는 가산이라 배타 규칙을 걷어내면 상쇄가 그냥 동작한다.
	{
		id = &"restraint", cname = "신의 억제",
		desc = "일반 적 출현량 -10%\n적이 줄어 경험치도 줄어든다",
		cat = "방어적 성장", rarity = &"common", repeat = true, max_stacks = 5,
		stat = Stats.SPAWN_RATE, pct = -0.10, excludes = &"warcry",
	},
	{
		id = &"warcry", cname = "전쟁의 부름",
		desc = "일반 적 출현량 +10%\n더 많은 적에게서\n추가 경험치를 얻는다",
		cat = "위험 투자", rarity = &"common", repeat = true, max_stacks = 5,
		stat = Stats.SPAWN_RATE, pct = 0.10, excludes = &"restraint",
	},
	# --- 우클릭 전용 -------------------------------------------------------------
	{
		id = &"cycle", cname = "천벌의 주기", desc = "특수 재사용\n대기시간 -15%",
		cat = "특수 강화", rarity = &"common", repeat = true, max_stacks = 3,
		# -12% -> -15% (유저 지시 2026-08-14). 기본 쿨이 5 -> 7 초로 무거워진 만큼
		# 이 카드가 되찾아 주는 폭도 같이 키운다.
		# ⚠️ pct 는 **합산**이다 (Stats: 최종 = 기본 × (1 + pct합)). 곱연산이 아니라
		#    3스택은 0.85³(-39%)이 아니라 **-45%** 다. 7.00 -> 3.85 초.
		stat = Stats.COOLDOWN_SPECIAL, pct = -0.15,
	},
	{
		id = &"swift_doom", cname = "신속한 천벌",
		desc = "특수 착탄 대기시간\n0.3초 감소",
		cat = "특수 강화", rarity = &"common", repeat = true, max_stacks = 3,
		stat = Stats.TELEGRAPH_SPECIAL, flat = -0.3,
	},
	# --- 평타 전용 ---------------------------------------------------------------
	{
		id = &"combo", cname = "몰아치는 신격",
		desc = "평타가 맞을수록 연격이 쌓여\n평타 피해가 오른다",
		cat = "평타 강화", rarity = &"common", repeat = true, max_stacks = 3,
		counter = &"combo_level",
	},
	{
		id = &"beat", cname = "파괴의 박자",
		desc = "평타 4회 명중마다\n다음 평타가 대강타가 된다",
		cat = "평타 강화", rarity = &"rare", repeat = false,
		flag = &"has_beat",
	},
	{
		# ⚠️ 줄바꿈은 손으로 넣는다 — desc 라벨에 autowrap 이 없어서 한 줄이 길면 카드 밖으로
		# 삐져나간다. 폭 238px / 15pt 기준 **한 줄 15자**가 한계.
		# 균열을 다시 쳐야 바위가 나온다는 걸 안 적어서 아무도 모르고 지나쳤다 (유저 지적).
		id = &"aftershock", cname = "여진",
		# 4줄로 늘렸더니 이 카드만 패널 안에서 높이가 튄다 — 다른 카드는 최대 3줄이다.
		desc = "갈라진 자리가 한 번 더 터진다\n다시 치면 바위가 솟고\n특수는 한 방에 솟는다",
		cat = "공격 패턴", rarity = &"rare", repeat = false,
		flag = &"has_aftershock",
	},
	{
		# 줄당 15자 한계 — 여진 카드 주석 참고.
		id = &"shockwave", cname = "충격파",
		desc = "고리가 퍼져 바깥의 적을\n밀어내며 깎는다\n인력과 만나면 회오리",
		cat = "공격 패턴", rarity = &"rare", repeat = false,
		flag = &"has_shockwave",
	},
	{
		# 순수 유틸 — 피해가 0 이다. 값은 **다음 공격이 더 걸리는 것**에서 나온다.
		# 메아리가 붙으면 한 번 더 끌고, 나중에 슬로우 패턴이 붙으면 같은 순간 함께 터진다
		# (유저 설계 2026-08-25). 그래서 착탄 시점 발동이다.
		id = &"pull", cname = "인력",
		desc = "타격한 자리로 끌어모은다\n무거운 적은 덜 끌린다\n충격파와 만나면 회오리",
		cat = "공격 패턴", rarity = &"rare", repeat = false,
		flag = &"has_pull",
	},
	{
		id = &"fire", cname = "불의 심장", desc = "공격에 불이 깃든다\n여진과 만나면 분화구가 열린다",
		cat = "속성", rarity = &"rare", repeat = false,
		flag = &"has_fire",
	},
]
