extends SceneTree
## 불덩이가 스치는 적도 주홍으로 번쩍이는지 — 그리고 **닿은 적만** 번쩍이는지.
## 불덩이는 같은 적을 한 번만 태우므로(_hit_ids) 플래시도 한 번이어야 한다.
## godot --headless --path . --script tools/verify_fireball_flash.gd

const EnemyScene := preload("res://scenes/enemy.tscn")

var _main

func _init() -> void:
	_run()

func _spawn(id: StringName, at: Vector3):
	var e = EnemyScene.instantiate()
	e.type_id = id
	_main.get_node("Enemies").add_child(e)
	e.global_position = at
	e.health = 9999.0        # 플래시만 보려고 죽지 않게
	e.set_physics_process(false)   # 제자리에 세워둔다
	return e

func _burn_of(e) -> float:
	var blob := e._mesh as MeshInstance3D
	if blob != null:
		var m := blob.material_override as StandardMaterial3D
		return m.emission_energy_multiplier if m != null and m.emission_enabled else 0.0
	var body := e._mesh.find_child("Body", true, false) as MeshInstance3D
	var v = body.get_instance_shader_parameter(&"flash")
	return float(v) if v != null else 0.0

func _run() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await process_frame
	await process_frame
	var hs = _main.get_node("HammerStrike")
	_main.set_physics_process(false)

	# 불덩이가 +x 로 굴러가는 길 위에 한 마리, 옆길에 한 마리
	var on_path = _spawn(&"grunt", Vector3(9, 0, 0))
	var off_path = _spawn(&"grunt", Vector3(9, 0, 14))
	await process_frame

	Fireball.spawn_roll(hs, Vector3.ZERO, Vector2(1, 0), 40.0, 2.0)
	print("길 위 %.2f / 옆길 %.2f  (발사 직후, 기대 0 / 0)" % [
		_burn_of(on_path), _burn_of(off_path)])

	# 굴러가서 스칠 때까지 (속도 6, 거리 9 -> 약 1.5초)
	var peak := 0.0
	var peak_off := 0.0
	for i in 30:
		await create_timer(0.08).timeout
		peak = maxf(peak, _burn_of(on_path))
		peak_off = maxf(peak_off, _burn_of(off_path))
	print("스친 뒤 최고값: 길 위 %.2f / 옆길 %.2f  (기대 > 0 / 0)" % [peak, peak_off])
	print("체력: 길 위 %d (9999 - 40 = 9959 기대) / 옆길 %d" % [
		roundi(on_path.health), roundi(off_path.health)])
	print("현재 플래시: 길 위 %.2f (기대 0 — 식었음)" % _burn_of(on_path))
	quit()
