extends SceneTree
## 인력 카드 검증 — 실제로 끌려오는가 / 무거운 몹이 절반인가 / 중심을 넘지 않는가.
## godot --headless --path . --script tools/verify_pull.gd

const EnemyScene := preload("res://scenes/enemy.tscn")

func _spawn(type_id: StringName, at: Vector3) -> Enemy:
	var e := EnemyScene.instantiate() as Enemy
	e.type_id = type_id          # ⚠️ add_child 전에 정해야 _ready 가 수치를 반영한다
	e.position = at              # ⚠️ add_child 전에 — 트리 밖에서 global_position 은 못 쓴다
	root.add_child(e)
	e.target = null              # 걷지 않게 — 끌림만 재려는 것이다
	return e

func _settle(seconds: float) -> void:
	await create_timer(seconds).timeout

func _run() -> void:
	var center := Vector3.ZERO
	var start := 12.0
	var dist := 6.0

	print("중심 (0,0,0) / 시작 거리 %.1f / 끌어당김 거리 %.1f" % [start, dist])
	var grunt := _spawn(&"grunt", Vector3(start, 0.0, 0.0))
	var heavy := _spawn(&"heavy", Vector3(0.0, 0.0, start))
	var runner := _spawn(&"runner", Vector3(-start, 0.0, 0.0))
	await process_frame
	await process_frame

	grunt.pull(center, dist)
	heavy.pull(center, dist)
	runner.pull(center, dist)
	await _settle(1.5)

	for row in [["개미(grunt)", grunt], ["장수풍뎅이(heavy)", heavy], ["콩벌레(runner)", runner]]:
		var e: Enemy = row[1]
		var now := e.global_position
		now.y = 0.0
		var moved := start - now.length()
		var resist: float = float(Enemy.TYPES.get(e.type_id, {}).get("knockback_resist", 0.0))
		print("  %-18s 이동 %5.2f  (기대 %.2f, resist %.1f)" % [
			row[0], moved, dist * (1.0 - resist * 0.5), resist])

	# 중심을 넘어가지 않는가 — 끌림 거리보다 가까이 있는 적
	print("")
	print("과잉 끌림 검사: 중심에서 2.0 인 적에게 거리 %.1f 로 끌기" % dist)
	var close := _spawn(&"grunt", Vector3(2.0, 0.0, 0.0))
	await process_frame
	close.pull(center, dist)
	await _settle(1.5)
	var cp := close.global_position
	cp.y = 0.0
	print("  최종 중심거리 %.2f  (PULL_MIN_GAP %.1f 이상이어야 하고 반대편으로 넘어가면 안 된다)"
		% [cp.length(), Enemy.PULL_MIN_GAP])
	print("  x 부호 유지: ", "OK" if cp.x > 0.0 else "실패 — 중심을 지나쳤다")
	quit()

func _init() -> void:
	_run()
