extends SceneTree
## 경사 대응 검증 (유저 지시 2026-08-16: 벌레도 조준 원도 경사를 타야 한다).
##   1) 지면 법선이 실제 경사와 맞는가
##   2) 벌레 몸이 그 법선을 따라 눕는가 (걷는 동안)
##   3) 조준 원이 지형을 타도록 준비됐는가 (쿼드 분할 + 높이 텍스처 연결)
##   4) 높이 텍스처 값이 height_at() 과 같은가 — 셰이더가 읽는 값이 곧 게임의 높이여야 한다
## godot --headless --path . --script tools/verify_slope_fit.gd

func _init() -> void:
	_run()

func _run() -> void:
	var fail := 0
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var g := main.get_node("Ground") as Ground
	var hs := main.get_node("HammerStrike") as HammerStrike

	# --- 1) 법선 ---
	# 평지는 정확히 위, 경사면은 기울어야 한다.
	var flat_n := g.normal_at(Main.to_world(85.0, 55.0))
	# ⚠️ 좌표를 박아두면 맵을 다시 만들 때마다 헛실패한다 (맵을 줄이자 그 자리가 평지가 됐다).
	#    **경사가 있으면서 걸을 수 있는 자리를 찾아서** 쓴다.
	var slope_at := Vector3.ZERO
	for i in 4000:
		var c := Vector3(randf_range(-60.0, 60.0), 0.0, randf_range(-60.0, 60.0))
		if g.smooth_at(c) > 0.6 and g.normal_at(c).angle_to(Vector3.UP) > deg_to_rad(6.0):
			slope_at = c
			break
	var slope_n := g.normal_at(slope_at)
	var ok1: bool = flat_n.angle_to(Vector3.UP) < 0.02 \
		and slope_n.angle_to(Vector3.UP) > 0.01
	fail += 0 if ok1 else 1
	print("1) 법선 — 벌판 %.1f도 / 비탈 %.1f도 (벌판 0, 비탈 >0) %s" % [
		rad_to_deg(flat_n.angle_to(Vector3.UP)), rad_to_deg(slope_n.angle_to(Vector3.UP)),
		"OK" if ok1 else "***"])

	# --- 2) 벌레가 경사를 따라 눕는가 ---
	var e := (load("res://scenes/enemy.tscn") as PackedScene).instantiate() as Enemy
	e.type_id = &"grunt"
	main.get_node("Enemies").add_child(e)
	e.global_position = Terrain.on(slope_at)
	e.target = main.get_node("BaseBlock")
	# ⚠️ **평균**으로 본다. 계단 턱을 넘는 순간에는 지면 법선이 홱 꺾이는데 몸은 천천히
	#    따라가므로(일부러 그렇게 뒀다) 최댓값은 그 찰나에 30도 가까이 튄다. 그걸로 재면
	#    "부드럽게 따라간다"는 의도를 실패로 잡는다.
	var worst := 0.0
	var sum := 0.0
	for i in 300:
		e._physics_process(1.0 / 60.0)
		var up: Vector3 = e.global_transform.basis.y.normalized()
		var d := rad_to_deg(up.angle_to(Terrain.normal(e.global_position)))
		worst = maxf(worst, d)
		sum += d
	var avg := sum / 300.0
	var scale_ok: bool = absf(e.scale.x - 1.0) < 0.01 and absf(e.scale.y - 1.0) < 0.01
	var ok2: bool = avg < 10.0 and scale_ok
	fail += 0 if ok2 else 1
	print("2) 몸 기울기 vs 지면 법선 — 평균 %.1f도 / 최대 %.1f도(턱 넘는 찰나), 스케일 유지 %s %s" % [
		avg, worst, scale_ok, "OK" if ok2 else "***"])
	e.queue_free()

	# --- 3) 조준 원 준비 ---
	var ind := hs.get_node("Indicator") as MeshInstance3D
	var quad := ind.mesh as PlaneMesh
	var mat := ind.material_override as ShaderMaterial
	var ok3: bool = quad != null and quad.subdivide_width >= 16 \
		and mat != null and bool(mat.get_shader_parameter("conform")) \
		and mat.get_shader_parameter("height_tex") != null
	fail += 0 if ok3 else 1
	print("3) 조준 쿼드 분할 %d / conform %s / 높이텍스처 %s %s" % [
		quad.subdivide_width if quad else -1,
		mat.get_shader_parameter("conform") if mat else null,
		mat.get_shader_parameter("height_tex") != null if mat else false,
		"OK" if ok3 else "***"])

	# --- 4) 셰이더가 읽는 높이 = 게임의 높이 ---
	var tex := g.height_texture()
	var img := tex.get_image()
	var bad := 0
	var gap := 0.0
	for i in 40:
		var gx := randi() % img.get_width()
		var gz := randi() % img.get_height()
		var w := Vector3(float(gx) * Ground.CELL - Ground.HALF, 0.0,
			float(gz) * Ground.CELL - Ground.HALF)
		var d: float = absf(img.get_pixel(gx, gz).r - g.height_at(w))
		gap = maxf(gap, d)
		if d > 0.01:
			bad += 1
	var ok4: bool = bad == 0
	fail += 0 if ok4 else 1
	print("4) 높이 텍스처 40지점 중 어긋남 %d개 (최대 %.3f) %s" % [
		bad, gap, "OK" if ok4 else "***"])

	print("")
	print("경사 대응 검증 통과" if fail == 0 else "경사 대응 검증 실패 %d 건" % fail)
	quit(0 if fail == 0 else 1)
