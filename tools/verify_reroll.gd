extends SceneTree
## 다시 뽑기 검증: 횟수 제한 / 손패가 실제로 바뀌는가 / 드래프트마다 재충전 /
## 풀이 마르면 숨는가 / 영구 강화로 횟수를 올릴 수 있는가.
## godot --headless --path . --script tools/verify_reroll.gd
func _init() -> void: _run()
func ok(c: bool) -> String: return "OK" if c else "*** 실패 ***"
func ids(hand: Array) -> Array: return hand.map(func(c): return c.id)

## 등장 연출(어두워지는 동안)엔 선택·리롤이 막힌다 — 그게 풀릴 때까지 기다린다.
func wait_intro(ui) -> void:
	for i in 200:
		if not ui._intro:
			return
		await process_frame

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var ui = main.get_node("CardUI")

	ui.open_draft()
	await wait_intro(ui)
	print("[기본 1회]")
	print("  드래프트 열림, 남은 리롤=%d  버튼 보임=%s  %s" % [
		ui._rerolls_left, ui._reroll_btn.visible, ok(ui._rerolls_left == 1 and ui._reroll_btn.visible)])
	var before := ids(ui._hand)
	ui._reroll()
	await process_frame
	print("  손패 %s -> %s" % [before, ids(ui._hand)])
	print("  남은 리롤=%d  버튼 보임=%s (기대 0 / false)  %s" % [
		ui._rerolls_left, ui._reroll_btn.visible, ok(ui._rerolls_left == 0 and not ui._reroll_btn.visible)])
	ui._reroll()
	print("  소진 후 한 번 더 시도 -> 남은 리롤=%d (음수가 되면 안 된다)  %s" % [
		ui._rerolls_left, ok(ui._rerolls_left == 0)])

	# 다음 드래프트에서 다시 채워지는가
	ui._queued = 1
	ui._open = false
	ui.open_draft()
	await process_frame
	print("\n[드래프트마다 재충전]")
	print("  새 드래프트 남은 리롤=%d (기대 1)  %s" % [ui._rerolls_left, ok(ui._rerolls_left == 1)])

	# 영구 강화 자리
	ui._queued = 1
	ui._open = false
	ui.rerolls_per_draft = 3
	ui.open_draft()
	await process_frame
	print("\n[영구 강화로 +2 했다고 가정]")
	print("  rerolls_per_draft=3 -> 남은 리롤=%d  %s" % [ui._rerolls_left, ok(ui._rerolls_left == 3)])

	# 리롤은 등장 보장을 무시하는가 — 첫 선택(picked 비어 있음)에서 확인한다.
	print("\n[리롤은 보장 무시]")
	ui.picked.clear()
	ui._queued = 1
	ui._open = false
	ui.rerolls_per_draft = 40
	ui.open_draft()
	await wait_intro(ui)
	var first_has := ids(ui._hand).any(func(i): return CardCatalog.by_id(i).cat == "공격 패턴")
	print("  최초 손패에 공격 패턴 있음=%s (보장이라 항상 true)  %s" % [first_has, ok(first_has)])
	var without := 0
	for i in 30:
		ui._rerolls_left = 40
		ui._reroll()
		if not ids(ui._hand).any(func(x): return CardCatalog.by_id(x).cat == "공격 패턴"):
			without += 1
	print("  리롤 30회 중 공격 패턴이 **없는** 손패 %d회 (0이면 보장이 아직 걸려 있다)  %s" % [
		without, ok(without > 0)])

	# 풀이 마르면 숨는가
	print("\n[풀 고갈]")
	for c in CardCatalog.CARDS:
		if c.repeat:
			for i in int(c.max_stacks):
				ui.picked.append(c.id)
	ui._queued = 1
	ui._open = false
	ui.open_draft()
	await process_frame
	print("  후보 %d개 / 손패 %d장 -> 리롤 가능=%s 버튼 보임=%s (기대 false)  %s" % [
		ui._pool().size(), ui._hand.size(), ui._can_reroll(), ui._reroll_btn.visible,
		ok(not ui._can_reroll() and not ui._reroll_btn.visible)])
	quit()
