extends SceneTree
func _init() -> void:
	_r()
func _r() -> void:
	var m: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var g := m.get_node("Ground") as Ground
	var mo := g.material_override as ShaderMaterial
	var shade = mo.get_shader_parameter("shade")
	print("A 지면 셰이더 %s / 색 %s / 그늘밝기 %s" % [
		mo.shader.resource_path.get_file(), mo.get_shader_parameter("col"), shade])
	print("B 지면 그림자캐스팅 %d (평지=0) / 성 캐스팅 %d" % [
		g.cast_shadow, (m.get_node("BaseBlock/Mesh") as MeshInstance3D).cast_shadow])
	var sun := m.get_node("Sun") as DirectionalLight3D
	print("C 태양 그림자 %s / 최대거리 %.0f / 에너지 %.2f" % [
		sun.shadow_enabled, sun.directional_shadow_max_distance, sun.light_energy])
	quit()
