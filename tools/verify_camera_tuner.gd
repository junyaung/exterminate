extends SceneTree
## 시점 튜너(CameraTuner)가 실제로 카메라를 옳게 배치하는지 — 눈으로 볼 수 없는 부분만 검증.
##   1) 항상 FOCUS 를 바라본다 (줌·각도를 바꿔도 초점이 안 흐른다)
##   2) 원근으로 바꿔도 **보이는 세로 폭이 같다** (줌이 안 튄다)
##   3) 화각을 좁히면 거리가 멀어진다 (= 원근이 약해지며 직교에 수렴)
##   4) 줌 아웃하면 스폰 존이 같이 밀려나 화면 밖에 남는다
## godot --headless --path . --script tools/verify_camera_tuner.gd

func _init() -> void:
	_run()

## 카메라가 보는 지면 위 초점.
func _focus_of(cam: Camera3D) -> Vector3:
	var o := cam.global_position
	var d := -cam.global_transform.basis.z
	return o - d * (o.y / d.y)

func _run() -> void:
	var fail := 0
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var cam := main.get_node("Camera3D") as Camera3D
	var t: CameraTuner = null
	for c in main.get_children():
		if c is CameraTuner:
			t = c
	if t == null:
		print("튜너가 씬에 안 붙었다 ***")
		quit(1)
		return

	# --- 1) 줌·각도를 바꿔도 초점이 유지된다 ---
	t.ortho_size = 60.0
	t.pitch = -68.0
	t._apply()
	var f := _focus_of(cam)
	var ok1: bool = f.distance_to(CameraTuner.FOCUS) < 0.05
	fail += 0 if ok1 else 1
	print("1) 줌 60 / 피치 -68 -> 초점 (%.2f, %.2f) (기대 원점) %s" % [
		f.x, f.z, "OK" if ok1 else "***"])

	# --- 2) 원근 전환해도 보이는 세로 폭이 같다 ---
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	t.fov = 28.0
	t._apply()
	var d := cam.global_position.distance_to(CameraTuner.FOCUS)
	var seen := 2.0 * d * tan(deg_to_rad(t.fov * 0.5))
	var ok2: bool = absf(seen - t.ortho_size) < 0.1
	fail += 0 if ok2 else 1
	print("2) 원근 fov 28 -> 거리 %.1f, 보이는 폭 %.1f (직교 size %.1f) %s" % [
		d, seen, t.ortho_size, "OK" if ok2 else "***"])
	var f2 := _focus_of(cam)
	var ok2b: bool = f2.distance_to(CameraTuner.FOCUS) < 0.05
	fail += 0 if ok2b else 1
	print("   원근에서도 초점 유지 (%.2f, %.2f) %s" % [
		f2.x, f2.z, "OK" if ok2b else "***"])

	# --- 3) 화각을 좁히면 멀어진다 ---
	t.fov = 12.0
	t._apply()
	var d2 := cam.global_position.distance_to(CameraTuner.FOCUS)
	var ok3: bool = d2 > d and cam.far > d2
	fail += 0 if ok3 else 1
	print("3) fov 28->12 -> 거리 %.1f -> %.1f, far %.0f %s" % [
		d, d2, cam.far, "OK" if ok3 else "***"])

	# --- 4) 스폰 존이 시야 배율만큼 밀려난다 ---
	var ok4: bool = absf(Main.view_scale - t.ortho_size / Main.VIEW_SIZE) < 0.001
	var far_pt := Main.random_spawn_point().length()
	fail += 0 if ok4 else 1
	print("4) view_scale %.2f (시야 %.0f / 기준 %.0f), 스폰 거리 %.1f %s" % [
		Main.view_scale, t.ortho_size, Main.VIEW_SIZE, far_pt,
		"OK" if ok4 else "***"])

	# 원래대로 돌려놓고 끝낸다 (씬 파일은 안 건드린다)
	Main.view_scale = 1.0
	print("")
	print("시점 튜너 검증 통과" if fail == 0 else "시점 튜너 검증 실패 %d 건" % fail)
	quit(0 if fail == 0 else 1)
