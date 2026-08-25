extends SceneTree
## 폭연(combust) 연출을 **프레임 단위로** 뜯어본다 — 장수풍뎅이 한 마리 기준.
## 확인하는 것:
##   1) 몸통 말고 **다른 오브젝트가 붙지 않는가** (불 막대기 같은 것)
##   2) 파트 6개가 전부 달아오르는가 (heat 0 -> 1)
##   3) 부풀고 흔들리는가 (pivot scale/position)
## godot --headless --path . --script tools/verify_combust.gd

func _init() -> void:
	_run()

func _child_count(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		c += 1 + _child_count(ch)
	return c

func _run() -> void:
	var fail := 0
	var scene := load("res://scenes/enemy.tscn") as PackedScene
	var e: Enemy = scene.instantiate()
	e.type_id = &"heavy"
	root.add_child(e)
	await process_frame

	var pivot := e.get_node("VisualPivot") as Node3D
	var before := _child_count(pivot)
	var t := 1.0
	e.combust(t)
	await process_frame
	var after := _child_count(pivot)
	var ok1: bool = after == before
	fail += 0 if ok1 else 1
	print("1) 폭연이 붙인 추가 오브젝트 %d개 (기대 0 — 벌레 몸통만 부푼다) %s" % [
		after - before, "OK" if ok1 else "*** 뭔가 더 붙는다 ***"])

	# 파트별 heat 를 프레임마다 읽는다. p³ 곡선이라 후반에 몰아쳐야 한다.
	var parts: Array[MeshInstance3D] = []
	for pname in e.RHINO_PARTS:
		var mi := (e._mesh as Node3D).find_child(String(pname), true, false) as MeshInstance3D
		if mi != null:
			parts.append(mi)
	print("")
	print("프레임   진행   heat   부푼정도  흔들림x   흔들림z")
	# ⚠️ 트윈을 실시간으로 흘려보내면 헤드리스 프레임레이트에 따라 곡선의 앞부분만 돈다
	#    (1초짜리 연출인데 0.2초만 진행돼 heat 가 0.01 에서 끝났다 — 1차 실측).
	#    pause 하고 custom_step 으로 **정확히 같은 간격씩** 밀어야 프레임 단위 검수가 된다.
	var tw: Tween = e._die_tw
	tw.pause()
	var heat_seen: Array[float] = []
	var steps := 12
	var dt := t / float(steps)
	for i in steps:
		if i > 0:
			tw.custom_step(dt)
		var h := -1.0
		var m := parts[0].get_surface_override_material(0) as ShaderMaterial
		if m != null:
			h = m.get_shader_parameter("heat")
		heat_seen.append(h)
		print("  f%-5d %5.2f  %5.2f   x%.3f   %+.3f   %+.3f" % [
			i, float(i) / float(steps), h, pivot.scale.y, pivot.position.x, pivot.position.z])

	# 모든 파트가 같은 heat 를 받는가 (한 파트만 달아오르면 색이 갈린다)
	var mismatch: Array[String] = []
	var ref := -1.0
	for mi in parts:
		var m2 := mi.get_surface_override_material(0) as ShaderMaterial
		if m2 == null:
			mismatch.append(mi.name + "(머티리얼 없음)")
			continue
		var hv: float = m2.get_shader_parameter("heat")
		if ref < 0.0:
			ref = hv
		elif not is_equal_approx(hv, ref):
			mismatch.append("%s(%.2f≠%.2f)" % [mi.name, hv, ref])
	var ok2: bool = mismatch.is_empty() and ref > 0.0
	fail += 0 if ok2 else 1
	print("")
	print("2) 파트 %d개 heat=%.2f, 불일치 %s %s" % [
		parts.size(), ref, mismatch if not mismatch.is_empty() else "없음",
		"OK" if ok2 else "*** 색변화가 안 걸린 파트가 있다 ***"])

	var ok3: bool = heat_seen[-1] > heat_seen[0]
	fail += 0 if ok3 else 1
	print("3) heat 가 %.2f -> %.2f 로 올라간다 %s" % [
		heat_seen[0], heat_seen[-1], "OK" if ok3 else "*** 안 달아오른다 ***"])

	print("")
	print("폭연 검증 통과" if fail == 0 else "폭연 검증 실패 %d 건" % fail)
	quit(0 if fail == 0 else 1)
