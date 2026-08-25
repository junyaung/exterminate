extends SceneTree
## 충격파 링이 실제로 때리는지 — 그리고 **링이 도착한 순서대로** 맞는지.
## 링은 중심에서 바깥으로 퍼지므로 가까운 적이 먼저, 먼 적이 나중에 맞아야 한다.
## godot --headless --path . --script tools/verify_ring_damage.gd

const EnemyScene := preload("res://scenes/enemy.tscn")

var _main

func _init() -> void:
	_run()

func _spawn(at: Vector3):
	var e = EnemyScene.instantiate()
	_main.get_node("Enemies").add_child(e)
	e.global_position = at
	e.health = 9999.0
	e.set_physics_process(false)      # 제자리에 세워둔다
	return e

func _run() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await process_frame
	await process_frame
	var hs = _main.get_node("HammerStrike")
	_main.set_physics_process(false)

	var radius := 2.08                     # 현재 평타 폭연 반경
	var reach: float = radius * Deflagration.RING_REACH
	print("폭연 반경 %.2f / 링 도달 %.2f (×%.2f) / 링 시간 %.2fs" % [
		radius, reach, Deflagration.RING_REACH, Deflagration.RING_TIME])
	print("")

	# 링 안쪽 / 예전 반경 밖이지만 링 안 / 링 밖 — 세 구간에 한 마리씩
	var d := [1.0, 2.9, 4.2]
	var e := []
	for dist in d:
		e.append(_spawn(Vector3(dist, 0, 0)))
	await process_frame

	Deflagration.detonate(hs, Vector3.ZERO, radius, 20.0, 4.0, 0)
	await create_timer(Deflagration.DELAY - 0.02).timeout

	# 링이 퍼지는 동안 누가 언제 맞는지 추적
	var hit_at := [-1.0, -1.0, -1.0]
	var t := 0.0
	for i in 24:
		await create_timer(0.02).timeout
		t += 0.02
		for k in 3:
			if hit_at[k] < 0.0 and e[k].health < 9999.0:
				hit_at[k] = t

	print("거리   피격시각   체력    (링 도달 %.2f)" % reach)
	for k in 3:
		print("%5.1f  %8s  %6d" % [d[k],
			("%.2fs" % hit_at[k]) if hit_at[k] >= 0.0 else "안 맞음",
			roundi(e[k].health)])
	print("")
	print("기대: 1.0 과 2.9 는 맞고(2.9 가 더 늦게), 4.2 는 링 밖이라 안 맞음")
	quit()
