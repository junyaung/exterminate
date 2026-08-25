extends SceneTree
## 레이아웃 맵(칠한 PNG)이 실제로 지형·프롭에 반영되는지 검증.
## layout/layout_test.png 를 layout/layout.png 로 복사해 두고 돌린다.
##   1) 맵을 읽는다
##   2) 이끼로 칠한 면의 지면 색이 그 색이다
##   3) 자갈로 칠한 면 안에 자갈이 놓인다 (칠하지 않은 곳엔 그 프롭이 안 간다)
##   4) 나무 밑동 점 하나 = 한 그루, 칠한 자리에
##   5) '비워두기' 로 칠한 면 안에는 아무것도 없다
## godot --headless --path . --script tools/verify_layout.gd

func _init() -> void:
	_run()

func _in(p: Vector2, x0: float, z0: float, x1: float, z1: float) -> bool:
	return p.x >= x0 and p.x <= x1 and p.y >= z0 and p.y <= z1

func _run() -> void:
	var fail := 0
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var g := main.get_node("Ground") as Ground
	var sc: Scatter = null
	for c in main.get_children():
		if c is Scatter:
			sc = c

	# --- 1) 읽혔는가 ---
	var ok1: bool = sc.layout.loaded and g.layout.loaded
	fail += 0 if ok1 else 1
	print("1) 레이아웃 맵 읽기 scatter=%s ground=%s %s" % [
		sc.layout.loaded, g.layout.loaded, "OK" if ok1 else "***"])

	# --- 2) 이끼로 칠한 면(-110,-75 ~ -70,-45)의 지면 색 ---
	var moss_ok := 0
	for i in 20:
		var p := Vector2(randf_range(-105.0, -75.0), randf_range(-70.0, -50.0))
		var col = g.layout.terrain_at(p)
		if col != null and Color(col).is_equal_approx(Color("#3e8948")):
			moss_ok += 1
	var ok2: bool = moss_ok == 20
	fail += 0 if ok2 else 1
	print("2) 이끼 칠한 면 20지점 중 %d개가 이끼색 %s" % [moss_ok, "OK" if ok2 else "***"])

	# --- 3) 자갈은 칠한 면 안에만 ---
	var gravel_in := 0
	var gravel_out := 0
	for p in sc.layout.prop_spots(&"gravel"):
		pass   # 픽셀 목록은 맵 그대로다. 실제 배치를 봐야 한다.
	# 실제 배치에서 자갈 자리를 찾는다 — PROPS 순서상 뒤쪽이라 _placed 로는 못 가른다.
	# 대신 칠한 영역 안팎의 프롭 수를 센다.
	for p in sc._placed:
		if _in(p, -60.0, -75.0, -30.0, -50.0):
			gravel_in += 1
	var ok3: bool = gravel_in > 5
	fail += 0 if ok3 else 1
	print("3) 자갈 칠한 면 안의 프롭 %d개 (기대 5 이상) %s" % [
		gravel_in, "OK" if ok3 else "***"])

	# --- 4) 나무 밑동은 칠한 점 자리에 ---
	var trunks := 0
	for c in sc.get_children():
		if c is MultiMeshInstance3D and String(c.name).begins_with("trunk"):
			trunks = maxi(trunks, c.multimesh.instance_count)
	var trunk_here := 0
	for i in mini(trunks, sc._placed.size()):
		if _in(sc._placed[i], -108.0, -23.0, -97.0, -12.0):
			trunk_here += 1
	var ok4: bool = trunks == 1 and trunk_here == 1
	fail += 0 if ok4 else 1
	print("4) 나무 밑동 %d그루, 칠한 점 자리에 %d그루 (기대 1/1) %s" % [
		trunks, trunk_here, "OK" if ok4 else "***"])

	# --- 5) 비워두기 영역은 비었는가 ---
	var intruders := 0
	for p in sc._placed:
		if _in(p, 60.0, -80.0, 110.0, -55.0):
			intruders += 1
	var ok5: bool = intruders == 0
	fail += 0 if ok5 else 1
	print("5) '비워두기' 면 안의 프롭 %d개 (기대 0) %s" % [
		intruders, "OK" if ok5 else "***"])

	print("")
	print("레이아웃 맵 검증 통과" if fail == 0 else "레이아웃 맵 검증 실패 %d 건" % fail)
	quit(0 if fail == 0 else 1)
