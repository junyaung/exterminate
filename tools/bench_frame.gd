extends SceneTree
## 실제 트리에서 도는 비용 (우리 코드 + AnimationPlayer + 스켈레톤).
## 애니메이션을 껐을 때와 비교해 무엇이 무거운지 가른다.
func _init() -> void:
	_r()
func _spawn(m: Node, n: int, base: Node3D, anim: bool) -> Array:
	var scene := load("res://scenes/enemy.tscn") as PackedScene
	var out: Array = []
	for i in n:
		var e := scene.instantiate() as Enemy
		e.type_id = [&"grunt", &"runner", &"heavy"][i % 3]
		m.get_node("Enemies").add_child(e)
		e.global_position = Main.random_spawn_point()
		e.target = base
		if not anim:
			for a in e.find_children("*", "AnimationPlayer", true, false):
				(a as AnimationPlayer).active = false
		out.append(e)
	return out
func _measure(frames: int) -> Array:
	var p := 0.0
	var ph := 0.0
	for i in frames:
		await process_frame
		p += Performance.get_monitor(Performance.TIME_PROCESS)
		ph += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	return [p / frames * 1000.0, ph / frames * 1000.0]
func _r() -> void:
	var m: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var base := m.get_node("BaseBlock") as Node3D
	for setup in [{n = 300, anim = true}, {n = 300, anim = false}]:
		for c in m.get_node("Enemies").get_children():
			c.free()
		_spawn(m, setup.n, base, setup.anim)
		for i in 20:
			await process_frame
		var r: Array = await _measure(90)
		print("B %d마리 애니%s — process %.2f ms / physics %.2f ms / 합 %.2f ms" % [
			setup.n, "ON" if setup.anim else "OFF", r[0], r[1], r[0] + r[1]])
	quit()
