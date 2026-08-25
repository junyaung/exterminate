extends SceneTree
## 폭연 연출 요소 검증 (헤드리스라 그림은 못 보지만 "존재와 값의 변화"는 잰다):
## heat 유니폼 상승 / 균열 빛줄기 알파·개수 / 가속 진동 / 폭발 순간 섬광·링·화염 생성.
## godot --headless --path . --script tools/verify_combust_fx.gd

const EnemyScene := preload("res://scenes/enemy.tscn")

func _init() -> void:
	_run()

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var hs = main.get_node("HammerStrike")
	hs.has_fire = true
	main.set_physics_process(false)

	var e = EnemyScene.instantiate()
	main.get_node("Enemies").add_child(e)
	e.global_position = Vector3.ZERO
	await process_frame
	hs._impact(Vector3.ZERO, 0.0)
	await process_frame

	var pivot: Node3D = e.get_node("VisualPivot")
	var body := e.get_node("VisualPivot/Ant").find_child("Body", true, false) as MeshInstance3D

	print("시각    heat    균열알파   피벗흔들림    스케일y")
	var waits := [0.3, 0.3, 0.25, 0.1]
	var when := [0.3, 0.6, 0.85, 0.95]
	for i in waits.size():
		await create_timer(waits[i]).timeout
		if not is_instance_valid(e):
			print("  (이미 터짐)")
			break
		var m0 := body.get_surface_override_material(0) as ShaderMaterial
		var cracks_a := []
		for c in pivot.get_children():
			if c is MeshInstance3D and c.material_override is StandardMaterial3D:
				cracks_a.append(snappedf((c.material_override as StandardMaterial3D).albedo_color.a, 0.01))
		print("%.2fs  %5.3f   %s개 max %.2f   x=%+.3f   %.2f" % [
			when[i], m0.get_shader_parameter("heat"),
			str(cracks_a.size()), cracks_a.max() if cracks_a.size() > 0 else -1.0,
			pivot.position.x, pivot.scale.y])

	# 폭발 직후: Deflagration 노드 밑에 섬광(구)/링(토러스)/화염(쿼드) 이 생겼는지
	await create_timer(0.15).timeout   # 1.15s — 터진 직후
	var flash := 0
	var rings := 0
	var flames := 0
	for d in hs.get_children():
		if d is Deflagration:
			for c in d.get_children():
				var mi := c as MeshInstance3D
				if mi == null:
					continue
				if mi.mesh is SphereMesh:
					flash += 1
				elif mi.mesh is TorusMesh:
					rings += 1
				elif mi.mesh is QuadMesh:
					flames += 1
	print("")
	print("폭발 1.15s: 섬광 %d (기대 1) / 충격파 링 %d (기대 1) / 화염 %d (기대 6~11)" % [
		flash, rings, flames])
	print("시체 소멸: ", not is_instance_valid(e), " (기대 true)")
	print("카메라 쉐이크 _shake = %.2f (기대 > 0)" % hs._shake)
	quit()
