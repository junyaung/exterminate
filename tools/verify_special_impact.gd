extends SceneTree
## 우클릭 특수 착탄 연출 검증 (유저 지시 2026-08-14):
##   · 먼지(ImpactDust)는 안 나온다
##   · 대신 돌 파편이 튄다 — **피해는 없다**
##   · 파편 체공이 special_debris_airtime 근처다
##   · 망치가 박힌 자리에 흙 자국이 생긴다
## godot --headless --path . --script tools/verify_special_impact.gd

func _init() -> void:
	_run()

func _count(n: Node, type_name: String) -> int:
	var c := 0
	for ch in n.get_children():
		if ch.get_class() == type_name:
			c += 1
	return c

## scorch 셰이더를 쓰는 바닥 판 = 흙 자국
func _dirt(hs: Node) -> int:
	var c := 0
	for ch in hs.get_children():
		var mi := ch as MeshInstance3D
		if mi == null:
			continue
		var pm := mi.mesh as PlaneMesh
		if pm == null:
			continue
		var m := pm.material as ShaderMaterial
		if m != null and m.shader == EruptRock.ScorchShader:
			c += 1
	return c

func _debris(hs: Node) -> Array[EruptRock]:
	var out: Array[EruptRock] = []
	for ch in hs.get_children():
		var r := ch as EruptRock
		if r != null and r._debris:
			out.append(r)
	return out

func _run() -> void:
	var fail := 0
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var hs := main.get_node("HammerStrike") as HammerStrike
	var none: Array[StringName] = []          # 메아리 없음
	hs.active_mods = none

	var dust0 := _count(hs, "CPUParticles3D")
	var at := Vector3(40, 0, 40)
	hs._special_blast(at, hs.special_radius(),
		100.0, 1.0)
	await process_frame

	# 1) 먼지가 안 나온다
	var dust := _count(hs, "CPUParticles3D") - dust0
	var ok1: bool = dust == 0
	fail += 0 if ok1 else 1
	print("1) 착탄 먼지 %d개 (기대 0 — 파편으로 교체) %s" % [
		dust, "OK" if ok1 else "*** 아직 먼지가 난다 ***"])

	# 2) 파편이 튄다
	var deb := _debris(hs)
	var ok2: bool = deb.size() == hs.special_debris
	fail += 0 if ok2 else 1
	print("2) 돌 파편 %d개 (기대 %d) %s" % [
		deb.size(), hs.special_debris, "OK" if ok2 else "***"])

	# 3) 파편은 피해가 없다
	var no_dmg := true
	for r in deb:
		if r._damage != 0.0 or r._radius != 0.0:
			no_dmg = false
	fail += 0 if no_dmg else 1
	print("3) 파편 피해 %s (기대 전부 0) %s" % [
		"없음" if no_dmg else "있다!", "OK" if no_dmg else "***"])

	# 4) 체공 시간 — 초속에서 역산 (t = 2v/g)
	var lo := INF
	var hi := -INF
	for r in deb:
		var t: float = 2.0 * r._vel.y / EruptRock.GRAVITY
		lo = minf(lo, t)
		hi = maxf(hi, t)
	var want: float = hs.special_debris_airtime
	var ok4: bool = lo > want * 0.75 and hi < want * 1.25
	fail += 0 if ok4 else 1
	print("4) 파편 체공 %.2f ~ %.2f초 (기대 %.2f초 ±편차) %s" % [
		lo, hi, want, "OK" if ok4 else "***"])

	# 5) 흙 자국
	var d := _dirt(hs)
	var ok5: bool = d == 1
	fail += 0 if ok5 else 1
	print("5) 흙 자국 %d개 (기대 1) %s" % [d, "OK" if ok5 else "***"])

	print("")
	print("특수 착탄 연출 검증 통과" if fail == 0 else "특수 착탄 연출 검증 실패 %d 건" % fail)
	quit(0 if fail == 0 else 1)
