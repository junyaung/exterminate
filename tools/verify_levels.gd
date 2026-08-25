extends SceneTree
## 처치 -> 경험치 -> 레벨업 -> 카드 드래프트 연결 검증 + 액트별 레벨 도달 예측.
## godot --headless --path . --script tools/verify_levels.gd

func _run_checks() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var ls = main.level_system
	var ui = main.get_node("CardUI")

	print("요구 경험치 곡선 (잡졸 1 / 러너 1 / 헤비 3)")
	var cum := 0.0
	for lv in range(1, 13):
		cum += LevelSystem.req_for(lv)
		print("  LV %2d -> %2d :  %6.0f   (누적 %7.0f)" % [
			lv, lv + 1, LevelSystem.req_for(lv), cum])

	print("")
	var need := int(ls.req())
	print("1) 잡졸 ", need - 1, "마리 처치 (요구치 ", need, " 직전) -> ")
	for i in need - 1:
		ls.add_xp(Enemy.xp_of(&"grunt"))
	print("   LV ", ls.level, " XP ", ls.xp, "/", ls.req(), " 카드열림=", ui._open,
		" (기대 LV1, 안 열림)")

	print("2) 한 마리 더 -> ")
	ls.add_xp(Enemy.xp_of(&"grunt"))
	print("   즉시: 카드열림=", ui._open, " paused=", paused,
		" (기대 false — 죽는 장면을 보여주려고 %.1f초 늦춘다)" % CardUI.DRAFT_DELAY)
	await create_timer(CardUI.DRAFT_DELAY + 0.2).timeout
	print("   LV ", ls.level, " 카드열림=", ui._open, " paused=", paused,
		" 대기열=", ui._queued, " (기대 LV2 / 열림 / paused)")
	print("   손패: ", ui._hand.map(func(c): return c.cname))

	# 고른다 -> 닫히고 대기열이 비면 다시 안 열린다
	ui._pick(0)
	await process_frame
	print("3) 1장 선택 후: 열림=", ui._open, " paused=", paused, " 대기열=", ui._queued,
		" picked=", ui.picked)

	# 서지를 통째로 쓸어 여러 레벨이 한 번에 오르는 상황
	print("")
	print("4) 헤비 60마리(경험치 180) 한꺼번에 처치 —")
	var before: int = ls.level
	for i in 60:
		ls.add_xp(Enemy.xp_of(&"heavy"))
	await create_timer(CardUI.DRAFT_DELAY + 0.2).timeout
	print("   LV ", before, " -> ", ls.level, " 대기열=", ui._queued,
		" 열림=", ui._open, " (레벨 오른 만큼 쌓여야 함)")
	var picks := 0
	while ui._queued > 0 and picks < 20:
		ui._pick(0)
		await process_frame
		await process_frame
		picks += 1
	print("   ", picks, "장 연속 선택 후: 대기열=", ui._queued, " 열림=", ui._open,
		" paused=", paused, " (기대 0 / false / false)")
	print("   최종 picked=", ui.picked.size(), "장, LV ", ls.level)

	print("")
	print("5) 스탯 반영: 피해 ", main.get_node("HammerStrike").stats.get_v(Stats.DAMAGE),
		" 반경 ", main.get_node("HammerStrike").stats.get_v(Stats.RADIUS))
	quit()

func _init() -> void:
	_run_checks()
