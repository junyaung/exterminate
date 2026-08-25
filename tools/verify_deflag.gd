extends SceneTree
## 폭연 검증. 개수 상한(평타 3 / 풀차징 6), 지연, 피해, 그리고 핵심 규칙인
## **폭연이 폭연을 낳지 않는다**.
##
## ⚠️ 폭연 노드 수를 세면 안 된다 — 터진 뒤에도 불꽃이 꺼질 때까지 0.9초 살아 있어서
## 앞 단계의 잔재가 섞인다. **생성 카운터(ProjectileStats)의 증분**으로 세야 정확하다.
## godot --headless --path . --script tools/verify_deflag.gd

const EnemyScene := preload("res://scenes/enemy.tscn")

var _main
var _hs

func _init() -> void:
	_run()

func _spawned() -> int:
	if not ProjectileStats.has(&"blast"):
		return 0
	return ProjectileStats._d[&"blast"].spawned

## center 주변 링에 적을 깐다. hp 를 주면 그 값으로 덮어써서 죽는 조건을 통제한다.
func _seed(center: Vector3, count: int, radius: float, hp := -1.0) -> Array:
	var out := []
	for i in count:
		var a := TAU * float(i) / float(count)
		var e = EnemyScene.instantiate()
		_main.get_node("Enemies").add_child(e)
		e.global_position = center + Vector3(cos(a), 0.0, sin(a)) * radius
		e.target = _main.get_node("BaseBlock")
		if hp > 0.0:
			e.health = hp
		out.append(e)
	return out

func _clear() -> void:
	for e in get_nodes_in_group("enemies"):
		e.die()
	await create_timer(1.6).timeout   # 시체 소멸 + 앞 단계 폭연(1초 지연) 잔재까지 정리

func _alive() -> int:
	return get_nodes_in_group("enemies").size()

func _run() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await process_frame
	await process_frame
	_hs = _main.get_node("HammerStrike")
	_hs.has_fire = true
	_main.set_physics_process(false)          # 웨이브 스폰 정지 — 실험 통제

	print("설정: 망치 피해 %d / 반경 %.1f | 폭연 피해 %d%% 반경 %d%% 지연 %.2fs" % [
		_hs.strike_damage(0.0), _hs.strike_radius(0.0),
		_hs.deflag_damage * 100.0, _hs.deflag_radius * 100.0, Deflagration.DELAY])
	print("")

	# --- 1) 평타 상한 3 ---
	await _clear()
	_seed(Vector3.ZERO, 10, 2.0)
	await process_frame
	var s0 := _spawned()
	_hs._impact(Vector3.ZERO, 0.0)
	await process_frame
	print("1) 평타로 10마리 처치 -> 폭연 %d개 생성 (기대 3)" % [_spawned() - s0])

	# --- 2) 지연과 피해량 ---
	var ring := _seed(Vector3.ZERO, 6, 1.4, 40.0)   # 폭연 20 으로는 안 죽는 체력
	await process_frame
	await create_timer(0.5).timeout
	var hp_early := roundi(ring[0].health) if is_instance_valid(ring[0]) else -1
	await create_timer(1.2).timeout   # 폭발(1.0s) + 링 스윕(0.32s) 이후
	var hp_late := []
	for e in ring:
		if is_instance_valid(e):
			hp_late.append(roundi(e.health))
	print("2) 0.5s 체력 %d (아직 안 터짐, 기대 40) -> 1.7s 체력 %s (기대 20 = 40-20)" % [
		hp_early, hp_late])

	# --- 3) 핵심: 폭연이 죽인 적은 다시 터지지 않는다 ---
	# 직접 타격 반경(4.0) 안에 4마리, **밖**(4.8)에 폭연으로만 죽을 약한 적 8마리.
	# 시체(3.5)에서 폭연 반경 1.8 이면 4.8 까지 닿는다.
	await _clear()
	_seed(Vector3.ZERO, 4, 3.5)                # 직접 타격으로 죽음 (100hp vs 100)
	var weak := _seed(Vector3.ZERO, 8, 4.8, 12.0)   # 타격 밖, 폭연 20 으로 죽음
	await process_frame
	var s3 := _spawned()
	_hs._impact(Vector3.ZERO, 0.0)
	await process_frame
	var made := _spawned() - s3
	await create_timer(1.6).timeout
	var chained := _spawned() - s3 - made
	var dead_weak := 0
	for e in weak:
		if not is_instance_valid(e) or e.dying:
			dead_weak += 1
	print("")
	print("3) 직접 처치 4마리 -> 폭연 %d개 (기대 3)" % made)
	print("   그 폭연이 타격 범위 **밖** 약한 적 %d/8 마리를 죽임" % dead_weak)
	print("   -> 그 죽음으로 추가 생성된 폭연: %d개 (기대 0 = 연쇄 없음)" % chained)

	# --- 4) 풀차징 상한 6 ---
	await _clear()
	_seed(Vector3.ZERO, 12, 5.0)
	await process_frame
	var s4 := _spawned()
	_hs._impact(Vector3.ZERO, 1.0)
	await process_frame
	print("")
	print("4) 풀차징으로 12마리 처치 -> 폭연 %d개 (기대 6)" % [_spawned() - s4])
	print("   폭연 반경: 평타 %.2f / 풀차징 %.2f (기대 ×%.1f)" % [
		_hs.stats.get_v(Stats.RADIUS) * _hs.deflag_radius,
		_hs.stats.get_v(Stats.RADIUS) * _hs.deflag_radius * _hs.deflag_radius_charged,
		_hs.deflag_radius_charged])

	# --- 5) 불 속성이 없으면 폭연도 없다 ---
	await _clear()
	_hs.has_fire = false
	_seed(Vector3.ZERO, 6, 2.0)
	await process_frame
	var s5 := _spawned()
	_hs._impact(Vector3.ZERO, 0.0)
	await process_frame
	await create_timer(0.6).timeout
	print("")
	print("5) 불 OFF 로 6마리 처치 -> 폭연 %d개 (기대 0)" % [_spawned() - s5])
	print(ProjectileStats.report())
	quit()
