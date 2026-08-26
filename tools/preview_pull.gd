extends Node3D
## 인력(끌어당김) 셰이더만 위에서 내려다보고 프레임을 뽑는 미리보기. 게임과 무관하다.
## 실행: Godot --path . tools/preview_pull.tscn -- <출력폴더>

const RADIUS := 9.6       # 평타 기준: 기본 반경 4.0 * pull_spread 2.4
const FRAMES := 10

func _ready() -> void:
	var outdir := "res://"
	var uargs := OS.get_cmdline_user_args()
	if uargs.size() > 0:
		outdir = uargs[0]
	# ⚠️ 카메라는 **코드로** 만든다. .tscn 의 Transform3D 리터럴은 행 우선이라
	#    직교 카메라를 손으로 적으면 전치돼서 하늘을 보고 있게 된다 (2026-08-18 실제로 밟음).
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 22.0
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#63c74d")   # 게임 잔디색 위에서 봐야 실제 대비가 나온다
	# 게임과 같은 블룸 — 앞머리 심지가 1 을 넘기게 만들어 놨으니 여기서도 켜야 같은 그림이 나온다
	env.glow_enabled = not ("NOGLOW" in OS.get_cmdline_user_args())
	env.glow_intensity = 0.9
	env.glow_hdr_threshold = 1.1
	cam.environment = env
	add_child(cam)
	cam.global_position = Vector3(0, 20, 0)
	cam.look_at(Vector3.ZERO, Vector3.FORWARD)
	cam.make_current()

	var mesh := MeshInstance3D.new()
	mesh.mesh = _disc(RADIUS)
	var mat := ShaderMaterial.new()
	# MAGNET 를 주면 새 쌍극자 자기장 셰이더로 뽑는다 (인력 v2 테스트).
	mat.shader = load("res://shaders/magnet.gdshader") \
		if "MAGNET" in OS.get_cmdline_user_args() \
		else load("res://shaders/pull.gdshader")
	mat.set_shader_parameter("seed", 3.0)
	# 색 후보 비교용 — CORE=#2ce8f5 GLOW=#0099db 처럼 넘긴다.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("CORE="):
			mat.set_shader_parameter("line_col", Color(a.substr(5)))
		elif a.begins_with("BOOST="):
			mat.set_shader_parameter("boost", a.substr(6).to_float())
		elif a.begins_with("GLOW="):
			mat.set_shader_parameter("glow_col", Color(a.substr(5)))
	# VORTEX 를 주면 조합(충격파+인력) 색·감김으로 뽑는다 — hammer_strike._pull_vfx 와 같은 값.
	if "VORTEX" in OS.get_cmdline_user_args():
		mat.set_shader_parameter("swirl", 0.62)
		mat.set_shader_parameter("boost", 1.3)
		mat.set_shader_parameter("core_col", Color(0.992, 0.820, 0.475))
		mat.set_shader_parameter("body_col", Color(0.173, 0.910, 0.961))
		mat.set_shader_parameter("tail_col", Color(0.922, 0.588, 0.380))
	mesh.material_override = mat
	add_child(mesh)

	await RenderingServer.frame_post_draw
	for i in FRAMES:
		var t := (float(i) + 0.5) / float(FRAMES)
		mat.set_shader_parameter("t", t)
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/pull_%02d.png" % [outdir, i])
		print("[preview] t=%.2f -> pull_%02d.png" % [t, i])
	get_tree().quit()

## 미리보기는 평지 기준 — 지형 추종은 게임 쪽 _shockwave_mesh 가 한다.
func _disc(radius: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var seg := 48
	var rings := 10
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
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
