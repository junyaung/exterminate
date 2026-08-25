extends SceneTree
## "넓은 울림"(공격 범위 +15%) 카드가 여진까지 넓히는지 실측한다.
## 최초 타격 / 여진 / 균열 지대 / 분출 피해 범위를 카드 전후로 비교.
## godot --headless --path . --script tools/verify_radius.gd

func _init() -> void:
	_run()

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var hs = main.get_node("HammerStrike")
	hs.has_aftershock = true

	print("카드   최초타격  여진(×%.1f)  풀차징여진  균열지대  분출반경" % hs.aftershock_radius)
	var rows := []
	for step in 3:
		if step > 0:
			hs.stats.add_pct(Stats.RADIUS, 0.15)   # 카드 "넓은 울림"
		# 실제로 한 대 쳐서 균열 지대를 만들고 그 반경을 읽는다 (계산식이 아니라 결과를 본다)
		for fx in get_nodes_in_group("crack_fields"):
			fx.expire()
		hs._cd = 0.0
		hs._strike(Vector3(60, 0, 60), 0.0)        # 적 없는 빈 땅
		await create_timer(0.75).timeout           # 임팩트(0.21) + 여진(0.35) 이후
		var field = null
		for f in get_nodes_in_group("crack_fields"):
			field = f
		rows.append({
			card = step,
			strike = hs.strike_radius(0.0),
			after = hs.strike_radius(0.0) * hs.aftershock_radius,
			after_charged = hs.strike_radius(1.0) * hs.aftershock_radius,
			field = field.field_radius if field != null else -1.0,
		})

	for r in rows:
		print("+%d장   %6.2f    %6.2f      %6.2f     %6.2f" % [
			r.card, r.strike, r.after, r.after_charged, r.field])

	var base: Dictionary = rows[0]
	var last: Dictionary = rows[2]
	print("")
	print("카드 2장(+15%% 씩) 후 배율 — 최초타격 ×%.4f / 여진 ×%.4f / 균열지대 ×%.4f" % [
		last.strike / base.strike, last.after / base.after, last.field / base.field])
	print("기대 ×%.4f (1.15 를 합산 적용: 1 + 0.15 + 0.15 = 1.30)" % 1.30)
	quit()
