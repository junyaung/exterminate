extends SceneTree
## 불덩이에 죽은 적이 **종이처럼 타서 재가 되는지** 검증 (유저 지시 2026-08-14).
##   · 모든 셀/먹선 서피스가 burn 셰이더로 갈렸는가 (한 파트라도 빠지면 그 조각만 안 탄다)
##   · dissolve 가 0 -> 1 로 진행하는가
##   · 재 파티클이 나오는가
##   · 망치 소각과 **같은 셰이더**를 쓰는가
## godot --headless --path . --script tools/verify_burn_death.gd

func _init() -> void:
	_run()

func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out

func _check(id: StringName, scene: PackedScene) -> int:
	var bad := 0
	var e: Enemy = scene.instantiate()
	e.type_id = id
	root.add_child(e)
	await process_frame

	# ⚠️ 실제 흐름을 그대로 태운다: 불덩이는 take_damage -> die() 로 죽인 **뒤** burn_away
	#    를 부른다. die() 가 몸을 랜덤 방향으로 돌려놓으므로, 그걸 안 되돌리면
	#    타기 직전에 몸이 홱 돌아간다 (유저 제보 2026-08-14).
	e.health = 1.0
	e.take_damage(999.0, e.global_position + Vector3(1, 0, 0))
	var yaw_after_die: float = e._pivot.rotation.y
	e.burn_away()
	await process_frame
	var ok_yaw: bool = absf(e._pivot.rotation.y) < 0.001 \
		and e._pivot.position.length() < 0.001
	if not ok_yaw:
		bad += 1
	print("  %-7s 죽을 때 랜덤회전 %.2f rad -> 소각 시작 시 %.2f rad (0 이어야 한다) %s" % [
		id, yaw_after_die, e._pivot.rotation.y, "OK" if ok_yaw else "*** 몸이 돌아간다 ***"])

	# 1) 서피스 전부가 burn 셰이더인가
	var total := 0
	var burned := 0
	for mi in _meshes(e._mesh):
		for i in mi.mesh.get_surface_count():
			total += 1
			var m := mi.get_surface_override_material(i) as ShaderMaterial
			if m != null and (m.shader == Enemy.CelBurnShader or m.shader == Enemy.InkBurnShader):
				burned += 1
	if burned != total:
		bad += 1
	print("  %-7s 서피스 %d/%d 가 소각 재질 %s" % [
		id, burned, total, "OK" if burned == total else "*** 안 갈린 서피스가 있다 ***"])

	# 2) 재 파티클
	var ash: CPUParticles3D = null
	for c in e.get_children():
		if c is CPUParticles3D and c.name == "BurnAsh":
			ash = c
	if ash == null or not ash.emitting:
		bad += 1
	print("  %-7s 재 파티클 %s (개수 %d) %s" % [
		id, "있음" if ash != null else "없음", ash.amount if ash != null else 0,
		"OK" if ash != null and ash.emitting else "***"])

	# 3) dissolve 진행 — 트윈을 직접 밀어서 본다 (헤드리스 실시간에 맡기면 곡선 앞부분만 돈다)
	var tw: Tween = e._die_tw
	tw.pause()
	var m0 := _first_burn(e)
	var d0: float = m0.get_shader_parameter("dissolve")
	tw.custom_step(Enemy.BURN_TIME * 0.9)
	var d1: float = m0.get_shader_parameter("dissolve")
	if not (d1 > d0 + 0.5):
		bad += 1
	print("  %-7s dissolve %.2f -> %.2f %s" % [
		id, d0, d1, "OK" if d1 > d0 + 0.5 else "*** 안 탄다 ***"])
	e.queue_free()
	return bad

func _first_burn(e: Enemy) -> ShaderMaterial:
	for mi in _meshes(e._mesh):
		for i in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(i) as ShaderMaterial
			if m != null:
				return m
	return null

func _run() -> void:
	var fail := 0
	var scene := load("res://scenes/enemy.tscn") as PackedScene
	for id in [&"grunt", &"runner", &"heavy"]:
		fail += await _check(id, scene)

	# 4) 망치 소각과 같은 셰이더를 쓰는가 — 불에 사라지는 문법이 하나여야 한다
	var same: bool = Enemy.CelBurnShader == HammerStrike.CelBurnShader \
		and Enemy.InkBurnShader == HammerStrike.InkBurnShader
	fail += 0 if same else 1
	print("")
	print("망치 소각과 같은 셰이더 사용: %s %s" % [same, "OK" if same else "***"])

	print("")
	print("소각 사망 검증 통과" if fail == 0 else "소각 사망 검증 실패 %d 건" % fail)
	quit(0 if fail == 0 else 1)
