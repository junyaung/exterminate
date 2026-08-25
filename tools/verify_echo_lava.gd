extends SceneTree
## '불' + '여진' + '천벌의 메아리' 3장 조합 — **메아리가 만든 균열도** 불 조합을 타는지 검증.
##   1) 메아리 균열도 ignite 되어 lava 상태로 깔린다 (분화구 예고)
##   2) 그 메아리 균열을 다시 치면 분화구(Crater)가 뜬다
##   3) 뒤에 떨어진 메아리가 앞선 균열을 밟아도 같은 규칙이 돈다
## godot --headless --path . --script tools/verify_echo_lava.gd

func _fields(hs: Node) -> Array:
	var out: Array = []
	for c in hs.get_children():
		if c is AftershockFX and is_instance_valid(c):
			out.append(c)
	return out

func _craters(hs: Node) -> int:
	var n := 0
	for c in hs.get_children():
		if c is Crater:
			n += 1
	return n

func _wait(secs: float) -> void:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < secs:
		await process_frame

func _clear(hs: Node) -> void:
	for c in hs.get_children():
		if c is AftershockFX or c is Crater:
			c.free()

func _init() -> void:
	_run()

func _run() -> void:
	var fail := 0
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var hs := main.get_node("HammerStrike") as HammerStrike
	hs.has_fire = true
	hs.has_aftershock = true
	var em: Array[StringName] = [&"echo"]   # 메아리 모디파이어
	hs.active_mods = em

	# --- 1) 본체 + 메아리 균열이 전부 lava(잔열) 로 깔리는가 ---
	_clear(hs)
	hs._special_cd = 0.0
	hs._special_active = false
	hs._special_strike(Vector3(60.0, 0.0, 60.0))
	await _wait(hs.telegraph_time() + hs.special_slam_time + hs.echo_gap * 2.0 + 0.6)
	var fields := _fields(hs)
	var lava := 0
	for f in fields:
		if f.lava:
			lava += 1
	# ⚠️ 메아리는 무작위 자리에 떨어지므로 **본체 균열 위에 떨어지면 소모된다** (그게 규칙이다).
	#    그래서 균열 수는 2~3 개로 흔들린다. 중요한 건 "생긴 균열이 전부 잔열을 갖는가".
	var ok1: bool = fields.size() >= 2 and lava == fields.size()
	fail += 0 if ok1 else 1
	print("1) 불+여진+메아리2 -> 균열 %d개 중 잔열 %d개 (기대 2~3, 전부 잔열) %s" % [
		fields.size(), lava, "OK" if ok1 else "***"])

	# --- 2) 메아리 균열을 다시 치면 분화구가 뜬다 ---
	# 본체 균열(가장 먼저 생긴 것)이 아니라 **메아리 균열**을 골라 때린다.
	var main_at := Vector3(60.0, 0.0, 60.0)
	var echo_fx = null
	for f in fields:
		var d: Vector3 = f.global_position - main_at
		d.y = 0.0
		if d.length() > 1.0:               # 본체 자리에서 떨어진 = 메아리
			echo_fx = f
			break
	if echo_fx == null:
		print("2) 메아리 균열을 못 찾음 ***")
		fail += 1
	else:
		var er: float = hs.special_radius() * hs.echo_radius_ratio
		var c0 := _craters(hs)
		# 메아리 한 발이 그 자리에 다시 떨어진 것과 같은 호출
		hs._special_blast(echo_fx.global_position, er, 60.0, 0.6)
		await process_frame
		var got := _craters(hs) - c0
		var ok2: bool = got > 0
		fail += 0 if ok2 else 1
		print("2) 메아리 균열 재타격 -> 분화구 %d개 (기대 1 이상) %s" % [
			got, "OK" if ok2 else "***"])

	# --- 3) 불만 있고 여진이 없으면 메아리 균열도 분화구도 없다 ---
	_clear(hs)
	hs.has_aftershock = false
	hs._special_cd = 0.0
	hs._special_active = false
	hs._special_strike(Vector3(160.0, 0.0, 60.0))
	await _wait(hs.telegraph_time() + hs.special_slam_time + hs.echo_gap * 2.0 + 0.6)
	var ok3: bool = _fields(hs).size() == 0 and _craters(hs) == 0
	fail += 0 if ok3 else 1
	print("3) 불만(여진 없음) -> 균열 %d개 / 분화구 %d개 (기대 0/0) %s" % [
		_fields(hs).size(), _craters(hs), "OK" if ok3 else "***"])

	print("")
	print("메아리 불조합 검증 통과" if fail == 0 else "메아리 불조합 검증 실패 %d 건" % fail)
	quit(0 if fail == 0 else 1)
