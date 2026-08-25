extends SceneTree

## 20분 런 자동 시뮬레이션 — 봇이 쿨다운마다 "가장 밀집한 지점"에 망치를 휘두른다.
## 봇은 조준이 거의 완벽하므로 결과는 숙련 플레이어의 상한선으로 읽을 것.
##
## 실행:  godot --headless --path . -s tools/sim_run.gd
## 출력:  표준출력 30초 버킷 곡선 + tools/sim_result.csv

const TIME_SCALE := 10.0
const BUCKET := 30.0
const HEADER := "t     act  kills  spawned  leak_hp  alive  heavy  base_hp"

## 버킷 한 줄. 루프 도중에도, 마지막 정리에서도 같은 서식을 쓴다.
func _print_row(r: Dictionary) -> void:
	print("%4ds  %d    %5d  %7d  %7d  %5d  %5d  %7d" % [
		r.t, r.act, r.kills, r.spawned, r.leak, r.alive, r.heavy, r.hp])

## 가상 업그레이드 스케줄 — 아직 없는 업그레이드 시스템의 성장 곡선 가정.
## 1차 시뮬(업그레이드 없음)은 9:24 에 패배했다: 맨몸 처리 상한 ≈ 9킬/초.
## 이 스케줄로 승리가 나오면, 이 수치가 업그레이드 시스템의 밸런스 목표치다.
const UPG_INTERVAL := 120.0   ## 2분마다 한 번
const UPG_RADIUS_PCT := 0.08  ## 반경 +8%p (20분 = 10회 → ×1.8 = 반경 7.2)
const UPG_COOLDOWN_PCT := -0.05  ## 쿨다운 -5%p (10회 → ×0.5 = 0.325s)

## 사람 흉내 핸디캡. 2차 시뮬(완벽 봇 + 반경10%/쿨6%)은 누수 0 완승 = 과잉.
const AIM_JITTER := 1.0       ## 조준 오차 (유닛). 1.5 는 반경 4의 37% — 과도했다 (3차 시뮬 7:13 패배)
const REACT_MIN := 0.08       ## 쿨다운이 돌아온 뒤 클릭까지 걸리는 시간
const REACT_MAX := 0.25

## 카드 보유 여부 — 투사체 효율을 재려면 켜야 한다.
const WITH_AFTERSHOCK := true
const WITH_FIRE := true

var _ready := false
var _ready_at := 0.0
var _pending_ratio := 0.0
var _taps := 0
var _charges := 0
# 타격 지점 주변 국소 적 밀도 (투사체가 "맞을 적이 있었는가"의 근거)
var _dens_samples := 0
var _dens_sum := 0.0
var _dens_max := 0

func _init() -> void:
	_run()

func _run() -> void:
	Engine.time_scale = TIME_SCALE
	Engine.max_physics_steps_per_frame = 32   # time_scale 배속에서 물리 틱이 잘리지 않게

	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	root.add_child(main)
	await process_frame
	await process_frame
	var hs := main.get_node("HammerStrike") as HammerStrike
	hs.has_aftershock = WITH_AFTERSHOCK
	hs.has_fire = WITH_FIRE
	ProjectileStats.reset()

	var rows: Array[Dictionary] = []
	var last_bucket := 0
	var prev := {kills = 0, spawned = 0, hp = 0.0}
	prev.hp = main.get_node("BaseBlock").health

	print("SIM start: time_scale=%s  base_hp=%d" % [TIME_SCALE, roundi(prev.hp)])
	# ⚠️ 예전엔 모든 행을 rows 에 쌓아뒀다가 **끝나고 한 번에** 찍었다. 20분 런이 오래 걸리는
	#    환경에서는 중간에 아무것도 못 보고, 도중에 끊으면 데이터가 통째로 날아간다
	#    (2026-08-14: 30분을 돌리고도 결과를 못 건졌다). 버킷마다 바로 찍는다 —
	#    끊어도 그때까지의 곡선은 남는다.
	print(HEADER)

	var next_upg := UPG_INTERVAL
	while not main.game_over and main.elapsed < Main.RUN_LENGTH + 120.0:
		await process_frame
		# --- 가상 업그레이드: 2분마다 반경/쿨감 ---
		while main.elapsed >= next_upg:
			hs.stats.add_pct(Stats.RADIUS, UPG_RADIUS_PCT)
			hs.stats.add_pct(Stats.COOLDOWN, UPG_COOLDOWN_PCT)
			print("UPGRADE @%ds  radius=%.2f  cooldown=%.3f" % [
				int(next_upg), hs.stats.get_v(Stats.RADIUS), hs.stats.get_v(Stats.COOLDOWN)])
			next_upg += UPG_INTERVAL
		# --- 봇: 쿨다운 회복 -> (필요하면 차징) -> 오차 있는 조준으로 스윙 ---
		if hs._cd <= 0.0:
			if not _ready:
				_ready = true
				# 정책: 평타와 풀차징의 "초당 처치량"을 비교해 큰 쪽을 고른다.
				# 평타는 잡졸만 즉사(무거운 적은 3방), 차징은 반경 2배로 전부 즉사.
				_pending_ratio = _choose_ratio(hs)
				var hold: float = hs.charge_max_time if _pending_ratio > 0.0 else 0.0
				_ready_at = main.elapsed + randf_range(REACT_MIN, REACT_MAX) + hold
			elif main.elapsed >= _ready_at:
				var target := _best_cluster(hs, _pending_ratio)
				if target != Vector3.INF:
					target += Vector3(randf_range(-AIM_JITTER, AIM_JITTER), 0.0,
						randf_range(-AIM_JITTER, AIM_JITTER))
					# 타격 지점 반경 7(투사체 산개 범위) 안의 적 수 — 국소 밀도
					var near := 0
					for e in get_nodes_in_group("enemies"):
						var dd: Vector3 = e.global_position - target
						dd.y = 0.0
						if dd.length() <= 7.0:
							near += 1
					_dens_samples += 1
					_dens_sum += float(near)
					_dens_max = maxi(_dens_max, near)
					hs._strike(target, _pending_ratio)
					if _pending_ratio > 0.0: _charges += 1
					else: _taps += 1
					_ready = false
		# --- 30초 버킷 기록 ---
		var b := int(main.elapsed / BUCKET)
		if b != last_bucket:
			var row := _snapshot(main, last_bucket, prev)
			rows.append(row)
			_print_row(row)      # ⚠️ 즉시 찍는다 — 아래 참조
			last_bucket = b

	var last_row := _snapshot(main, last_bucket, prev)
	rows.append(last_row)
	_print_row(last_row)

	# --- 출력 ---
	var csv := "t_sec,act,kills,spawned,leak_hp,alive_end,base_hp\n"
	for r in rows:
		csv += "%d,%d,%d,%d,%d,%d,%d\n" % [r.t, r.act, r.kills, r.spawned, r.leak, r.alive, r.hp]
	var f := FileAccess.open("res://tools/sim_result.csv", FileAccess.WRITE)
	f.store_string(csv)
	f.close()

	var base: BaseBlock = main.get_node("BaseBlock")
	print("SWINGS taps=%d  charges=%d (%.0f%% 차징)" % [
		_taps, _charges, 100.0 * _charges / maxi(_taps + _charges, 1)])
	print("DENSITY 타격 지점 반경 7 안의 적: 평균 %.1f마리  최대 %d마리 (표본 %d회)" % [
		_dens_sum / maxf(float(_dens_samples), 1.0), _dens_max, _dens_samples])
	print(ProjectileStats.report())
	print("RESULT %s  elapsed=%ds  kills=%d  spawned=%d  suppressed=%d  base=%d/%d" % [
		"VICTORY" if main.victory else ("DEFEAT" if main.game_over else "TIMEOUT"),
		int(main.elapsed), main.kills, main.spawned, main.suppressed,
		roundi(base.health), roundi(base.max_health)])
	quit()

## 완료된 버킷 하나의 스냅샷 (kills/spawned/누수는 버킷 내 증가분).
func _snapshot(main: Main, bucket: int, prev: Dictionary) -> Dictionary:
	var base: BaseBlock = main.get_node("BaseBlock")
	var row := {
		t = bucket * int(BUCKET),
		act = clampi(bucket * int(BUCKET) / int(Main.ACT_LENGTH), 0, 3) + 1,
		kills = main.kills - prev.kills,
		spawned = main.spawned - prev.spawned,
		leak = roundi(prev.hp - base.health),
		alive = main.alive_count(),
		heavy = _heavy_alive(),
		hp = roundi(base.health),
	}
	prev.kills = main.kills
	prev.spawned = main.spawned
	prev.hp = base.health
	return row

func _heavy_alive() -> int:
	var n := 0
	for e in get_nodes_in_group("enemies"):
		if e.type_id == &"heavy":
			n += 1
	return n

## 평타 vs 풀차징 중 초당 처치량이 큰 쪽의 ratio 를 돌려준다.
func _choose_ratio(hs) -> float:
	var pts: Array = []
	for e in get_nodes_in_group("enemies"):
		pts.append({p = e.global_position, h = e.type_id != &"grunt"})
	if pts.is_empty():
		return 0.0
	var r: float = hs.stats.get_v(Stats.RADIUS)
	var rc: float = r * hs.charge_radius_mult
	var react := (REACT_MIN + REACT_MAX) * 0.5
	var cd: float = hs.stats.get_v(Stats.COOLDOWN)
	var best_tap := 0.0
	var best_chg := 0.0
	for i in mini(24, pts.size()):
		var c: Vector3 = pts[randi() % pts.size()].p
		var n_tap := 0    # 평타 반경 안의 잡졸 (즉사하는 것만)
		var n_chg := 0    # 차징 반경 안의 전부 (잡졸·무거운 적 모두 즉사)
		for q in pts:
			var d: Vector3 = q.p - c
			d.y = 0.0
			var dist := d.length()
			if dist <= rc:
				n_chg += 1
				if dist <= r and not q.h:
					n_tap += 1
		best_tap = maxf(best_tap, n_tap / (cd + react))
		best_chg = maxf(best_chg, n_chg / (cd + react + hs.charge_max_time))
	return 1.0 if best_chg > best_tap else 0.0

## 살아있는 적 중 표본 24마리를 후보로, 반경 내 "위협 가중치 합"이 최대인 위치를 고른다.
## 단순 밀집도만 보면 기지에 붙은 놈을 방치하게 된다 — 실제 플레이어는 기지를 지킨다.
func _best_cluster(hs: HammerStrike, ratio := 0.0) -> Vector3:
	var pts: Array = []
	for e in get_nodes_in_group("enemies"):
		pts.append({p = e.global_position, w = _threat(e)})
	if pts.is_empty():
		return Vector3.INF
	var r2: float = pow(hs.stats.get_v(Stats.RADIUS) * lerpf(1.0, hs.charge_radius_mult, ratio), 2.0)
	var best: Vector3 = pts[0].p
	var best_score := -1.0
	for i in mini(24, pts.size()):
		var cand: Vector3 = pts[randi() % pts.size()].p
		var score := 0.0
		for q in pts:
			var d: Vector3 = q.p - cand
			d.y = 0.0
			if d.length_squared() <= r2:
				score += q.w
		if score > best_score:
			best_score = score
			best = cand
	return best

## 기지에 가까울수록 위협적이다.
func _threat(e) -> float:
	if e.target == null:
		return 1.0
	var d: Vector3 = e.global_position - e.target.global_position
	d.y = 0.0
	return 1.0 + 4.0 * clampf(1.0 - d.length() / 30.0, 0.0, 1.0)
