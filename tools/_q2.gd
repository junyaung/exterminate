extends SceneTree
func _init() -> void:
	_r()
func _r() -> void:
	var m: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var g := m.get_node("Ground") as Ground
	var mo := g.material_override
	if mo is ShaderMaterial:
		print("Q 셰이더=", (mo as ShaderMaterial).shader.resource_path.get_file(),
			" 색=", (mo as ShaderMaterial).get_shader_parameter("col"),
			" 지면그림자=", g.cast_shadow)
	else:
		print("Q 머티리얼 종류가 다르다: ", mo)
	quit()
