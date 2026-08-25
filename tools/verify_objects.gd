extends SceneTree
## 오브젝트 시스템 1단계 검증.
##   godot --headless --path . --script tools/verify_objects.gd
## 확인 항목: 태그 매칭 / 적용 순서(수량=합, 나머지=곱) / 깊이 상한 / 실제 생성 수

## 타입 있는 배열이라 리터럴로 못 넘긴다 — 상수로 한 번만 만든다
const SHOCK_TAGS: Array[StringName] = [&"area", &"ground"]
const PROJ_TAGS: Array[StringName] = [&"projectile"]
const AREA_TAGS: Array[StringName] = [&"area"]

var fail := 0
func ok(c: bool) -> String:
	fail += 0 if c else 1
	return "OK" if c else "***"
func near(a: float, b: float) -> bool:
	return absf(a - b) < 0.001

## ⚠️ active_mods 는 Array[StringName] 이라 **일반 Array 리터럴을 그대로 대입하면 실패**한다.
func mods_of(ids: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for i in ids:
		out.append(i)
	return out

func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var hs = main.get_node("HammerStrike")

	print("\n[태그 매칭] 모디파이어가 맞는 오브젝트에만 걸리는가")
	var proj := ObjectSpec.make(&"fireball", PROJ_TAGS, null)
	var area := ObjectSpec.make(&"shockwave", SHOCK_TAGS, null)
	var rock := ObjectSpec.make(&"erupt_rock", PROJ_TAGS, null)
	var crat := ObjectSpec.make(&"crater", SHOCK_TAGS, null)
	var defl := ObjectSpec.make(&"deflagration", AREA_TAGS, null)
	var crack := ObjectSpec.make(&"crack_field", SHOCK_TAGS, null)
	var slam := ObjectSpec.make(&"special_slam", AREA_TAGS, null)
	var all := [proj, area, rock, crat, defl, crack, slam]
	print("  %-6s %-6s %-6s %-7s %-6s %-5s %-6s %-6s" % [
		"", "불덩이", "충격파", "분출바위", "분화구", "폭연", "균열", "특수"])
	for m in Modifiers.MODS:
		var row := "  %-7s" % m.mname
		for o in all:
			row += " %-7s" % ("O" if Modifiers.matches(m, o) else "X")
		print(row)
	print("  질주는 불덩이만 (충격파는 projectile 이 아니다)  %s" % ok(
		Modifiers.matches(Modifiers.by_id(&"swift"), proj)
		and not Modifiers.matches(Modifiers.by_id(&"swift"), area)))
	print("  잔류는 충격파만 (불덩이는 ground 가 아니다)  %s" % ok(
		Modifiers.matches(Modifiers.by_id(&"linger"), area)
		and not Modifiers.matches(Modifiers.by_id(&"linger"), proj)))
	print("  메아리는 둘 다 (tags 가 비면 전부)  %s" % ok(
		Modifiers.matches(Modifiers.by_id(&"echo"), proj)
		and Modifiers.matches(Modifiers.by_id(&"echo"), area)))

	print("\n[수량은 합, 나머지는 곱] 다중화 2장")
	hs.active_mods = mods_of([&"multi", &"multi"])
	var s2 = hs.fireball_spec(100.0, 2.0, 3)
	print("  수량 3 -> %d (합이면 7, 곱이면 8.3)  %s" % [s2.count, ok(s2.count == 7)])
	print("  피해 100 -> %.1f (0.6 두 번 = 36)  %s" % [s2.damage, ok(near(s2.damage, 36.0))])
	print("  반경 2.0 -> %.2f (0.7 두 번 = 0.98)  %s" % [s2.radius, ok(near(s2.radius, 0.98))])
	print("  시각 배율도 같이 %.2f (반경과 어긋나면 안 됨)  %s" % [s2.scale,
		ok(near(s2.scale, s2.radius / 2.0))])

	print("\n[정반대 축] 거대화 + 다중화를 같이 먹으면 상쇄된다 (둘 다 발사체)")
	hs.active_mods = mods_of([&"giant", &"multi"])
	var s3 = hs.fireball_spec(100.0, 2.0, 3)
	print("  수량 3 -> %d (+2 -1)  %s" % [s3.count, ok(s3.count == 4)])
	print("  반경 2.0 -> %.2f (2.0 × 0.7)  %s" % [s3.radius, ok(near(s3.radius, 2.8))])

	print("\n[태그 안 맞으면 안 걸린다] 충격파에 질주·다중화")
	hs.active_mods = mods_of([&"swift", &"multi"])
	var s4 = hs.object_spec(&"shockwave", SHOCK_TAGS, 50.0, 9.6)
	print("  수량 1 그대로 %d / 속도 1.0 그대로 %.2f  %s" % [s4.count, s4.speed,
		ok(s4.count == 1 and near(s4.speed, 1.0))])
	hs.active_mods = mods_of([&"linger", &"wide"])
	var s5 = hs.object_spec(&"shockwave", SHOCK_TAGS, 50.0, 9.6)
	print("  잔류+광역화는 걸린다: 수명 %.1f / 반경 %.2f  %s" % [s5.lifetime, s5.radius,
		ok(near(s5.lifetime, 2.0) and near(s5.radius, 19.2))])

	print("\n[분출 바위·분화구] 카드 하나가 오브젝트 둘을 만드는 경우")
	hs.active_mods = mods_of([&"multi", &"linger", &"wide"])
	var rs = hs.rock_spec(50.0, 6.0, 4)
	print("  분출 바위 수량 4 -> %d (다중화 걸림, projectile)  %s" % [rs.count, ok(rs.count == 6)])
	print("  분출 판 반경 6.0 -> %.2f (다중화 ×0.7만, 광역화는 면적 전용이라 안 걸림)  %s" % [
		rs.radius, ok(near(rs.radius, 4.2))])
	print("  분출 바위 수명 %.2f (잔류는 ground 라 안 걸림)  %s" % [rs.lifetime,
		ok(near(rs.lifetime, 1.0))])
	var cs = hs.crater_spec(4.0)
	var bs = hs.fireball_spec(40.0, 1.4, 3)
	print("  분화구 수명 %.1f (잔류 걸림) / 수량 %d (다중화는 ground+area 라 안 걸림)  %s" % [
		cs.lifetime, cs.count, ok(near(cs.lifetime, 2.0) and cs.count == 1)])
	print("  같은 분화구가 뿜는 불덩이 수량 %d (다중화 걸림)  %s" % [bs.count, ok(bs.count == 5)])

	print("\n[폭연·균열] 새로 태그 단 둘")
	hs.active_mods = mods_of([&"giant", &"wide", &"linger"])
	var ds = hs.deflag_spec(80.0, 3.0, 3)
	print("  폭연 시체 수 3 -> %d (거대화는 발사체 전용이라 안 걸림) / 반경 3.0 -> %.2f (광역화 ×2)  %s" % [
		ds.count, ds.radius, ok(ds.count == 3 and near(ds.radius, 6.0))])
	print("  폭연 수명 %.2f (잔류는 ground 라 안 걸림 — 폭연은 바닥에 안 남는다)  %s" % [
		ds.lifetime, ok(near(ds.lifetime, 1.0))])
	var ks = hs.crack_spec(4.0)
	print("  균열 반경 4.0 -> %.2f (광역화) / 수명 %.1f (잔류)  %s" % [
		ks.radius, ks.lifetime, ok(near(ks.radius, 8.0) and near(ks.lifetime, 2.0))])

	print("\n[메아리 망치] 카드가 아니라 모디파이어로 나온다")
	hs.active_mods = mods_of([])
	var sp0 = hs.special_spec(250.0, 6.0)
	hs.active_mods = mods_of([&"echo"])
	var sp1 = hs.special_spec(250.0, 6.0)
	hs.active_mods = mods_of([&"echo", &"echo"])
	var sp2 = hs.special_spec(250.0, 6.0)
	print("  메아리 0장 -> repeat %d / 1장 -> %d / 2장 -> %d (합)  %s" % [
		sp0.repeat, sp1.repeat, sp2.repeat,
		ok(sp0.repeat == 0 and sp1.repeat == 1 and sp2.repeat == 2)])
	print("  메아리 세기 %.2f (본체의 60%%)  %s" % [sp1.repeat_power,
		ok(near(sp1.repeat_power, 0.6))])
	print("  '천벌의 메아리' 카드는 사라졌다  %s" % ok(CardCatalog.by_id(&"echo").is_empty()))

	print("\n[충격파 카드는 세 공격 전부에] 특수에도 걸리는가")
	hs.active_mods = mods_of([])
	print("  특수 충격파 반경 %.2f = 맥스 차징 %.2f  %s" % [
		hs.special_shock_spread(), hs.strike_radius(1.0) * hs.shock_spread,
		ok(near(hs.special_shock_spread(), hs.strike_radius(1.0) * hs.shock_spread))])
	var at := Vector3(70, 0, 70)
	var probe = load("res://scenes/enemy.tscn").instantiate()
	probe.type_id = &"grunt"
	main.add_child(probe)
	probe.global_position = at + Vector3(12.0, 0, 0)   # 직격(6.0) 밖, 고리(19.2) 안
	await process_frame
	probe.stats.set_base(Stats.HEALTH, 99999.0)
	for has in [false, true]:
		hs.has_shockwave = has
		probe.health = 99999.0
		hs._special_blast(at, hs.special_radius(),
			hs.stats.get_v(Stats.DAMAGE) * hs.special_damage_mult, 1.0)
		await process_frame
		var got: float = 99999.0 - probe.health
		print("  카드 %s -> 고리 자리(12.0) 피해 %.0f  %s" % [
			"있음" if has else "없음", got,
			ok(got > 0.0 if has else is_equal_approx(got, 0.0))])
	probe.free()

	print("\n[분출은 도넛이 때린다] 바위는 연출, 판정은 면적")
	hs.active_mods = mods_of([])
	var eat := Vector3(90, 0, 90)
	var erad := 6.0
	var probes := {"한가운데": 0.5, "도넛안": erad * 0.7, "도넛밖": erad * 1.4}
	var pm := {}
	for k in probes:
		var pe = load("res://scenes/enemy.tscn").instantiate()
		pe.type_id = &"grunt"
		main.add_child(pe)
		pe.global_position = eat + Vector3(probes[k], 0, 0)
		await process_frame
		pe.stats.set_base(Stats.HEALTH, 99999.0)
		pe.health = 99999.0
		pm[k] = pe
	hs._erupt_rocks(eat, erad, 100.0, 0.0, hs.normal_erupt_rocks_mul)
	# ⚠️ 판정은 **첫 바위가 착지할 때** 들어간다 (2026-08-18) — 같은 프레임에 재면 0 이다.
	#    프레임 수를 박지 말고 결과가 나올 때까지 기다린다 (헤드리스는 프레임 간격이 들쭉날쭉).
	for i in 600:
		await process_frame
		if pm["도넛안"].health < 99999.0:
			break
	var mid: float = 99999.0 - pm["한가운데"].health
	var inr: float = 99999.0 - pm["도넛안"].health
	var outr: float = 99999.0 - pm["도넛밖"].health
	print("  한가운데 %.0f / 도넛안 %.0f / 도넛밖 %.0f  %s" % [mid, inr, outr,
		ok(is_equal_approx(mid, 0.0) and inr > 0.0 and is_equal_approx(outr, 0.0))])
	var vis := true
	for r in hs.find_children("*", "EruptRock", false, false):
		if not r._debris and not r.visual_only:
			vis = false
	print("  솟은 바위가 전부 연출 전용  %s" % ok(vis))
	for k in pm:
		pm[k].free()

	print("\n[분출 개수는 도넛 넓이에서 나온다] 바위는 연출이라 개수가 판정을 안 바꾼다")
	var fld: float = hs.secondary_radius(0.0) * hs.aftershock_radius * hs.normal_erupt_spread
	for case in [["없음", []], ["거대화", [&"giant"]]]:
		var m3: Array[StringName] = []
		for i in case[1]:
			m3.append(i)
		hs.active_mods = m3
		for c in hs.find_children("*", "EruptRock", false, false):
			c.free()
		await process_frame
		hs._erupt_rocks(Vector3(-200, 0, -200), fld, 100.0, 0.0, hs.normal_erupt_rocks_mul)
		await process_frame
		var bodies := 0
		for r in hs.find_children("*", "EruptRock", false, false):
			if not r._debris:
				bodies += 1
		print("  %-5s 몸통 %d개 (상한 %d)  %s" % [case[0], bodies, hs.ERUPT_MAX,
			ok(bodies > 1 and bodies <= hs.ERUPT_MAX)])
		for c in hs.find_children("*", "EruptRock", false, false):
			c.free()
	# ⚠️ 거대화가 개수를 **늘려야** 한다. 스펙을 굽는 순서를 틀리면 오히려 줄어든다.
	hs.active_mods = mods_of([])
	var n0 := roundi(hs._erupt_fill_count(hs.rock_spec(0.0, fld * hs.erupt_field_mul, 1).radius))
	hs.active_mods = mods_of([&"giant"])
	var n1 := roundi(hs._erupt_fill_count(hs.rock_spec(0.0, fld * hs.erupt_field_mul, 1).radius))
	print("  넓이 기준 개수: 없음 %d -> 거대화 %d (반경 ×2 면 넓이 ×4)  %s" % [
		n0, n1, ok(n1 >= n0 * 3)])

	print("\n[거대화 = 분출 판이 넓어진다] 바위는 연출, 판정 도넛이 같이 커진다")
	for case in [["없음", [], 6.0], ["거대화", [&"giant"], 12.0], ["다중화", [&"multi"], 4.2]]:
		var mm2: Array[StringName] = []
		for i in case[1]:
			mm2.append(i)
		hs.active_mods = mm2
		var rsp = hs.rock_spec(50.0, 6.0, 4)
		print("  %-5s 판 반경 6.0 -> %5.2f (기대 %.2f) / 도넛 %.2f~%.2f / 바위 %.1f배  %s" % [
			case[0], rsp.radius, case[2], rsp.radius * hs.ERUPT_NEAR, rsp.radius * hs.ERUPT_FAR,
			rsp.scale, ok(near(rsp.radius, case[2]))])
		print("        바위 크기와 판 반경이 같은 배율  %s" % ok(near(rsp.scale, rsp.radius / 6.0)))

	print("\n[바위는 겹쳐도 되지만 반드시 지면에 닿는다]")
	for case in [["없음", []], ["거대화", [&"giant"]]]:
		var mm: Array[StringName] = []
		for i in case[1]:
			mm.append(i)
		hs.active_mods = mm
		for c in hs.find_children("*", "EruptRock", false, false):
			c.free()
		hs._erupt_rocks(Vector3(120, 0, 120), 6.0, 100.0, 0.0, hs.normal_erupt_rocks_mul)
		for i in 400:
			await process_frame
			var down := true
			for r in hs.find_children("*", "EruptRock", false, false):
				if not r._landed:
					down = false
			if down:
				break
		var worst := -INF
		var old_gap := 0.0
		var n := 0
		for r in hs.find_children("*", "EruptRock", false, false):
			if r._debris or not r._landed:
				continue
			n += 1
			# 최저 정점의 월드 높이 - 지면. 0 이하여야 닿거나 박힌 것이다.
			worst = maxf(worst, (r.global_position.y - r._lowest_drop())
				- Terrain.h(r.global_position))
			# 예전 AABB 방식이었으면 얼마나 떴을지 (참고용)
			var bb = r._mesh.transform.basis
			old_gap = maxf(old_gap, (absf(bb.x.y) * r._half.x + absf(bb.y.y) * r._half.y
				+ absf(bb.z.y) * r._half.z) - r._lowest_drop())
		print("  %-5s 바위 %d개 / 뜬 높이 최대 %.4f  %s   (AABB 방식이면 %.2f 떴다)" % [
			case[0], n, worst, ok(worst <= 0.001), old_gap])
		for c in hs.find_children("*", "EruptRock", false, false):
			c.free()

	print("\n[분열은 분출 바위에 안 걸린다] excludes")
	var fb_spec := ObjectSpec.make(&"fireball", PROJ_TAGS, null)
	var rk_spec := ObjectSpec.make(&"erupt_rock", PROJ_TAGS, null)
	var sp := Modifiers.by_id(&"split")
	print("  불덩이=%s / 분출바위=%s (둘 다 발사체인데 바위만 제외)  %s" % [
		"O" if Modifiers.matches(sp, fb_spec) else "X",
		"O" if Modifiers.matches(sp, rk_spec) else "X",
		ok(Modifiers.matches(sp, fb_spec) and not Modifiers.matches(sp, rk_spec))])

	print("\n[깊이 상한] 분열이 무한히 이어지지 않는가")
	var r := DamageSource.root(&"normal")
	var d1 := r.child(&"fireball", 0.6)
	var d2 := d1.child(&"fireball_split", 0.6)
	print("  깊이 0/1/2, 계수 %.2f/%.2f/%.2f" % [r.proc_coeff, d1.proc_coeff, d2.proc_coeff])
	print("  깊이 0·1 은 자식 가능, 깊이 2 는 불가 (MAX_DEPTH=%d)  %s" % [
		DamageSource.MAX_DEPTH, ok(r.can_spawn() and d1.can_spawn() and not d2.can_spawn())])
	var spec_deep := ObjectSpec.make(&"x", [], d2)
	print("  깊이 2 스펙의 child_src 는 null  %s" % ok(spec_deep.child_src(&"y") == null))

	print("\n[실제 생성 수] 분화구가 스펙대로 뿜는가")
	for mods in [[], [&"multi"], [&"giant"]]:
		hs.active_mods = mods_of(mods)
		var spec = hs.fireball_spec(40.0, 1.4, 3)
		var before: int = hs.find_children("*", "Fireball", false, false).size()
		Crater.spawn(hs, hs, hs.crater_spec(4.0), spec)
		await process_frame
		var made: int = hs.find_children("*", "Fireball", false, false).size() - before
		print("  %-8s 스펙 수량 %d -> 실제 %d개  %s" % [
			"없음" if mods.is_empty() else str(mods[0]), spec.count, made,
			ok(made == spec.count)])
		for f in hs.find_children("*", "Fireball", false, false):
			f.free()

	print("\n[출처 전달] 불덩이가 준 피해에 출처가 실리는가")
	hs.active_mods = mods_of([])
	hs._swing_src = DamageSource.root(&"normal")
	var spec6 = hs.fireball_spec(999.0, 3.0, 1)
	var e = load("res://scenes/enemy.tscn").instantiate()
	e.type_id = &"grunt"
	main.add_child(e)
	e.global_position = Vector3(50, 0, 50)
	await process_frame
	e.stats.set_base(Stats.HEALTH, 99999.0)
	e.health = 99999.0
	var fb = Fireball.spawn_roll(hs, Vector3(50, 0, 50), Vector2(1, 0), 999.0, 3.0, spec6)
	fb._rolling = true
	fb._roll_left = 1.0
	fb.global_position = Vector3(50, 0.6, 50)
	# ⚠️ 프레임 수를 박아두면 안 된다 — 불덩이 접촉 판정은 물리 프레임에서 도는데
	#    헤드리스는 프레임 간격이 들쭉날쭉해서 2프레임이면 놓칠 때가 있다 (실제로 놓쳤다).
	#    **결과가 나올 때까지** 기다리되 상한을 둔다.
	for i in 60:
		await process_frame
		if e.last_src != null:
			break
	print("  피해 들어감=%s  출처=%s  %s" % [99999.0 - e.health > 0.0,
		e.last_src, ok(e.last_src != null and e.last_src.object_id == &"fireball")])

	print("\n%s" % ("오브젝트 시스템 검증 통과" if fail == 0 else "실패 %d 건" % fail))
	quit()
