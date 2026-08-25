extends SceneTree
## 보스(거대 사슴벌레) 검증 — 스펙 항목별로.
## 주기 5s / 예고 0.8s / 돌진 3배속 / 풀차징 예고 가격 시 취소 + 1.5s 기절 / 기절 중 피해 +50%
## godot --headless --path . --script tools/verify_boss.gd

func _init() -> void:
	_run()

func _sname(s: int) -> String:
	return ["걷기", "예고", "돌진", "기절", "대기", "치켜듦"][s]

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var hs = main.get_node("HammerStrike")
	var bar = main.get_node("HUD/BossBar")
	main.set_physics_process(false)          # 웨이브 스폰 정지

	var boss = main.spawn_boss()
	boss.global_position = Vector3(30, 0, 0)
	await process_frame
	print("보스: 체력 %d  이동속도 %.2f (헤비 %.2f)  크기 %.0f (헤비 %.1f)  피격반경 %.1f" % [
		boss.stats.get_v(Stats.HEALTH), boss.stats.get_v(Stats.SPEED),
		3.5 * 0.6, boss.scale.x, 1.4, boss.hit_radius])
	print("주기 %.1fs / 예고 %.1fs / 돌진 %.1fs ×%.0f배속 / 기절 %.1fs (피해 ×%.1f)" % [
		Boss.CYCLE, Boss.TELEGRAPH, Boss.CHARGE_TIME, Boss.CHARGE_MULT,
		Boss.STUN_TIME, Boss.STUN_DAMAGE_MULT])
	print("")

	# --- 1) 사이클: 걷기 -> 예고 -> 돌진 ---
	print("1) 사이클 (거리 = 기지까지)")
	var prev := -1
	var t := 0.0
	var charge_start := Vector3.ZERO
	for i in 520:
		if boss.state != prev:
			var d: float = boss.global_position.distance_to(main.get_node("BaseBlock").global_position)
			print("   %5.2fs  %s  (기지까지 %.1f)" % [t, _sname(boss.state), d])
			if boss.state == Boss.State.CHARGE:
				charge_start = boss.global_position
			elif prev == Boss.State.CHARGE:
				var moved := charge_start.distance_to(boss.global_position)
				print("          -> 돌진 이동거리 %.1f (평소 %.1f 예상)" % [
					moved, boss.stats.get_v(Stats.SPEED) * Boss.CHARGE_TIME])
			prev = boss.state
		await physics_frame
		t += 1.0 / 60.0
		if t > 9.5:      # 걷기 5.0 + 예고 0.8 + 돌진 2.2 = 8.0 이 다 들어가야 한다
			break

	# --- 2) 예고 중이라도 스택이 안 차면 취소되지 않는다 ---
	print("")
	while boss.state != Boss.State.TELEGRAPH:
		await physics_frame
	var need := ceili(Boss.STUN_STACK_MAX / Boss.STACK_FULL)
	boss.on_hammer(1.0)
	print("2) 예고 중 풀차징 1대 -> 스택 %.0f/%.0f, 상태 %s (기대 예고 유지 — %d대 필요)" % [
		boss.stun_stack, Boss.STUN_STACK_MAX, _sname(boss.state), need])

	# --- 3) 스택이 차면 그 순간 취소 + 기절 ---
	for i in need - 1:
		boss.on_hammer(1.0)
	print("3) 예고 중 풀차징 %d대째 -> 스택 만충, 상태 %s (기대 기절 = 돌진 취소)" % [
		need, _sname(boss.state)])

	# --- 4) 기절 중 피해 +50% ---
	var hp0: float = boss.health
	boss.take_damage(100.0, Vector3.ZERO)
	var dealt_stun: float = hp0 - boss.health
	print("4) 기절 중 100 피해 -> 실제 %.0f 깎임 (기대 150)" % dealt_stun)

	# 기절이 풀리길 기다렸다가 같은 피해를 다시
	var waited := 0.0
	while boss.state == Boss.State.STUN and waited < 7.0:
		await physics_frame
		waited += 1.0 / 60.0
	print("   기절 지속 %.2fs (기대 %.1f), 해제 후 상태 %s, 면역 %.1fs" % [
		waited, Boss.STUN_TIME, _sname(boss.state), boss.stun_immune])
	var hp1: float = boss.health
	boss.take_damage(100.0, Vector3.ZERO)
	print("   기절 해제 후 100 피해 -> 실제 %.0f 깎임 (기대 100)" % (hp1 - boss.health))

	# --- 5) 큰 몸이라도 가장자리에서 맞는가 ---
	print("")
	boss.global_position = Vector3(60, 0, 0)
	await physics_frame
	var hp2: float = boss.health
	# 망치 반경 4.0 + 보스 피격반경 8.4 = 12.4 까지 닿아야 한다
	hs._damage_area(Vector3(71, 0, 0), 4.0, 100.0)      # 중심에서 11 떨어진 곳
	print("5) 중심에서 11 떨어진 곳 타격(반경 4) -> 피해 %s (기대 맞음: 4+8.4=12.4)" % [
		"들어감" if boss.health < hp2 else "안 들어감"])
	var hp3: float = boss.health
	hs._damage_area(Vector3(75, 0, 0), 4.0, 100.0)      # 중심에서 15 떨어진 곳
	print("   중심에서 15 떨어진 곳 -> 피해 %s (기대 안 맞음)" % [
		"들어감" if boss.health < hp3 else "안 들어감"])

	# --- 6) 체력 바 ---
	print("")
	bar._process(0.1)
	print("6) 보스 바 표시=%s (기대 true)" % bar.visible)
	boss.die()
	await process_frame
	bar._process(0.1)
	print("   보스 사망 후 표시=%s (기대 false)" % bar.visible)
	quit()
