extends SceneTree
## 새 카드 7종 검증 (유저 스펙 2026-08-13).
## godot --headless --path . --script tools/verify_newcards.gd
func _init() -> void: _run()
func ok(c: bool) -> String: return "OK" if c else "*** 실패 ***"
func near(a: float, b: float) -> bool: return absf(a - b) < 0.01

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var hs = main.get_node("HammerStrike")

	print("[카탈로그]")
	for c in CardCatalog.CARDS:
		var kind := "stat" if c.has("stat") else ("stats" if c.has("stats") \
			else ("counter" if c.has("counter") else "flag"))
		print("  %-11s %-9s %-6s %-13s 최대 %s" % [c.id, c.cat, c.rarity, kind,
			c.max_stacks if c.has("max_stacks") else 1])

	# --- 담금질: 평타 전용 ---
	var n0: float = hs.strike_damage(0.0)
	var c0: float = hs.strike_damage(1.0)
	var s0: float = hs.stats.get_v(Stats.DAMAGE) * hs.special_damage_mult
	hs.stats.add_pct(Stats.DAMAGE_NORMAL, 0.20)
	print("\n[담금질] 평타 피해 +20% — 차징·우클릭은 그대로여야")
	print("  평타 %.0f->%.0f (+20%%)  %s" % [n0, hs.strike_damage(0.0),
		ok(near(hs.strike_damage(0.0), n0 * 1.2))])
	print("  차징 %.0f->%.0f  우클릭 %.0f->%.0f (둘 다 그대로)  %s" % [
		c0, hs.strike_damage(1.0), s0, hs.stats.get_v(Stats.DAMAGE) * hs.special_damage_mult,
		ok(near(hs.strike_damage(1.0), c0)
			and near(hs.stats.get_v(Stats.DAMAGE) * hs.special_damage_mult, s0))])

	# --- 거인의 힘: 세 공격 전부 ---
	n0 = hs.strike_damage(0.0)
	c0 = hs.strike_damage(1.0)
	s0 = hs.stats.get_v(Stats.DAMAGE) * hs.special_damage_mult
	hs.stats.add_pct(Stats.DAMAGE, 0.10)
	print("\n[거인의 힘] 직접 피해 +10%")
	print("  평타 %.0f->%.0f  차징 %.0f->%.0f  우클릭 %.0f->%.0f  %s" % [
		n0, hs.strike_damage(0.0), c0, hs.strike_damage(1.0),
		s0, hs.stats.get_v(Stats.DAMAGE) * hs.special_damage_mult,
		ok(near(hs.strike_damage(0.0), n0 * 1.10) and near(hs.strike_damage(1.0), c0 * 1.10)
			and near(hs.stats.get_v(Stats.DAMAGE) * hs.special_damage_mult, s0 * 1.10))])

	# --- 확장된 권능: 직격만, 2차는 제외 ---
	var rn: float = hs.strike_radius(0.0)
	var rc: float = hs.strike_radius(1.0)
	var rs: float = hs.special_radius()
	var r2: float = hs.secondary_radius(0.0)
	hs.stats.add_pct(Stats.RADIUS_ALL, 0.10)
	print("\n[확장된 권능] 직격 반경 +10% / 2차는 그대로")
	print("  평타 %.2f->%.2f  차징 %.2f->%.2f  %s" % [rn, hs.strike_radius(0.0),
		rc, hs.strike_radius(1.0),
		ok(near(hs.strike_radius(0.0), rn * 1.1) and near(hs.strike_radius(1.0), rc * 1.1))])
	print("  우클릭 직격 %.2f->%.2f  %s" % [
		rs, hs.special_radius(), ok(near(hs.special_radius(), rs * 1.1))])
	print("  2차(여진) 반경 %.2f->%.2f (그대로여야)  %s" % [
		r2, hs.secondary_radius(0.0), ok(near(hs.secondary_radius(0.0), r2))])

	# --- 넓은 울림이 우클릭에 새지 않는가 (기존 버그) ---
	var before: float = hs.special_radius()
	hs.stats.add_pct(Stats.RADIUS, 0.15)
	print("\n[넓은 울림(평타 전용)이 우클릭에 새는가]")
	print("  우클릭 직격 %.2f -> %.2f (그대로여야)  %s" % [
		before, hs.special_radius(), ok(near(hs.special_radius(), before))])

	# --- 천벌의 주기 ---
	var cd0: float = hs.stats.get_v(Stats.COOLDOWN_SPECIAL)
	for i in 3:
		hs.stats.add_pct(Stats.COOLDOWN_SPECIAL, -0.12)
	print("\n[천벌의 주기] 쿨 -12% ×3")
	print("  %.2f -> %.2f (기대 %.2f)  %s" % [cd0, hs.stats.get_v(Stats.COOLDOWN_SPECIAL),
		cd0 * 0.64, ok(near(hs.stats.get_v(Stats.COOLDOWN_SPECIAL), cd0 * 0.64))])

	# --- 신속한 천벌: 예고 시간이 스택당 0.2초씩 (고정값) ---
	# 카탈로그에 적힌 값을 그대로 읽어 검사한다 — 수치를 테스트에 복사해두면 카드를 고칠 때
	# 한쪽만 바뀌어 검사가 거짓 통과한다.
	var sd := CardCatalog.by_id(&"swift_doom")
	print("\n[신속한 천벌] 착탄 대기시간 %.1f초 ×%d" % [sd.flat, sd.max_stacks])
	var base_tg: float = hs.telegraph_time()
	var tg_ok := true
	for i in int(sd.max_stacks):
		hs.stats.add_flat(Stats.TELEGRAPH_SPECIAL, sd.flat)
		var want: float = base_tg + sd.flat * float(i + 1)
		var got: float = hs.telegraph_time()
		if not near(got, want):
			tg_ok = false
		print("  %d스택 -> %.1f초 (기대 %.1f)" % [i + 1, got, want])
	print("  전 구간 일치  %s" % ok(tg_ok))
	# 총 연출이 쿨타임보다 길면 이전 망치가 아직 타는 중에 다음 발이 나간다.
	# ⚠️ 실패가 아니다 — 망치는 각각 별도 노드라 동작은 정상이고, 화면에 두 개가 겹칠 뿐이다.
	#    다만 '신속한 천벌'과 '천벌의 주기'를 같이 쌓으면 이 상황이 실제로 나오므로 수치를 남긴다.
	var total: float = hs.telegraph_time() + hs.special_slam_time \
		+ hs.special_linger + hs.special_evaporate
	var cd: float = hs.stats.get_v(Stats.COOLDOWN_SPECIAL)
	print("  총 연출 = 예고 %.1f + 낙하 %.2f + 유지 %.1f + 소각 %.1f = %.2f초 / 쿨 %.1f -> %s" % [
		hs.telegraph_time(), hs.special_slam_time, hs.special_linger, hs.special_evaporate,
		total, cd, "겹침 없음" if total <= cd else "%.2f초 겹침 (망치 2개 동시 표시)" % (total - cd)])
	for i in int(sd.max_stacks):
		hs.stats.add_flat(Stats.TELEGRAPH_SPECIAL, -sd.flat)   # 뒤 검사에 영향 없게 되돌린다

	# --- 몰아치는 신격 ---
	print("\n[몰아치는 신격] 레벨별 스택/배율")
	for lv in [1, 2, 3]:
		hs.combo_level = lv
		var line := "  L%d 최대 %d스택:" % [lv, hs.combo_max()]
		for st in range(hs.combo_max() + 1):
			hs._combo = st
			line += " %d->+%d%%" % [st, roundi((hs.combo_mult() - 1.0) * 100.0)]
		print(line)
	hs.combo_level = 1
	hs._combo = 3
	print("  L1 3스택 -> 평타 배율 %.2f (기대 1.18)  %s" % [
		hs.combo_mult(), ok(near(hs.combo_mult(), 1.18))])
	hs._combo = 0
	hs._tally_normal_hit(true, false)
	print("  명중 -> 스택 %d, 남은시간 %.1f  %s" % [hs._combo, hs._combo_left,
		ok(hs._combo == 1 and near(hs._combo_left, hs.combo_window))])
	hs._tally_normal_hit(false, false)
	print("  빗나감 -> 스택 %d (즉시 0)  %s" % [hs._combo, ok(hs._combo == 0)])

	# --- 파괴의 박자 ---
	print("\n[파괴의 박자]")
	hs.has_beat = true
	hs._beat = 0
	var seq := []
	for i in 5:
		var b: bool = hs.is_beat_strike(0.0)
		seq.append("대강타" if b else "평타(%d)" % hs._beat)
		hs._tally_normal_hit(true, b)
	print("  연속 명중 5회: %s  %s" % [seq, ok(seq[3] == "대강타" and seq[4] == "평타(0)")])
	hs._beat = 3
	hs._tally_normal_hit(false, true)
	print("  대강타가 빗나감 -> 카운터 %d (3 유지, 다음도 대강타)  %s" % [
		hs._beat, ok(hs._beat == 3 and hs.is_beat_strike(0.0))])
	print("  차징은 대강타가 안 된다: %s  %s" % [
		hs.is_beat_strike(1.0), ok(not hs.is_beat_strike(1.0))])

	# --- 메아리 모디파이어: 실제 낙하까지 (예전 '천벌의 메아리' 카드를 대체) ---
	print("\n[메아리 모디파이어]")
	var em: Array[StringName] = [&"echo"]
	hs.active_mods = em
	hs.has_beat = false
	hs.combo_level = 0
	var target := Vector3(6, 0, 6)
	# 메아리가 성 안에 찍히면 밖으로 밀리는가
	var base := main.get_node("BaseBlock") as Node3D
	var inside: Vector3 = base.global_position
	var fixed: Vector3 = hs._clamp_to_arena(inside)
	var away: float = Vector2(fixed.x - base.global_position.x,
		fixed.z - base.global_position.z).length()
	print("  성 중심에 찍힌 좌표를 보정 -> 성에서 %.2f 만큼 밀려남 (반폭 %.1f 이상)  %s" % [
		away, Enemy.PILL_BASE_HALF, ok(away >= Enemy.PILL_BASE_HALF)])

	hs._special_cd = 0.0
	hs._special_active = false
	hs._special_strike(target)
	await create_timer(hs.telegraph_time() + hs.special_slam_time + 0.05).timeout
	var main_only := 0
	for c in hs.get_children():
		if c is Node3D and c.name == "EchoHammer":
			main_only += 1
	print("  본체 착탄 직후 메아리 %d개 (아직 0 — %.1f초 뒤에 온다)  %s" % [
		main_only, hs.echo_gap, ok(main_only == 0)])
	await create_timer(hs.echo_gap + hs.special_slam_time + 0.1).timeout
	# ⚠️ 노드 개수만 세면 안 된다 — 원본 망치가 visible=false 라 복제본이 **보이지 않는 채로**
	#    떨어져도 개수는 1 이 나온다 (실제로 그렇게 버그를 놓쳤다). 보이는지까지 확인한다.
	var echoes := 0
	var shown := 0
	var dist := 0.0
	# ⚠️ 노드 위치는 **그립**이다. 망치가 15도 기울어 꽂히므로 그립과 촉(=실제 착탄점)이
	#    수평으로 최대 sin(15°)×길이 만큼 어긋난다 — 그립으로 재면 거리가 3유닛까지 틀린다.
	#    verify_special 과 같은 방식으로 촉을 역산해서 잰다.
	var es: float = hs.hammer_scale * hs.radius_scale() * hs.special_scale_mult
	for c in hs.get_children():
		if c is Node3D and c.name == "EchoHammer":
			echoes += 1
			var node := c as Node3D
			if node.visible:
				shown += 1
			var tip: Vector3 = node.global_position \
				+ node.basis.orthonormalized() * (Vector3.UP * HammerStrike.HEAD_TIP_Y * es)
			dist = Vector2(tip.x - target.x, tip.z - target.z).length()
	# 거리는 성 보정(_clamp_to_arena)이 밀어낼 수 있으므로 하한만 검사한다.
	# 망치 반폭(모델 0.361 × 스케일)보다 멀어야 두 망치가 따로 읽힌다.
	var half: float = 0.361 * hs.hammer_scale * hs.radius_scale() * hs.special_scale_mult
	print("  %.1f초 뒤 메아리 %d개(보이는 것 %d개), 본체에서 %.1f 유닛 (설정 %.1f~%.1f)  %s" % [
		hs.echo_gap, echoes, shown, dist, hs.echo_dist_min, hs.echo_dist_max,
		ok(echoes == 1 and shown == 1 and dist >= hs.echo_dist_min - 0.01)])
	print("  망치 반폭 %.2f -> 겹침 %.1f 유닛 (최소 거리 %.1f 기준)  %s" % [
		half, maxf(0.0, half * 2.0 - hs.echo_dist_min), hs.echo_dist_min,
		ok(hs.echo_dist_min > half)])
	print("  메아리 1장 = 1발, 세기 60%%, 낙하 시차 %.2f초 (2장이면 2발)" % hs.echo_gap)
	quit()
