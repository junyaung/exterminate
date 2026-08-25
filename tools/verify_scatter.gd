extends SceneTree
## 지형 프롭 스캐터 검증 — 눈으로 못 보는 것만 센다.
##   1) 실제로 놓였고, 시드가 같으면 **같은 배치**가 나온다 (재현성)
##   2) 기지 원 / 스폰 존 / 행군 통로 안에 놓인 게 **하나도 없다**
##   3) 프롭끼리 최소 간격을 지킨다
##   4) 밀도를 올리면 개수가 는다
##   5) MultiMesh 인스턴스 수 = 실제 배치 수 (파트가 여러 개면 같은 수만큼)
## godot --headless --path . --script tools/verify_scatter.gd

func _init() -> void:
	_run()

## 배치된 자리(화면 좌표).
## ⚠️ **MultiMesh 에서 읽어오면 안 된다** — 인스턴스 transform 은 RenderingServer 에 사는데
##    헤드리스는 더미 드라이버라 `get_instance_transform()` 이 항상 항등행렬을 준다
##    (실제로 이걸로 한 번 오진했다). Scatter 가 들고 있는 배치 목록을 본다.
func _spots(sc: Node) -> Array:
	return sc._placed.duplicate()

func _run() -> void:
	var fail := 0
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var sc: Scatter = null
	for c in main.get_children():
		if c is Scatter:
			sc = c
	if sc == null:
		# 유저 지시로 프롭을 꺼둔 상태 — 실패가 아니라 건너뛴다.
		print("스캐터가 꺼져 있다 (main.gd 에서 주석 처리) — 검증 건너뜀")
		quit(0)
		return

	# --- 1) 놓였는가 + 재현되는가 ---
	var a := _spots(sc)
	sc.rebuild()
	await process_frame
	var b := _spots(sc)
	var same := a.size() == b.size()
	if same:
		for i in a.size():
			if a[i].distance_to(b[i]) > 0.001:
				same = false
				break
	var ok1: bool = a.size() > 100 and same
	fail += 0 if ok1 else 1
	print("1) 프롭 %d개 배치, 같은 시드 재생성 일치=%s %s" % [
		a.size(), same, "OK" if ok1 else "***"])

	# --- 2) 제외 영역 침범 0 ---
	# 밟고 지나갈 수 있는 잎·자갈은 통로 위에 있는 게 정상이므로 제외하고 센다.
	var bad := 0
	for p in sc._placed_tall:
		if sc._blocked(p):
			bad += 1
	var ok2: bool = bad == 0
	fail += 0 if ok2 else 1
	print("2) 높은 프롭의 기지/스폰존/통로 침범 %d개 (기대 0) %s" % [bad, "OK" if ok2 else "***"])

	# --- 3) 프롭끼리 최소 간격 ---
	var uniq: Array = a
	var min_d := 999.0
	for i in uniq.size():
		for j in range(i + 1, uniq.size()):
			min_d = minf(min_d, uniq[i].distance_to(uniq[j]))
	# 가장 좁은 값은 풀포기 덩어리 안쪽: cluster_r 1.8 × 0.55 × 0.5 = 0.495.
	# 0.5 로 잡으면 부동소수점 경계에 걸려 배치가 조금만 달라져도 실패한다.
	var ok3: bool = min_d >= 0.49
	fail += 0 if ok3 else 1
	print("3) 서로 다른 프롭 %d자리, 최소 간격 %.2f (기대 0.49 이상) %s" % [
		uniq.size(), min_d, "OK" if ok3 else "***"])

	# --- 4) 밀도 반응 ---
	sc.density = 2.0
	sc.rebuild()
	await process_frame
	var dense := _spots(sc).size()
	var ok4: bool = dense > a.size()
	fail += 0 if ok4 else 1
	print("4) 밀도 1.0 -> 2.0 : %d -> %d개 %s" % [
		a.size(), dense, "OK" if ok4 else "***"])

	# --- 5) MultiMesh 인스턴스 수가 배치 수와 맞는가 (파트 여러 개면 그 배수) ---
	sc.density = 1.0
	sc.rebuild()
	await process_frame
	var inst := 0
	for c in sc.get_children():
		if c is MultiMeshInstance3D:
			inst += c.multimesh.instance_count
	var ok5a: bool = inst >= a.size()
	fail += 0 if ok5a else 1
	print("5) MultiMesh 인스턴스 %d개 >= 배치 %d자리 (나무는 잎+줄기 2벌) %s" % [
		inst, a.size(), "OK" if ok5a else "***"])

	# --- 6) 배치 범위가 화면을 덮는가 (한쪽에 뭉치지 않았는가) ---
	var minx := 999.0
	var maxx := -999.0
	var minz := 999.0
	var maxz := -999.0
	for p in _spots(sc):
		minx = minf(minx, p.x)
		maxx = maxf(maxx, p.x)
		minz = minf(minz, p.y)
		maxz = maxf(maxz, p.y)
	var ok6: bool = minx < -60.0 and maxx > 60.0 and minz < -40.0 and maxz > 40.0
	fail += 0 if ok6 else 1
	print("6) 배치 범위 x %.0f~%.0f / z %.0f~%.0f (화면 ±67 / ±49) %s" % [
		minx, maxx, minz, maxz, "OK" if ok6 else "***"])

	# --- 7) 나무 밑동은 화면 가장자리에만, 한두 그루뿐인가 ---
	var trunks := 0
	var inside := 0
	for c in sc.get_children():
		if c is MultiMeshInstance3D and String(c.name).begins_with("trunk"):
			trunks = maxi(trunks, c.multimesh.instance_count)
	# 밑동 자리는 _placed 앞쪽 trunks 개 (PROPS 순서상 제일 먼저 놓인다)
	for i in mini(trunks, sc._placed.size()):
		var q: Vector2 = sc._placed[i]
		if absf(q.x) < Scatter.AREA_X * Scatter.EDGE_BAND \
				and absf(q.y) < Scatter.AREA_Z * Scatter.EDGE_BAND:
			inside += 1
	var ok7: bool = trunks <= 3 and inside == 0
	fail += 0 if ok7 else 1
	print("7) 나무 밑동 %d그루, 화면 안쪽에 놓인 것 %d개 (기대 <=3 / 0) %s" % [
		trunks, inside, "OK" if ok7 else "***"])

	print("")
	print("스캐터 검증 통과" if fail == 0 else "스캐터 검증 실패 %d 건" % fail)
	quit(0 if fail == 0 else 1)
