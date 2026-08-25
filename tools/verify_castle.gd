extends SceneTree
## 성의 자동 사격 + 횃불 + 보스 크기 검증 (유저 요청 2026-08-17).
##   1) 보스가 2배로 커졌고 피격 반경도 같이 커졌다
##   2) 궁수가 **사거리 안**의 적만 쏜다
##   3) 표적 규칙이 모드대로 고른다 (가장 가까운 / 가장 강한 / 가장 먼)
##   4) 사격 즉시 궤적선이 생기고, **짧은 비행 뒤** 피해가 들어간다 (화살 메시는 없다)
##   6) 러너(HP 50)는 한 방에 죽는다
##   5) 횃불이 성 양옆에 있고, 불꽃이 흔들린다
## godot --headless --path . --script tools/verify_castle.gd

func _init() -> void:
	_run()

func _spawn(main: Node, at: Vector3, hp: float, type_id := &"grunt") -> Enemy:
	var e := (load("res://scenes/enemy.tscn") as PackedScene).instantiate() as Enemy
	e.type_id = type_id
	main.get_node("Enemies").add_child(e)
	e.global_position = at
	e.health = hp
	return e

func _run() -> void:
	var fail := 0
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var archer := main.get_node("CastleArcher") as CastleArcher
	var base := main.get_node("BaseBlock") as Node3D

	# --- 1) 보스 크기 ---
	var stag: Dictionary = Enemy.TYPES[&"stag"]
	var ok1: bool = absf(float(stag.scale) - 28.0) < 0.01 \
		and absf(float(stag.hit_radius) - 16.8) < 0.01
	fail += 0 if ok1 else 1
	print("1) 보스 크기 %.1f / 피격반경 %.1f (기대 28.0 / 16.8) %s" % [
		stag.scale, stag.hit_radius, "OK" if ok1 else "***"])

	# --- 2) 사거리 밖은 안 쏜다 ---
	var near := _spawn(main, base.global_position + Vector3(10.0, 0.0, 0.0), 500.0)
	var far := _spawn(main, base.global_position + Vector3(120.0, 0.0, 0.0), 500.0)
	var pick := archer._pick()
	var ok2: bool = pick == near
	fail += 0 if ok2 else 1
	print("2) 사거리 %.0f — 10 유닛 적을 고름=%s (120 유닛 적은 무시) %s" % [
		archer.range_units, pick == near, "OK" if ok2 else "***"])

	# --- 3) 모드별 표적 ---
	var mid := _spawn(main, base.global_position + Vector3(30.0, 0.0, 0.0), 900.0)
	archer.mode = CastleArcher.Mode.NEAREST
	var a := archer._pick()
	archer.mode = CastleArcher.Mode.STRONGEST
	var b := archer._pick()
	archer.mode = CastleArcher.Mode.FARTHEST
	var c := archer._pick()
	var ok3: bool = a == near and b == mid and c == mid
	fail += 0 if ok3 else 1
	print("3) 가장가까운=%s / 가장강한=%s / 가장먼=%s (기대 10유닛 / 900체력 / 30유닛) %s" % [
		"10유닛" if a == near else "?", "900체력" if b == mid else "?",
		"30유닛" if c == mid else "?", "OK" if ok3 else "***"])
	archer.mode = CastleArcher.Mode.NEAREST

	# --- 4) 궤적선은 즉시, 피해는 도착 후 ---
	# ⚠️ **쏜 다음 프레임엔 아직 안 맞아야 한다.** 여기가 헐거우면 즉발(저격총)로 돌아가도
	#    테스트가 통과해버린다. 궤적선 존재 / 화살 메시 부재도 같이 본다.
	var before := near.health
	archer._cd = 0.0
	await process_frame
	var tracer: Node = null
	var arrow: Node = null
	for ch in main.get_children():
		if ch.name.begins_with("Tracer"):
			tracer = ch
		if ch.name.begins_with("Arrow"):
			arrow = ch
	var in_flight: bool = tracer != null and near.health == before
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1500 and near.health >= before:
		await process_frame
	var ok4: bool = in_flight and near.health < before and arrow == null
	fail += 0 if ok4 else 1
	print("4) 궤적선=%s / 발사 직후 무피해=%s / 도착 후 %.0f -> %.0f / 화살메시=%s %s" % [
		tracer != null, in_flight, before, near.health, arrow != null, "OK" if ok4 else "***"])

	# --- 5) 횃불 ---
	var torches: Array = []
	for ch in main.get_children():
		if ch is Torch:
			torches.append(ch)
	var flicker := false
	if torches.size() > 0:
		var t: Torch = torches[0]
		var s0: Vector3 = t._flame.scale
		var t1 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t1 < 400:
			await process_frame
			if not t._flame.scale.is_equal_approx(s0):
				flicker = true
				break
	var ok5: bool = torches.size() == 2 and flicker
	fail += 0 if ok5 else 1
	print("5) 횃불 %d개 / 불꽃 흔들림 %s %s" % [
		torches.size(), flicker, "OK" if ok5 else "***"])

	# --- 6) 러너는 한 방 ---
	# ⚠️ 러너 체력(50)과 사격 피해(60)의 관계를 못 박는 테스트다. 둘 중 하나를 건드려
	#    한 방이 깨지면 여기서 잡힌다 (유저 지시: "러너는 한방이야").
	near.queue_free()
	mid.queue_free()
	far.queue_free()
	await process_frame
	var run_hp: float = float(Enemy.TYPES[&"runner"].health)
	var runner := _spawn(main, base.global_position + Vector3(8.0, 0.0, 0.0), run_hp, &"runner")
	archer._cd = 0.0
	var t2 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t2 < 1500 and not runner.dying:
		await process_frame
	var ok6: bool = runner.dying and archer.damage >= run_hp
	fail += 0 if ok6 else 1
	print("6) 러너 HP %.0f vs 사격 피해 %.0f — 한 방에 사망=%s %s" % [
		run_hp, archer.damage, runner.dying, "OK" if ok6 else "***"])

	print("")
	print("성 사격·횃불 검증 통과" if fail == 0 else "성 사격·횃불 검증 실패 %d 건" % fail)
	quit(0 if fail == 0 else 1)
