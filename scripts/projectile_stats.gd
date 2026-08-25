class_name ProjectileStats
extends RefCounted

## 바위·불덩이의 **생성 대비 실효** 추적기.
## 많이 만들어지는데 실제로 맞는 게 적으면 탄도/착지 배치 메커니즘의 문제다.
## 순수 정적 카운터 — 노드도 오토로드도 아니라 아무 데서나 부를 수 있다.
##
## damage 는 **실제로 깎인 체력**만 센다. 남은 체력보다 큰 피해는 wasted(과잉)로 따로 빼는데,
## 이게 크면 "안 맞는" 게 아니라 "필요 이상으로 세게 때리는" 낭비라는 뜻이라 처방이 다르다.

static var _d := {}

static func _row(id: StringName) -> Dictionary:
	if not _d.has(id):
		_d[id] = {
			spawned = 0,    ## 만들어진 수
			landed = 0,     ## 착지해서 판정까지 간 수
			hit_any = 0,    ## 한 마리라도 맞힌 수
			hits = 0,       ## 맞힌 적 연인원
			damage = 0.0,   ## 실제로 깎인 체력
			wasted = 0.0,   ## 남은 체력을 넘긴 과잉 피해
			kills = 0,
		}
	return _d[id]

static func spawned(id: StringName) -> void:
	_row(id).spawned += 1

static func landed(id: StringName, hits: int, damage: float, wasted: float, kills: int) -> void:
	var r := _row(id)
	r.landed += 1
	r.hits += hits
	r.damage += damage
	r.wasted += wasted
	r.kills += kills
	if hits > 0:
		r.hit_any += 1

static func reset() -> void:
	_d.clear()

static func has(id: StringName) -> bool:
	return _d.has(id) and _d[id].spawned > 0

## HUD 한 줄. 예: "ROCK 32발 명중 41% 피해 1450 (45/발)"
static func line(id: StringName, label: String) -> String:
	if not has(id):
		return ""
	var r: Dictionary = _d[id]
	var per: float = r.damage / maxf(float(r.spawned), 1.0)
	return "%s %d발  명중 %d%%  피해 %d (%d/발)" % [
		label, r.spawned,
		roundi(100.0 * float(r.hit_any) / maxf(float(r.spawned), 1.0)),
		roundi(r.damage), roundi(per)]

## 콘솔 상세 리포트.
static func report() -> String:
	if _d.is_empty():
		return "[stats] 아직 기록 없음"
	var out := "\n[stats] 투사체 효율 ─────────────────────────────\n"
	out += "        생성  착지  명중  헛방  적중연인원  실피해  과잉  처치\n"
	for id in _d:
		var r: Dictionary = _d[id]
		out += "  %-6s %4d  %4d  %4d  %4d  %9d  %6d  %5d  %4d\n" % [
			id, r.spawned, r.landed, r.hit_any, r.landed - r.hit_any,
			r.hits, roundi(r.damage), roundi(r.wasted), r.kills]
	out += "\n"
	for id in _d:
		var r: Dictionary = _d[id]
		var sp: float = maxf(float(r.spawned), 1.0)
		out += "  %s: 명중률 %.0f%% | 발당 적 %.2f마리 | 발당 실피해 %.1f | 과잉비율 %.0f%%\n" % [
			id,
			100.0 * float(r.hit_any) / sp,
			float(r.hits) / sp,
			r.damage / sp,
			100.0 * r.wasted / maxf(r.damage + r.wasted, 1.0)]
	out += "\n  읽는 법: 명중률이 낮으면 흩뿌리는 범위/거리가 적 분포와 안 맞는 것.\n"
	out += "           발당 적 수가 1 미만이면 반경이 좁거나 착지가 흩어지는 것.\n"
	out += "           과잉비율이 높으면 개당 피해가 과한 것(반경을 넓히는 게 이득).\n"
	return out
