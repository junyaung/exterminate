extends SceneTree
## 카드 창 등장 연출 검증.
##   1) 어둠막이 즉시 100% 가 아니라 서서히 짙어지는가
##   2) 연출 중에는 클릭/키가 **먹히지 않는가** (연타 중 사고 선택 방지)
##   3) 연출 + 여유가 끝나면 정상 동작하는가
## godot --headless --path . --script tools/verify_draft_intro.gd
func _init() -> void: _run()
func ok(c: bool) -> String: return "OK" if c else "*** 실패 ***"

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	# ⚠️ 씬 로드에 걸린 시간이 **첫 process 프레임의 delta 에 통째로 실린다.** 그대로 열면
	#    그 한 프레임에 트윈이 0.24초어치 점프해서 페이드가 이미 끝난 것처럼 측정된다.
	#    실제 게임(60fps)에선 안 생기는 헤드리스 전용 함정이라, 프레임을 몇 개 흘려보낸다.
	for i in 8:
		await process_frame
	await create_timer(0.1, true, false, true).timeout
	var ui = main.get_node("CardUI")
	print("등장 시간=%.2f초  이후 무시 여유=%.2f초  (합 %.2f초)  창 뜨기까지 기본 틈=%.2f초" % [
		CardUI.DRAFT_INTRO, CardUI.DRAFT_GRACE,
		CardUI.DRAFT_INTRO + CardUI.DRAFT_GRACE, CardUI.DRAFT_DELAY])

	ui.open_draft()
	print("\n[연출 시작]")
	print("  어둠막 투명도 %.2f (0 에서 시작해야 서서히 어두워진다)  %s" % [
		ui._root.modulate.a, ok(is_equal_approx(ui._root.modulate.a, 0.0))])
	print("  일시정지=%s (어두워짐과 동시에)  %s" % [paused, ok(paused)])

	# 연출 도중 클릭 — 사고 선택이 나면 안 된다
	var picked_before: int = ui.picked.size()
	ui._pick(0)
	print("  연출 중 카드 클릭 -> 고른 카드 %d장 (그대로 %d장이어야)  %s" % [
		ui.picked.size(), picked_before, ok(ui.picked.size() == picked_before)])
	var rr: int = ui._rerolls_left
	ui._reroll()
	print("  연출 중 리롤 -> 남은 리롤 %d (그대로 %d 여야)  %s" % [
		ui._rerolls_left, rr, ok(ui._rerolls_left == rr)])

	# 중반: 어둠막이 짙어지는 중, 아직 잠겨 있어야
	await create_timer(CardUI.DRAFT_INTRO * 0.5, true, false, true).timeout
	print("\n[연출 중반]")
	print("  어둠막 %.2f (0 과 1 사이여야)  %s" % [
		ui._root.modulate.a, ok(ui._root.modulate.a > 0.0 and ui._root.modulate.a < 1.0)])
	ui._pick(0)
	print("  아직 클릭 무시 -> 고른 카드 %d장  %s" % [
		ui.picked.size(), ok(ui.picked.size() == picked_before)])

	# 연출 + 여유가 끝난 뒤
	await create_timer(CardUI.DRAFT_INTRO + CardUI.DRAFT_GRACE, true, false, true).timeout
	print("\n[연출 종료]")
	print("  어둠막 %.2f (1.0)  %s" % [ui._root.modulate.a, ok(is_equal_approx(ui._root.modulate.a, 1.0))])
	print("  잠금 해제=%s  %s" % [not ui._intro, ok(not ui._intro)])
	ui._pick(0)
	print("  이제 클릭이 먹힌다 -> 고른 카드 %d장 (1장 늘어야)  %s" % [
		ui.picked.size(), ok(ui.picked.size() == picked_before + 1)])
	quit()
