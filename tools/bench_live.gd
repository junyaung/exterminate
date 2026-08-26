extends SceneTree
## **실제 게임을 렌더까지 돌리며** 프레임 비용을 잰다. 헤드리스는 렌더를 안 하므로
## 여기서만 GPU·드로우콜이 보인다. ⚠️ --headless 를 붙이면 안 된다.
##
##   WAVE=5 SECS=25 godot --path . --script tools/bench_live.gd

func _init() -> void:
	_run()

func _run() -> void:
	var m: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var w := int(OS.get_environment("WAVE")) if OS.get_environment("WAVE") != "" else 5
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 25.0
	# 해당 웨이브로 바로 보낸다 — 5웨이브까지 실제로 기다리면 몇 분이다.
	m.wave = maxi(w - 1, 0)
	m.spawning = true
	# 드래프트가 열리면 게임이 멈춰 측정이 죽는다 — 대신 골라 준다.
	_autopick(m.get_node("CardUI"))
	print("웨이브 %d 로 이동, %d초 측정" % [w, secs])
	print("  t   적   fps   process  physics  드로우콜  렌더객체")
	# NOANIM=1 이면 도중에 모든 AnimationPlayer 를 끈다 — 애니가 process 를 얼마나
	# 먹는지 가르는 A/B. 렌더·게임 로직은 그대로 둔다.
	var noanim := OS.get_environment("NOANIM") != ""
	var t := 0.0
	while t < secs:
		await create_timer(1.0).timeout
		t += 1.0
		if noanim and int(t) == int(secs * 0.5):
			var n := 0
			for e in m.get_tree().get_nodes_in_group("enemies"):
				for a in (e as Node).find_children("*", "AnimationPlayer", true, false):
					(a as AnimationPlayer).active = false
					n += 1
			print("  --- 애니메이션 %d개 끔 ---" % n)
		print("  %2d  %4d  %5.1f  %6.2fms %6.2fms  %6d  %6d" % [
			int(t),
			m.alive_count(),
			Performance.get_monitor(Performance.TIME_FPS),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	# 무엇이 쌓였는가 — 클래스별 노드 수 상위
	var census := {}
	var stack: Array = [m]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var key: String = n.get_class()
		var scr = n.get_script()
		if scr != null:
			key += "/" + scr.resource_path.get_file()
		census[key] = census.get(key, 0) + 1
		for c in n.get_children():
			stack.append(c)
	var rows := census.keys()
	rows.sort_custom(func(a, b): return census[a] > census[b])
	print("")
	print("씬 노드 수 상위 12:")
	for i in mini(12, rows.size()):
		print("   %-42s %5d" % [rows[i], census[rows[i]]])
	quit()

func _autopick(ui) -> void:
	while true:
		await create_timer(0.25).timeout
		if ui._open and not ui._hand.is_empty():
			ui._pick(randi() % ui._hand.size())
