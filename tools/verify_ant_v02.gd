extends SceneTree
## 개미 v02(귀여운 스타일) glb 가 Godot 규약대로 들어왔는지 검증.
## godot --headless --path . --script tools/verify_ant_v02.gd

func _run_checks() -> void:
	var scn = load("res://scenes/enemy.tscn")
	var e = scn.instantiate()
	e.type_id = &"grunt"
	root.add_child(e)
	await process_frame

	var ant = e.find_child("Ant", true, false)
	print("Ant 노드: ", ant != null)
	var body = ant.find_child("Body", true, false)
	var outline = ant.find_child("Outline", true, false)
	print("Body: ", body != null, "  서피스 ", body.mesh.get_surface_count(), " (기대 4)")
	print("Outline: ", outline != null, "  서피스 ",
		outline.mesh.get_surface_count() if outline else -1, " (기대 1)")
	for i in body.mesh.get_surface_count():
		var ov = body.get_surface_override_material(i)
		print("  서피스 %d override=%s" % [i, ov.get_class() if ov else "없음"])

	var ap = ant.find_child("AnimationPlayer", true, false)
	print("애니메이션: ", ap.get_animation_list() if ap else "없음", " (기대 walk)")
	if ap and ap.has_animation(&"walk"):
		var a = ap.get_animation(&"walk")
		print("  walk 길이 %.2f초  루프=%s" % [a.length, a.loop_mode != Animation.LOOP_NONE])

	# 크기: v01 과 같아야 히트박스·물량감이 유지된다
	var aabb = body.get_aabb()
	print("AABB 크기: %.2f x %.2f x %.2f (블렌더 2.53 / 1.29 / 1.29)" % [
		aabb.size.x, aabb.size.y, aabb.size.z])
	print("바닥 접지: y_min %.3f (0 근처여야 함)" % aabb.position.y)
	quit()

func _init() -> void:
	_run_checks()
