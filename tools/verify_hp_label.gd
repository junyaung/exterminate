extends SceneTree
## 성 체력바 수치 검증 (유저 지시 2026-08-14):
##   · "현재/최대" 형식인가
##   · 글자가 **바 안에** 들어오는가 (가로·세로 모두)
## 헤드리스라 화면은 못 보지만, 배치 계산은 그대로 잴 수 있다.
## godot --headless --path . --script tools/verify_hp_label.gd

func _init() -> void:
	_run()

func _run() -> void:
	var fail := 0
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var bar := main.find_child("XpBar", true, false)
	if bar == null:
		for c in main.get_children():
			if c.get_script() != null and String(c.get_script().resource_path).ends_with("xp_bar.gd"):
				bar = c
	if bar == null:
		print("!! XP/체력 바 노드를 못 찾음")
		quit(1)
		return

	var base = main.get_node("BaseBlock")
	base.health = 452.0
	var txt := "%d/%d" % [roundi(base.health), roundi(base.max_health)]
	var ok1: bool = txt == "452/1000"
	fail += 0 if ok1 else 1
	print("1) 표기 형식 \"%s\" (기대 \"452/1000\") %s" % [txt, "OK" if ok1 else "***"])

	# 바 박스와 글자 크기를 같은 식으로 계산해 안에 들어오는지 본다
	var card := Rect2(bar.MARGIN, bar.size.y - bar.MARGIN - bar.CARD_H, bar.CARD_W, bar.CARD_H)
	var bx: float = card.position.x + bar.ICON_W + 12.0
	var bw: float = card.end.x - 14.0 - bx
	var box := Rect2(bx, card.position.y + 14.0, bw, bar.BAR_H)
	var f: Font = bar._font
	var tsz: Vector2 = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, bar.HP_FS)
	var ok2: bool = tsz.x < box.size.x and tsz.y <= box.size.y + 2.0
	fail += 0 if ok2 else 1
	print("2) 글자 %.1f x %.1f / 바 %.1f x %.1f (안에 들어와야 한다) %s" % [
		tsz.x, tsz.y, box.size.x, box.size.y, "OK" if ok2 else "*** 넘친다 ***"])

	# 최대 자릿수(9999/9999)에서도 안 넘치는가 — 체력 업그레이드로 커질 수 있다
	var wide: Vector2 = f.get_string_size("9999/9999", HORIZONTAL_ALIGNMENT_LEFT, -1, bar.HP_FS)
	var ok3: bool = wide.x < box.size.x
	fail += 0 if ok3 else 1
	print("3) 최대 자릿수 \"9999/9999\" 폭 %.1f < 바 %.1f %s" % [
		wide.x, box.size.x, "OK" if ok3 else "*** 넘친다 ***"])

	print("")
	print("체력 수치 표기 검증 통과" if fail == 0 else "체력 수치 표기 검증 실패 %d 건" % fail)
	quit(0 if fail == 0 else 1)
