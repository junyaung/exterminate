extends SceneTree
## _physics_process 안을 **부위별로** 잰다. 무엇이 비싼지 추측하지 않기 위한 도구.
## godot --headless --path . --script tools/bench_parts.gd

const N := 600
const FRAMES := 40

func _init() -> void:
	_run()

func _time(label: String, list: Array, f: Callable) -> float:
	for i in 5:                              # 예열
		for e in list:
			f.call(e)
	var t0 := Time.get_ticks_usec()
	for i in FRAMES:
		for e in list:
			f.call(e)
	var ms := float(Time.get_ticks_usec() - t0) / float(FRAMES) / 1000.0
	print("  %-28s %6.2f ms  (한 마리 %5.1f us)" % [label, ms, ms * 1000.0 / float(N)])
	return ms

func _run() -> void:
	var m: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var base := m.get_node("BaseBlock") as Node3D
	var scene := load("res://scenes/enemy.tscn") as PackedScene
	var list: Array = []
	for i in N:
		var e := scene.instantiate() as Enemy
		e.type_id = [&"grunt", &"runner", &"heavy"][i % 3]
		m.get_node("Enemies").add_child(e)
		e.global_position = Main.random_spawn_point()
		e.target = base
		list.append(e)
	await process_frame

	var g := Terrain.ground()
	print("몹 %d마리 / 지형 평지=%s" % [N, "예" if g == null or g.is_flat else "아니오"])
	print("")

	var whole := _time("_physics_process 전체", list, func(e): e._physics_process(1.0 / 60.0))
	print("  ---- 부위별 ----")
	_time("_steer_dir", list, func(e):
		var d: Vector3 = base.global_position - e.global_position
		d.y = 0.0
		e._steer_dir(d, d.length()))
	_time("_anim_lod", list, func(e): e._anim_lod())
	_time("_face_and_tilt", list, func(e): e._face_and_tilt(Vector3.FORWARD, 1.0 / 60.0))
	_time("stats.get_v(ATTACK_RANGE)", list, func(e): e.stats.get_v(Stats.ATTACK_RANGE))
	_time("Terrain.h(위치)", list, func(e): Terrain.h(e.global_position))
	print("")
	print("  (부위 합이 전체보다 작으면 나머지는 이동·애니 속도 갱신 등이다)")
	quit()
