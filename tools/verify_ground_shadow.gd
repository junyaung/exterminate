extends SceneTree
## 인위적 접지 그림자 검증.
## ⚠️ 대상은 **개미뿐**이다 (유저 지시 2026-08-14). 콩벌레·장수풍뎅이는 몸집이 커서
##    태양 그림자로 충분하고, 타원을 겹치면 그림자가 두 겹으로 보인다.
## 개미: 붙었는지 / 크기가 발자국에 맞는지 / 지면에 붙어 있는지 / 도로 그림자를 안 드리우는지.
## 나머지: 붙지 **않았는지**.
## godot --headless --path . --script tools/verify_ground_shadow.gd

func _init() -> void:
	_run()

func _run() -> void:
	var fail := 0
	var scene := load("res://scenes/enemy.tscn") as PackedScene
	print("%-7s %-9s 그림자 크기      몸 폭   비율   높이" % ["종류", "모델"])
	for id in [&"grunt", &"heavy", &"runner"]:
		var e: Enemy = scene.instantiate()
		e.type_id = id
		root.add_child(e)
		await process_frame
		var sh := e.get_node_or_null("GroundShadow") as MeshInstance3D
		if id != &"grunt":
			var none_ok: bool = sh == null
			fail += 0 if none_ok else 1
			print("%-7s %-9s 타원 없음(태양 그림자만) %s" % [
				id, (e._mesh as Node3D).name, "OK" if none_ok else "*** 붙어 있다 ***"])
			e.queue_free()
			continue
		if sh == null:
			print("%-7s 그림자 없음 ***" % id)
			fail += 1
			e.queue_free()
			continue
		# 몸 폭 (엔티티 로컬 x) — 그림자가 이것보다 크면 발밑을 벗어난다
		var model: Node3D = e._mesh
		var inv: Transform3D = (e.global_transform as Transform3D).affine_inverse()
		var lo := INF
		var hi := -INF
		for mi in e._shadow_meshes(model):
			var ab: AABB = mi.get_aabb()
			var rel: Transform3D = inv * mi.global_transform
			for c in 8:
				var p: Vector3 = rel * (ab.position + ab.size * Vector3(
					float(c & 1), float((c >> 1) & 1), float((c >> 2) & 1)))
				lo = minf(lo, p.x)
				hi = maxf(hi, p.x)
		var body_w := hi - lo
		var pm := sh.mesh as PlaneMesh
		var ratio := pm.size.x / body_w
		var ok: bool = ratio > 0.6 and ratio < 1.0 \
			and sh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
			and sh.position.y > 0.0 and sh.position.y < 0.1 \
			and pm.size.y <= pm.size.x * Enemy.SHADOW_LEN_CAP + 0.001
		fail += 0 if ok else 1
		print("%-7s %-9s %5.2f x %5.2f   %5.2f  %.2f   y=%.2f %s" % [
			id, model.name, pm.size.x, pm.size.y, body_w, ratio, sh.position.y,
			"OK" if ok else "***"])
		e.queue_free()

	print("")
	print("접지 그림자 검증 통과" if fail == 0 else "접지 그림자 검증 실패 %d 건" % fail)
	quit(0 if fail == 0 else 1)
