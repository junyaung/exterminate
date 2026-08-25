extends SceneTree
## 불 피해 플래시 검증. 핵심은 **맞은 개체만** 번쩍이는가 —
## 머티리얼이 종류별로 공유되므로, 잘못 짜면 화면의 같은 몹이 전부 같이 빛난다.
## godot --headless --path . --script tools/verify_burn_flash.gd

const EnemyScene := preload("res://scenes/enemy.tscn")

var _main

func _init() -> void:
	_run()

func _spawn(id: StringName, at: Vector3):
	var e = EnemyScene.instantiate()
	e.type_id = id
	_main.get_node("Enemies").add_child(e)
	e.global_position = at
	e.health = 999.0        # 플래시만 보려고 죽지 않게 한다
	return e

func _burn_of(e) -> float:
	var blob := e._mesh as MeshInstance3D
	if blob != null:
		var m := blob.material_override as StandardMaterial3D
		return m.emission_energy_multiplier if m != null and m.emission_enabled else 0.0
	var body := e._mesh.find_child("Body", true, false) as MeshInstance3D
	var v = body.get_instance_shader_parameter(&"flash")
	return float(v) if v != null else 0.0

## 플래시 색 (개미는 instance uniform, 구체는 emission).
func _col_of(e) -> Color:
	var blob := e._mesh as MeshInstance3D
	if blob != null:
		var m := blob.material_override as StandardMaterial3D
		return m.emission if m != null else Color.BLACK
	var body := e._mesh.find_child("Body", true, false) as MeshInstance3D
	var c = body.get_instance_shader_parameter(&"flash_col")
	return Color(c) if c != null else Color.BLACK

func _run() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await process_frame
	await process_frame
	var hs = _main.get_node("HammerStrike")
	hs.has_fire = true
	_main.set_physics_process(false)

	# 개미 3마리: 두 마리는 폭연 반경 안, 한 마리는 멀리
	var near_a = _spawn(&"grunt", Vector3(0.5, 0, 0))
	var near_b = _spawn(&"grunt", Vector3(-0.6, 0, 0.4))
	var far = _spawn(&"grunt", Vector3(20, 0, 20))
	# 구체 placeholder 도 한 마리 (StandardMaterial3D 경로)
	var blob_near = _spawn(&"heavy", Vector3(0.9, 0, -0.5))
	var blob_far = _spawn(&"heavy", Vector3(24, 0, 20))
	await process_frame

	print("플래시 전:  가까운개미 %.2f / 먼개미 %.2f / 가까운구체 %.2f / 먼구체 %.2f" % [
		_burn_of(near_a), _burn_of(far), _burn_of(blob_near), _burn_of(blob_far)])

	# 원점에서 폭연 하나를 직접 터뜨린다 (반경 1.8)
	Deflagration.detonate(hs, Vector3.ZERO, 1.8, 20.0, 4.0, 0)
	await create_timer(Deflagration.DELAY + 0.06).timeout

	print("터진 직후: 가까운개미 %.2f / 먼개미 %.2f / 가까운구체 %.2f / 먼구체 %.2f" % [
		_burn_of(near_a), _burn_of(far), _burn_of(blob_near), _burn_of(blob_far)])
	print("           (기대: 가까운 둘 > 0,  먼 둘 = 0)")
	print("           둘째 개미도 함께 번쩍임: %.2f (개체별이면 near_a 와 무관하게 > 0)" % [
		_burn_of(near_b)])

	await create_timer(0.30).timeout
	print("0.36s 뒤:  가까운개미 %.2f / 가까운구체 %.2f  (기대 0 으로 식음)" % [
		_burn_of(near_a), _burn_of(blob_near)])

	# 공유 머티리얼 오염 검사: 먼 개미의 머티리얼이 near 와 같은 리소스인지
	var m_near := (near_a._mesh.find_child("Body", true, false) as MeshInstance3D) \
		.get_surface_override_material(0)
	var m_far := (far._mesh.find_child("Body", true, false) as MeshInstance3D) \
		.get_surface_override_material(0)
	print("")
	print("개미 머티리얼이 공유 리소스인가: %s (기대 true — 사본을 안 만들어 배칭이 산다)" % [
		m_near == m_far])
	print("그래도 먼 개미는 안 번쩍였다 -> instance uniform 이 개체별로 동작한 것")

	# --- 색 구분: 불(주홍) vs 바위(흰색) ---
	print("")
	var a = _spawn(&"grunt", Vector3(50, 0, 50))
	var b = _spawn(&"grunt", Vector3(52, 0, 50))
	var blob_a = _spawn(&"heavy", Vector3(54, 0, 50))
	await process_frame
	a.flash_burn()
	b.flash_hit()
	blob_a.flash_hit()
	await process_frame
	print("불 맞은 개미 색 %s (기대 %s)" % [
		_col_of(a).to_html(false), Enemy.FLASH_BURN.to_html(false)])
	print("바위 맞은 개미 색 %s (기대 %s)" % [
		_col_of(b).to_html(false), Enemy.FLASH_HIT.to_html(false)])
	print("바위 맞은 구체 색 %s (기대 %s)" % [
		_col_of(blob_a).to_html(false), Enemy.FLASH_HIT.to_html(false)])
	quit()
