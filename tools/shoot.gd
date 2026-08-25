extends SceneTree
## 게임 화면을 PNG 로 저장한다 (README·홍보용).
## 컴퓨터를 조작하지 않는다 — 게임이 자기 프레임버퍼를 직접 굽고 종료한다.
##
##   godot --path . --script tools/shoot.gd            # 기본 20초 지점, docs/screenshot.png
##   AT=35 OUT=docs/late.png godot --path . --script tools/shoot.gd
##
## ⚠️ --headless 를 붙이면 안 된다. 헤드리스는 렌더를 하지 않아 초록 배경만 나온다.

func _init() -> void:
	_shoot()

func _autopick(ui) -> void:
	while true:
		await create_timer(0.25).timeout
		if ui._open and not ui._hand.is_empty():
			ui._pick(randi() % ui._hand.size())

## 적이 가장 빽빽한 자리 — 카드 효과는 몹이 몰린 데서 찍어야 읽힌다.
func _busiest(main) -> Vector3:
	var best := Vector3.ZERO
	var best_n := -1
	for node in main.get_tree().get_nodes_in_group("enemies"):
		var n := 0
		for other in main.get_tree().get_nodes_in_group("enemies"):
			if node.global_position.distance_to(other.global_position) < 9.0:
				n += 1
		if n > best_n:
			best_n = n
			best = node.global_position
	return best

func _shoot() -> void:
	var at := float(OS.get_environment("AT")) if OS.get_environment("AT") != "" else 20.0
	var out := OS.get_environment("OUT")
	if out == "":
		out = "docs/screenshot.png"

	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	# ⚠️ main.gd 의 spawning 기본값이 false 라 켜 주지 않으면 적이 한 마리도 안 나온다
	# (게임 안에서는 V 키로만 켜진다). verify_waves.gd 도 같은 이유로 직접 켠다.
	main.spawning = true
	# 레벨업하면 드래프트가 열리며 게임이 멈춘다 — 아무도 안 고르면 거기서 얼어붙는다.
	# 무인 촬영이라 대신 골라 준다 (무엇을 고르는지는 구도에 영향이 없어 무작위).
	_autopick(main.get_node("CardUI"))
	# STRIKE=<ratio> 를 주면 촬영 직전에 망치를 한 번 내리친다 (0=평타, 1=풀차징).
	# CARDS="pull,shockwave" 로 패턴 카드를 켠다. 카드는 무작위라 기다려서는 못 본다.
	var hs = main.get_node("HammerStrike")
	for c in OS.get_environment("CARDS").split(",", false):
		if hs.get(&"has_" + c) != null:
			hs.set(&"has_" + c, true)
	await create_timer(at).timeout
	if OS.get_environment("STRIKE") != "":
		hs._strike(_busiest(main), float(OS.get_environment("STRIKE")))
		await create_timer(float(OS.get_environment("STRIKE_AT")) \
			if OS.get_environment("STRIKE_AT") != "" else 0.12).timeout
	# 구도 보정: PANX/PANZ 로 화면 기준 오프셋을 준다 (기본은 시작 위치 그대로).
	var pan := Vector2(float(OS.get_environment("PANX")), float(OS.get_environment("PANZ")))
	if pan != Vector2.ZERO:
		var cam := main.get_node("Camera3D") as Camera3D
		cam.global_position += Main.to_world(pan.x, pan.y)
		await create_timer(0.3).timeout
	print("[shoot] 웨이브 %d, 생존 %d, 처치 %d" % [
		main.wave + 1, main.alive_count(), main.kills])
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out)
	print("[shoot] %s  (%dx%d, %.1f초 지점)" % [out, img.get_width(), img.get_height(), at])
	quit()
