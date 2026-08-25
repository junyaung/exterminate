extends SceneTree
## 콩벌레(러너) 검증: 크기·이속·구르기 속도, 그리고
## **말린 채 굴러와 성에 일격 -> 펴짐 -> 기본 공격** 전이가 실제로 그 순서로 일어나는가.
## godot --headless --path . --script tools/verify_pillbug.gd

var dmg_log: Array = []

class FakeBase extends Node3D:
	var log: Array
	var hp := 0.0
	func take_damage(d: float) -> void:
		hp += d
		log.append(d)

func _init() -> void:
	_run()

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	# ⚠️ 이 검증은 **콩벌레 상태기계**(구르기->펴기->공격)를 보는 것이지 지형 검증이 아니다.
	#    산이 있는 판에서는 길찾기·통행 규칙에 걸려 굴러오지도 못한다. 지형을 잠깐 평지로
	#    만들고 잰다 (메모리에서만 지운다 — 지형 파일은 그대로다).
	var _g := main.get_node_or_null("Ground") as Ground
	if _g != null:
		_g.clear_edits()
		_g.build()
	await process_frame
	var e = load("res://scenes/enemy.tscn").instantiate()
	e.type_id = &"runner"
	main.add_child(e)
	await process_frame

	var fake := FakeBase.new()
	fake.log = dmg_log
	main.add_child(fake)
	fake.global_position = Vector3.ZERO
	e.target = fake
	e.global_position = Vector3(40, 0, 0)

	print("scale=%.2f  speed=%.2f  roll_ups=%.2f  attack_range=%.1f" % [
		e.scale.x, e.stats.get_v(Stats.SPEED), e._roll_ups(),
		e.stats.get_v(Stats.ATTACK_RANGE)])
	print("구르기 speed_scale = %.2f (1.0 에 가까울수록 미끄러짐 없음)" %
		(e.stats.get_v(Stats.SPEED) / e._roll_ups()))

	var seen: Array[String] = []
	var slam_at := -1
	for i in 400:
		e._physics_process(1.0 / 60.0)
		await process_frame
		var a: String = e._anim.current_animation if e._anim != null else "?"
		var tag := "%s%s" % [a, "(curled)" if e._curled else ""]
		if seen.is_empty() or seen[-1] != tag:
			seen.append(tag)
			print("  f%-3d dist=%5.2f  %s" % [i, e.global_position.distance_to(Vector3.ZERO), tag])
		if slam_at < 0 and dmg_log.size() > 0:
			slam_at = i
			print("  >>> 일격 %.1f (기대 %.1f = damage 3.0 x SLAM_MULT 3.0)" % [dmg_log[0], 9.0])
	print("")
	print("상태 순서: %s" % [seen])
	print("일격 프레임=%d  누적 피해=%.1f  피해 틱 수=%d" % [slam_at, fake.hp, dmg_log.size()])
	quit()
