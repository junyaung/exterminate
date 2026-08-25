extends SceneTree
## 우클릭 특수 녹화용. Godot Movie Maker(--write-movie)와 함께 쓴다.
##   Godot --path . --write-movie <out.png> --fixed-fps 30 --resolution 640x500 \
##         --script tools/record_special.gd
## ⚠️ --headless 를 붙이면 렌더가 안 돼 프레임이 안 나온다. 창이 실제로 뜬다.
##
## 고정 fps 로 돌기 때문에 create_timer 대신 **프레임 수**로 진행을 센다.
const FPS := 60
const TARGET := Vector3(0, 0, 0)
const MOBS := 7          ## 밀려나는 게 보이도록 표적 주변에 세워둔다

var _f := 0

func _init() -> void: _run()

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var hs = main.get_node("HammerStrike")
	main.set_physics_process(false)          # 웨이브 스폰을 멈춰 화면을 깨끗하게
	hs._indicator.visible = false            # 조준 원이 마우스(0,0)를 따라 구석에 떠 있어 지운다
	# 카메라를 표적 위로 옮긴다 (기본 위치는 기지 쪽을 본다)
	var cam := main.get_node("Camera3D") as Camera3D
	cam.position = TARGET + Vector3(11.868, 20.0, 11.868)
	cam.size = 34.0

	# 쇼크웨이브에 밀려나는 걸 보여줄 적들
	var scene := load("res://scenes/enemy.tscn")
	for i in MOBS:
		var e = scene.instantiate()
		e.type_id = &"grunt"
		main.add_child(e)
		var a := TAU * float(i) / float(MOBS)
		e.global_position = TARGET + Vector3(cos(a), 0.0, sin(a)) * randf_range(3.0, 7.0)
		e.stats.set_base(Stats.HEALTH, 99999.0)   # 죽어 사라지면 넉백이 안 보인다
		e.health = 99999.0
	for i in 6:
		await process_frame

	hs._special_strike(TARGET)
	# 예고 2.0 + 강타 0.09 + 유지 2.0 + 소각 0.9 = 4.99초 + 재 낙진 1.5초
	var total := int(6.6 * FPS)
	while _f < total:
		_f += 1
		await process_frame
	print("RECORDED %d frames" % _f)
	quit()
