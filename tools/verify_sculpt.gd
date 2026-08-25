extends SceneTree
## 지형 스컬프트 툴 검증 — 손으로 못 재는 것만 잰다.
##   1) 판 자리가 실제로 낮아지고, 붓 중심이 가장 깊다 (가장자리는 얕게 = 경사가 생긴다)
##   2) 붓 밖은 안 건드린다
##   3) 채우기(우클릭)로 되돌아온다
##   4) 저장 -> 불러오기로 같은 지형이 살아난다
##   5) 메시가 실제로 그 높이로 다시 구워진다 (화면에 반영)
##   6) 초기화하면 절차 생성 상태로 돌아간다
## godot --headless --path . --script tools/verify_sculpt.gd

func _init() -> void:
	_run()

func _mesh_y_near(g: Ground, at: Vector3, r: float) -> float:
	## 메시 정점 중 at 근처의 가장 낮은 y — 실제로 구워진 지오메트리를 본다.
	var arrays := (g.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var lo := 999.0
	for v in verts:
		if Vector2(v.x - at.x, v.z - at.z).length() <= r:
			lo = minf(lo, v.y)
	return lo

func _run() -> void:
	var fail := 0
	# ⚠️ 이 검증은 save_edits() 를 부르므로 **실제 지형 파일을 덮어쓴다.**
	#    (한 번 그렇게 만들어 둔 지형을 날렸다.) 먼저 원본을 들고 있다가 끝나면 되돌린다.
	var backup := ""
	if FileAccess.file_exists(Ground.EDIT_PATH):
		backup = FileAccess.open(Ground.EDIT_PATH, FileAccess.READ).get_as_text()
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var g := main.get_node("Ground") as Ground
	var ed := main.get_node("TerrainEditor") as TerrainEditor
	var ok_ed: bool = ed != null
	g.clear_edits()

	var at := Vector3(50.0, 0.0, -50.0)      # 전투 지역 밖
	var before := g.height_at(at)

	# --- 1) 판다 ---
	for i in 20:
		g.sculpt(at, 14.0, -0.45)             # 붓질 20번 = 대략 9유닛
	var center := g.height_at(at)
	var edge := g.height_at(at + Vector3(11.0, 0.0, 0.0))
	var ok1: bool = center < before - 5.0 and edge > center + 1.0
	fail += 0 if ok1 else 1
	print("1) 판 뒤 중심 %.2f / 가장자리 %.2f (판 깊이 %.2f, 경사가 생겨야) %s" % [
		center, edge, before - center, "OK" if ok1 else "***"])

	# --- 2) 붓 밖은 그대로 ---
	var far := at + Vector3(30.0, 0.0, 0.0)
	var far_h := g.height_at(far)
	var ok2: bool = absf(far_h - g.edit_at(far)) < 0.001 and absf(g.edit_at(far)) < 0.001
	fail += 0 if ok2 else 1
	print("2) 붓 밖(30유닛) 깎인 값 %.4f (기대 0) %s" % [
		g.edit_at(far), "OK" if ok2 else "***"])

	# --- 3) 채우면 되돌아온다 ---
	for i in 20:
		g.sculpt(at, 14.0, 0.45)
	var back := g.height_at(at)
	var ok3: bool = absf(back - before) < 0.01
	fail += 0 if ok3 else 1
	print("3) 같은 횟수로 채운 뒤 %.3f (원래 %.3f) %s" % [
		back, before, "OK" if ok3 else "***"])

	# --- 4) 저장 -> 불러오기 ---
	for i in 20:
		g.sculpt(at, 14.0, -0.45)
	var dug := g.height_at(at)
	g.save_edits()
	g.clear_edits()
	var cleared := g.height_at(at)
	g.load_edits()
	var loaded := g.height_at(at)
	var ok4: bool = absf(cleared - before) < 0.01 and absf(loaded - dug) < 0.05
	fail += 0 if ok4 else 1
	print("4) 저장 %.2f -> 지움 %.2f -> 불러옴 %.2f %s" % [
		dug, cleared, loaded, "OK" if ok4 else "***"])

	# --- 5) 메시에 반영되는가 ---
	g.build()
	var my := _mesh_y_near(g, at, 6.0)
	var ok5: bool = my < before - 4.0
	fail += 0 if ok5 else 1
	print("5) 다시 구운 메시의 최저 정점 %.2f (판 높이 %.2f 부근이어야) %s" % [
		my, dug, "OK" if ok5 else "***"])

	# --- 6) 초기화 ---
	g.clear_edits()
	g.build()
	var my2 := _mesh_y_near(g, at, 6.0)
	var ok6: bool = absf(my2) < 1.0 and ok_ed
	fail += 0 if ok6 else 1
	print("6) 초기화 뒤 메시 최저 정점 %.2f, 에디터 노드=%s %s" % [
		my2, ok_ed, "OK" if ok6 else "***"])

	# --- 7) 계단 + 절벽이 실제 지오메트리로 생기는가 ---
	# (유저 지적: 부드러운 언덕은 직교+셀 조합에서 높이차가 안 읽힌다 -> 수직 벽이 필요)
	for i in 30:
		g.sculpt(Vector3(50.0, 0.0, -50.0), 16.0, -0.5)
	g.build()
	var arrays2 := (g.mesh as ArrayMesh).surface_get_arrays(0)
	var vs: PackedVector3Array = arrays2[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arrays2[Mesh.ARRAY_NORMAL]
	var walls := 0
	var flats := 0
	var off_step := 0
	for i in range(0, vs.size(), 3):
		# 가파른 면 = 절벽. 나머지는 평평한 단이어야 하고, 그 높이는 STEP 의 배수여야 한다.
		if absf(ns[i].y) < 0.55:
			walls += 1
		elif absf(vs[i].y - vs[i + 1].y) < 0.01 and absf(vs[i].y - vs[i + 2].y) < 0.01:
			flats += 1
			if absf(fmod(vs[i].y, Ground.STEP)) > 0.01:
				off_step += 1
	var ok7: bool = walls > 100 and off_step == 0 and flats > 1000
	fail += 0 if ok7 else 1
	print("7) 절벽면 %d장 / 평평한 단 %d장 (단 높이가 %.1f 배수 아닌 것 %d장) %s" % [
		walls, flats, Ground.STEP, off_step, "OK" if ok7 else "***"])

	# --- 8) 다듬기 붓이 울퉁불퉁을 편다 ---
	g.clear_edits()
	# 일부러 들쭉날쭉하게 판다
	for i in 12:
		var a := TAU * float(i) / 12.0
		g.sculpt(Vector3(-40.0 + cos(a) * 7.0, 0.0, 40.0 + sin(a) * 7.0), 6.0,
			-3.0 if i % 2 == 0 else -0.5)
	var rough := 0.0
	for i in 24:
		var a2 := TAU * float(i) / 24.0
		var p1 := Vector3(-40.0 + cos(a2) * 7.0, 0.0, 40.0 + sin(a2) * 7.0)
		var p2 := Vector3(-40.0 + cos(a2 + 0.26) * 7.0, 0.0, 40.0 + sin(a2 + 0.26) * 7.0)
		rough += absf(g.raw_at(p1) - g.raw_at(p2))
	for i in 30:
		g.smooth_brush(Vector3(-40.0, 0.0, 40.0), 16.0, 0.5)
	var rough2 := 0.0
	for i in 24:
		var a3 := TAU * float(i) / 24.0
		var q1 := Vector3(-40.0 + cos(a3) * 7.0, 0.0, 40.0 + sin(a3) * 7.0)
		var q2 := Vector3(-40.0 + cos(a3 + 0.26) * 7.0, 0.0, 40.0 + sin(a3 + 0.26) * 7.0)
		rough2 += absf(g.raw_at(q1) - g.raw_at(q2))
	var ok8: bool = rough2 < rough * 0.6
	fail += 0 if ok8 else 1
	print("8) 다듬기 전 요철 %.2f -> 후 %.2f (40%% 이상 줄어야) %s" % [
		rough, rough2, "OK" if ok8 else "***"])
	g.clear_edits()
	g.build()

	if backup != "":
		var f := FileAccess.open(Ground.EDIT_PATH, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
		print("(원래 지형 파일 복원)")

	print("")
	print("스컬프트 검증 통과" if fail == 0 else "스컬프트 검증 실패 %d 건" % fail)
	quit(0 if fail == 0 else 1)
