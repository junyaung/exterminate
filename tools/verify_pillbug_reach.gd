extends SceneTree
## 콩벌레가 성과 겹치지 않는가. 정지 거리에서 **자세별 앞끝**이 성 벽을 넘는지 계산한다.
## 블렌더 실측 도달거리(Enemy.PILL_REACH_*)를 그대로 쓰므로 렌더 없이도 판정된다.
func _init() -> void: _run()

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var e = load("res://scenes/enemy.tscn").instantiate()
	e.type_id = &"runner"
	main.add_child(e)
	await process_frame
	var half := Enemy.PILL_BASE_HALF
	var sc: float = e.scale.x
	var rows := [
		["말린 채 굴러와 멈춤", e._curled_range(), Enemy.PILL_REACH_CURLED * sc],
		["펴진 뒤 기본공격",   e.stats.get_v(Stats.ATTACK_RANGE), Enemy.PILL_REACH_UNCURLED * sc],
	]
	print("성 반폭=%.2f  콩벌레 scale=%.2f" % [half, sc])
	for r in rows:
		var stop: float = r[1]
		var reach: float = r[2]
		var gap: float = (stop - half) - reach     # 몸 앞끝과 성 벽 사이 (음수면 박힌다)
		print("%-18s 정지=%.2f  앞끝도달=%.2f  벽까지 여유=%+.3f  %s" % [
			r[0], stop, reach, gap, "OK" if gap >= 0.0 else "*** 성에 박힘 ***"])
	quit()
