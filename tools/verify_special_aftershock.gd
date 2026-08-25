extends SceneTree
## 우클릭 특수의 여진 검증 (유저 지시 2026-08-14: "특수도 일반처럼 모든 게 적용되게").
##   · 여진 카드가 있으면 특수도 **균열을 만든다**
##   · 균열 위를 치면 **소모**해서 분출한다 (새로 만들지 않는다 — 무한 연쇄 방지)
##   · 균열 크기가 **그 공격의 범위에 비례**한다 (메아리는 작게)
##   · 불까지 있으면 분화구가 뜬다
## godot --headless --path . --script tools/verify_special_aftershock.gd

func _init() -> void:
	_run()

func _fields(hs: Node) -> Array:
	var out: Array = []
	for c in hs.get_children():
		if c is AftershockFX:
			out.append(c)
	return out

func _craters(hs: Node) -> int:
	var n := 0
	for c in hs.get_children():
		if c is Crater:
			n += 1
	return n

## 균열은 aftershock_delay(0.35초) 뒤 fire() 에서야 반경이 정해지고 active 가 된다.
## ⚠️ 그 전에 재면 반경이 0 이고, 그때 다시 때리면 _crack_field_at 이 못 찾아서
##    **새 균열이 하나 더 생긴다** — 검증이 실제 동작을 오해하기 딱 좋은 지점이다.
func _wait_active(fx: Node, secs := 1.5) -> void:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < secs:
		await process_frame
		if fx != null and is_instance_valid(fx) and fx.active:
			return

func _run() -> void:
	var fail := 0
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var hs := main.get_node("HammerStrike") as HammerStrike
	var none: Array[StringName] = []          # 메아리 없음
	hs.active_mods = none

	# --- 1) 여진 없으면 균열도 없다 ---
	hs.has_aftershock = false
	hs.has_fire = false
	var n0 := _fields(hs).size()
	hs._special_blast(Vector3(20, 0, 20), hs.special_radius(), 100.0, 1.0)
	await process_frame
	var made0 := _fields(hs).size() - n0
	var ok1: bool = made0 == 0
	fail += 0 if ok1 else 1
	print("1) 여진 카드 없음 -> 균열 %d개 (기대 0) %s" % [made0, "OK" if ok1 else "***"])

	# --- 2) 여진 있으면 특수도 균열을 만든다 ---
	hs.has_aftershock = true
	var n1 := _fields(hs).size()
	var at := Vector3(60, 0, 60)
	hs._special_blast(at, hs.special_radius(), 100.0, 1.0)
	await process_frame
	var fields := _fields(hs)
	var made1 := fields.size() - n1
	var ok2: bool = made1 == 1
	fail += 0 if ok2 else 1
	print("2) 여진 카드 있음 -> 균열 %d개 (기대 1) %s" % [made1, "OK" if ok2 else "***"])

	# --- 3) 균열 크기가 공격 범위에 비례 ---
	var fx = fields[-1]
	await _wait_active(fx)
	var want: float = hs.special_radius() * hs.special_crack_fit
	# fire() 는 radius × aftershock_radius 로 지대를 넓힌다
	var ok3: bool = absf(fx.field_radius - want * hs.aftershock_radius) < want * 0.25
	fail += 0 if ok3 else 1
	print("3) 균열 반경 %.2f (특수 직격 %.2f × %.2f = %.2f 기준) %s" % [
		fx.field_radius, hs.special_radius(), hs.special_crack_fit, want,
		"OK" if ok3 else "***"])

	# 메아리(연출 강도 0.6, 반경 85%)는 더 작은 균열을 만들어야 한다
	var n2 := _fields(hs).size()
	var er: float = hs.special_radius() * hs.echo_radius_ratio
	hs._special_blast(Vector3(90, 0, 90), er, 60.0, 0.6)
	await process_frame
	var efx = _fields(hs)[-1]
	await _wait_active(efx)
	var ok4: bool = efx.field_radius < fx.field_radius
	fail += 0 if ok4 else 1
	print("4) 메아리 균열 %.2f < 본체 균열 %.2f %s" % [
		efx.field_radius, fx.field_radius, "OK" if ok4 else "***"])

	# --- 5) 균열 위를 치면 소모한다 (새로 안 만든다) ---
	var before := _fields(hs).size()   # fx 는 위에서 이미 active 가 됐다
	hs._special_blast(at, hs.special_radius(), 100.0, 1.0)
	await process_frame
	var after := _fields(hs).size()
	var ok5: bool = after <= before      # 소모돼 사라지거나 그대로 — 늘어나면 안 된다
	fail += 0 if ok5 else 1
	print("5) 균열 위 재타격 -> 균열 %d -> %d개 (늘어나면 무한 연쇄) %s" % [
		before, after, "OK" if ok5 else "***"])

	# --- 6) 불 + 여진 조합: 균열을 치면 분화구 ---
	hs.has_fire = true
	var at2 := Vector3(140, 0, 140)
	hs._special_blast(at2, hs.special_radius(), 100.0, 1.0)
	await process_frame
	await _wait_active(_fields(hs)[-1])
	var c0 := _craters(hs)
	hs._special_blast(at2, hs.special_radius(), 100.0, 1.0)
	await process_frame
	var ok6: bool = _craters(hs) > c0
	fail += 0 if ok6 else 1
	print("6) 불+여진, 균열 위 재타격 -> 분화구 %d개 생성 %s" % [
		_craters(hs) - c0, "OK" if ok6 else "***"])

	print("")
	print("특수 여진 검증 통과" if fail == 0 else "특수 여진 검증 실패 %d 건" % fail)
	quit(0 if fail == 0 else 1)
