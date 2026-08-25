extends SceneTree
## 보라 웅덩이(BloodPool) 지오메트리 검증 — 헤드리스로 **보이는지**를 판정한다.
## godot --headless --path . --script tools/verify_blood_pool.gd
##
## 헤드리스는 그림을 못 그리므로 "노드가 생겼다"만으로는 화면에 보이는지 알 수 없다.
## 실제로 첫 판은 감는 방향이 뒤집혀 통째로 컬링됐는데 노드 검사만으로는 통과했다.
## 그래서 메시 삼각형을 직접 뜯어 두 가지를 잰다:
##   ① 위에서 봤을 때 앞면인가 (오른손 법칙 노멀이 -Y = Godot 앞면 규약)
##   ② 셰이딩 노멀이 위를 향하는가 (아래를 향하면 빛을 등져 새까맣다)
##   ③ 셀 2톤이 실제로 갈리는가 (해 방향 기준 N·L 이 threshold 를 양쪽으로 넘는가)

## main.tscn 의 Sun: 빛이 오는 방향(표면 -> 광원) = 기저의 +Z 축
const SUN_TO_LIGHT := Vector3(0.6393, 0.7660, -0.0672)

func _init() -> void:
	_run()

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_physics_process(false)

	var pool := BloodPool.spawn(main, Vector3(10, 0, 10), 6.0)
	await process_frame
	var ok := true

	# 실제 씬의 해 방향과 상수가 맞는지 먼저 확인 (씬을 고치면 여기가 먼저 깨져야 한다)
	var sun := main.get_node("Sun") as DirectionalLight3D
	var to_light: Vector3 = sun.global_basis.z.normalized()
	print("해 방향(표면->광원): %s, 고도 %.1f°" % [to_light, rad_to_deg(asin(to_light.y))])
	if to_light.distance_to(SUN_TO_LIGHT) > 0.05:
		print("   주의: main.tscn 의 해가 바뀌었다 — CEL_THRESHOLD 재계산 필요")

	for part in [{n = "웅덩이", mi = pool._pool}, {n = "먹선", mi = pool._rim}]:
		var arrays: Array = part.mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var tris := verts.size() / 3
		var back_facing := 0
		var down_normals := 0
		var ndl_lo := 9.9
		var ndl_hi := -9.9
		for t in tris:
			var a := verts[t * 3]
			var b := verts[t * 3 + 1]
			var c := verts[t * 3 + 2]
			# Godot 앞면 = 카메라에서 시계방향 = 오른손 법칙 노멀이 시선 반대(위에서 보면 -Y)
			if (b - a).cross(c - a).y > 0.0:
				back_facing += 1
			for k in 3:
				var n := norms[t * 3 + k]
				if n.y <= 0.0:
					down_normals += 1
				var ndl: float = n.dot(to_light)
				ndl_lo = minf(ndl_lo, ndl)
				ndl_hi = maxf(ndl_hi, ndl)
		print("[%s] 삼각형 %d / 뒷면 %d (기대 0) / 아래보는 노멀 %d (기대 0)" % [
			part.n, tris, back_facing, down_normals])
		print("        N·L 범위 %.2f ~ %.2f" % [ndl_lo, ndl_hi])
		if back_facing > 0 or down_normals > 0:
			ok = false

	# 셀 2톤: 웅덩이의 N·L 이 threshold 를 양쪽으로 넘어야 밝은 면/어두운 면이 같이 나온다
	var arrays: Array = pool._pool.mesh.surface_get_arrays(0)
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var lit := 0
	var dark := 0
	for n in norms:
		if n.dot(to_light) >= BloodPool.CEL_THRESHOLD:
			lit += 1
		else:
			dark += 1
	print("셀 2톤 (threshold %.2f): 밝은 면 %d / 어두운 면 %d — 둘 다 0보다 커야 한다" % [
		BloodPool.CEL_THRESHOLD, lit, dark])
	if lit == 0 or dark == 0:
		ok = false

	# 수면 반사 조각: 해 쪽에 있고, 위에서 앞면이어야 한다
	var glints: Array = pool._glints
	print("반사 조각 %d개 (기대 2~3)" % glints.size())
	if glints.size() < 2 or glints.size() > 3:
		ok = false
	var sun_h := Vector3(to_light.x, 0.0, to_light.z).normalized()
	for g: MeshInstance3D in glints:
		var side: float = Vector3(g.position.x, 0.0, g.position.z).normalized().dot(sun_h)
		var ga: Array = g.mesh.surface_get_arrays(0)
		var gv: PackedVector3Array = ga[Mesh.ARRAY_VERTEX]
		var back := 0
		for t in gv.size() / 3:
			if (gv[t * 3 + 1] - gv[t * 3]).cross(gv[t * 3 + 2] - gv[t * 3]).y > 0.0:
				back += 1
		print("   해 방향 성분 %+.2f (기대 >0) / 뒷면 %d (기대 0)" % [side, back])
		if side <= 0.0 or back > 0:
			ok = false

	# 수명: 퍼짐 0.9 + 유지 2.0 + 페이드 0.6 = 3.5초 뒤 사라진다
	for i in 260:
		paused = false
		await physics_frame
	print("4.3초 뒤 남아있나: %s (기대 false)" % str(is_instance_valid(pool)))
	if is_instance_valid(pool):
		ok = false

	print("결과: ", "PASS" if ok else "FAIL")
	quit()
