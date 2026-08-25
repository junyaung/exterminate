extends Node3D
## 분출 도넛 판정 범위 표시를 위에서 내려다보고 한 장 찍는다. 게임과 무관한 미리보기.
## 실행: Godot --path . tools/preview_erupt_area.tscn -- <출력폴더>

const FIELD := 6.0      # 판 반경 (거대화면 12.0)

func _ready() -> void:
	var uargs := OS.get_cmdline_user_args()
	var outdir: String = uargs[0] if uargs.size() > 0 else "res://"
	var giant := "GIANT" in uargs
	var field := FIELD * (2.0 if giant else 1.0)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 30.0
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#63c74d")
	cam.environment = env
	add_child(cam)
	cam.global_position = Vector3(0, 20, 0)
	cam.look_at(Vector3.ZERO, Vector3.FORWARD)
	cam.make_current()

	var mi := MeshInstance3D.new()
	mi.mesh = _disc(field * 1.05)          # ERUPT_FAR
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/debug_ring.gdshader")
	m.set_shader_parameter("inner", 0.3 / 1.05)   # ERUPT_NEAR / ERUPT_FAR
	m.set_shader_parameter("alpha_mul", 1.0)
	mi.material_override = m
	add_child(mi)

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		"%s/erupt_area_%s.png" % [outdir, "giant" if giant else "base"])
	print("[preview] 판 반경 %.1f / 도넛 %.2f ~ %.2f" % [field, field * 0.3, field * 1.05])
	get_tree().quit()

func _disc(radius: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var seg := 64
	var rings := 12
	for ri in rings + 1:
		var fr := float(ri) / float(rings)
		for si in seg + 1:
			var fa := float(si) / float(seg)
			var ang := fa * TAU
			verts.append(Vector3(cos(ang) * fr * radius, 0.0, sin(ang) * fr * radius))
			uvs.append(Vector2(fr, fa))
	for ri in rings:
		for si in seg:
			var a := ri * (seg + 1) + si
			var b := a + seg + 1
			idx.append_array([a, b, a + 1, a + 1, b, b + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mm := ArrayMesh.new()
	mm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mm
