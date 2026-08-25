extends SceneTree
## 망치와 이펙트가 **지형 높이**를 따라가는지 검증 (2026-08-16 높이 인식 2단계).
## 예전엔 전부 y=0 을 가정해서, 고원 위를 때리면 균열·분화구·바위가 절벽 아래
## 허공이나 땅속에 생겼다.
##   1) 마우스 광선이 고원 표면을 맞힌다 (y=0 평면이 아니라)
##   2) 균열이 지면 높이에 생긴다
##   3) 분화구도 지면 높이에
##   4) 분출 바위가 그 자리 지면에 착지한다
##   5) 낮은 벌판에서도 여전히 맞다 (회귀)
## godot --headless --path . --script tools/verify_height_fx.gd

func _init() -> void:
	_run()

func _fields(hs: Node) -> Array:
	var out: Array = []
	for c in hs.get_children():
		if c is AftershockFX:
			out.append(c)
	return out

func _run() -> void:
	var fail := 0
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var g := main.get_node("Ground") as Ground
	var hs := main.get_node("HammerStrike") as HammerStrike
	var cam := main.get_node("Camera3D") as Camera3D
	# ⚠️ 지형은 지금 평지다 (유저 지시로 되돌림). 높이 처리를 검증하려면 높이가 있어야 하므로
	#    **이 검증이 직접 고원을 하나 쌓는다.** 실제 지형 파일에 기대지 않으니, 지형을
	#    바꾸든 지우든 이 검증은 그대로 돈다.
	var hill := Main.to_world(-45.0, -30.0)
	for i in 24:
		g.sculpt(hill, 26.0, 0.5)
	g.build()

	# --- 1) 마우스 광선이 지형을 맞히는가 ---
	# 고원 위 한 점을 화면 좌표로 바꾼 뒤, 그 픽셀에서 다시 광선을 쏴 같은 자리가 나오는지.
	var plateau := Terrain.on(hill)
	var px := cam.unproject_position(plateau)
	var o := cam.project_ray_origin(px)
	var d := cam.project_ray_normal(px)
	# _mouse_ground 와 같은 방식으로 훑는다 (마우스 위치를 헤드리스에서 못 만든다)
	var hit := Vector3.ZERO
	var prev := 1.0
	var t := 0.0
	while t < 400.0:
		var p := o + d * t
		var diff := p.y - g.height_at(p)
		if diff <= 0.0 and prev > 0.0:
			hit = p
			break
		prev = diff
		t += 1.0
	var ok1: bool = hit.distance_to(plateau) < 3.0 and plateau.y > 6.0
	fail += 0 if ok1 else 1
	print("1) 고원(높이 %.1f) 겨냥 -> 맞은 지점 y=%.2f, 어긋남 %.2f %s" % [
		plateau.y, hit.y, hit.distance_to(plateau), "OK" if ok1 else "***"])

	# --- 2) 균열이 지면 높이에 ---
	hs.has_aftershock = true
	hs.has_fire = false
	var at := plateau
	hs._special_blast(at, hs.special_radius(), 100.0, 1.0)
	await process_frame
	var fx = _fields(hs)[-1]
	var ok2: bool = absf(fx.global_position.y - g.height_at(at)) < 0.01
	fail += 0 if ok2 else 1
	print("2) 균열 y=%.2f / 지면 %.2f %s" % [
		fx.global_position.y, g.height_at(at), "OK" if ok2 else "***"])

	# --- 3) 분화구도 ---
	hs.has_fire = true
	hs._special_blast(Terrain.on(Main.to_world(-48.0, -28.0)),
		hs.special_radius(), 100.0, 1.0)
	await process_frame
	var crater = null
	for c in hs.get_children():
		if c is Crater:
			crater = c
	var ok3: bool = crater != null \
		and absf(crater.global_position.y - g.height_at(crater.global_position)) < 0.01
	fail += 0 if ok3 else 1
	print("3) 분화구 y=%.2f / 지면 %.2f %s" % [
		0.0 if crater == null else crater.global_position.y,
		0.0 if crater == null else g.height_at(crater.global_position),
		"OK" if ok3 else "***"])

	# --- 4) 분출 바위가 지면에 착지 ---
	hs.has_fire = false
	var before := 0
	for c in hs.get_children():
		if c is EruptRock:
			before += 1
	hs._special_blast(plateau, hs.special_radius(), 100.0, 1.0)
	# 포물선을 다 그리고 착지할 때까지 기다린다
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2500:
		await process_frame
	var landed := 0
	var worst := 0.0
	for c in hs.get_children():
		if c is EruptRock and is_instance_valid(c) and not c._debris:
			var gap: float = absf(c.global_position.y - g.height_at(c.global_position))
			# 바위는 자기 반높이만큼 위에 놓이므로 여유를 크게 본다
			if gap < 3.0:
				landed += 1
			worst = maxf(worst, gap)
	var ok4: bool = landed > 5 and worst < 3.0
	fail += 0 if ok4 else 1
	print("4) 고원 위 바위 %d개가 지면 근처(최대 어긋남 %.2f) %s" % [
		landed, worst, "OK" if ok4 else "***"])

	# --- 5) 낮은 벌판에서도 (회귀) ---
	# ⚠️ 산이 있는 판에서는 (40,30) 도 산기슭이라 0 이 아니다. 확실히 벌판인 데서 잰다.
	var field := Terrain.on(Main.to_world(85.0, 55.0))
	hs._special_blast(field, hs.special_radius(), 100.0, 1.0)
	await process_frame
	var fx2 = _fields(hs)[-1]
	var ok5: bool = absf(fx2.global_position.y - field.y) < 0.01 and field.y < 0.5
	fail += 0 if ok5 else 1
	print("5) 벌판 균열 y=%.2f / 지면 %.2f %s" % [
		fx2.global_position.y, field.y, "OK" if ok5 else "***"])

	g.clear_edits()
	g.build()

	print("")
	print("높이 이펙트 검증 통과" if fail == 0 else "높이 이펙트 검증 실패 %d 건" % fail)
	quit(0 if fail == 0 else 1)
