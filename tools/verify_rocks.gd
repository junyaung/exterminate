extends SceneTree
## 바위 asset 임포트 검증: 조각 개수 / 이름 / 본체·먹선 짝 / 재질 / 원점 / 폴리곤 수.
## godot --headless --path . --script tools/verify_rocks.gd

const KINDS := {
	"BOULDER": 6, "ROCK": 4, "PEBBLE": 4, "CHIP": 6, "SHARD": 4,
}

func _init() -> void:
	_run()

func _run() -> void:
	var fail := 0
	var ps := load("res://assets/models/rocks.glb") as PackedScene
	if ps == null:
		print("!! rocks.glb 로드 실패")
		quit(1)
		return
	var n := ps.instantiate()
	root.add_child(n)
	await process_frame

	var body := {}     # 이름 -> MeshInstance3D (본체)
	var ink := {}      # 이름 -> MeshInstance3D (먹선)
	for mi in _all_mesh(n):
		if mi.name.ends_with("Ink"):
			ink[String(mi.name).substr(0, String(mi.name).length() - 3)] = mi
		else:
			body[String(mi.name)] = mi

	# 1) 분류별 개수
	var counts := {}
	for k in body:
		var kind: String = String(k).split("_")[0]
		counts[kind] = int(counts.get(kind, 0)) + 1
	print("조각 %d개 (먹선 포함 메시 %d개)" % [body.size(), body.size() + ink.size()])
	for kind in KINDS:
		var got: int = int(counts.get(kind, 0))
		var ok: bool = got == int(KINDS[kind])
		fail += 0 if ok else 1
		print("  %-8s %d개 (기대 %d) %s" % [kind, got, KINDS[kind], "OK" if ok else "***"])

	# 2) 본체마다 먹선이 짝으로 있는가 — 하나라도 빠지면 그 조각만 외곽선이 없다
	var no_ink: Array[String] = []
	for k in body:
		if not ink.has(k):
			no_ink.append(String(k))
	fail += 0 if no_ink.is_empty() else 1
	print("먹선 없는 조각: %s %s" % [
		no_ink if not no_ink.is_empty() else "없음", "OK" if no_ink.is_empty() else "***"])

	# 3) 재질 이름 — Godot 쪽에서 이름으로 색을 꽂을 것이므로 이게 살아 있어야 한다
	var mat_names := {}
	for k in body:
		for i in body[k].mesh.get_surface_count():
			var m: Material = body[k].mesh.surface_get_material(i)
			mat_names[m.resource_name if m != null else "?"] = true
	var want_mats := ["Cel_RockTop", "Cel_RockBase"]
	var mats_ok := true
	for w in want_mats:
		if not mat_names.has(w):
			mats_ok = false
	fail += 0 if mats_ok else 1
	print("본체 재질: %s (기대 %s) %s" % [
		mat_names.keys(), want_mats, "OK" if mats_ok else "***"])

	# 4) 원점이 무게중심인가 — 무작위 회전이 제자리에서 돌아야 한다.
	#    AABB 중심이 원점에서 반지름의 25% 안이면 합격으로 본다 (볼록껍질이라 완전 일치는 아니다).
	var off_bad: Array[String] = []
	var rmin := INF
	var rmax := -INF
	for k in body:
		var ab: AABB = body[k].mesh.get_aabb()
		var c: Vector3 = ab.position + ab.size * 0.5
		var r: float = ab.size.length() * 0.5
		rmin = minf(rmin, r)
		rmax = maxf(rmax, r)
		if c.length() > r * 0.25:
			off_bad.append("%s(%.3f)" % [k, c.length()])
	fail += 0 if off_bad.is_empty() else 1
	print("원점 어긋난 조각: %s %s" % [
		off_bad if not off_bad.is_empty() else "없음", "OK" if off_bad.is_empty() else "***"])
	print("반지름 범위 %.3f ~ %.3f (게임에서 배율을 곱해 쓴다)" % [rmin, rmax])

	# 5) 폴리곤 예산
	var tris := 0
	for mi in _all_mesh(n):
		for s in mi.mesh.get_surface_count():
			tris += mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
	print("총 삼각형 %d (조각당 평균 %.1f, 먹선 포함)" % [tris, float(tris) / float(body.size())])

	n.queue_free()
	print("")
	print("바위 asset 검증 통과" if fail == 0 else "바위 asset 검증 실패 %d 건" % fail)
	quit(0 if fail == 0 else 1)

func _all_mesh(nd: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if nd is MeshInstance3D and (nd as MeshInstance3D).mesh != null:
		out.append(nd)
	for c in nd.get_children():
		out.append_array(_all_mesh(c))
	return out
