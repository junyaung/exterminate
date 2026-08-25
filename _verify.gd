extends SceneTree
func _init() -> void:
	_run()
func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var hs = main.get_node("HammerStrike")
	hs.has_aftershock = true
	hs.has_fire = true
	hs._cd = 0.0
	hs._strike(Vector3.ZERO, 0.0)
	await create_timer(0.7).timeout
	var fx = get_nodes_in_group("crack_fields")[0]

	var on := 0
	for i in 40:
		var p: Vector3 = fx.random_crack_point()
		var lp := Vector2(p.x - fx.global_position.x, p.z - fx.global_position.z)
		if fx._touches_crack(lp, 0.05): on += 1
	print("random_crack_point() 40회 중 균열 선 위: ", on, " / 40")

	hs._cd = 0.0
	hs._strike(Vector3.ZERO, 0.0)
	# 임팩트는 _strike 로부터 tap_swing_time(0.045) 뒤다 (평타는 예비 동작 없음).
	# 그 전에 확인하면 분화구가 아직 없다.
	await create_timer(0.4).timeout
	var crater = null
	for c in hs.get_children():
		if c is Crater: crater = c
	print("분화구 자식 노드 수: ", crater.get_child_count(), " (기대 0)")
	var pts := []
	for c in hs.get_children():
		if c is Fireball and pts.size() < 6:
			pts.append("%.1f" % Vector2(c.global_position.x, c.global_position.z).length())
	print("발사 직후 불덩이의 중심 거리: ", pts)
	print("균열 boost(맥동): ", fx._crack_mat.get_shader_parameter("boost"))
	print("")
	print("수명 (분화구 5초, 균열도 5초여야 함)")
	await create_timer(2.0).timeout
	print("  2.1s  균열 ", is_instance_valid(fx), " / 분화구 ", is_instance_valid(crater),
		" / balls ", crater.balls_fired if is_instance_valid(crater) else -1)
	await create_timer(2.5).timeout
	print("  4.6s  균열 ", is_instance_valid(fx), " / 분화구 ", is_instance_valid(crater),
		" / balls ", crater.balls_fired if is_instance_valid(crater) else -1)
	await create_timer(1.6).timeout
	print("  6.2s  균열 ", is_instance_valid(fx), " / 분화구 ", is_instance_valid(crater))
	quit()
