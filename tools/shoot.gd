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
	await create_timer(at).timeout
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
