extends SceneTree
## '신의 억제' / '전쟁의 부름' 검증 — 스폰량 배율과 배타 규칙.
## godot --headless --path . --script tools/verify_spawn_cards.gd
func _init() -> void: _run()
func ok(c: bool) -> String: return "OK" if c else "*** 실패 ***"
func near(a: float, b: float) -> bool: return absf(a - b) < 0.001

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var hs = main.get_node("HammerStrike")
	var ui = main.get_node("CardUI")
	main.set_physics_process(false)
	main.elapsed = 30.0                      # 액트 1 안쪽

	var base: float = main.current_rate()
	print("기본 초당 스폰 %.2f마리 (액트 %d, 경과 %.0f초)" % [
		base, main.act_index() + 1, main.elapsed])

	print("\n[전쟁의 부름] 스택별 초당 스폰")
	for i in 5:
		hs.stats.add_pct(Stats.SPAWN_RATE, 0.10)
		var want: float = base * (1.0 + 0.1 * float(i + 1))
		print("  %d스택 (+%d%%) -> %.2f마리 (기대 %.2f)  %s" % [
			i + 1, (i + 1) * 10, main.current_rate(), want,
			ok(near(main.current_rate(), want))])

	# 스펙의 예시: 기본 4마리 × 1.3 = 5.2
	print("\n[스펙 예시 검산] 기본 4마리 × 전쟁의 부름 3스택")
	var s2 := Stats.new({Stats.SPAWN_RATE: 1.0})
	for i in 3:
		s2.add_pct(Stats.SPAWN_RATE, 0.10)
	print("  4.00 × %.2f = %.2f마리 (기대 5.20)  %s" % [
		s2.get_v(Stats.SPAWN_RATE), 4.0 * s2.get_v(Stats.SPAWN_RATE),
		ok(near(4.0 * s2.get_v(Stats.SPAWN_RATE), 5.2))])

	# 상쇄: 배타 규칙을 걷어내도 수식이 성립하는가 (스탯 자체는 가산)
	print("\n[상쇄 수식] 전쟁 3스택 + 억제 1스택")
	var s3 := Stats.new({Stats.SPAWN_RATE: 1.0})
	for i in 3:
		s3.add_pct(Stats.SPAWN_RATE, 0.10)
	s3.add_pct(Stats.SPAWN_RATE, -0.10)
	print("  배율 %.2f (기대 1.20 = +30%% -10%%)  %s" % [
		s3.get_v(Stats.SPAWN_RATE), ok(near(s3.get_v(Stats.SPAWN_RATE), 1.2))])

	print("\n[배타 규칙]")
	var ids: Array = ui._pool().map(func(c): return c.id)
	print("  아무것도 안 골랐을 때 둘 다 등장: %s / %s  %s" % [
		&"restraint" in ids, &"warcry" in ids,
		ok(&"restraint" in ids and &"warcry" in ids)])
	ui.picked.append(&"warcry")
	ids = ui._pool().map(func(c): return c.id)
	print("  전쟁의 부름을 고른 뒤 -> 전쟁=%s 억제=%s (억제가 빠져야)  %s" % [
		&"warcry" in ids, &"restraint" in ids,
		ok(&"warcry" in ids and not (&"restraint" in ids))])
	# 5스택까지 채우면 자기 자신도 빠진다
	for i in 4:
		ui.picked.append(&"warcry")
	ids = ui._pool().map(func(c): return c.id)
	print("  5스택 소진 -> 전쟁=%s 억제=%s (둘 다 빠져야)  %s" % [
		&"warcry" in ids, &"restraint" in ids,
		ok(not (&"warcry" in ids) and not (&"restraint" in ids))])
	quit()
