extends SceneTree
## '여진' + '천벌의 메아리' 를 같이 들었을 때, 우클릭 특수의 **본체와 메아리 망치 전부**가
## 여진(균열)을 남기는지 실제 낙하 경로(_special_strike)로 검증한다.
## godot --headless --path . --script tools/verify_echo_aftershock.gd

func _fields(hs: Node) -> int:
	var n := 0
	for c in hs.get_children():
		if c is AftershockFX:
			n += 1
	return n

func _wait(secs: float) -> void:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < secs:
		await process_frame

func _init() -> void:
	_run()

func _run() -> void:
	# ⚠️ **난수를 고정한다.** 메아리 착지 자리는 randf_range 로 정해지는데(_spawn_echoes),
	#    메아리가 본체 균열 **안에** 떨어지면 새 균열을 만드는 대신 기존 것을 소모한다.
	#    그래서 시드를 안 박으면 "레벨 3 -> 균열 3개" 검사가 절반쯤 무작위로 실패한다
	#    (실제로 겪었다 — 코드 변경과 무관한 오탐이었다).
	seed(20260818)
	var fail := 0
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var hs := main.get_node("HammerStrike") as HammerStrike
	hs.has_fire = false

	# 본체 1발 + 메아리 모디파이어 장수만큼 추가 = 기대 균열 수.
	# ⚠️ 예전엔 '천벌의 메아리' 카드 레벨(1->1발, 2/3->2발)이었다. 카드가 사라지고
	#    모디파이어로 합쳐진 뒤로는 **장수 = 발수**다 (수량은 합이라는 규약과 같다).
	for case in [[0, 1], [1, 2], [2, 3]]:
		var lvl: int = case[0]
		var want: int = case[1]
		hs.has_aftershock = true
		var em: Array[StringName] = []
		for i in lvl:
			em.append(&"echo")
		hs.active_mods = em
		# 이전 사례의 균열이 남아 섞이지 않게 전부 치운다
		for c in hs.get_children():
			if c is AftershockFX:
				c.free()
		hs._special_cd = 0.0
		hs._special_active = false
		hs._special_strike(Vector3(40.0 + 40.0 * lvl, 0.0, 40.0))
		# 예고 + 낙하 + 메아리 시차 + 여진 지연(0.35)까지만 기다린다.
		# ⚠️ 더 오래 기다리면 안 된다 — 균열은 LINGER(3초) 뒤 스스로 사라져서
		#    먼저 떨어진 것부터 없어진다 (레벨 3 은 시차가 짧아 먼저 만료된다).
		# 간격은 이제 레벨과 무관하게 echo_gap 하나다 (레벨 개념이 사라졌다)
		var stagger: float = hs.echo_gap
		await _wait(hs.telegraph_time() + hs.special_slam_time + stagger * 2.0 + 0.6)
		var got := _fields(hs)
		var ok: bool = got == want
		fail += 0 if ok else 1
		print("메아리 %d장 -> 균열 %d개 (기대 %d = 본체1 + 메아리%d) %s" % [
			lvl, got, want, want - 1, "OK" if ok else "***"])

	# 여진 카드가 없으면 메아리가 있어도 균열은 안 생긴다
	for c in hs.get_children():
		if c is AftershockFX:
			c.free()
	hs.has_aftershock = false
	var em: Array[StringName] = [&"echo"]
	hs.active_mods = em
	hs._special_cd = 0.0
	hs._special_active = false
	hs._special_strike(Vector3(200.0, 0.0, 40.0))
	await _wait(hs.telegraph_time() + hs.special_slam_time + hs.echo_gap * 3.0 + 1.5)
	var none := _fields(hs)
	var ok0: bool = none == 0
	fail += 0 if ok0 else 1
	print("여진 없음 + 메아리 3 -> 균열 %d개 (기대 0) %s" % [none, "OK" if ok0 else "***"])

	print("")
	print("메아리 여진 검증 통과" if fail == 0 else "메아리 여진 검증 실패 %d 건" % fail)
	quit(0 if fail == 0 else 1)
