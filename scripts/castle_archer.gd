class_name CastleArcher
extends Node3D

## 성의 자동 사격 (유저 요청 2026-08-17). 성이 스스로 가장 가까운 적에게 쏜다.
##
## ⚠️ **표적 고르는 규칙을 처음부터 갈라뒀다.** 유저가 "나중에 가장 가까운/가장 강한/가장 먼
##    적 등 모드를 고르게 만들 것"이라고 했으므로, 지금은 NEAREST 하나만 쓰더라도
##    `Mode` 와 `_pick()` 을 분리해 둔다 — 모드를 늘릴 때 여기 한 곳만 고치면 된다.
##
## ⚠️ **화살 자체는 그리지 않는다** (유저 지시 2026-08-17). 날아가는 화살 메시는
##    이 카메라(직교·먼 거리)에서 몇 픽셀짜리 막대라 읽히지도 않는다. 대신 **하얀 궤적선**
##    한 줄로 쐈다는 사실만 알린다 (`scripts/arrow_tracer.gd`).
##
## ⚠️ **직선 + 즉발은 저격총이 된다** (유저 지적 2026-08-17). 궤적은 포물선이고, 도달까지
##    아주 짧은 비행 시간이 있다. 그래서 **피해는 화살이 닿는 순간**(`arrived` 시그널) 확정된다.
##    명중률은 여전히 100% 다 — 궤적선이 표적을 매 프레임 따라가므로 피하는 일이 없다.

enum Mode {
	NEAREST,      ## 가장 가까운 적
	STRONGEST,    ## 남은 체력이 가장 많은 적
	FARTHEST,     ## 사거리 안에서 가장 먼 적
}

@export var mode: Mode = Mode.NEAREST
@export var range_units := 42.0     ## 사거리
@export var interval := 0.9         ## 발사 간격(초)
## ⚠️ **러너(HP 50)를 한 방에 죽이는 게 이 값의 존재 이유다** (유저 지시 2026-08-17).
##    러너 체력을 바꾸면 여기도 같이 볼 것. grunt(100)는 두 방, heavy(220)는 네 방.
@export var damage := 60.0
## 활 자리 — 성 꼭대기 모서리에서 쏜다. 성 상자가 5×4×5 라 그 위쪽.
@export var muzzle := Vector3(0.0, 4.2, 0.0)

## 비행 시간. ⚠️ **미세해야 한다** — 길면 성이 곡사포가 되고 명중 타이밍이 뭉갠다.
## 사거리 42 유닛 끝에서도 0.26초다(눈으로는 "휙" 한 번).
const FLIGHT_MIN := 0.10
const FLIGHT_SPEED := 160.0   ## 유닛/초 — 이 값이 클수록 짧아진다

var _cd := 0.0

func _process(delta: float) -> void:
	_cd -= delta
	if _cd > 0.0:
		return
	var t := _pick()
	if t == null:
		return
	_cd = interval
	_shoot(t)

## 표적 고르기. 모드가 늘어도 여기만 손대면 된다.
func _pick() -> Enemy:
	var from := global_position + muzzle
	var best: Enemy = null
	var best_score := -1.0
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var e := node as Enemy
		if e == null or e.dying:
			continue
		var d := Vector2(e.global_position.x - from.x, e.global_position.z - from.z).length()
		if d > range_units:
			continue
		var score := 0.0
		match mode:
			Mode.NEAREST:
				score = range_units - d          # 가까울수록 높다
			Mode.STRONGEST:
				score = e.health
			Mode.FARTHEST:
				score = d
		if score > best_score:
			best_score = score
			best = e
	return best

func _shoot(target: Enemy) -> void:
	var from := global_position + muzzle
	var flight := maxf(FLIGHT_MIN, from.distance_to(target.global_position) / FLIGHT_SPEED)
	var tracer := ArrowTracer.shoot(get_parent(), from, target, flight)
	# 피해는 **닿는 순간**. 명중률 100% 라 빗나감은 없고, 날아가는 사이에 다른 것에 죽었을
	# 때만 그냥 지나간다(그 화살은 허공에 꽂힌 셈 — 죽은 놈을 또 때리진 않는다).
	tracer.arrived.connect(func() -> void:
		if is_instance_valid(target) and not target.dying:
			target.take_damage(damage, from))
