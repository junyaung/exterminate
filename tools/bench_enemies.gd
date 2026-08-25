extends SceneTree
## 몹 수를 늘려가며 **물리 프레임 CPU 시간**을 잰다 (렌더는 헤드리스라 안 잡힌다).
## godot --headless --path . --script tools/bench_enemies.gd
func _init() -> void:
	_r()
func _r() -> void:
	var m: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var base := m.get_node("BaseBlock") as Node3D
	var scene := load("res://scenes/enemy.tscn") as PackedScene
	var list: Array[Enemy] = []
	for count in [100, 300, 600]:
		while list.size() < count:
			var e := scene.instantiate() as Enemy
			e.type_id = [&"grunt", &"runner", &"heavy"][list.size() % 3]
			m.get_node("Enemies").add_child(e)
			e.global_position = Main.random_spawn_point()
			e.target = base
			list.append(e)
		# 예열
		for i in 10:
			for e in list:
				e._physics_process(1.0 / 60.0)
		var t0 := Time.get_ticks_usec()
		for i in 60:
			for e in list:
				e._physics_process(1.0 / 60.0)
		var us := float(Time.get_ticks_usec() - t0) / 60.0
		print("B %d마리 — 프레임당 %.2f ms (한 마리 %.1f us) / 60fps 예산 16.7ms 대비 %.0f%%" % [
			count, us / 1000.0, us / float(count), us / 16700.0 * 100.0])
	quit()
