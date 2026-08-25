extends SceneTree
## 시간대 무드 조명 검증 (낮 / 노을 / 밤).
##   1) 무드마다 태양·환경·색조가 서로 다르다
##   2) 여명은 태양 고도가 가장 낮다 = 그림자가 가장 길다
##   3) T 키 순환이 세 무드를 돈다
## ⚠️ **RenderingServer 의 전역 셰이더 유니폼은 헤드리스에서 읽지 않는다** — get / get_list
##    둘 다 더미 렌더러에서 멈춘다(실측). 색조가 실제로 화면에 먹히는지는 눈으로만 확인 가능하고,
##    여기서는 무드 표의 값이 태양·환경에 제대로 반영되는지까지만 본다.
## godot --headless --path . --script tools/verify_mood.gd

func _init() -> void:
	_run()

func _run() -> void:
	var fail := 0
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var mood := main.get_node("Mood") as Mood
	var sun := main.get_node("Sun") as DirectionalLight3D
	var env := (main.get_node("WorldEnvironment") as WorldEnvironment).environment

	var seen := {}
	var pitch := {}
	for phase in [Mood.Phase.DAY, Mood.Phase.SUNSET, Mood.Phase.NIGHT]:
		mood.apply(phase)
		var tint: Color = Mood.PRESETS[phase].tint
		seen["%s|%.2f|%s|%s|%.3f" % [sun.light_color.to_html(false), sun.light_energy,
			env.background_color.to_html(false), tint.to_html(false), env.fog_density]] = true
		pitch[phase] = absf(rad_to_deg(sun.rotation.x))
		var st: Color = Mood.PRESETS[phase].shadow_tint
		var shade: float = Mood.PRESETS[phase].shade
		# 대비 = 빛 쪽 밝기 / 그림자 쪽 밝기. 낮을수록 밋밋하다.
		var lit_v: float = maxf(maxf(tint.r, tint.g), tint.b)
		var sh_v: float = maxf(maxf(st.r, st.g), st.b) * shade
		# 그림자 길이 = 물체 높이 대비 몇 배로 늘어지는가 = 1 / tan(고도)
		var shadow_len := 1.0 / maxf(tan(absf(sun.rotation.x)), 0.01)
		print("   %s — 태양 %s(%.2f) 고도 %.0f도(그림자 %.1f배) / 배경 %s / 빛 %s / 그림자 %s×%.2f / 지면×%.2f / 대비 %.1f배 / 안개 %s" % [
			Mood.PRESETS[phase].name, sun.light_color.to_html(false), sun.light_energy,
			absf(rad_to_deg(sun.rotation.x)), shadow_len, env.background_color.to_html(false),
			tint.to_html(false), st.to_html(false), shade,
			float(Mood.PRESETS[phase].ground_mul), lit_v / maxf(sh_v, 0.001),
			"켬(%.3f)" % env.fog_density if env.fog_enabled else "끔"])

	var ok1: bool = seen.size() == 3
	fail += 0 if ok1 else 1
	print("1) 무드별 설정이 서로 다른가 (%d/3) %s" % [seen.size(), "OK" if ok1 else "***"])

	# 대비가 최소 2배는 나야 "선명하다"로 읽힌다 (유저 지적으로 추가한 기준).
	var flat := 0
	for phase in [Mood.Phase.DAY, Mood.Phase.SUNSET, Mood.Phase.NIGHT]:
		var t2: Color = Mood.PRESETS[phase].tint
		var s2: Color = Mood.PRESETS[phase].shadow_tint
		var ratio: float = maxf(maxf(t2.r, t2.g), t2.b) \
			/ maxf(maxf(maxf(s2.r, s2.g), s2.b) * float(Mood.PRESETS[phase].shade), 0.001)
		if ratio < 2.0:
			flat += 1
	var ok_contrast: bool = flat == 0
	fail += 0 if ok_contrast else 1
	print("1b) 대비가 2배 미만인 무드 %d개 (기대 0) %s" % [flat, "OK" if ok_contrast else "***"])

	var ok2: bool = pitch[Mood.Phase.SUNSET] < pitch[Mood.Phase.DAY] \
		and pitch[Mood.Phase.SUNSET] < pitch[Mood.Phase.NIGHT]
	fail += 0 if ok2 else 1
	print("2) 태양 고도 낮 %.0f / 노을 %.0f / 밤 %.0f (노을 최저 = 그림자 최장) %s" % [
		pitch[Mood.Phase.DAY], pitch[Mood.Phase.SUNSET], pitch[Mood.Phase.NIGHT],
		"OK" if ok2 else "***"])

	mood.apply(Mood.Phase.DAY)
	var seq: Array = []
	for i in 4:
		seq.append(Mood.PRESETS[mood.current].name)
		mood.cycle()
	var ok3: bool = seq.size() == 4 and seq[0] == "낮" and seq[3] == "낮"
	fail += 0 if ok3 else 1
	print("3) 순환 %s %s" % [seq, "OK" if ok3 else "***"])

	print("")
	print("무드 조명 검증 통과" if fail == 0 else "무드 조명 검증 실패 %d 건" % fail)
	quit(0 if fail == 0 else 1)
