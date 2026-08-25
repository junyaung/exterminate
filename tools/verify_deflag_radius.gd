extends SceneTree
## "넓은 울림"(범위 +15%) 카드가 폭연에 어떻게 작용하는지 실측.
## 개수 상한 / 실제 터진 수 / 폭연 반경 / 폭연 총피해를 카드 0~2장으로 비교한다.
## godot --headless --path . --script tools/verify_deflag_radius.gd

const EnemyScene := preload("res://scenes/enemy.tscn")

var _main
var _hs

func _init() -> void:
	_run()

func _blast_row() -> Dictionary:
	if not ProjectileStats.has(&"blast"):
		return {spawned = 0, damage = 0.0, hits = 0}
	return ProjectileStats._d[&"blast"]

## 균일 밀도 격자 — 반경이 커질수록 더 많이 죽는 상황을 재현한다.
func _seed_grid(spacing: float, half: int) -> int:
	var n := 0
	for ix in range(-half, half + 1):
		for iz in range(-half, half + 1):
			var e = EnemyScene.instantiate()
			_main.get_node("Enemies").add_child(e)
			e.global_position = Vector3(float(ix) * spacing, 0.0, float(iz) * spacing)
			e.target = _main.get_node("BaseBlock")
			n += 1
	return n

func _clear() -> void:
	for e in get_nodes_in_group("enemies"):
		e.die()
	await create_timer(1.4).timeout

func _run() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await process_frame
	await process_frame
	_hs = _main.get_node("HammerStrike")
	_hs.has_fire = true
	_main.set_physics_process(false)

	print("균일 밀도 격자(간격 1.2) 위에 평타 1회. 카드 = 공격 범위 +15%%")
	print("")
	print("카드   타격반경  직접처치  폭연개수  폭연반경  폭연피해  상한")
	for step in 3:
		if step > 0:
			_hs.stats.add_pct(Stats.RADIUS, 0.15)
		await _clear()
		var total := _seed_grid(1.2, 8)
		await process_frame
		var before := get_nodes_in_group("enemies").size()
		var r0 := _blast_row()
		var s0: int = r0.spawned
		var d0: float = r0.damage
		_hs._impact(Vector3.ZERO, 0.0)
		await process_frame
		var kills := before - get_nodes_in_group("enemies").size()
		var made: int = _blast_row().spawned - s0
		await create_timer(1.0).timeout
		var dmg: float = _blast_row().damage - d0
		print("+%d장   %6.2f  %8d  %8d  %8.2f  %8d  %4d" % [
			step, _hs.strike_radius(0.0), kills, made,
			_hs.stats.get_v(Stats.RADIUS) * _hs.deflag_radius, roundi(dmg),
			_hs.deflag_count])
		if total == 0:
			break

	print("")
	print("풀차징 비교 (카드 2장 상태)")
	await _clear()
	_seed_grid(1.2, 10)
	await process_frame
	var before2 := get_nodes_in_group("enemies").size()
	var s2: int = _blast_row().spawned
	_hs._impact(Vector3.ZERO, 1.0)
	await process_frame
	print("  풀차징: 타격반경 %.2f  직접처치 %d  폭연 %d개 (상한 %d)" % [
		_hs.strike_radius(1.0), before2 - get_nodes_in_group("enemies").size(),
		_blast_row().spawned - s2, _hs.deflag_count_charged])
	quit()
