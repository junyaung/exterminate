extends SceneTree

## 짧은 진단 시뮬 — **불 속성만 든 상태**(여진 없음)에서 폭연이 실제로 몇 마리를 죽이는지.
## sim_run.gd 의 봇 정책을 그대로 쓰되 액트 1 앞부분만 돌린다.
## 실행: godot --headless --path . --script tools/sim_deflag.gd

const RUN_SECONDS := 90.0    ## 게임 내 시간
const TIME_SCALE := 1.0   ## --fixed-fps 로 실시간 동기화를 끄므로 배속이 불필요하다
const AIM_JITTER := 1.0
const REACT_MIN := 0.08
const REACT_MAX := 0.25

var _ready_flag := false
var _ready_at := 0.0
var _pending_ratio := 0.0
var _taps := 0
var _charges := 0

func _init() -> void:
	_run()

func _run() -> void:
	Engine.time_scale = TIME_SCALE
	Engine.max_physics_steps_per_frame = 32

	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	root.add_child(main)
	await process_frame
	await process_frame
	var hs := main.get_node("HammerStrike") as HammerStrike
	hs.has_fire = true          # 첫 카드로 불만 뽑은 상황
	hs.has_aftershock = false
	ProjectileStats.reset()

	print("불 속성 단독 / 여진 없음 / 업그레이드 없음 — %d초 시뮬" % RUN_SECONDS)
	print("폭연: 평타 %d구, 피해 %d (스윙의 %d%%), 반경 %.2f, 퓨즈 %.1fs" % [
		hs.deflag_count, roundi(hs.strike_damage(0.0) * hs.deflag_damage),
		hs.deflag_damage * 100.0, hs.stats.get_v(Stats.RADIUS) * hs.deflag_radius,
		Deflagration.DELAY])
	print("")

	# ⚠️ 중간 집계를 반드시 찍는다. 끝에서만 출력하면 오래 걸려 중단했을 때 아무것도 안 남는다.
	print("게임시간  총처치  폭연터짐  폭연처치  폭연실피해  생존")
	var next_report := 10.0

	while not main.game_over and main.elapsed < RUN_SECONDS:
		await process_frame
		if main.elapsed >= next_report:
			next_report += 10.0
			var r: Dictionary = ProjectileStats._d.get(&"blast", {})
			print("  %3ds  %7d  %8d  %8d  %10d  %5d" % [
				int(main.elapsed), main.kills, r.get("spawned", 0), r.get("kills", 0),
				roundi(r.get("damage", 0.0)), main.alive_count()])
		if hs._cd <= 0.0:
			if not _ready_flag:
				_ready_flag = true
				_pending_ratio = _choose_ratio(hs)
				var hold: float = hs.charge_max_time if _pending_ratio > 0.0 else 0.0
				_ready_at = main.elapsed + randf_range(REACT_MIN, REACT_MAX) + hold
			elif main.elapsed >= _ready_at:
				var target := _best_cluster(hs, _pending_ratio)
				if target != Vector3.INF:
					target += Vector3(randf_range(-AIM_JITTER, AIM_JITTER), 0.0,
						randf_range(-AIM_JITTER, AIM_JITTER))
					hs._strike(target, _pending_ratio)
					if _pending_ratio > 0.0: _charges += 1
					else: _taps += 1
					_ready_flag = false

	var row: Dictionary = ProjectileStats._d.get(&"blast", {})
	var blast_kills: int = row.get("kills", 0)
	var blast_spawned: int = row.get("spawned", 0)
	print("경과 %ds  총 처치 %d  스폰 %d  기지 %d/%d" % [
		int(main.elapsed), main.kills, main.spawned,
		roundi(main.get_node("BaseBlock").health),
		roundi(main.get_node("BaseBlock").max_health)])
	print("스윙 평타 %d / 차징 %d" % [_taps, _charges])
	print(ProjectileStats.report())
	print("── 폭연 결산 ──────────────────────────────")
	print("  터진 수 %d  |  폭연이 직접 죽인 적 %d 마리" % [blast_spawned, blast_kills])
	print("  전체 처치 중 폭연 기여: %.1f%%" % [
		100.0 * float(blast_kills) / maxf(float(main.kills), 1.0)])
	print("  폭연 1구당 처치 %.2f 마리" % [
		float(blast_kills) / maxf(float(blast_spawned), 1.0)])
	quit()

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
		var n_tap := 0
		var n_chg := 0
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

func _threat(e) -> float:
	if e.target == null:
		return 1.0
	var d: Vector3 = e.global_position - e.target.global_position
	d.y = 0.0
	return 1.0 + 4.0 * clampf(1.0 - d.length() / 30.0, 0.0, 1.0)
