extends SceneTree
## 지형 인식 이동 검증 (유저 선택 2026-08-16: 게임을 높이 인식하게).
##   1) 흐름장이 만들어지고, 스폰 자리에서 성까지 길이 있다
##   2) 평지에서는 어디든 지나갈 수 있다
##   3) 벌레가 지면 위를 걷는다
##   4) 산악이면 스폰->성 **직선이 막혀 있다** = 비탈길로 돌아올 수밖에 없다
##   5) 산 위에 있는 동안에는 **항상 길 위** = 산허리로 새지 않는다
## (지형 파일 layout/terrain_edit.json 을 넣으면 절벽·비탈길 검증으로 돌아간다 —
##  tools/make_terrain.py 로 언제든 다시 만들 수 있다)
## godot --headless --path . --script tools/verify_nav.gd

func _init() -> void:
	_run()

func _run() -> void:
	var fail := 0
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var g := main.get_node("Ground") as Ground
	var nav := main.get_node("NavMap") as NavMap
	var base := main.get_node("BaseBlock") as Node3D

	# --- 1) 스폰 자리에서 성까지 길이 있는가 ---
	var bad := 0
	for i in 40:
		if not nav.reachable(Main.random_spawn_point()):
			bad += 1
	var ok1: bool = nav.n > 0 and bad == 0
	fail += 0 if ok1 else 1
	print("1) 스폰 40지점 중 성에 못 닿는 곳 %d개 (기대 0) %s" % [
		bad, "OK" if ok1 else "***"])

	# 지형이 있는 판인지 평지인지 보고 검증 내용을 바꾼다 — 지형 파일을 넣었다 뺐다 하므로
	# 한쪽 기준으로 박아두면 매번 고쳐야 한다.
	var peak := 0.0
	for i in 200:
		peak = maxf(peak, g.height_at(Vector3(randf_range(-110.0, 110.0), 0.0,
			randf_range(-110.0, 110.0))))
	var hilly: bool = peak > 4.0
	print("   (지형 최고 높이 %.1f — %s 기준으로 검증)" % [
		peak, "산악" if hilly else "평지"])

	# --- 2) 절벽이 막혀 있는가 (산악일 때만) ---
	if hilly:
		# ⚠️ 아무 데나 찍어서는 가파른 구간이 잘 안 걸린다. **높이차가 큰 구간만 모아** 놓고
		#    그 중 몇 %가 막히는지 본다. 절벽이 제구실을 하면 대부분 막혀야 한다.
		var steep_total := 0
		var blocked := 0
		for i in 400:
			var a := Vector3(randf_range(-70.0, 70.0), 0.0, randf_range(-70.0, 70.0))
			var up := a + Vector3(randf_range(-4.0, 4.0), 0.0, randf_range(-4.0, 4.0))
			if g.height_at(up) - g.height_at(a) < 1.5:
				continue
			steep_total += 1
			if not NavMap.passable(g, a, up):
				blocked += 1
		var rate := 100.0 * float(blocked) / maxf(float(steep_total), 1.0)
		var ok2b: bool = steep_total > 10 and rate > 80.0
		fail += 0 if ok2b else 1
		print("2) 높이차 큰 구간 %d개 중 막힌 곳 %d개 (%.0f%%, 80%% 이상이어야) %s" % [
			steep_total, blocked, rate, "OK" if ok2b else "***"])
	else:
		var flat_ok := 0
		for i in 20:
			var a2 := Vector3(randf_range(-80.0, 80.0), 0.0, randf_range(-80.0, 80.0))
			var b2 := a2 + Vector3(randf_range(-8.0, 8.0), 0.0, randf_range(-8.0, 8.0))
			if NavMap.passable(g, a2, b2):
				flat_ok += 1
		fail += 0 if flat_ok == 20 else 1
		print("2) 평지 20구간 중 지나갈 수 있는 곳 %d개 (기대 20) %s" % [
			flat_ok, "OK" if flat_ok == 20 else "***"])

	# --- 3·4) 실제로 걷게 한다 ---
	# ⚠️ **콩벌레(runner)도 넣는다.** 굴러오는 동안에는 자기 코드에서 직접 움직이는데,
	#    거기가 길찾기를 안 거쳐서 산을 뚫고 지나갔다 (유저 지적 2026-08-16).
	var cases := [
		{name = "아래쪽 존", at = Main.to_world(10.0, 66.0), kind = &"grunt"},
		{name = "오른쪽 존", at = Main.to_world(80.0, 25.0), kind = &"grunt"},
		{name = "콩벌레", at = Main.to_world(80.0, 25.0), kind = &"runner"},
	]
	var float_worst := 0.0
	var gain_on := 0.0     ## 올라간 높이 합 (참고용 지표)
	var off_path_steps := 0   ## 산 위에서 '걸을 수 없는 칸'을 밟은 프레임 수
	var all_arrived := true
	var txt := ""
	for case in cases:
		var enemy := (load("res://scenes/enemy.tscn") as PackedScene).instantiate() as Enemy
		enemy.type_id = case.kind
		main.get_node("Enemies").add_child(enemy)
		enemy.global_position = case.at
		enemy.target = base
		var straight := Vector2(case.at.x - base.global_position.x,
			case.at.z - base.global_position.z).length()
		var walked := 0.0
		var prev := enemy.global_position
		var steps := 0
		while steps < 20000:
			var flat3 := Vector2(enemy.global_position.x - base.global_position.x,
				enemy.global_position.z - base.global_position.z).length()
			if flat3 <= 6.0:
				break
			enemy._physics_process(1.0 / 60.0)
			steps += 1
			walked += prev.distance_to(enemy.global_position)
			float_worst = maxf(float_worst,
				absf(enemy.global_position.y - Terrain.h(enemy.global_position)))
			gain_on += maxf(enemy.global_position.y - prev.y, 0.0)
			# **산 위에 있는 동안에는 걸을 수 있는 칸(길)만 밟아야 한다** (유저 지시: 길로만).
			# ⚠️ 마스크 값을 벌레 위치에서 바로 재면 안 된다 — 걷기 판정은 4유닛 격자의
			#    **칸 단위**라, 길 칸 안이어도 칸 가장자리에서는 마스크가 0 으로 나온다.
			#    "막힌 칸에 발을 들였는가"로 재는 게 규칙과 같은 잣대다.
			if enemy.global_position.y > 1.0 and not nav.is_walkable(enemy.global_position):
				off_path_steps += 1
			prev = enemy.global_position
		var arrived: bool = steps < 20000
		all_arrived = all_arrived and arrived
		if not arrived:
			var sp := Basis(Vector3.UP, deg_to_rad(-Main.VIEW_YAW)) * enemy.global_position
			print("   막힌 자리 화면(%.0f, %.0f) y=%.2f" % [sp.x, sp.z, enemy.global_position.y])
		txt += " %s %.2f배(%s)" % [case.name, walked / maxf(straight, 0.001),
			"도착" if arrived else "**못 감**"]
		enemy.queue_free()

	var ok3: bool = float_worst < 0.01 and all_arrived
	fail += 0 if ok3 else 1
	print("3) 지면과의 어긋남 %.4f, 주행 —%s %s" % [
		float_worst, txt, "OK" if ok3 else "***"])

	# --- 4) 산악이면: 직선으로는 못 올라온다 = 돌아올 수밖에 없다 ---
	# ⚠️ "올라간 높이의 몇 %가 길 위였나"로 재려다 헛짚었다. 벌레는 넓은 단 위를 걸으며
	#    미세하게 오르내리는데(한 번에 0.05 미만), 그 잔값까지 다 더해지니 길 밖 비중이
	#    실제와 무관하게 커졌다. **지형 자체를 검사**하는 편이 정확하다:
	#    스폰에서 성으로 가는 직선이 막혀 있으면, 도착했다는 건 돌아왔다는 뜻이다.
	if hilly:
		var blocked_lines := 0
		for case in cases:
			var from: Vector3 = case.at
			var to := base.global_position
			var n := int(from.distance_to(to) / 4.0)
			var blocked_here := false
			for i in n:
				var a := from.lerp(to, float(i) / float(n))
				var b := from.lerp(to, float(i + 1) / float(n))
				if not NavMap.passable(g, a, b):
					blocked_here = true
					break
			if blocked_here:
				blocked_lines += 1
		var ok4: bool = blocked_lines == cases.size()
		fail += 0 if ok4 else 1
		print("4) 스폰->성 직선이 막힌 경우 %d/%d (막혀야 돌아온다) %s" % [
			blocked_lines, cases.size(), "OK" if ok4 else "***"])

		var ok5: bool = off_path_steps == 0
		fail += 0 if ok5 else 1
		print("5) 산 위에서 길 밖 칸을 밟은 프레임 %d (기대 0) %s" % [
			off_path_steps, "OK" if ok5 else "***"])
	else:
		print("4) 평지라 우회 검증은 건너뛴다")

	print("")
	print("지형 이동 검증 통과" if fail == 0 else "지형 이동 검증 실패 %d 건" % fail)
	quit(0 if fail == 0 else 1)
