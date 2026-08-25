extends SceneTree
## 범위 업그레이드에 따라 망치가 같이 커지는지 실측.
## 스케일뿐 아니라 **타격면이 여전히 커서 지점에 정확히 닿는지**까지 본다 —
## 크기만 키우고 역산을 안 고치면 큰 망치가 목표를 빗나간다.
## godot --headless --path . --script tools/verify_hammer_size.gd

func _init() -> void:
	_run()

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var hs = main.get_node("HammerStrike")
	var hammer: Node3D = hs.get_node("WeaponHammer")
	main.set_physics_process(false)

	print("카드   공격범위  망치배율  평타크기  풀차징크기  머리중심오차")
	for step in 3:
		if step > 0:
			hs.stats.add_pct(Stats.RADIUS, 0.15)
		var r: float = hs.stats.get_v(Stats.RADIUS)
		var rs: float = hs.radius_scale()

		# 실제로 쳐서 임팩트 순간의 크기와 타격면 위치를 잰다
		var target := Vector3(12.0, 0.0, -7.0)
		hs._cd = 0.0
		hs._strike(target, 0.0)
		await create_timer(0.25).timeout          # 임팩트(0.21s) 직후
		var tap_scale: float = hammer.scale.x
		# 머리 중심 = 그립 + 자루방향(+Y) × HEAD_CENTER_Y × s.
		# ⚠️ basis 는 **스케일을 이미 품고 있다** — normalized() 를 안 하면 s 가 두 번 곱해진다.
		# (첫 시도에서 오차 17~30 이 나온 원인이 이것. 코드가 아니라 측정이 틀렸다.)
		var head: Vector3 = hammer.global_position \
			+ hammer.global_transform.basis.y.normalized() * (HammerStrike.HEAD_CENTER_Y * tap_scale)
		var err := Vector2(head.x - target.x, head.z - target.z).length()

		await create_timer(0.6).timeout
		hs._cd = 0.0
		hs._strike(target, 1.0)
		await create_timer(0.25).timeout
		var chg_scale: float = hammer.scale.x
		await create_timer(0.6).timeout

		print("+%d장  %8.2f  %8.3f  %8.2f  %10.2f  %10.3f" % [
			step, r, rs, tap_scale, chg_scale, err])

	print("")
	print("기대: 망치배율 = 공격범위 / 기본반경(%.1f)" % hs.base_radius)
	print("      풀차징크기 = 평타크기 × charge_scale_mult(%.2f)" % hs.charge_scale_mult)
	print("      머리중심오차는 0 에 가까워야 한다 (크기가 변해도 커서에 닿는다)")
	quit()
