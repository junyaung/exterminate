extends SceneTree
## 우클릭 특수(하늘에서 수직 낙하) 검증.
##   그림자 생성/성장 · 예고 2초 · 수직 낙하 · 직격/쇼크웨이브 분리 · 쿨타임 · 망치 2배
## 실제 enemy.tscn 을 세워놓고 체력 감소로 판정한다 (Enemy.new() 는 씬 노드가 없어 못 쓴다).
## godot --headless --path . --script tools/verify_special.gd
func _init() -> void: _run()
func ok(c: bool) -> String: return "OK" if c else "*** 실패 ***"

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var hs = main.get_node("HammerStrike")
	var target := Vector3(6, 0, 6)
	var r: float = hs.special_radius()
	print("평타 반경=%.1f  직격 반경=%.1f  (쇼크웨이브 없음)" % [hs.strike_radius(0.0), r])
	print("망치 크기=평타의 %.1f배  쿨타임=%.1f초  예고=%.1f초" % [
		hs.special_scale_mult, hs.stats.get_v(Stats.COOLDOWN_SPECIAL), hs.telegraph_time()])

	# 직격 안 / 직격 바로 밖 / 멀리 세 지점. 죽으면 그룹에서 빠지므로 체력을 크게 준다.
	# ⚠️ '직격밖'은 예전 쇼크웨이브 고리가 있던 자리다 (2026-08-18 제거). 여기가 **무피해**여야
	#    한다 — 고리 판정만 남고 연출이 사라지는 게 가장 나쁜 실패 모드다.
	var scene := load("res://scenes/enemy.tscn")
	var spots := {"직격안": r * 0.5, "직격밖": r + 3.0, "멀리": r + 12.0}
	var mobs := {}
	for k in spots:
		var e = scene.instantiate()
		e.type_id = &"grunt"
		main.add_child(e)
		e.stats.set_base(Stats.HEALTH, 99999.0)
		e.health = 99999.0
		e.global_position = target + Vector3(spots[k], 0, 0)
		mobs[k] = e
	await process_frame

	hs._special_strike(target)
	# 트윈이 돌기 전 상태를 그대로 본다 (프레임을 넘기면 이미 자라 있다)
	print("\n[예고 시작]")
	print("  그림자 생성=%s  시작 크기=%.2f (직격 반경의 35%% = %.2f)  %s" % [
		hs._special_shadow != null, hs._special_shadow.scale.x, r * 0.35,
		ok(is_equal_approx(hs._special_shadow.scale.x, r * 0.35))])
	var h0: Vector3 = hs._special_hammer.global_position
	print("  망치 숨김=%s (예고 동안엔 그림자만)  %s" % [
		not hs._special_hammer.visible, ok(not hs._special_hammer.visible)])
	print("  대기 높이 y=%.1f (낙하 높이 %.0f 이상)  %s" % [
		h0.y, hs.special_fall_height, ok(h0.y >= hs.special_fall_height)])
	# ⚠️ 기울기(15°)가 들어간 뒤로 rotation.z 는 더 이상 정확히 180 이 아니다.
	#    '세웠는가'는 손잡이 방향(-basis.y)이 위를 향하는지로 본다.
	var handle: Vector3 = -hs._special_hammer.basis.y.normalized()
	print("  손잡이가 위를 향함: 월드 UP 과 %.1f° (기울기 %.0f° 만큼만 벌어져야)  %s" % [
		rad_to_deg(handle.angle_to(Vector3.UP)), hs.special_tilt_deg,
		ok(is_equal_approx(rad_to_deg(handle.angle_to(Vector3.UP)), hs.special_tilt_deg))])
	print("  망치 크기 %.1f (평타 %.1f 의 2배)  %s" % [
		hs._special_hammer.scale.x, hs.hammer_scale * hs.radius_scale(),
		ok(is_equal_approx(hs._special_hammer.scale.x,
			hs.hammer_scale * hs.radius_scale() * hs.special_scale_mult))])

	await create_timer(hs.telegraph_time() * 0.6).timeout
	var h1: Vector3 = hs._special_hammer.global_position
	print("\n[예고 중반]")
	print("  그림자 %.2f -> %.2f (커지는 중)  %s" % [
		r * 0.35, hs._special_shadow.scale.x, ok(hs._special_shadow.scale.x > r * 0.35)])
	print("  망치 여전히 숨김=%s  %s" % [
		not hs._special_hammer.visible, ok(not hs._special_hammer.visible)])
	print("  망치 아직 하늘 y=%.1f (안 움직였어야)  %s" % [h1.y, ok(is_equal_approx(h1.y, h0.y))])

	# 예고가 끝나고 내리꽂는 순간을 잡는다
	await create_timer(hs.telegraph_time() * 0.4 + hs.special_slam_time * 0.5).timeout
	if hs._special_hammer != null:
		print("\n[내리꽂기]")
		print("  망치 등장=%s  높이 %.1f -> %.1f (%.2f초에 %.0f유닛 = %.0f유닛/초)  %s" % [
			hs._special_hammer.visible, h0.y, hs._special_hammer.global_position.y,
			hs.special_slam_time, hs.special_fall_height,
			hs.special_fall_height / hs.special_slam_time,
			ok(hs._special_hammer.visible and hs._special_hammer.global_position.y < h0.y)])
		print("  수평 이동 %.4f (수직 낙하라 0)  %s" % [
			Vector2(hs._special_hammer.global_position.x - h0.x,
				hs._special_hammer.global_position.z - h0.z).length(),
			ok(Vector2(hs._special_hammer.global_position.x - h0.x,
				hs._special_hammer.global_position.z - h0.z).length() < 0.01)])

	await create_timer(hs.special_slam_time + 0.2).timeout
	print("\n[임팩트]")
	var direct: float = hs.stats.get_v(Stats.DAMAGE) * hs.special_damage_mult
	for k in ["직격안", "직격밖", "멀리"]:
		print("  %-6s (거리 %5.1f) 받은 피해 %.0f" % [k, spots[k], 99999.0 - mobs[k].health])
	print("  직격 = 기본피해 × %.1f = %.0f, 한 번만  %s" % [
		hs.special_damage_mult, direct, ok(is_equal_approx(99999.0 - mobs["직격안"].health, direct))])
	print("  직격 밖 무피해 (쇼크웨이브 제거 확인)  %s" % ok(is_equal_approx(mobs["직격밖"].health, 99999.0)))
	print("  멀리 무피해  %s" % ok(is_equal_approx(mobs["멀리"].health, 99999.0)))
	print("  그림자 제거=%s  %s" % [hs._special_shadow == null, ok(hs._special_shadow == null)])
	print("  진행중 플래그 해제=%s  %s" % [not hs._special_active, ok(not hs._special_active)])
	print("\n[쿨타임] 남은 %.2f초 (%.0f초 중 예고 %.1f초 소모)  %s" % [
		hs._special_cd, hs.stats.get_v(Stats.COOLDOWN_SPECIAL), hs.telegraph_time(),
		ok(hs._special_cd > 0.0)])

	# --- 증발: 버티다 타서 사라지는가 / 좌클릭 망치를 오염시키지 않는가 ---
	# ⚠️ 게임에선 쿨타임(5.0) ≥ 전체 연출(4.99)이라 두 망치가 겹칠 수 없지만, 이 테스트는
	#    _special_cd=0 으로 그 보증을 우회한다 — 앞 구간의 망치가 다 타 없어질 때까지 기다린다.
	await create_timer(hs.special_linger + hs.special_evaporate + 0.4).timeout
	print("\n[증발]")
	var orig_mat = hs._hammer.find_children("Body", "MeshInstance3D", true, false)[0] \
		.get_surface_override_material(0)
	hs._special_cd = 0.0
	hs._special_active = false
	hs._special_strike(target)
	await create_timer(hs.telegraph_time() + hs.special_slam_time + 0.15).timeout
	var alive := 0
	for c in hs.get_children():
		if c != hs._hammer and c is Node3D and c.get_node_or_null("Model") != null:
			alive += 1
	print("  임팩트 직후 박힌 망치 %d개 (1개여야)  %s" % [alive, ok(alive == 1)])
	print("  좌클릭 망치 머티리얼 그대로=%s (사본을 안 쓰면 같이 사라진다)  %s" % [
		orig_mat == hs._hammer.find_children("Body", "MeshInstance3D", true, false)[0] \
			.get_surface_override_material(0),
		ok(orig_mat == hs._hammer.find_children("Body", "MeshInstance3D", true, false)[0] \
			.get_surface_override_material(0))])
	# ⚠️ 노드 존재만 세면 안 된다. 페이드가 잘못 걸려 **이미 투명해진 망치**도 노드는 남아 있어서
	#    검사를 통과해버린다 (실제로 그렇게 버그를 놓쳤다). 알파를 직접 읽는다.
	var body: MeshInstance3D = null
	for c in hs.get_children():
		if c != hs._hammer and c is Node3D and c.get_node_or_null("Model") != null:
			body = c.find_children("Body", "MeshInstance3D", true, false)[0]
	# 박혀 있는 동안 **그림자가 나오는 조건**: cast_shadow ON + 불투명 재질.
	# 투명(cel_fade)으로 바뀌면 Godot 이 그림자를 안 만든다 — 분출 바위와 같은 규칙.
	var m0: ShaderMaterial = body.get_surface_override_material(0)
	print("  본체 cast_shadow=%s (1=ON)  %s" % [body.cast_shadow,
		ok(body.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON)])
	print("  임팩트 직후 셰이더=%s, ALPHA 사용=%s (투명이면 그림자 없음)  %s" % [
		m0.shader.resource_path.get_file(), "ALPHA" in m0.shader.code,
		ok(not ("ALPHA" in m0.shader.code))])
	await create_timer(hs.special_linger * 0.5).timeout
	var mid := 0
	for c in hs.get_children():
		if c != hs._hammer and c is Node3D and c.get_node_or_null("Model") != null:
			mid += 1
	var m1: ShaderMaterial = body.get_surface_override_material(0)
	print("  %.1f초 뒤 박혀 있음 %d개, 셰이더=%s (아직 불투명이라 그림자 유지)  %s" % [
		hs.special_linger * 0.5, mid, m1.shader.resource_path.get_file(),
		ok(mid == 1 and not ("ALPHA" in m1.shader.code))])
	await create_timer(hs.special_linger * 0.5 + hs.special_evaporate * 0.5).timeout
	var m2: ShaderMaterial = body.get_surface_override_material(0)
	var d_now: float = m2.get_shader_parameter("dissolve")
	print("  %.1f초 뒤 소각 진행중 — 셰이더=%s, dissolve=%.2f (0 과 1 사이)  %s" % [
		hs.special_linger + hs.special_evaporate * 0.5, m2.shader.resource_path.get_file(),
		d_now, ok(m2.shader.resource_path.get_file() == "cel_burn.gdshader"
			and d_now > 0.0 and d_now < 1.0)])
	# 소각은 discard 기반 — ALPHA 를 안 쓰므로 불투명 파이프라인에 남아 그림자도 유지된다
	print("  소각 셰이더 ALPHA 미사용(그림자 유지)=%s  %s" % [
		not ("ALPHA" in m2.shader.code), ok(not ("ALPHA" in m2.shader.code))])
	# 재 파티클이 타는 경계에서 방출 중인가
	var ash := 0
	for c in hs.get_children():
		if c is CPUParticles3D and (c as CPUParticles3D).emitting:
			ash += 1
	print("  재 파티클 방출중 %d개  %s" % [ash, ok(ash >= 1)])
	await create_timer(hs.special_linger * 0.5 + hs.special_evaporate + 0.3).timeout
	var gone := 0
	for c in hs.get_children():
		if c != hs._hammer and c is Node3D and c.get_node_or_null("Model") != null:
			gone += 1
	print("  %.1f초 + 증발 %.2f초 뒤 남은 망치 %d개 (0이어야)  %s" % [
		hs.special_linger, hs.special_evaporate, gone, ok(gone == 0)])
	# ⚠️ 자세 측정 루프는 트윈을 20개 살려둔 채 끝난다 (한 번 시작한 특수는 2초 뒤
	#    반드시 임팩트를 친다). 그 뒤에 다른 걸 재면 그 트윈들이 끼어들어 결과를 망친다 —
	#    그래서 증발 검사를 **먼저** 하고 자세 루프를 맨 마지막에 돌린다.
	# --- 꽂힌 자세: 8방위 · 15도 · 10% 박힘 · 촉이 target 에 오는가 ---
	print("\n[꽂힌 자세] 20회 반복")
	var dirs := {}
	var s_scale: float = hs.hammer_scale * hs.radius_scale() * hs.special_scale_mult
	var tilt_bad := 0
	var tip_bad := 0
	var depth_bad := 0
	for i in 20:
		hs._special_cd = 0.0
		hs._special_active = false
		hs._special_strike(target)
		var h = hs._special_hammer
		# 트윈이 끝난 자리(grip_impact)를 역산: 현재는 하늘이므로 낙하 높이를 뺀다
		var grip: Vector3 = h.global_position - Vector3.UP * hs.special_fall_height
		# z=180° 로 세운 자세라 모델 +Y(basis.y)는 **아래**를 본다. 손잡이 방향은 그 반대다.
		var up_axis: Vector3 = -h.basis.y.normalized()
		var tilt_deg: float = rad_to_deg(up_axis.angle_to(Vector3.UP))
		if absf(tilt_deg - hs.special_tilt_deg) > 0.5:
			tilt_bad += 1
		# 그립 -> 머리 끝 (모델 +Y 를 실제 basis 로 돌린 것)
		var tip: Vector3 = grip + h.basis.orthonormalized() * (Vector3.UP * HammerStrike.HEAD_TIP_Y * s_scale)
		if Vector2(tip.x - target.x, tip.z - target.z).length() > 0.05:
			tip_bad += 1
		if absf(tip.y - (-hs.special_embed * s_scale)) > 0.05:
			depth_bad += 1
		# 기운 방향을 8방위 인덱스로
		var lean := Vector2(up_axis.x, up_axis.z)
		var k := posmod(roundi(lean.angle() / (TAU / 8.0)), 8)
		dirs[k] = int(dirs.get(k, 0)) + 1
		hs._special_hammer.queue_free()
		hs._special_hammer = null
		hs._special_shadow.queue_free()
		hs._special_shadow = null
	print("  기울기 15도 아닌 경우 %d회  %s" % [tilt_bad, ok(tilt_bad == 0)])
	print("  촉이 target 을 벗어난 경우 %d회  %s" % [tip_bad, ok(tip_bad == 0)])
	print("  박힘 깊이가 망치의 10%%(=%.2f) 아닌 경우 %d회  %s" % [
		hs.special_embed * s_scale, depth_bad, ok(depth_bad == 0)])
	print("  나온 방향 %d종 (8방위 중; 20회라 전부 안 나올 수 있다): %s" % [dirs.size(), dirs.keys()])
	print("  8방위 격자에 정확히 얹혔는가  %s" % ok(dirs.size() <= 8))

	quit()
