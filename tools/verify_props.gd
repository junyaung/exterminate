extends SceneTree
## 블렌더 프롭 → Godot 반입 검증 (2026-08-17).
##   1) glb 8종이 Body/Outline 두 노드로 읽힌다
##   2) 서피스 머티리얼 이름이 전부 셀 톤 표에 있다 (모르는 이름 = 색이 돌 톤으로 떨어진다)
##   3) 나무는 껍질/잎 **두 톤**으로 칠해진다 (한 장으로 덮이면 기둥까지 초록이 된다)
##   4) Scatter 가 실제로 깔린다 + 먹선 파트는 **그림자가 꺼져 있다**
##   5) 프롭이 기지 위에 올라가지 않는다
## godot --headless --path . --script tools/verify_props.gd

const IDS := [&"tree", &"stump", &"branch", &"boulder",
	&"stone_l", &"stone_m", &"stone_s", &"leaf"]

func _init() -> void:
	_run()

func _run() -> void:
	var fail := 0

	# --- 1~2) 모델 로드 + 머티리얼 이름 ---
	var missing := []
	var unknown := []
	for id in IDS:
		var m: Dictionary = PropModels.get_model(id)
		if not (m.has("body") and m.has("outline")):
			missing.append(id)
			continue
		var body: Mesh = m.body
		for i in body.get_surface_count():
			var mat := body.surface_get_material(i) as ShaderMaterial
			if mat == null or mat.shader == null:
				unknown.append("%s#%d" % [id, i])
	var ok1: bool = missing.is_empty() and unknown.is_empty()
	fail += 0 if ok1 else 1
	print("1) 모델 %d종 로드 / 빠짐=%s / 셀 미적용=%s %s" % [
		IDS.size(), missing, unknown, "OK" if ok1 else "***"])

	# --- 3) 나무는 두 톤 ---
	var tree: Mesh = PropModels.get_model(&"tree").get("body")
	var tones := []
	if tree != null:
		for i in tree.get_surface_count():
			var mat := tree.surface_get_material(i) as ShaderMaterial
			tones.append(mat.get_shader_parameter("light_tone"))
	var ok3: bool = tones.size() >= 2 and tones[0] != tones[1]
	fail += 0 if ok3 else 1
	print("3) 나무 서피스 톤 %s %s" % [tones, "OK" if ok3 else "***"])

	# --- 4~5) 씬에서 실제 배치 ---
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var scatter := main.get_node_or_null("Scatter")
	var mms: Array = []
	if scatter != null:
		for c in scatter.get_children():
			if c is MultiMeshInstance3D:
				mms.append(c)
	var total := 0
	var shadowed_ink := 0
	for mi in mms:
		total += (mi as MultiMeshInstance3D).multimesh.instance_count
	# 먹선 파트는 body 파트 **뒤에** 붙는다 (한 프롭당 두 개, 순서 고정).
	for i in range(1, mms.size(), 2):
		if (mms[i] as MultiMeshInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			shadowed_ink += 1
	var ok4: bool = mms.size() == IDS.size() * 2 and total > 0 and shadowed_ink == 0
	fail += 0 if ok4 else 1
	print("4) MultiMesh %d개 (기대 %d) / 인스턴스 %d / 그림자 켜진 먹선 %d %s" % [
		mms.size(), IDS.size() * 2, total, shadowed_ink, "OK" if ok4 else "***"])

	# 기지 위 침범 — 성 발자국 안에 놓인 프롭이 있으면 성이 가려진다.
	var base := main.get_node("BaseBlock") as Node3D
	var on_base := 0
	for mi in mms:
		var mm := (mi as MultiMeshInstance3D).multimesh
		for i in mm.instance_count:
			var p := mm.get_instance_transform(i).origin
			if Vector2(p.x - base.global_position.x, p.z - base.global_position.z).length() < 8.0:
				on_base += 1
	var ok5: bool = on_base == 0
	fail += 0 if ok5 else 1
	print("5) 기지 8유닛 안에 놓인 프롭 %d개 %s" % [on_base, "OK" if ok5 else "***"])

	# --- 6) 시드 저장 -> 다른 시드로 흔들어놓고 -> 다시 불러오면 같은 배치가 나오는가 ---
	# ⚠️ 저장이 됐는지가 아니라 **같은 그림이 재현되는지**를 본다. 시드만 맞고 밀도가 다르면
	#    뽑는 개수가 달라져 배치가 통째로 바뀌므로, 파일에는 둘 다 들어가야 한다.
	var before_pos: Array[Vector3] = []
	if scatter != null:
		scatter.save_map_seed()
		for i in mini(10, mms.size()):
			before_pos.append((mms[i] as MultiMeshInstance3D).multimesh.get_instance_transform(0).origin)
		scatter.seed_value += 7          # M 키를 몇 번 누른 셈
		scatter.density = 0.55
		scatter.rebuild()
		scatter.load_map_seed()
		scatter.rebuild()
		# ⚠️ rebuild() 의 queue_free 는 **프레임 끝에** 처리된다 — 바로 자식을 세면 옛 노드와
		#    새 노드를 같이 세서 개수가 두 배가 된다 (처음에 이걸로 오탐이 났다).
		await process_frame
		await process_frame
	var after: Array[MultiMeshInstance3D] = []
	if scatter != null:
		for c in scatter.get_children():
			if c is MultiMeshInstance3D:
				after.append(c)
	var same := before_pos.size() > 0 and after.size() == mms.size()
	if same:
		for i in before_pos.size():
			if after[i].multimesh.get_instance_transform(0).origin.distance_to(before_pos[i]) > 0.001:
				same = false
				break
	fail += 0 if same else 1
	print("6) 시드 저장 -> 흔들기 -> 복원 후 같은 배치 %s %s" % [same, "OK" if same else "***"])

	print("")
	print("프롭 반입 검증 통과" if fail == 0 else "프롭 반입 검증 실패 %d 건" % fail)
	quit(0 if fail == 0 else 1)
