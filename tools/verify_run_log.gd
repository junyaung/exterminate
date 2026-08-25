extends SceneTree
## 판 기록(RunLog)이 실제 파일로 떨어지는지 검증.
## godot --headless --path . --script tools/verify_run_log.gd

func _run_checks() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	# 액트 1을 막 넘긴 상태를 흉내낸다 (5분 경과).
	main.kills = 812
	main.spawned = 1000
	main.get_node("BaseBlock").take_damage(180.0)
	main.level_system.add_xp(39.0)   # 레벨업 직전 — 카드 창이 열리면 트리가 멈춰 검증이 막힌다
	var hs = main.get_tree().get_first_node_in_group("hammer")
	hs.tap_swings = 300
	hs.charged_swings = 12
	hs.special_swings = 4
	main.elapsed = 300.5
	await physics_frame     # _physics_process 가 액트 경계를 잡아 기록한다
	await physics_frame

	print("기록 파일: ", main.run_log.path)
	print("존재: ", FileAccess.file_exists(main.run_log.path))
	var data = JSON.parse_string(FileAccess.get_file_as_string(main.run_log.path))
	print("이벤트 수: ", data.events.size(), " (기대 1)")
	print(JSON.stringify(data.events[0], "  "))

	# 패배도 남는지
	main.get_node("BaseBlock").take_damage(99999.0)
	await physics_frame
	data = JSON.parse_string(FileAccess.get_file_as_string(main.run_log.path))
	print("이벤트 수: ", data.events.size(), " (기대 2)")
	print("마지막 이벤트: ", data.events[1].event, " / 누적 피해 ",
		data.events[1].base_damage_taken, " (기대 defeat / 1000)")
	quit()

func _init() -> void:
	_run_checks()
