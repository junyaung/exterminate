extends SceneTree
## 그림자 설정 점검 — 어떤 메시가 그림자를 드리우는지 실제 노드에서 읽는다.
## godot --headless --path . --script tools/verify_shadows.gd

func _sname(v: int) -> String:
	return ["OFF", "ON", "DOUBLE_SIDED", "SHADOWS_ONLY"][v]

func _dump(n: Node, ind: String) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		print("%s%-12s 그림자 %s  (서피스 %d)" % [
			ind, mi.name, _sname(mi.cast_shadow), mi.mesh.get_surface_count() if mi.mesh else 0])
	for c in n.get_children():
		_dump(c, ind + "  ")

func _init() -> void:
	_run()

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_physics_process(false)

	var sun := main.get_node("Sun") as DirectionalLight3D
	print("Sun.shadow_enabled = %s / 최대거리 %.0f" % [
		str(sun.shadow_enabled), sun.directional_shadow_max_distance])
	# 태양 고도 — 낮을수록 그림자가 길고, 높을수록 몸 밑에 깔려 안 보인다.
	var ldir: Vector3 = -sun.global_transform.basis.z
	print("태양 고도 %.0f° -> 그림자 길이 = 키의 %.2f 배 (몸에 가려지는 정도)" % [
		rad_to_deg(asin(-ldir.y)), 1.0 / tan(asin(-ldir.y))])
	print("Ground 그림자 받음: %s" % str((main.get_node("Ground") as MeshInstance3D).visible))
	print("")

	# 개미 (grunt)
	var ant := load("res://scenes/enemy.tscn").instantiate() as Enemy
	ant.type_id = &"grunt"
	main.add_child(ant)
	ant.global_position = Vector3(6, 0, 6)
	await process_frame
	print("[개미 grunt]")
	_dump(ant, "  ")

	# 보스
	print("")
	print("[보스 stag]")
	var boss = main.spawn_boss()
	await process_frame
	_dump(boss, "  ")
	quit()
