extends SceneTree
## 조준 원 바깥 고리 = 우클릭 쿨타임 (유저 아이디어 2026-08-14).
##   · 셰이더의 aim_r 과 스크립트의 AIM_R 이 **같은 값**인가 (어긋나면 원이 사거리와 다르다)
##   · 조준 원의 실제 반지름이 사거리와 일치하는가
##   · cd_ratio 가 0(방금 씀) -> 1(준비 완료) 로 차는가
## godot --headless --path . --script tools/verify_aim_cooldown.gd

func _init() -> void:
	_run()

## 셰이더 소스에서 uniform 기본값을 긁는다. "uniform float aim_r = 0.86;" 꼴.
func _default_uniform(sh: Shader, name: String) -> float:
	for line in sh.code.split("\n"):
		var t := String(line).strip_edges()
		if t.begins_with("uniform float " + name):
			var eq := t.find("=")
			if eq >= 0:
				return float(t.substr(eq + 1).replace(";", "").strip_edges())
	return -1.0

func _run() -> void:
	var fail := 0
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var hs := main.get_node("HammerStrike") as HammerStrike
	var ind := hs.get_node("Indicator") as MeshInstance3D
	var mat := ind.material_override as ShaderMaterial

	# 1) 셰이더 aim_r == 스크립트 AIM_R
	# ⚠️ 인스펙터에서 안 덮은 유니폼은 get_shader_parameter 가 null 을 준다 —
	#    그땐 셰이더 소스에서 기본값을 직접 읽는다 (Shader 에 기본값 조회 API 가 없다).
	var sp = mat.get_shader_parameter("aim_r")
	var shader_r: float = float(sp) if sp != null else _default_uniform(mat.shader, "aim_r")
	var ok1: bool = is_equal_approx(shader_r, HammerStrike.AIM_R)
	fail += 0 if ok1 else 1
	print("1) 셰이더 aim_r=%.3f / 스크립트 AIM_R=%.3f %s" % [
		shader_r, HammerStrike.AIM_R, "OK" if ok1 else "*** 어긋남 — 원이 사거리와 다르다 ***"])

	# 2) 조준 원의 실제 반지름 = 사거리
	hs._process(0.016)
	await process_frame
	var quad_half: float = ind.scale.x            # PlaneMesh 기본 2x2 -> 반폭 1 * scale
	var drawn: float = quad_half * shader_r
	var want: float = hs.strike_radius(0.0)
	var ok2: bool = absf(drawn - want) < 0.01
	fail += 0 if ok2 else 1
	print("2) 그려지는 원 반지름 %.3f / 실제 사거리 %.3f %s" % [
		drawn, want, "OK" if ok2 else "***"])

	# 3) 쿨 고리: 방금 쓰면 0, 다 돌면 1
	hs._special_cd = hs.stats.get_v(Stats.COOLDOWN_SPECIAL)
	hs._special_active = false
	hs._process(0.016)
	var r0: float = mat.get_shader_parameter("cd_ratio")
	hs._special_cd = 0.0
	hs._process(0.016)
	var r1: float = mat.get_shader_parameter("cd_ratio")
	var ok3: bool = r0 < 0.05 and r1 > 0.95
	fail += 0 if ok3 else 1
	print("3) cd_ratio 방금씀 %.2f -> 준비완료 %.2f %s" % [
		r0, r1, "OK" if ok3 else "***"])

	# 4) 절반 남았을 때 절반쯤 차 있는가
	hs._special_cd = hs.stats.get_v(Stats.COOLDOWN_SPECIAL) * 0.5
	hs._process(0.016)
	var rh: float = mat.get_shader_parameter("cd_ratio")
	var ok4: bool = absf(rh - 0.5) < 0.05
	fail += 0 if ok4 else 1
	print("4) 쿨 절반 남음 -> cd_ratio %.2f (기대 0.50) %s" % [rh, "OK" if ok4 else "***"])

	print("")
	print("조준 원 쿨 고리 검증 통과" if fail == 0 else "조준 원 쿨 고리 검증 실패 %d 건" % fail)
	quit(0 if fail == 0 else 1)
