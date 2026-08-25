extends SceneTree
## 웨이브 구조 검증 (유저 결정 2026-08-18: 10 웨이브 / 전멸해야 다음).
##   1) 웨이브 분량을 **넘겨 뱉지 않는다** (넘치면 "다 잡았는데 안 끝난다"가 된다)
##   2) 다 뱉었는데 적이 남아 있으면 웨이브가 **안 넘어간다**
##   3) 전멸시키면 다음 웨이브로 넘어가고 소강이 생긴다
##   4) 마지막 웨이브를 깨면 승리
## godot --headless --path . --script tools/verify_waves.gd

func _init() -> void:
	_run()

func _kill_all(main: Node) -> void:
	for e in main.get_tree().get_nodes_in_group("enemies"):
		(e as Enemy).die()

func _run() -> void:
	var fail := 0
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.spawning = true

	# --- 1) 분량 초과 스폰이 없는가 ---
	var w0: Dictionary = main.wave_data()
	var t0 := Time.get_ticks_msec()
	while main.wave_spawned < int(w0.count) and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
	var ok1: bool = main.wave_spawned == int(w0.count)
	fail += 0 if ok1 else 1
	print("1) 1웨이브 스폰 %d / 정원 %d (초과 없음) %s" % [
		main.wave_spawned, int(w0.count), "OK" if ok1 else "***"])

	# --- 2) 적이 남아 있으면 안 넘어간다 ---
	await process_frame
	var alive: int = main.alive_count()
	var ok2: bool = main.wave == 0 and alive > 0
	fail += 0 if ok2 else 1
	print("2) 다 뱉었지만 %d마리 생존 -> 여전히 %d웨이브 %s" % [
		alive, main.wave + 1, "OK" if ok2 else "***"])


	# --- 3) 전멸 -> 다음 웨이브 + 소강 ---
	# ⚠️ 웨이브 판정은 _physics_process 에서 돈다 — idle 프레임 두 번으로는 못 잡는다.
	#    (처음에 그렇게 짜서 "안 넘어간다"는 오탐이 났다.) 조건을 걸고 기다린다.
	_kill_all(main)
	var t1 := Time.get_ticks_msec()
	while main.wave == 0 and Time.get_ticks_msec() - t1 < 2000:
		await process_frame
	var ok3: bool = main.wave == 1 and main.wave_cleared == 1 and main._lull > 0.0
	fail += 0 if ok3 else 1
	print("3) 전멸 후 -> %d웨이브 / 클리어 %d / 소강 %.1f초 %s" % [
		main.wave + 1, main.wave_cleared, main._lull, "OK" if ok3 else "***"])

	# ⚠️ 예전엔 여기서 "하루 주기가 웨이브를 따라가는가"를 봤다. 그 기능은 뺐다
	#    (유저 지시 2026-08-18: 자동 진행 대신 낮/노을/밤을 **직접 고른다**).
	#    시간대 동작은 tools/verify_mood_clock.gd 가 본다.

	# --- 5) 마지막 웨이브를 깨면 승리 ---
	main.wave = Main.WAVE_COUNT - 1
	main.wave_spawned = int(main.wave_data().count)
	main._lull = 0.0
	_kill_all(main)
	await process_frame
	await process_frame
	var ok4: bool = main.game_over and main.victory
	fail += 0 if ok4 else 1
	print("4) 마지막 웨이브 클리어 -> 승리 %s %s" % [main.victory, "OK" if ok4 else "***"])

	print("")
	print("웨이브 검증 통과" if fail == 0 else "웨이브 검증 실패 %d 건" % fail)
	quit(0 if fail == 0 else 1)
