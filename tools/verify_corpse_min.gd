extends SceneTree
## BossCorpse 크래시 격리 테스트 — 단계별로 어디서 죽는지 찾는다.

func _init() -> void:
	_run()

func _run() -> void:
	var parent := Node3D.new()
	root.add_child(parent)
	await process_frame

	print("1) corpse glb instantiate...")
	var sc: Node = load("res://assets/models/stag_corpse.glb").instantiate()
	print("   ok. children:")
	_dump(sc, "   ")
	var head := sc.find_child("Head", true, false) as MeshInstance3D
	print("   Head mesh: ", head.mesh if head != null else "NULL")
	var head_mesh: Mesh = head.mesh if head != null else null
	sc.free()

	print("2) BossCorpse.spawn with BoxMesh...")
	var box := BoxMesh.new()
	var c1 := BossCorpse.spawn(parent, Transform3D.IDENTITY, Vector3.ZERO,
		[{mesh = box, mats = [], shadow = true}], Vector3(1, 8, 0), Vector3.UP, 2.0)
	await process_frame
	print("   ok: ", c1)

	print("3) BossCorpse.spawn with corpse Head mesh...")
	var c2 := BossCorpse.spawn(parent, Transform3D.IDENTITY, Vector3(1.05, 0.48, 0),
		[{mesh = head_mesh, mats = [], shadow = true}], Vector3(1, 8, 0), Vector3.UP, 2.0)
	await process_frame
	print("   ok: ", c2)

	print("4) 물리 3초 (착지 + ImpactDust + 페이드)...")
	for i in 180:
		await physics_frame
	print("   ok. 남은 조각: ", _count(parent))
	print("PASS")
	quit()

func _dump(n: Node, ind: String) -> void:
	for ch in n.get_children():
		print(ind, ch.name, " (", ch.get_class(), ")")
		_dump(ch, ind + "  ")

func _count(parent: Node) -> int:
	var n := 0
	for ch in parent.get_children():
		if ch is BossCorpse:
			n += 1
	return n
