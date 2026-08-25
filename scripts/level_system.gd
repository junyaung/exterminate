class_name LevelSystem
extends RefCounted

## 처치 -> 경험치 -> 레벨업 -> 카드 3장. 런 하나의 성장 시계.
##
## 요구 경험치 = `XP_FIRST × 레벨^XP_CURVE` (다항).
##
## ⚠️ **등비(×1.45)를 먼저 써봤다가 버렸다.** 스폰율은 액트마다 대략 2배씩 늘어나는데
## 등비 요구치는 레벨마다 배수로 뛰므로 증가 속도가 훨씬 가팔라, 성장이 앞으로 쏠린다 —
## 스폰 스케줄러를 그대로 복제해 측정한 결과가 **액트별 9 / 3 / 2 / 2장**이었다.
## 다항으로 바꾸면 요구치가 완만해져 후반 물량 증가와 보조가 맞는다: **5 / 4 / 4 / 5장**.
##
## `Stats` 와 같은 이유로 Node 가 아니라 RefCounted 다: **자식 노드의 `_ready()` 는 부모보다
## 먼저 돈다.** Node 로 두고 Main._ready() 에서 만들면 CardUI/XpBar 가 연결하려는 순간엔
## 아직 null 이다. 변수 초기화식으로 만들면 어떤 _ready() 보다도 먼저 존재한다.
##
## 성장 속도는 이 둘로만 조절한다. 바꾼 뒤엔 반드시 재보고 넣을 것:
##   godot --headless --path . --script tools/sim_levels.gd
##   (후보 비교: XPF=12 XPC=1.4 godot --headless ... — 웨이브별 레벨 도달을 찍어준다)
##   XP_FIRST — 첫 레벨업까지 필요한 경험치. 올리면 전 구간이 같이 느려진다.
##   XP_CURVE — 뒤로 갈수록 얼마나 가팔라지는가. 1.0 이면 등차, 키우면 후반이 무거워진다.
##
## ⚠️ **웨이브 도입으로 몹 총량이 줄어 40/1.5 는 너무 느려졌다** (유저 지적 2026-08-25).
## 액트 시절 곡선은 2만 마리를 흘려보내는 전제였는데, 전멸 조건의 웨이브는 총 5,290마리다.
## 시뮬 실측: 40/1.5 는 **웨이브당 정확히 1장, 런 전체 10장** — 액트 시절 18장의 절반이다.
## 12/1.4 로 내려 **웨이브당 2장, 런 전체 19장**으로 되돌렸다 (몹 하나의 체감 가치 ×3.3).
## 곡선도 1.5 -> 1.4 로 눕혔다: 웨이브 경험치가 뒤로 갈수록 1.3배씩 붙는데 요구치가 lv^1.5
## 로 자라면 둘이 상쇄돼 후반에도 계속 1장씩만 나온다 — 물량이 늘어난 보람이 없다.

const XP_FIRST := 12.0
const XP_CURVE := 1.4

## 레벨이 올랐다. 한 번의 폭발로 여러 번 오르면 그 횟수만큼 발생한다.
signal leveled(new_level: int)

var level := 1
var xp := 0.0            ## 현재 레벨 안에서 쌓은 양 (요구치에 도달하면 0으로 되감김)
var total_xp := 0.0      ## 런 전체 누적 (리포트용)

## level 에서 다음 레벨로 가는 데 필요한 경험치.
static func req_for(lv: int) -> float:
	return XP_FIRST * pow(float(lv), XP_CURVE)

func req() -> float:
	return req_for(level)

## 현재 레벨의 진행도 0~1. 경험치 바가 읽는 값.
func progress() -> float:
	return clampf(xp / req(), 0.0, 1.0)

## 적 하나를 잡았다. 요구치를 넘으면 넘긴 만큼 다음 레벨로 이월된다 —
## 서지를 통째로 쓸어 한 번에 두세 레벨이 오르는 일이 실제로 일어난다.
## 경험치 배율의 출처. Main 이 망치의 stats 를 꽂아준다 ('성장의 축복' 카드).
## null 이면 배율 1.0 — 검증 스크립트처럼 망치가 없는 환경에서도 돌아야 한다.
var stats: Stats

func add_xp(amount: float) -> void:
	if amount <= 0.0:
		return
	if stats != null:
		amount *= stats.get_v(Stats.XP_GAIN)
	xp += amount
	total_xp += amount
	while xp >= req():
		xp -= req()
		level += 1
		leveled.emit(level)
