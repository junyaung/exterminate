extends SceneTree
## 헤비(장수풍뎅이) 배선 검증: 모델 배정 / 파트·먹선 재질 / 애니 전이 / 인게임 크기.
## godot --headless --path . --script tools/verify_rhino.gd

## 폭 = 모델 폭(2.13 BU) × 모델 스케일(0.5634) × 헤비 스케일(4.48)
const EXPECT_WIDTH := 5.38
const BASE_HALF := 2.5       ## 성 블록 5×4×5 의 반폭 (scenes/main.tscn)

func _init() -> void:
	_run()

func _run() -> void:
	var fail := 0
	var scene := load("res://scenes/enemy.tscn") as PackedScene

	# 1) heavy 만 장수풍뎅이를 쓰고, 나머지는 원래 모델을 유지한다
	for id in [&"grunt", &"heavy", &"runner"]:
		var e = scene.instantiate()
		e.type_id = id
		root.add_child(e)
		await process_frame
		var shown: Array[String] = []
		for n in ["Ant", "Pillbug", "Rhino", "Blob"]:
			var m := e.get_node("VisualPivot/" + n) as Node3D
			if m != null and m.visible:
				shown.append(n)
		var want: String = {&"grunt": "Ant", &"heavy": "Rhino", &"runner": "Pillbug"}[id]
		var ok: bool = shown.size() == 1 and shown[0] == want
		fail += 0 if ok else 1
		print("%-7s 보이는 모델 %s (기대 %s) %s" % [id, shown, want, "OK" if ok else "*** 틀림 ***"])
		e.queue_free()

	# 2) 헤비 상세
	var e2 = scene.instantiate()
	e2.type_id = &"heavy"
	root.add_child(e2)
	await process_frame
	var rhino := e2.get_node("VisualPivot/Rhino") as Node3D
	var anim := rhino.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var skel := rhino.find_child("Skeleton3D", true, false) as Skeleton3D
	print("")
	print("헤비  본 %d  애니 %s 재생중=%s  speed_scale=%.2f" % [
		skel.get_bone_count(), anim.current_animation, anim.is_playing(), anim.speed_scale])

	# 파트 6개 + 먹선 6개가 전부 재질을 받았는가
	var missing: Array[String] = []
	var shadow_on: Array[String] = []
	for part in e2.RHINO_PARTS:
		var mi := rhino.find_child(String(part), true, false) as MeshInstance3D
		if mi == null or mi.get_surface_override_material(0) == null:
			missing.append(String(part))
		var ink := rhino.find_child(String(part) + "Ink", true, false) as MeshInstance3D
		if ink == null or ink.get_surface_override_material(0) == null:
			missing.append(String(part) + "Ink")
		elif ink.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			shadow_on.append(String(part) + "Ink")
	fail += 0 if missing.is_empty() else 1
	fail += 0 if shadow_on.is_empty() else 1
	print("      재질 미배정 %s / 먹선이 그림자 드리움 %s" % [
		missing if not missing.is_empty() else "없음",
		shadow_on if not shadow_on.is_empty() else "없음"])

	# 3) 인게임 크기 — 교체 전 구체와 같은 폭이어야 밸런스가 안 흔들린다
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for mi in _all_mesh(rhino):
		var ab := mi.get_aabb()
		var g := mi.global_transform
		for c in 8:
			var p: Vector3 = g * (ab.position + ab.size * Vector3(
				float(c & 1), float((c >> 1) & 1), float((c >> 2) & 1)))
			lo = lo.min(p)
			hi = hi.max(p)
	var sz := hi - lo
	var wok: bool = absf(sz.x - EXPECT_WIDTH) < 0.12
	fail += 0 if wok else 1
	print("      인게임 크기 길이%.2f 폭%.2f 높이%.2f  (폭 기대 %.2f) %s" % [
		sz.z, sz.x, sz.y, EXPECT_WIDTH, "OK" if wok else "*** 폭 어긋남 ***"])

	# 4) 애니 전이 — 사거리 밖이면 walk, 안이면 attack. 공격 애니는 속도 배율 1.0 고정.
	e2.target = null
	e2._rhino_anim(false)
	var a1 := anim.current_animation
	var s1 := anim.speed_scale
	e2._rhino_anim(true)
	var a2 := anim.current_animation
	var s2 := anim.speed_scale
	var tok: bool = a1 == "walk" and a2 == "attack" and is_equal_approx(s2, 1.0)
	fail += 0 if tok else 1
	print("      전이 걷기=%s(%.2f배) -> 공격=%s(%.2f배) %s" % [
		a1, s1, a2, s2, "OK" if tok else "*** 틀림 ***"])
	e2.queue_free()

	# 5) 정지 위치 — 실제로 걸어와 멈춘 뒤 **뿔 끝이 성벽 어디에 서는지** 잰다.
	#    사거리는 중심점 거리라, 몸이 커지면 이 값을 안 올렸을 때 몸통이 성 안에 박힌다.
	var tgt := Node3D.new()
	root.add_child(tgt)                       # 성 중심 = 원점
	var e3 = scene.instantiate()
	e3.type_id = &"heavy"
	root.add_child(e3)
	await process_frame
	e3.global_position = Vector3(0, 0, 40)
	e3.target = tgt
	for i in 4000:                            # 느린 몹이라 넉넉히
		e3._physics_process(1.0 / 60.0)
		if e3._attacking:
			break
	var d3: float = (e3.global_position as Vector3).length()
	var front := _front_gap(e3.get_node("VisualPivot/Rhino") as Node3D, tgt.global_position)
	var sok: bool = e3._attacking and front > -1.2 and front < 0.6
	fail += 0 if sok else 1
	print("      정지 거리 %.2f  뿔 끝이 성벽에서 %+.2f (음수=파고듦, -1.2~+0.6 허용) %s" % [
		d3, front, "OK" if sok else "*** 성에 박힌다 ***"])
	print("      hit_radius %.2f (몸통 반길이 — 망치가 몸 가장자리를 때려도 맞는다)" % e3.hit_radius)
	e3.queue_free()
	tgt.queue_free()

	print("")
	print("헤비 배선 검증 통과" if fail == 0 else "헤비 배선 검증 실패 %d 건" % fail)
	quit(0 if fail == 0 else 1)

## 목표(성 중심)에 가장 가까운 정점이 성벽 바깥으로 얼마나 떨어져 있나. 음수면 파고든 것.
func _front_gap(model: Node3D, center: Vector3) -> float:
	var nearest := INF
	for mi in _all_mesh(model):
		var ab := mi.get_aabb()
		var g := mi.global_transform
		for c in 8:
			var p: Vector3 = g * (ab.position + ab.size * Vector3(
				float(c & 1), float((c >> 1) & 1), float((c >> 2) & 1)))
			nearest = minf(nearest, Vector2(p.x - center.x, p.z - center.z).length())
	return nearest - BASE_HALF

func _all_mesh(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_mesh(c))
	return out
