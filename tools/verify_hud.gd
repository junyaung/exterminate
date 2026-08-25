extends SceneTree
## HUD 개편 검증 (UX 가이드 1~4번 적용분).
##   모듈 존재 / 마우스 통과(사각지대 금지) / 카드가 읽는 값 / Status 라벨 축소 / 보스바 상수
## godot --headless --path . --script tools/verify_hud.gd
func _init() -> void: _run()
func ok(c: bool) -> String: return "OK" if c else "*** 실패 ***"

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var hud = main.get_node("HUD")
	var modules: HudModules = null
	for c in hud.get_children():
		if c is HudModules:
			modules = c
	print("[구조]")
	print("  HudModules 생성=%s  %s" % [modules != null, ok(modules != null)])
	print("  마우스 통과=%s (안 하면 공격 사각지대)  %s" % [
		modules.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		ok(modules.mouse_filter == Control.MOUSE_FILTER_IGNORE)])
	var xp = hud.get_node("XpBar")
	print("  좌하단 카드(XpBar) 마우스 통과  %s" % ok(xp.mouse_filter == Control.MOUSE_FILTER_IGNORE))

	print("\n[Status 라벨 — 개발용만 남았는가]")
	main.elapsed = 12.0
	main._physics_process(0.0)   # HUD 갱신 경로
	var txt: String = main._hud.text
	var clean := not ("BASE" in txt) and not ("SWARM" in txt) and not ("LV" in txt)
	print("  BASE/SWARM/LV 텍스트 제거=%s  %s" % [clean, ok(clean)])

	print("\n[좌하단 카드 값]")
	main._base.health = 640.0
	xp._process(10.0)            # 큰 delta 로 표시값을 목표까지 끌어온다
	print("  거점 체력 표시값 %.2f (기대 0.64)  %s" % [xp._hp_shown,
		ok(absf(xp._hp_shown - 0.64) < 0.02)])
	main.level_system.xp = LevelSystem.req_for(1) * 0.5
	xp._process(10.0)
	print("  경험치 표시값 %.2f (기대 0.50)  %s" % [xp._shown,
		ok(absf(xp._shown - 0.5) < 0.02)])

	print("\n[보스 바 슬림]")
	print("  폭 비율 %.0f%% (기대 40%%)  %s" % [(1.0 - BossBar.SIDE * 2.0) * 100.0,
		ok(absf(1.0 - BossBar.SIDE * 2.0 - 0.4) < 0.001)])
	print("  높이 %.0f (22 미만)  %s" % [BossBar.H, ok(BossBar.H < 22.0)])
	quit()
