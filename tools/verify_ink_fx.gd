extends SceneTree
## 균열/분출화염 먹선 검증 — 셰이더 컴파일과 **구워 넣은 UV** 를 직접 잰다.
## godot --headless --path . --script tools/verify_ink_fx.gd
##
## 헤드리스는 그림을 못 그리므로, 먹선이 나올 조건(UV.y = ±1, UV2.x = 반폭)이
## 메시에 실제로 들어갔는지를 본다. 안 들어가면 셰이더가 아무리 맞아도 선이 안 나온다.

func _init() -> void:
	_run()

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_physics_process(false)
	var ok := true

	# 1) 균열 메시의 UV 굽기
	var fx := AftershockFX.new()
	main.add_child(fx)
	fx.begin(4.5, 1.0)
	await process_frame
	var crack: MeshInstance3D = null
	for c in fx.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is ArrayMesh \
				and (c as MeshInstance3D).mesh.get_surface_count() > 0:
			var m := (c as MeshInstance3D).get_active_material(0)
			if m is ShaderMaterial and (m as ShaderMaterial).shader.resource_path.ends_with("crack.gdshader"):
				crack = c
				break
	if crack == null:
		print("FAIL: 균열 메시를 못 찾음")
		quit()
		return

	var arr: Array = crack.mesh.surface_get_arrays(0)
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var uv2v = arr[Mesh.ARRAY_TEX_UV2]
	print("균열 정점 %d개" % uv.size())
	if uv2v == null:
		print("FAIL: UV2 가 없다 — 반폭이 안 구워졌으니 먹선 굵기를 못 정한다")
		ok = false
	else:
		var uv2: PackedVector2Array = uv2v
		var side_lo := 9.9
		var side_hi := -9.9
		var hw_lo := 9.9
		var hw_hi := -9.9
		for i in uv.size():
			side_lo = minf(side_lo, uv[i].y)
			side_hi = maxf(side_hi, uv[i].y)
			hw_lo = minf(hw_lo, uv2[i].x)
			hw_hi = maxf(hw_hi, uv2[i].x)
		print("  UV.y(가로 위치) %.2f ~ %.2f  (기대 -1 ~ 1)" % [side_lo, side_hi])
		print("  UV2.x(반폭)     %.3f ~ %.3f  (0 이면 먹선이 안 보인다)" % [hw_lo, hw_hi])
		if side_lo > -0.99 or side_hi < 0.99 or hw_lo <= 0.0:
			ok = false
		# 먹선이 균열을 다 덮어버리지 않는지: 가장 가는 곳의 반폭 > 먹선 굵기
		print("  가장 가는 반폭 %.3f vs 먹선 %.3f — %s" % [hw_lo, AftershockFX.CRACK_INK,
			"OK (심이 남는다)" if hw_lo > AftershockFX.CRACK_INK else "먹선이 통째로 덮는다"])
		if hw_lo <= AftershockFX.CRACK_INK:
			ok = false

	var cm := crack.get_active_material(0) as ShaderMaterial
	print("균열 ink_width = %.3f (기대 %.3f)" % [
		cm.get_shader_parameter("ink_width"), AftershockFX.CRACK_INK])
	if not is_equal_approx(cm.get_shader_parameter("ink_width"), AftershockFX.CRACK_INK):
		ok = false

	# 2) 분출 화염 먹선 — 켠 쪽만 켜져야 한다.
	# 화염(lava_flame)은 **불 속성 카드가 여진과 결합했을 때만** 나온다(ignite -> 용암 모드).
	# 그냥 erupt() 면 금색 빛줄기(light_ray)라 화염이 0장이다.
	# ⚠️ erupt() 는 `active` 일 때만 동작한다 — fire() 로 지대를 살려둬야 한다.
	fx.ignite()
	fx.fire(4.5)
	fx.erupt()
	await process_frame
	var flames := 0
	var inked := 0
	for c in fx.get_children():
		if not (c is MeshInstance3D):
			continue
		var mm := (c as MeshInstance3D).mesh
		if not (mm is QuadMesh) or mm.material == null:
			continue
		var sm := mm.material as ShaderMaterial
		if sm == null or not sm.shader.resource_path.ends_with("lava_flame.gdshader"):
			continue
		flames += 1
		if sm.get_shader_parameter("ink_width") != null \
				and float(sm.get_shader_parameter("ink_width")) > 0.0:
			inked += 1
	print("분출 화염 %d장 중 먹선 켜진 것 %d장 (기대 전부)" % [flames, inked])
	if flames == 0 or inked != flames:
		ok = false

	# 3) 폭연 화염은 **꺼진 채**여야 한다 (유저: 폭연 룩은 손대지 말 것)
	Deflagration.detonate(main, Vector3(20, 0, 20), 3.0, 50.0, 0.0)
	for i in 80:
		paused = false
		await physics_frame
	var d_flames := 0
	var d_inked := 0
	for c in main.get_children():
		if not (c is Deflagration):
			continue
		for q in c.get_children():
			if not (q is MeshInstance3D):
				continue
			var mm := (q as MeshInstance3D).mesh
			if not (mm is QuadMesh) or mm.material == null:
				continue
			var sm := mm.material as ShaderMaterial
			if sm == null or not sm.shader.resource_path.ends_with("lava_flame.gdshader"):
				continue
			d_flames += 1
			var w = sm.get_shader_parameter("ink_width")
			if w != null and float(w) > 0.0:
				d_inked += 1
	print("폭연 화염 %d장 중 먹선 켜진 것 %d장 (기대 0 — 폭연 룩 유지)" % [d_flames, d_inked])
	if d_inked != 0:
		ok = false

	print("결과: ", "PASS" if ok else "FAIL")
	quit()
