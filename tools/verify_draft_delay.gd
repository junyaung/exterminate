extends SceneTree
## 카드 창이 뜨는 시점 검증. 헤드리스는 실시간보다 빨리 도므로 **트리 타이머 기준**으로만 잰다.
##   1) 폭연 없음        -> DRAFT_DELAY 지나면 열려 있어야 한다
##   2) 폭연이 부푸는 중  -> 퓨즈가 끝나기 전엔 닫혀 있어야 하고, 터진 뒤 열려야 한다
## godot --headless --path . --script tools/verify_draft_delay.gd
func _init() -> void: _run()

func wait(t: float) -> void:
	await create_timer(t).timeout

func ok(cond: bool) -> String:
	return "OK" if cond else "*** 실패 ***"

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var ui = main.get_node("CardUI")
	print("DRAFT_DELAY=%.2f  MAX=%.2f  폭연 퓨즈=%.2f\n" % [
		CardUI.DRAFT_DELAY, CardUI.DRAFT_DELAY_MAX, Deflagration.DELAY])

	# --- 1) 폭연 없음 ---
	main.level_system.leveled.emit(2)
	await wait(CardUI.DRAFT_DELAY * 0.4)
	print("폭연없음 | %.2f초: 열림=%s  %s" % [CardUI.DRAFT_DELAY * 0.4, ui._open, ok(not ui._open)])
	await wait(CardUI.DRAFT_DELAY * 1.2)
	print("폭연없음 | %.2f초: 열림=%s  %s" % [CardUI.DRAFT_DELAY * 1.6, ui._open, ok(ui._open)])

	# 다음 케이스를 위해 완전히 초기화 (대기열이 남으면 닫자마자 다시 열린다)
	ui._queued = 0
	ui._open = false
	ui._root.visible = false
	paused = false
	await process_frame

	# --- 2) 폭연이 부푸는 중 ---
	Deflagration.detonate(main, Vector3(5, 0, 5), 3.0, 10.0, 1.0)
	main.level_system.leveled.emit(3)
	await wait(CardUI.DRAFT_DELAY * 1.6)
	print("폭연중   | %.2f초: 열림=%s  대기중인폭연=%d  %s" % [CardUI.DRAFT_DELAY * 1.6,
		ui._open, get_nodes_in_group(Deflagration.BLAST_PENDING).size(),
		ok(not ui._open)])
	await wait(Deflagration.DELAY)
	print("폭연중   | %.2f초: 열림=%s  대기중인폭연=%d  %s" % [
		CardUI.DRAFT_DELAY * 1.6 + Deflagration.DELAY, ui._open,
		get_nodes_in_group(Deflagration.BLAST_PENDING).size(), ok(ui._open)])
	quit()
