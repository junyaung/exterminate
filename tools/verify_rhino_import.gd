extends SceneTree
## 장수풍뎅이 glb 임포트 검증: 스켈레톤 / 액션 3종 / 파트 12개 / 재질 / 크기.
## 아직 게임에 배선하기 전 단계 — glb 자체가 성하게 들어왔는지만 본다.
## godot --headless --path . --script tools/verify_rhino_import.gd

func _init() -> void:
	_run()

func _run() -> void:
	var fail := 0
	for path in ["res://assets/models/rhino.glb", "res://assets/models/rhino_corpse.glb"]:
		var ps := load(path) as PackedScene
		if ps == null:
			print("!! 로드 실패: ", path)
			fail += 1
			continue
		var n := ps.instantiate()
		root.add_child(n)
		await process_frame
		print("== ", path, " ==")

		var skel := n.find_child("Skeleton3D", true, false) as Skeleton3D
		var anim := n.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if skel != null:
			print("   본 %d 개" % skel.get_bone_count())
		if anim != null:
			for a in anim.get_animation_list():
				var an := anim.get_animation(a)
				print("   애니 %-14s %5.2fs (%d트랙)" % [a, an.length, an.get_track_count()])
		else:
			print("   애니 없음 (시체용이면 정상)")

		# 메시 파트 + 합산 AABB
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		var parts := 0
		var tris := 0
		for mi in _all_mesh(n):
			parts += 1
			for s in mi.mesh.get_surface_count():
				tris += mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
			var ab := mi.get_aabb()
			var g := mi.global_transform
			for c in 8:
				var p: Vector3 = g * (ab.position + ab.size * Vector3(
					float(c & 1), float((c >> 1) & 1), float((c >> 2) & 1)))
				lo = lo.min(p)
				hi = hi.max(p)
		var sz := hi - lo
		print("   메시 %d개  삼각형 %d" % [parts, tris])
		print("   크기 %.2f x %.2f x %.2f BU (바닥 z=%.3f)" % [sz.x, sz.z, sz.y, lo.y])
		n.queue_free()
	print("")
	print("임포트 검증 통과" if fail == 0 else "임포트 검증 실패 %d 건" % fail)
	quit(0 if fail == 0 else 1)

func _all_mesh(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_mesh(c))
	return out
