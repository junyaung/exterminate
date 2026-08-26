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
	var t := 0.0
	while t < secs:
		await create_timer(1.0).timeout
		t += 1.0
		print("  %2d  %4d  %5.1f  %6.2fms %6.2fms  %6d  %6d" % [
			int(t),
			m.alive_count(),
			Performance.get_monitor(Performance.TIME_FPS),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	quit()

func _autopick(ui) -> void:
	while true:
		await create_timer(0.25).timeout
		if ui._open and not ui._hand.is_empty():
			ui._pick(randi() % ui._hand.size())
