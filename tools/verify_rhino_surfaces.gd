extends SceneTree
## 파트별 서피스에 **그 서피스의 재질에 맞는 색**이 꽂혔는지 검증한다.
##
## ⚠️ 이 검사가 왜 필요한가: glTF 는 그 파트가 실제로 쓰는 재질만 프리미티브로 만든다.
##    블렌더 슬롯이 4개여도 임포트 후 서피스는 1~2개다. 그래서 "슬롯 번호 = 서피스 번호"
##    라는 가정으로 색을 꽂으면 **엉뚱한 부위가 칠해진다** — 실제로 장수풍뎅이 뿔이
##    딱지날개색으로 칠해져 상아뿔 배색이 인게임에 한 번도 안 나왔다 (2026-08-14).
##    사슴벌레(보스)도 같은 방식이라 같이 본다.
## godot --headless --path . --script tools/verify_rhino_surfaces.gd

func _init() -> void:
	_run()

func _hex(m: Material) -> String:
	var sm := m as ShaderMaterial
	if sm == null:
		var st := m as StandardMaterial3D
		return st.albedo_color.to_html(false) if st != null else "?"
	var c = sm.get_shader_parameter("light_tone")
	return (c as Color).to_html(false) if c != null else "?"

## want: glb 재질 이름 -> 기대하는 밝은색 hex
func _check(title: String, model: Node3D, parts: Array, want: Dictionary) -> int:
	print("[%s]" % title)
	var bad := 0
	for part in parts:
		var mi := model.find_child(String(part), true, false) as MeshInstance3D
		if mi == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			var nm := src.resource_name if src != null else ""
			var ov := mi.get_surface_override_material(i)
			var got := _hex(ov) if ov != null else "미배정"
			var exp := "?"
			for key in want:
				if nm.begins_with(String(key)):
					exp = String(want[key])
			var ok: bool = exp != "?" and got.to_lower() == exp.to_lower()
			if not ok:
				bad += 1
			print("  %-11s s%d %-18s -> #%-8s (기대 #%s) %s" % [
				part, i, nm, got, exp, "OK" if ok else "*** 틀림 ***"])
	return bad

func _run() -> void:
	var bad := 0
	var scene := load("res://scenes/enemy.tscn") as PackedScene
	var e: Enemy = scene.instantiate()
	e.type_id = &"heavy"
	root.add_child(e)
	await process_frame
	bad += _check("장수풍뎅이 (헤비)", e.get_node("VisualPivot/Rhino"), e.RHINO_PARTS, {
		"Cel_RhinoElytra": "3e2731",   # 딱지날개 = 어두운 몸
		"Cel_RhinoPron":   "c28569",   # 전흉배판 + 가슴뿔 = 상아
		"Cel_RhinoDark":   "3e2731",   # 머리·다리
		"Cel_RhinoHair":   "262b44",   # 털 술
	})
	e.queue_free()

	print("")
	var boss = load("res://scenes/boss.tscn").instantiate()
	root.add_child(boss)
	await process_frame
	bad += _check("사슴벌레 (보스)", boss.get_node("VisualPivot/Stag"),
		[&"Head", &"Thorax", &"Abdomen"], {
			"Cel_StagShell": "3a4466",
			"Cel_StagGold":  "fee761",
			"Cel_StagLimb":  "262b44",
			"Stag_Eye":      "ff0044",
		})
	# 시체 조각(비스킨 정적 메시)도 같은 이름 매칭을 타는지 본다 — 여기가 어긋나면
	# 살아있을 땐 멀쩡한데 **죽는 순간 색이 바뀐다**.
	print("")
	print("[사슴벌레 시체 조각 (비스킨)]")
	for part in [&"Head", &"Thorax", &"Abdomen"]:
		var cm: Dictionary = boss.corpse_meshes()[part]
		if cm.mesh == null:
			continue
		var order: Array = boss.stag_surface_mats(cm.mesh)
		for i in (cm.mesh as Mesh).get_surface_count():
			var src: Material = (cm.mesh as Mesh).surface_get_material(i)
			var nm: String = src.resource_name if src != null else ""
			var got: String = _hex(order[i])
			var exp := "?"
			for key in {"Cel_StagShell": "3a4466", "Cel_StagGold": "fee761",
					"Cel_StagLimb": "262b44", "Stag_Eye": "ff0044"}:
				if nm.begins_with(key):
					exp = {"Cel_StagShell": "3a4466", "Cel_StagGold": "fee761",
						"Cel_StagLimb": "262b44", "Stag_Eye": "ff0044"}[key]
			var ok: bool = exp != "?" and got.to_lower() == exp.to_lower()
			if not ok:
				bad += 1
			print("  %-11s s%d %-18s -> #%-8s (기대 #%s) %s" % [
				part, i, nm, got, exp, "OK" if ok else "*** 틀림 ***"])
	boss.queue_free()

	print("")
	print("서피스 배색 검증 통과" if bad == 0 else "서피스 배색 검증 실패 %d 건" % bad)
	quit(0 if bad == 0 else 1)
