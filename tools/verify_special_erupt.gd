extends SceneTree
## 유저 지시 2026-08-16 — 특수는 **재타격 없이도** 여진과 함께 바위가 솟는다.
##   1) 여진 카드 + 특수 1발 -> 균열도 남고 바위도 솟는다
##   2) 여진 카드가 없으면 바위도 없다
##   3) 메아리 바위는 본체보다 적게 솟는다 (fx_scale 0.6)
##   4) 남은 균열을 다시 치면 종전 규칙대로 소모 -> 분출/분화구
##   5) 불까지 있으면 **첫 방부터** 바위 대신 분화구가 열리고 불덩이를 뿜는다
##   9) 평타 여진도 **재타격 없이 바로** 바위가 솟는다 (유저 지시 2026-08-18)
##  10) 그 바위는 특수보다 **적고 좁게** 솟는다 — 이게 평타와 특수의 유일한 차이다
## godot --headless --path . --script tools/verify_special_erupt.gd

func _count(hs: Node, type_name: String) -> int:
	var n := 0
	for c in hs.get_children():
		if not is_instance_valid(c):
			continue
		# ⚠️ 특수 파편(_special_debris)도 EruptRock 이다. 피해 없는 잔해는 빼고
		#    **분출 바위만** 센다 — 안 그러면 여진 없이도 수십 개가 잡힌다.
		if type_name == "rock" and c is EruptRock and not c._debris:
			n += 1
		elif type_name == "field" and c is AftershockFX:
			n += 1
		elif type_name == "crater" and c is Crater:
			n += 1
	return n

func _wait(secs: float) -> void:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < secs:
		await process_frame

## ⚠️ 균열(AftershockFX)은 **치우지 않는다**. 0.35초 여진 트윈이 걸려 있어서 중간에
##    free 하면 람다 캡처가 날아갔다는 엔진 경고가 뜬다. 사례마다 자리를 멀리 띄우고
##    개수는 증감으로 본다.
func _clear(hs: Node) -> void:
	for c in hs.get_children():
		if c is Crater or c is EruptRock:
			c.free()

func _init() -> void:
	_run()

func _run() -> void:
	var fail := 0
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var hs := main.get_node("HammerStrike") as HammerStrike
	hs.has_fire = false
	var none: Array[StringName] = []          # 메아리 없음
	hs.active_mods = none
	var rad := hs.special_radius()
	var direct := 100.0

	# --- 1) 여진 있음 + 특수 1발 -> 균열 + 바위 ---
	_clear(hs)
	hs.has_aftershock = true
	hs._special_blast(Vector3(60, 0, 60), rad, direct, 1.0)
	# ⚠️ 기다리지 않는다 — 바위는 **충돌과 같은 프레임**에 나와야 한다 (유저 지시).
	await process_frame
	var rocks := _count(hs, "rock")
	var fields := _count(hs, "field")
	# ⚠️ 개수는 이제 **도넛 넓이**에서 나온다 (2026-08-18). "8 × 배율" 로 못 센다.
	#    여기서 볼 것은 "여러 개가 나왔고 성능 상한을 안 넘겼는가" 뿐이다.
	var ok1: bool = rocks > 1 and rocks <= hs.ERUPT_MAX and fields == 1
	fail += 0 if ok1 else 1
	print("1) 여진+특수 1발(즉시) -> 바위 %d개 (넓이 기준, 상한 %d), 균열 %d개 %s" % [
		rocks, hs.ERUPT_MAX, fields, "OK" if ok1 else "***"])

	# --- 2) 여진 없으면 바위도 없다 ---
	_clear(hs)
	hs.has_aftershock = false
	hs._special_blast(Vector3(120, 0, 60), rad, direct, 1.0)
	await _wait(hs.aftershock_delay + 0.3)   # 늦게 나오는 것도 없어야 하니 여기선 기다린다
	var ok2: bool = _count(hs, "rock") == 0
	fail += 0 if ok2 else 1
	print("2) 여진 없음 -> 바위 %d개 (기대 0) %s" % [
		_count(hs, "rock"), "OK" if ok2 else "***"])

	# --- 3) 메아리는 적게 솟는다 ---
	_clear(hs)
	hs.has_aftershock = true
	var er: float = rad * hs.echo_radius_ratio
	hs._special_blast(Vector3(180, 0, 60), er, direct * 0.6, 0.6)
	await process_frame
	var echo_rocks := _count(hs, "rock")
	var ok3: bool = echo_rocks > 0 and echo_rocks < rocks
	fail += 0 if ok3 else 1
	print("3) 메아리 바위 %d개 < 본체 %d개 %s" % [
		echo_rocks, rocks, "OK" if ok3 else "***"])

	# --- 4) 남은 균열 재타격은 종전대로 소모된다 ---
	_clear(hs)
	var at := Vector3(240, 0, 60)
	var base_fields := _count(hs, "field")
	hs._special_blast(at, rad, direct, 1.0)
	await _wait(hs.aftershock_delay + 0.3)   # 균열은 여전히 0.35초 뒤에 지대가 된다
	var before := _count(hs, "field") - base_fields
	hs._special_blast(at, rad, direct, 1.0)
	await process_frame
	var after := _count(hs, "field") - base_fields
	var ok4: bool = before == 1 and after <= before
	fail += 0 if ok4 else 1
	print("4) 균열 재타격 -> 균열 %d -> %d개 (늘어나면 무한 연쇄) %s" % [
		before, after, "OK" if ok4 else "***"])

	# --- 5) 불 조합: 첫 방부터 분화구 + 불덩이 (유저 지시 2026-08-16) ---
	_clear(hs)
	hs.has_fire = true
	var at2 := Vector3(300, 0, 60)
	hs._special_blast(at2, rad, direct, 1.0)
	await process_frame
	var c_first := _count(hs, "crater")
	var r_first := _count(hs, "rock")
	# 불이면 바위 대신 분화구 — 둘 다 나오면 첫 방이 과해진다
	var ok5: bool = c_first == 1 and r_first == 0
	fail += 0 if ok5 else 1
	print("5) 불+여진 특수 첫 방(즉시) -> 분화구 %d개(기대 1) / 바위 %d개(기대 0) %s" % [
		c_first, r_first, "OK" if ok5 else "***"])

	# --- 6) 그 분화구가 실제로 불덩이를 뿜는가 ---
	var crater = null
	for c in hs.get_children():
		if c is Crater:
			crater = c
			break
	var balls := 0
	if crater != null:
		await process_frame
		balls = crater.balls_fired
	var ok6: bool = balls == hs.crater_balls_special
	fail += 0 if ok6 else 1
	print("6) 특수 분화구 불덩이 %d발 (기대 %d발, 후속 없음) %s" % [
		balls, hs.crater_balls_special, "OK" if ok6 else "***"])

	# --- 7) 메아리 분화구는 본체보다 한 발 적게 뿜는다 (charge 0.6) ---
	_clear(hs)
	var er2: float = rad * hs.echo_radius_ratio
	hs._special_blast(Vector3(360, 0, 60), er2, direct * 0.6, 0.6)
	await process_frame
	await process_frame
	var echo_balls := 0
	for c in hs.get_children():
		if c is Crater:
			echo_balls = c.balls_fired
	var ok7: bool = echo_balls > 0 and echo_balls < balls
	fail += 0 if ok7 else 1
	print("7) 메아리 분화구 불덩이 %d발 < 본체 %d발 %s" % [
		echo_balls, balls, "OK" if ok7 else "***"])

	# --- 8) 남은 균열 재타격은 종전대로 또 분화구 ---
	var c_before := _count(hs, "crater")
	hs._special_blast(Vector3(360, 0, 60), er2, direct * 0.6, 0.6)
	await process_frame
	var ok8: bool = _count(hs, "crater") > c_before
	fail += 0 if ok8 else 1
	print("8) 균열 재타격 -> 분화구 %d -> %d개 %s" % [
		c_before, _count(hs, "crater"), "OK" if ok8 else "***"])

	# --- 9~10) 평타 여진: 즉시 분출 + 특수보다 적고 좁게 ---
	# ⚠️ 평타는 _strike 를 거치면 스윙 애니메이션(0.21초)을 기다려야 한다 —
	#    여기서는 임팩트 지점만 보므로 _impact 를 직접 부른다 (여진이 여진을 낳지 않는 경로).
	_clear(hs)
	hs.has_aftershock = true
	hs.has_fire = false
	var n_at := Vector3(300, 0, 60)
	hs._impact(n_at, 0.0)
	await process_frame
	var n_rocks := _count(hs, "rock")
	# 평타도 넓이 기준이다. 특수보다는 **적어야** 한다 — 판이 좁으니까.
	var ok9: bool = n_rocks > 1 and n_rocks < rocks
	fail += 0 if ok9 else 1
	print("9) 평타 여진 1방(즉시) -> 바위 %d개 (특수 %d개보다 적어야) %s" % [
		n_rocks, rocks, "OK" if ok9 else "***"])

	# 산개 반경 — **착지한 자리**로 잰다.
	# ⚠️ 스폰 직후에 재면 전부 0 이 나온다. 바위는 중심에서 태어나 목표 지점으로 날아가므로
	#    (EruptRock.spawn_at 은 origin 에서 land 로 속도를 역산한다) 착지까지 기다려야 한다.
	await _wait(1.1)
	var n_spread := 0.0
	for c in hs.get_children():
		if c is EruptRock and not (c as EruptRock)._debris:
			var d := Vector2(c.global_position.x - n_at.x, c.global_position.z - n_at.z)
			n_spread = maxf(n_spread, d.length())
	_clear(hs)
	var s_at := Vector3(360, 0, 60)
	hs._special_blast(s_at, rad, direct, 1.0)
	await process_frame
	var s_rocks := _count(hs, "rock")
	await _wait(1.1)
	var s_spread := 0.0
	for c in hs.get_children():
		if c is EruptRock and not (c as EruptRock)._debris:
			var d2 := Vector2(c.global_position.x - s_at.x, c.global_position.z - s_at.z)
			s_spread = maxf(s_spread, d2.length())
	var ok10: bool = n_rocks < s_rocks and n_spread < s_spread
	fail += 0 if ok10 else 1
	print("10) 평타 %d개/반경 %.1f  <  특수 %d개/반경 %.1f %s" % [
		n_rocks, n_spread, s_rocks, s_spread, "OK" if ok10 else "***"])

	print("")
	print("특수 즉시분출 검증 통과" if fail == 0 else "특수 즉시분출 검증 실패 %d 건" % fail)
	quit(0 if fail == 0 else 1)
