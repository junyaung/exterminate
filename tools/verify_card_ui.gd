extends SceneTree
## 카드 UI 입력 검증. 핵심은 **카드 어느 지점을 눌러도 반응하는가** —
## 리본/아이콘(윗절반)이 이벤트를 가로채면 아래쪽 글씨 부분만 먹힌다.
## godot --headless --path . --script tools/verify_card_ui.gd

func _init() -> void:
	_run()

## 패널 안에서 마우스를 실제로 받는 노드를 찾는다 (자식이 위에 있으므로 자식 우선).
func _blocker(node: Control, local: Vector2) -> Control:
	var found: Control = null
	for c in node.get_children():
		if c is Control:
			var ctl := c as Control
			if ctl.mouse_filter != Control.MOUSE_FILTER_IGNORE \
					and Rect2(ctl.position, ctl.size).has_point(local):
				found = ctl
			var deeper := _blocker(ctl, local - ctl.position)
			if deeper != null:
				found = deeper
	return found

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var ui = main.get_node("CardUI")
	ui.open_draft()
	await process_frame
	await process_frame

	var row = ui._row
	print("카드 %d장" % row.get_child_count())
	var slot: Control = row.get_child(0)
	var panel: Control = slot.get_child(0)
	print("슬롯 mouse_filter=%d (2=IGNORE)  패널 mouse_filter=%d (0=STOP)" % [
		slot.mouse_filter, panel.mouse_filter])
	print("")

	# 카드 세로 5구간을 훑어 이벤트를 가로채는 자식이 있는지 본다
	print("카드 안 세로 위치별로 패널보다 먼저 마우스를 먹는 자식:")
	var bad := 0
	for f in [0.08, 0.25, 0.45, 0.7, 0.92]:
		var local := Vector2(panel.size.x * 0.5, panel.size.y * f)
		var b := _blocker(panel, local)
		var name_s := "없음 (패널이 받음)" if b == null else "%s <- 가로챔!" % b.get_class()
		if b != null:
			bad += 1
		print("  세로 %3d%%  %s" % [int(f * 100), name_s])
	print("")
	print("가로채는 자식 %d 개 (기대 0)" % bad)

	# 호버 발광이 스타일박스에 실제로 걸리는지
	var sb: StyleBoxFlat = panel.get_theme_stylebox("panel")
	print("")
	print("호버 전: shadow %s size=%d offset=%s" % [
		sb.shadow_color.to_html(false), sb.shadow_size, sb.shadow_offset])
	panel.mouse_entered.emit()
	await create_timer(0.2).timeout
	print("호버 중: shadow %s size=%d offset=%s  (금색 #fdd179 로 번져야 함)" % [
		sb.shadow_color.to_html(false), sb.shadow_size, sb.shadow_offset])
	print("         패널 scale=%.2f rotation=%.3f (커지고 반듯해짐)" % [
		panel.scale.x, panel.rotation])
	panel.mouse_exited.emit()
	await create_timer(0.2).timeout
	print("호버 후: shadow %s size=%d  scale=%.2f (원래대로)" % [
		sb.shadow_color.to_html(false), sb.shadow_size, panel.scale.x])

	# 윗쪽(아이콘 자리)을 클릭했을 때 실제로 선택되는지
	print("")
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	panel.gui_input.emit(ev)
	await process_frame
	print("카드 윗부분 클릭 -> picked=%s  화면 닫힘=%s (기대 1장 / true)" % [
		ui.picked, not ui._open])
	quit()
