extends SceneTree
## 분출 바위가 그림자를 만드는가.
## 헤드리스는 렌더를 안 하므로 **그림자가 나오는 조건**을 구조로 검사한다:
##   1) MeshInstance3D.cast_shadow 가 켜져 있고
##   2) 살아 있는 동안의 재질이 **불투명**해야 한다 (ALPHA 를 쓰면 투명 파이프라인 -> 그림자 없음)
## godot --headless --path . --script tools/verify_rock_shadow.gd
func _init() -> void: _run()
func ok(c: bool) -> String: return "OK" if c else "*** 실패 ***"

func writes_alpha(sh: Shader) -> bool:
	return "ALPHA" in sh.code

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var r := EruptRock.new()
	main.add_child(r)
	r.global_position = Vector3(0, 4, 0)
	await process_frame

	var mi: MeshInstance3D = r._mesh
	print("[살아 있는 동안]")
	print("  cast_shadow=%s (1=ON)  %s" % [mi.cast_shadow,
		ok(mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON)])
	var live: ShaderMaterial = r._mat
	print("  본체 셰이더=%s" % live.shader.resource_path.get_file())
	print("  ALPHA 를 쓰는가=%s (쓰면 투명 -> 그림자 없음)  %s" % [
		writes_alpha(live.shader), ok(not writes_alpha(live.shader))])

	print("\n[먹선 껍질]")
	var ink: MeshInstance3D = null
	for c in mi.get_children():
		if c is MeshInstance3D:
			ink = c
	print("  cast_shadow=%s (0=OFF — 껍질은 그림자를 만들면 안 된다)  %s" % [
		ink.cast_shadow, ok(ink.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)])

	print("\n[사라질 때]")
	var fade := r._fade_material()
	print("  갈아끼울 셰이더=%s  ALPHA 사용=%s  %s" % [
		fade.shader.resource_path.get_file(), writes_alpha(fade.shader),
		ok(writes_alpha(fade.shader))])
	var same := true
	for k in ["light_tone", "dark_tone", "threshold"]:
		if fade.get_shader_parameter(k) != live.get_shader_parameter(k):
			same = false
	print("  색·경계가 살아 있을 때와 동일=%s (룩이 튀지 않아야)  %s" % [same, ok(same)])
	quit()
