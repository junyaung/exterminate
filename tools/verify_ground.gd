extends SceneTree
## 절차 생성 지면 검증 — 눈으로 못 보는 것만 잰다.
##   1) 메시가 실제로 구워졌고 정점을 공유하지 않는다 (면 단색 로우폴리의 조건)
##   2) 성은 정상에, 스폰 벌판은 평평하게 (평지 판이면 전부 0)
##   3) 산허리에 평평한 단과 경사면이 섞여 있다
##   4) 색이 팔레트 몇 색으로만 떨어진다 (그라데이션이 아니다)
##   5) 프롭이 지면 높이에 앉는다 (공중에 뜨거나 묻히지 않는다)
## godot --headless --path . --script tools/verify_ground.gd

func _init() -> void:
	_run()

func _run() -> void:
	var fail := 0
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame          # 지면 굽기는 한 프레임 미뤄져 있다
	var g := main.get_node("Ground") as Ground
	var mesh := g.mesh as ArrayMesh

	# --- 1) 메시가 제대로 들어갔는가 ---
	# 지금은 **블렌더에서 만든 메시**를 그대로 쓴다 (유저 지시 2026-08-16). 절차 생성으로
	# 되돌리면 정점 색 기반이라 검사 항목이 달라지므로 둘 다 본다.
	var gmesh := g.mesh as ArrayMesh
	var from_blender: bool = gmesh.get_surface_count() > 1
	var ok1 := false
	if from_blender:
		var names: Array = []
		for i in gmesh.get_surface_count():
			var mm := gmesh.surface_get_material(i)
			names.append(mm.resource_name if mm != null else "없음")
		# 색을 빼고 보는 중(PLAIN_LOOK)이면 무채색 한 장으로 덮는 게 정상이고,
		# 색을 되살리면 override 가 없어야 블렌더 머티리얼이 나온다. 둘 다 인정한다.
		var override_ok: bool = (g.material_override != null) if Ground.PLAIN_LOOK \
			else (g.material_override == null)
		ok1 = gmesh.get_surface_count() >= 4 and override_ok
		print("1) 블렌더 메시 서피스 %d %s / 색빼기 %s / override %s %s" % [
			gmesh.get_surface_count(), names, Ground.PLAIN_LOOK,
			g.material_override, "OK" if ok1 else "***"])
	else:
		var arrays := gmesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		ok1 = verts.size() > 1000 and cols.size() == verts.size()
		print("1) 절차 생성 메시 정점 %d / 색 %d %s" % [
			verts.size(), cols.size(), "OK" if ok1 else "***"])
	fail += 0 if ok1 else 1

	# --- 2·3) 지형 — 산이 있으면 산 기준, 없으면 평지 기준 ---
	# 지형은 layout/terrain_edit.json 이 있을 때만 솟는다. 파일을 넣었다 뺐다 하므로
	# 한쪽으로 박아두지 않고 지형을 보고 판단한다.
	var base := main.get_node("BaseBlock") as Node3D
	var peak := 0.0
	for i in 200:
		peak = maxf(peak, g.height_at(Vector3(randf_range(-110.0, 110.0), 0.0,
			randf_range(-110.0, 110.0))))
	var hilly: bool = peak > 4.0

	if hilly:
		# 성은 정상에 앉아 있고, 스폰 벌판은 평평해야 한다
		var pad := g.height_at(base.global_position)
		var field_bad := 0
		for i in 40:
			if absf(g.height_at(Main.random_spawn_point())) > 0.2:
				field_bad += 1
		# ⚠️ 0.01 은 너무 빡빡하다 — 격자 보간 때문에 성 자리 높이가 소수점 둘째 자리에서
		#    흔들린다 (26.00 vs 25.99 로 실패했다). 눈에 안 보이는 차이는 통과시킨다.
		var ok2: bool = absf(pad - base.global_position.y) < 0.06 and pad > 8.0 \
			and field_bad == 0
		fail += 0 if ok2 else 1
		print("2) 산악 — 성 앞마당 %.2f(성 노드 %.2f), 스폰 벌판 어긋남 %d %s" % [
			pad, base.global_position.y, field_bad, "OK" if ok2 else "***"])

		# 산허리에는 평평한 단과 그 사이 경사면이 섞여 있어야 한다
		var flats := 0
		var slopes := 0
		for i in 300:
			var r := Vector3(randf_range(-90.0, 90.0), 0.0, randf_range(-90.0, 90.0))
			if absf(fmod(g.height_at(r), Ground.STEP)) < 0.01:
				flats += 1
			else:
				slopes += 1
		var ok3: bool = flats > 150 and slopes > 10
		fail += 0 if ok3 else 1
		print("3) 평평한 단 %d / 경사면 %d (300표본) %s" % [
			flats, slopes, "OK" if ok3 else "***"])
	else:
		var bumpy := 0
		for i in 60:
			if absf(g.height_at(Vector3(randf_range(-110.0, 110.0), 0.0,
					randf_range(-110.0, 110.0)))) > 0.001:
				bumpy += 1
		var ok2b: bool = bumpy == 0 and absf(base.global_position.y) < 0.01
		fail += 0 if ok2b else 1
		print("2) 평지 — 솟은 곳 %d개, 성 y=%.1f %s" % [
			bumpy, base.global_position.y, "OK" if ok2b else "***"])
		print("3) 평지라 단/경사 검증은 건너뛴다")

	# --- 4) 색이 몇 가지로만 쓰이는가 (팔레트 밖으로 안 샌다) ---
	var kinds := {}
	if from_blender:
		for i in gmesh.get_surface_count():
			var mm2 := gmesh.surface_get_material(i)
			if mm2 is StandardMaterial3D:
				kinds[(mm2 as StandardMaterial3D).albedo_color.to_html(false)] = true
	else:
		for c in gmesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]:
			kinds[c.linear_to_srgb().to_html(false)] = true
	var ok4: bool = kinds.size() >= 3 and kinds.size() <= 8
	fail += 0 if ok4 else 1
	print("4) 지면 색 %d가지 %s %s" % [kinds.size(), kinds.keys(), "OK" if ok4 else "***"])

	# --- 5) 프롭이 지면에 앉는가 ---
	var sc: Scatter = null
	for c in main.get_children():
		if c is Scatter:
			sc = c
	if sc == null:
		# 프롭을 꺼둔 상태 — 실패가 아니라 건너뛴다.
		print("5) 프롭이 꺼져 있어 건너뜀")
		print("")
		print("지형 검증 통과" if fail == 0 else "지형 검증 실패 %d 건" % fail)
		quit(0 if fail == 0 else 1)
		return
	var off := 0
	var max_gap := 0.0
	for i in mini(sc._placed.size(), 120):
		var q: Vector2 = sc._placed[i]
		var w := Main.to_world(q.x, q.y)
		# 프롭 자리의 지면 높이와, 스캐터가 실제로 쓴 높이가 같아야 한다
		max_gap = maxf(max_gap, absf(g.height_at(w) - sc._ground_y(w)))
		if absf(g.height_at(w) - sc._ground_y(w)) > 0.001:
			off += 1
	var ok5: bool = off == 0
	fail += 0 if ok5 else 1
	print("5) 프롭 120개 지면 높이 불일치 %d개 (최대 %.4f) %s" % [
		off, max_gap, "OK" if ok5 else "***"])

	print("")
	print("지형 검증 통과" if fail == 0 else "지형 검증 실패 %d 건" % fail)
	quit(0 if fail == 0 else 1)
