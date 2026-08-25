extends SceneTree
## 카드 시스템 검증: 최대 중첩 / 평타·차징 스탯 분리 / 범위 카드가 차징에 안 새는가 / 경험치 배율.
## godot --headless --path . --script tools/verify_cards.gd
func _init() -> void: _run()

func ok(c: bool) -> String: return "OK" if c else "*** 실패 ***"

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var ui = main.get_node("CardUI")
	var hs = main.get_node("HammerStrike")

	print("[카탈로그]")
	for c in CardCatalog.CARDS:
		print("  %-12s %-8s 최대중첩=%s" % [c.id, c.rarity,
			c.max_stacks if c.has("max_stacks") else "1 (flag)"])

	print("\n[기본값]")
	print("  평타 쿨=%.2f  차징 쿨=%.2f  차징시간=%.2f  평타범위=%.2f  풀차징범위=%.2f  풀차징피해=%.0f" % [
		hs.stats.get_v(Stats.COOLDOWN), hs.stats.get_v(Stats.COOLDOWN_CHARGED),
		hs.charge_time(), hs.strike_radius(0.0), hs.strike_radius(1.0), hs.strike_damage(1.0)])

	# --- 넓은 울림 ×3: 평타 범위만 올라야 한다 ---
	var r0n: float = hs.strike_radius(0.0)
	var r0c: float = hs.strike_radius(1.0)
	for i in 3:
		hs.stats.add_pct(Stats.RADIUS, 0.15)
	print("\n[넓은 울림 ×3]")
	print("  평타 범위 %.2f -> %.2f (기대 +45%%)  %s" % [r0n, hs.strike_radius(0.0),
		ok(is_equal_approx(snappedf(hs.strike_radius(0.0), 0.01), snappedf(r0n * 1.45, 0.01)))])
	print("  풀차징 범위 %.2f -> %.2f (기대 그대로)  %s" % [r0c, hs.strike_radius(1.0),
		ok(is_equal_approx(hs.strike_radius(1.0), r0c))])

	# --- 신속한 강타 ×5: 평타 쿨만 ---
	var c0: float = hs.stats.get_v(Stats.COOLDOWN)
	var cc0: float = hs.stats.get_v(Stats.COOLDOWN_CHARGED)
	for i in 5:
		hs.stats.add_pct(Stats.COOLDOWN, -0.10)
	print("\n[신속한 강타 ×5]")
	print("  평타 쿨 %.3f -> %.3f (기대 -50%%)  %s" % [c0, hs.stats.get_v(Stats.COOLDOWN),
		ok(is_equal_approx(hs.stats.get_v(Stats.COOLDOWN), c0 * 0.5))])
	print("  차징 쿨 %.3f -> %.3f (기대 그대로)  %s" % [cc0, hs.stats.get_v(Stats.COOLDOWN_CHARGED),
		ok(is_equal_approx(hs.stats.get_v(Stats.COOLDOWN_CHARGED), cc0))])

	# --- 응축 ×4 / 과충전 ×3 ---
	var t0: float = hs.charge_time()
	for i in 4:
		hs.stats.add_pct(Stats.CHARGE_TIME, -0.20)
	var d0: float = hs.strike_damage(1.0)
	var cr0: float = hs.strike_radius(1.0)
	for i in 3:
		hs.stats.add_pct(Stats.CHARGE_DAMAGE, 0.30)
		hs.stats.add_pct(Stats.CHARGE_RADIUS, 0.10)
	print("\n[응축 ×4 / 과충전 ×3]")
	print("  차징시간 %.2f -> %.2f (데드존 %.2f 아래로는 안 내려간다)" % [
		t0, hs.charge_time(), hs.charge_deadzone])
	print("  풀차징 피해 %.0f -> %.0f (기대 +90%%)  %s" % [d0, hs.strike_damage(1.0),
		ok(is_equal_approx(hs.strike_damage(1.0), d0 * 1.9))])
	print("  풀차징 범위 %.2f -> %.2f (기대 +30%%)  %s" % [cr0, hs.strike_radius(1.0),
		ok(is_equal_approx(hs.strike_radius(1.0), cr0 * 1.3))])
	print("  평타 피해는 그대로여야: %.0f  %s" % [hs.strike_damage(0.0),
		ok(is_equal_approx(hs.strike_damage(0.0), hs.stats.get_v(Stats.DAMAGE)))])

	# --- 성장의 축복 ---
	print("\n[성장의 축복 ×2]")
	main.level_system.total_xp = 0.0
	main.level_system.add_xp(100.0)
	var base_gain: float = main.level_system.total_xp
	hs.stats.add_pct(Stats.XP_GAIN, 0.25)
	hs.stats.add_pct(Stats.XP_GAIN, 0.25)
	main.level_system.total_xp = 0.0
	main.level_system.add_xp(100.0)
	print("  경험치 100 -> %.0f 였다가 %.0f (기대 150)  %s" % [
		base_gain, main.level_system.total_xp,
		ok(is_equal_approx(main.level_system.total_xp, 150.0))])

	# --- 최대 중첩: 풀에서 빠지는가 ---
	print("\n[최대 중첩 소진]")
	for c in CardCatalog.CARDS:
		if c.repeat:
			for i in int(c.max_stacks):
				ui.picked.append(c.id)
	var pool = ui._pool()
	# ⚠️ 개수를 박아두지 말 것 — 카드가 늘 때마다 이 검사가 깨진다 (실제로 깨졌다).
	#    "반복 카드가 다 빠지고 flag 카드만 남는다" 를 카탈로그에서 세어 확인한다.
	var flag_total := 0
	for c in CardCatalog.CARDS:
		if not c.repeat:
			flag_total += 1
	print("  반복 카드를 전부 채운 뒤 풀: %s (flag %d장만 남아야 한다)  %s" % [
		pool.map(func(c): return c.id), flag_total, ok(pool.size() == flag_total)])
	quit()
