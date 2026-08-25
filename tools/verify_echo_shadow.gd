extends SceneTree
## '천벌의 메아리' 추가 망치의 **예고 그림자와 낙하 시차** 검증.
## ⚠️ 처음엔 그림자가 낙하하는 동안에만 자랐다 (예고가 아니라 장식이었다).
##    지금은 우클릭 특수와 같은 문법이다: 그림자가 **먼저** 뜨고, 예고가 끝나야 망치가 떨어진다.
## 확인: 본체 착탄 순간 바로 뜨는가 / 망치보다 먼저 뜨는가 / 임팩트와 동시에 걷히는가.
## godot --headless --path . --script tools/verify_echo_shadow.gd

func _init() -> void:
	_run()

## drop_shadow 셰이더를 쓰는 원판만 센다 (개미 접지 그림자와 구분).
func _shadows(hs: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for c in hs.get_children():
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var pm := mi.mesh as PrimitiveMesh
		if pm == null:
			continue
		var m := pm.material as ShaderMaterial
		if m != null and m.shader == HammerStrike.ShadowShader:
			out.append(mi)
	return out

func _hammers(hs: Node) -> int:
	var n := 0
	for c in hs.get_children():
		if c.name.begins_with("EchoHammer"):
			n += 1
	return n

func _run() -> void:
	var fail := 0
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var hs := main.get_node("HammerStrike") as HammerStrike

	# --- 1) 본체 그림자가 먼저, 메아리 그림자가 stagger 뒤에 ---
	#    ⚠️ 예전엔 메아리를 **본체 착탄 시점**에 스폰했다. 그러면 본체가 다 떨어진 뒤에야
	#       두 번째 예고가 시작돼 시차가 (본체예고 + gap) 이 된다. 지금은 예고를 겹쳐 돌려서
	#       시차가 곧 echo_gap 이다 (유저 지시 2026-08-14).
	var em: Array[StringName] = [&"echo"]
	hs.active_mods = em
	var radius: float = hs.special_radius() * hs.echo_radius_ratio
	hs._special_strike(Vector3(20, 0, 20))
	await process_frame
	var n0 := _shadows(hs).size()
	var ok1: bool = n0 == 1
	fail += 0 if ok1 else 1
	print("1) 특수 발동 직후 그림자 %d개 (기대 1 = 본체만) %s" % [
		n0, "OK" if ok1 else "*** 메아리 예고가 너무 일찍/늦게 뜬다 ***"])

	# ⚠️ 프레임 수로 시간을 세면 안 된다 — 헤드리스는 프레임 간격이 들쭉날쭉해서
	#    1/60 씩 더하면 실제 경과와 어긋난다 (1차 실측: 0.5초를 0.90 으로 쟀다).
	#    실제 시계(get_ticks_msec)로 잰다. 트윈도 같은 시계로 돈다.
	var t0 := Time.get_ticks_msec()
	var t := 0.0
	var seen2 := false
	for i in 3000:
		await process_frame
		t = float(Time.get_ticks_msec() - t0) / 1000.0
		if _shadows(hs).size() >= 2:
			seen2 = true
			break
	var ok2: bool = seen2 and absf(t - hs.echo_gap) < 0.25
	fail += 0 if ok2 else 1
	print("2) 두 번째 그림자가 %.2f초 뒤 등장 (기대 %.2f초) %s" % [
		t, hs.echo_gap, "OK" if ok2 else "***"])

	# --- 3) 낙하 시차: 첫 망치와 두 번째 망치의 **착탄** 간격 ---
	#    ⚠️ 망치 노드가 사라지는 시점을 재면 안 된다 — 착탄 뒤 2초를 박힌 채 버티다
	#       증발하므로 그게 곧 착탄이 아니다 (1차 실측: 3.48초로 나왔다).
	#       그림자는 **착탄 순간 정확히** 걷히므로 그림자 개수가 줄어드는 때를 잰다.
	var drops: Array[float] = []
	var prev := _shadows(hs).size()
	var d0 := Time.get_ticks_msec()
	for i in 6000:
		await process_frame
		var now := _shadows(hs).size()
		if now < prev:
			for k in (prev - now):
				drops.append(float(Time.get_ticks_msec() - d0) / 1000.0)
		prev = now
		if drops.size() >= 2:
			break
	var gap: float = (drops[1] - drops[0]) if drops.size() >= 2 else -1.0
	var gap_ok: bool = drops.size() >= 2 and absf(gap - hs.echo_gap) < 0.25
	fail += 0 if gap_ok else 1
	print("3) 착탄 시차 %.2f초 (기대 %.2f초) %s" % [
		gap, hs.echo_gap, "OK" if gap_ok else "***"])

	print("")
	print("메아리 그림자 검증 통과" if fail == 0 else "메아리 그림자 검증 실패 %d 건" % fail)
	quit(0 if fail == 0 else 1)
