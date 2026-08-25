extends SceneTree
## 지면 분출 바위 검증: 본체는 blender 조각을 쓰는가 / 잔해가 같이 나오는가 /
## **아무도 안 때리는가**(2026-08-18: 바위는 전부 연출, 판정은 도넛) / 크기와 먹선이 붙는가.
## godot --headless --path . --script tools/verify_erupt_rocks.gd

func _init() -> void:
	_run()

func _rocks(parent: Node) -> Array[EruptRock]:
	var out: Array[EruptRock] = []
	for c in parent.get_children():
		if c is EruptRock:
			out.append(c)
	return out

func _run() -> void:
	var fail := 0
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var hs := main.get_node("HammerStrike") as HammerStrike

	# --- 1) 한 발 쏘면 본체 1 + 잔해 여러 개 ---
	var before := _rocks(hs).size()
	EruptRock.spawn_at(hs, Vector3(20, 0, 20), Vector3(24, 0, 22), 50.0, 1.6)
	await process_frame
	var made := _rocks(hs).slice(before)
	var bodies := 0
	var debris := 0
	for r in made:
		if r._debris:
			debris += 1
		else:
			bodies += 1
	var ok1: bool = bodies == 1 and debris >= EruptRock.DEBRIS_COUNT.x \
		and debris <= EruptRock.DEBRIS_COUNT.y
	fail += 0 if ok1 else 1
	print("1) 분출 한 번 -> 본체 %d + 잔해 %d개 (기대 본체 1, 잔해 %d~%d) %s" % [
		bodies, debris, EruptRock.DEBRIS_COUNT.x, EruptRock.DEBRIS_COUNT.y,
		"OK" if ok1 else "***"])

	# --- 2) 조각 종류: 본체는 BOULDER/ROCK, 잔해는 PEBBLE/CHIP/SHARD ---
	var kind_bad: Array[String] = []
	for r in made:
		# ⚠️ 메시 resource_name 은 'rocks_EXP_ROCK_A' 라 분류에 못 쓴다. 뽑을 때의 이름을 본다.
		var nm: String = r._pick
		var kind: String = nm.split("_")[0] if nm != "" else "?"
		var want: Array = EruptRock.DEBRIS_KINDS if r._debris else EruptRock.DAMAGE_KINDS
		if not (kind in want):
			kind_bad.append("%s(%s, debris=%s)" % [nm, kind, r._debris])
	fail += 0 if kind_bad.is_empty() else 1
	print("2) 조각 분류 어긋남: %s %s" % [
		kind_bad if not kind_bad.is_empty() else "없음", "OK" if kind_bad.is_empty() else "***"])

	# --- 3) 크기 / 먹선 / 그림자 ---
	var size_bad: Array[String] = []
	for r in made:
		var mi: MeshInstance3D = r._mesh
		# 배율은 **가장 긴 축**을 목표에 맞춘다 — 여기서도 같은 축을 재야 한다
		var sz: Vector3 = mi.mesh.get_aabb().size * mi.scale.x
		var d: float = maxf(sz.x, maxf(sz.y, sz.z))
		var lo: float = EruptRock.DEBRIS_SIZE.x if r._debris else EruptRock.SIZE_MIN.x
		var hi: float = EruptRock.DEBRIS_SIZE.y if r._debris else EruptRock.SIZE_MAX.x
		if d < lo - 0.01 or d > hi + 0.01:
			size_bad.append("%s %.2f (%.2f~%.2f)" % [r._pick, d, lo, hi])
		if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
			size_bad.append("%s 그림자꺼짐" % r._pick)
		var ink: MeshInstance3D = null
		for c in mi.get_children():
			if c is MeshInstance3D:
				ink = c
		if ink == null:
			size_bad.append("%s 먹선없음" % r._pick)
		elif ink.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			size_bad.append("%s 먹선이 그림자 드리움" % r._pick)
	fail += 0 if size_bad.is_empty() else 1
	print("3) 크기/먹선/그림자 문제: %s %s" % [
		size_bad if not size_bad.is_empty() else "없음", "OK" if size_bad.is_empty() else "***"])

	# --- 4) 착지해도 아무도 안 때리는가 (핵심) ---
	#    ⚠️ 2026-08-18 에 규칙이 바뀌었다: 분출의 **실제 판정은 도넛 면적**이고 바위는 전부
	#       연출이다 (HammerStrike._erupt_rocks). 그래서 게임이 실제로 쓰는 경로는
	#       visual_only=true 다 — 잔해든 본체든 착지가 피해를 내면 안 된다.
	#       도넛이 제대로 때리는지는 tools/verify_objects.gd 가 본다.
	var scene := load("res://scenes/enemy.tscn") as PackedScene
	var e: Enemy = scene.instantiate()
	main.add_child(e)
	await process_frame
	e.global_position = Vector3(60, 0, 60)
	var hp0: float = e.health

	var deb := EruptRock.spawn_debris(hs, Vector3(60, 0, 60), Vector3(60, 0, 60))
	deb.global_position = Vector3(60, 0.2, 60)
	deb._vel = Vector3(0, -1, 0)
	deb._land()
	await process_frame
	var hp_after_debris: float = e.health

	# 게임과 **같은 방식**으로 본체를 띄운다 — 연출 전용이다
	var body := EruptRock.spawn_at(hs, Vector3(60, 0, 60), Vector3(60, 0, 60), 0.0, 0.0)
	body.visual_only = true
	body.global_position = Vector3(60, 0.2, 60)
	body._vel = Vector3(0, -1, 0)
	body._land()
	await process_frame
	var hp_after_body: float = e.health

	var ok4: bool = is_equal_approx(hp_after_debris, hp0) and is_equal_approx(hp_after_body, hp0)
	fail += 0 if ok4 else 1
	print("4) 체력 %.0f -> 잔해 착지 후 %.0f -> 연출 본체 착지 후 %.0f (둘 다 그대로여야 함) %s" % [
		hp0, hp_after_debris, hp_after_body, "OK" if ok4 else "***"])

	# --- 5) 사라지는 연출: 서피스 전부가 투명 재질로 갈리는가 ---
	#    ⚠️ 예전엔 재질이 하나뿐이라 0번 서피스만 갈면 됐다. 지금은 몸통/흙밑동이 갈려 있어서
	#       0번만 갈면 밑동만 불투명하게 남는다. 그리고 _mat 을 참조하던 코드는 아예 죽었다
	#       (실행 중 "Cannot call method on a null value", 유저 제보 2026-08-14).
	var fr := EruptRock.spawn_at(hs, Vector3(80, 0, 80), Vector3(80, 0, 80), 10.0, 1.0)
	fr.global_position = Vector3(80, 0.2, 80)
	fr._vel = Vector3(0, -1, 0)
	fr._land()
	fr._start_fade(0.0)
	for i in 20:
		await process_frame
		if not is_instance_valid(fr):
			break
	var fade_ok := true
	if is_instance_valid(fr):
		var mi2: MeshInstance3D = fr._mesh
		for i in mi2.mesh.get_surface_count():
			var m2 := mi2.get_surface_override_material(i) as ShaderMaterial
			if m2 == null or m2.shader != EruptRock.CelFadeShader:
				fade_ok = false
	fail += 0 if fade_ok else 1
	print("5) 페이드: 서피스 전부 투명 재질로 교체 %s" % ["OK" if fade_ok else "*** 일부가 안 갈렸다 ***"])

	# --- 6) 박히는 깊이: 본체 15~25% / 잔해는 얕게 ---
	#    ⚠️ 낙하 예고 그림자는 넣었다가 **뺐다** (유저 지시 2026-08-14). 태양 그림자만으로
	#       충분하다는 판단 — 바위는 이미 cast_shadow 가 켜져 있어 공중에서 자리를 알려준다.
	var b2 := _rocks(hs).size()
	var r6 := EruptRock.spawn_at(hs, Vector3(100, 0, 100), Vector3(104, 0, 102), 50.0, 2.0)
	await process_frame
	var made6 := _rocks(hs).slice(b2)
	r6.global_position = Vector3(100, 0.2, 100)
	r6._vel = Vector3(0, -1, 0)
	r6._land()
	await process_frame
	var full: float = r6._lowest_drop() * 2.0
	var frac: float = -(r6.global_position.y - r6._lowest_drop()) / full
	var ok6: bool = frac >= EruptRock.BURY.x - 0.01 and frac <= EruptRock.BURY.y + 0.01
	fail += 0 if ok6 else 1
	print("6) 본체가 박힌 깊이 %.1f%% (기대 %.0f~%.0f%%) %s" % [
		frac * 100.0, EruptRock.BURY.x * 100.0, EruptRock.BURY.y * 100.0,
		"OK" if ok6 else "***"])

	var deb6: EruptRock = null
	for r in made6:
		if r._debris:
			deb6 = r
			break
	if deb6 != null:
		deb6.global_position = Vector3(100, 0.2, 100)
		deb6._vel = Vector3(0, -1, 0)
		deb6._land()
		await process_frame
		var dfull: float = deb6._lowest_drop() * 2.0
		var dfrac: float = -(deb6.global_position.y - deb6._lowest_drop()) / dfull
		var ok7: bool = absf(dfrac - EruptRock.BURY_DEBRIS) < 0.01
		fail += 0 if ok7 else 1
		print("7) 잔해가 박힌 깊이 %.1f%% (기대 %.0f%% — 얹힌 정도) %s" % [
			dfrac * 100.0, EruptRock.BURY_DEBRIS * 100.0, "OK" if ok7 else "***"])

	# --- 8) 파헤쳐진 흙 자국 (유저 지시 2026-08-14) ---
	#    ⚠️ 밑동 어둠과 침하 모션은 넣었다가 **뺐다** — 흙 자국 하나만 쓰기로 했다.
	var b8 := _rocks(hs).size()
	var r8 := EruptRock.spawn_at(hs, Vector3(120, 0, 120), Vector3(120, 0, 120), 10.0, 1.0)
	var made8 := _rocks(hs).slice(b8)
	r8.global_position = Vector3(120, 0.2, 120)
	r8._vel = Vector3(0, -1, 0)
	r8._land()
	await process_frame

	var d8: MeshInstance3D = r8._dirt
	var ok8: bool = d8 != null and d8.top_level \
		and d8.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
		and absf(d8.global_position.y - EruptRock.DIRT_Y) < 0.01
	fail += 0 if ok8 else 1
	print("8) 흙 자국 — 생성=%s / 회전 안물려받음=%s / 높이 %.2f %s" % [
		d8 != null, d8.top_level if d8 != null else false,
		d8.global_position.y if d8 != null else -1.0, "OK" if ok8 else "***"])

	# 자국은 바위보다 **넓어야** 밀려난 흙으로 읽힌다
	var foot: float = maxf(r8._half.x, r8._half.z)
	var half: float = (d8.mesh as PlaneMesh).size.x * 0.5 if d8 != null else 0.0
	var ok9: bool = half > foot * 1.5 and half < foot * 3.0
	fail += 0 if ok9 else 1
	print("9) 자국 반경 %.2f (바위 반폭 %.2f 의 %.1f배 — 1.5~3.0 기대) %s" % [
		half, foot, half / foot if foot > 0.0 else 0.0, "OK" if ok9 else "***"])

	# glow 는 0 이어야 한다. 기본값(1.6)이면 자국이 벌겋게 타올라 '그을린 자리'가 된다.
	var g: float = (d8.mesh as PlaneMesh).material.get_shader_parameter("glow") if d8 != null else -1.0
	var ok10: bool = is_equal_approx(g, 0.0)
	fail += 0 if ok10 else 1
	print("10) 자국 glow=%.2f (기대 0 — 불이 아니라 흙이다) %s" % [g, "OK" if ok10 else "***"])

	# 잔해엔 흙 자국이 없어야 한다
	var deb8: EruptRock = null
	for r in made8:
		if r._debris:
			deb8 = r
			break
	if deb8 != null:
		deb8.global_position = Vector3(120, 0.2, 120)
		deb8._vel = Vector3(0, -1, 0)
		deb8._land()
		await process_frame
		var ok11: bool = deb8._dirt == null
		fail += 0 if ok11 else 1
		print("11) 잔해엔 흙 자국 없음 %s" % ["OK" if ok11 else "*** 붙어 있다 ***"])

	print("")
	print("분출 바위 검증 통과" if fail == 0 else "분출 바위 검증 실패 %d 건" % fail)
	quit(0 if fail == 0 else 1)
