extends SceneTree
## 카드 보관함 검증: 소지 목록(중첩은 합쳐짐) / Tab 창 목록 / 일시정지.
## 경험치 바 위 띠는 제거됐으므로(2026-08-13) 띠 타일 수·클릭 차단 검사도 함께 뺐다.
## godot --headless --path . --script tools/verify_shelf.gd

func _init() -> void:
	_run()

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var ui = main.get_node("CardUI")
	var shelf = main.get_node("CardShelf")
	main.set_physics_process(false)

	print("시작: 소지 %d종 (기대 0)" % shelf._owned().size())

	# 카드를 먹은 것처럼 만든다 — 담금질 3장(중첩), 여진 1장
	for id in [&"damage", &"damage", &"aftershock", &"damage"]:
		ui.picked.append(id)
		ui.card_picked.emit(id)
	await process_frame
	print("4장 획득(담금질×3, 여진×1) -> 소지 %d종 (기대 2 — 중첩은 합쳐짐)"
		% shelf._owned().size())

	var owned = shelf._owned()
	for row in owned:
		print("   %-10s ×%d  (%s)" % [row.card.cname, row.count, row.card.rarity])

	# Tab 창
	print("")
	print("Tab 전: 열림=%s paused=%s" % [shelf._open, paused])
	shelf._show()
	await process_frame
	print("Tab 후: 열림=%s paused=%s  목록 %d줄 (기대 2)" % [
		shelf._open, paused, shelf._list.get_child_count()])
	shelf._close()
	await process_frame
	print("닫은 뒤: 열림=%s paused=%s" % [shelf._open, paused])

	# 드래프트가 열려 있으면 Tab 은 무시되어야 한다 (pause 다툼 방지)
	ui.open_draft()
	await process_frame
	var ev := InputEventKey.new()
	ev.keycode = KEY_TAB
	ev.pressed = true
	shelf._unhandled_input(ev)
	print("")
	print("드래프트 중 Tab: 보관함 열림=%s (기대 false), 드래프트 열림=%s (기대 true)" % [
		shelf._open, ui._open])
	quit()
