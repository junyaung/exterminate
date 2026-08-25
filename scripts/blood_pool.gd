class_name BloodPool
extends Node3D

## 보스 일반 사망 때 시체에서 흘러나오는 보라색 액체 웅덩이 (유저 스펙, 2026-08-13).
## 배색은 nice31 보라 두 단계뿐: 밝은 면 #7a5859 / 어두운 면·테두리 #593e47.
## 검은 먹선은 유저 지시로 뺐다 — 테두리 밑판도 어두운 **보라**라서, 외곽선이 아니라
## 액체 가장자리에 고인 음영으로 읽힌다. 셀 2톤(그늘쪽 초승달)과 같은 색이라 톤이 하나로 묶인다.
##
## ⚠️ **바닥 데칼의 감는 방향**: Godot 은 카메라에서 봤을 때 시계방향인 면을 앞면으로 친다.
## 즉 위에서 내려다보이는 바닥 면은 **오른손 법칙 노멀이 아래(-Y)** 를 향하도록 감아야 한다
## (aftershock_fx 의 균열 쿼드와 같은 규약). 반대로 감으면 컬링돼서 **아무것도 안 보인다** —
## 실제로 첫 판이 그래서 화면에 안 나왔다. 셰이딩 노멀은 감는 방향과 따로 명시한다.
##
## ⚠️ **평평한 판에는 셀 셰이딩이 안 걸린다**: 노멀이 전부 위라 N·L 이 한 값(햇빛 고도 50° →
## 0.766)이라서 어느 threshold 를 줘도 전부 밝은 톤 아니면 전부 어두운 톤이다. 그래서
## **고원 + 급한 가장자리** 단면으로 만든다 — 평평한 윗면은 밝은 톤, 23° 기울어진 테두리 링은
## 해 반대쪽만 어두운 톤으로 떨어져서 초승달 모양 그림자가 생긴다. 이게 셀 룩의 2톤이다.

const GROW := 0.9
const HOLD := 2.0
const FADE := 0.6

const SEGMENTS := 18
const PLATEAU := 0.80        ## 평평한 윗면의 반경 비율. 나머지가 기울어진 테두리 링.
const TOP_Y := 0.55          ## 윗면 높이 — 기울기가 셀 경계를 만든다 (23°)
const RIM_Y := 0.05          ## 가장자리 높이 (지면 z-fight 방지)
const INK_Y := 0.02          ## 음영 밑판은 웅덩이보다 낮게
const INK_GROW := 1.07       ## 음영이 삐져나오는 비율 — 가장자리에 어두운 보라 띠가 된다

const COL_LIGHT := Color(0.478, 0.345, 0.349)   # nice31 #7a5859
const COL_DARK := Color(0.349, 0.243, 0.278)    # nice31 #593e47
## 수면 반사 하이라이트. 액체의 "빛 반사"는 물리 스페큘러가 아니라 **그려 넣는 조각**이다 —
## 수면은 평평해서 노멀이 한 방향이라 진짜 스페큘러는 전체가 한 번에 켜지거나 꺼진다.
## 해 쪽 가장자리 근처에 길쭉한 밝은 조각 몇 개 = 카툰 액체 문법.
const COL_GLINT := Color(0.835, 0.839, 0.859)   # nice31 #d5d6db — 순백 아래 한 단계
## 햇빛 고도 50° → 평평한 윗면의 N·L = 0.766. 그 아래이면서 기운 테두리(sin(50-23)=0.45)
## 위인 값이어야 "윗면 밝음 + 그늘쪽 테두리 어두움"이 된다.
const CEL_THRESHOLD := 0.6

const CelShader := preload("res://shaders/cel.gdshader")
const FadeShader := preload("res://shaders/cel_fade.gdshader")

var _pool: MeshInstance3D
var _rim: MeshInstance3D
var _rim_mat: StandardMaterial3D
var _fade_mat: ShaderMaterial
var _glints: Array[MeshInstance3D] = []
var _glint_mats: Array[StandardMaterial3D] = []


static func spawn(parent: Node, at: Vector3, radius: float) -> BloodPool:
	var p := BloodPool.new()
	parent.add_child(p)
	p.global_position = Terrain.on(at)
	p._build(radius)
	p._run()
	return p


func _build(radius: float) -> void:
	# 울퉁불퉁한 윤곽 — 매끈한 원은 물/마법처럼 보인다 (균열에서 확립한 규칙)
	var radii: Array[float] = []
	for i in SEGMENTS:
		radii.append(radius * randf_range(0.78, 1.05))

	_pool = MeshInstance3D.new()
	_pool.mesh = _pool_mesh(radii, TOP_Y, RIM_Y)
	var cel := ShaderMaterial.new()
	cel.shader = CelShader
	cel.set_shader_parameter("light_tone", COL_LIGHT)
	cel.set_shader_parameter("dark_tone", COL_DARK)
	cel.set_shader_parameter("threshold", CEL_THRESHOLD)
	_pool.set_surface_override_material(0, cel)
	_pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pool)

	# 음영 테두리: 같은 윤곽을 납작하게, 조금 크게, 웅덩이보다 낮게.
	# 검은 먹선이 아니라 셀 어두운 톤과 같은 보라 — "가장자리에 고인 그늘"이다.
	_rim = MeshInstance3D.new()
	_rim.mesh = _pool_mesh(radii, INK_Y, INK_Y)
	_rim.scale = Vector3(INK_GROW, 1.0, INK_GROW)
	_rim_mat = StandardMaterial3D.new()
	_rim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rim_mat.albedo_color = COL_DARK                 # nice31 #593e47
	_rim.set_surface_override_material(0, _rim_mat)
	_rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rim)

	_build_glints(radius)


## 수면 반사 조각들 — 해가 있는 쪽 가장자리 근처에, 테두리와 나란한 길쭉한 블롭 2~3개.
## 해 방향은 씬의 Sun 에서 읽는다 (해를 옮기면 반사도 따라 옮겨지도록).
func _build_glints(radius: float) -> void:
	var toward_sun := Vector3(0.64, 0.0, -0.07)      # main.tscn Sun 기준 폴백
	var sun := get_tree().root.find_child("Sun", true, false) as DirectionalLight3D
	if sun != null:
		toward_sun = sun.global_basis.z              # 표면 -> 광원
	toward_sun.y = 0.0
	toward_sun = toward_sun.normalized() if toward_sun.length() > 0.01 else Vector3.RIGHT
	var yaw := atan2(toward_sun.x, toward_sun.z)
	for i in randi_range(2, 3):
		var mi := MeshInstance3D.new()
		mi.mesh = _glint_mesh()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = COL_GLINT
		mi.set_surface_override_material(0, m)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		# 해 쪽으로 40~65% 지점, 테두리와 나란히(진행 방향에 수직으로 길게)
		var side := Vector3(toward_sun.z, 0.0, -toward_sun.x)
		var pos := toward_sun * radius * randf_range(0.40, 0.65) \
			+ side * radius * randf_range(-0.35, 0.35)
		mi.position = Vector3(pos.x, TOP_Y + 0.02, pos.z)
		mi.rotation.y = yaw + randf_range(-0.25, 0.25)
		mi.scale = Vector3(radius * randf_range(0.10, 0.16), 1.0,
			radius * randf_range(0.30, 0.55))
		_glints.append(mi)
		_glint_mats.append(m)


## 길쭉한 반사 블롭 (단위 크기 — 노드 scale 로 늘인다). 감는 방향은 웅덩이 윗면과 같은 규약.
func _glint_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = []
	var n := 10
	for i in n:
		var a := TAU * float(i) / n
		var r := randf_range(0.8, 1.05)
		pts.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
	var center := Vector3.ZERO
	for i in n:
		_tri(st, center, pts[i], pts[(i + 1) % n])
	return st.commit()


## 고원 + 기운 테두리 단면의 원반. top_y == rim_y 면 그냥 납작한 판(먹선용).
func _pool_mesh(radii: Array[float], top_y: float, rim_y: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(0.0, top_y, 0.0)
	var inner: Array[Vector3] = []
	var outer: Array[Vector3] = []
	for i in SEGMENTS:
		var a := TAU * float(i) / SEGMENTS
		var c := Vector2(cos(a), sin(a))
		inner.append(Vector3(c.x * radii[i] * PLATEAU, top_y, c.y * radii[i] * PLATEAU))
		outer.append(Vector3(c.x * radii[i], rim_y, c.y * radii[i]))
	for i in SEGMENTS:
		var j := (i + 1) % SEGMENTS
		# 윗면 부채꼴. 순서 (center, inner[i], inner[j]) 가 위에서 앞면.
		_tri(st, center, inner[i], inner[j])
		# 기운 테두리 두 장
		_tri(st, inner[i], outer[i], outer[j])
		_tri(st, inner[i], outer[j], inner[j])
	return st.commit()


## 삼각형 하나. 감는 방향은 그대로 두고, **셰이딩 노멀은 위를 향하도록 뒤집어** 넣는다
## (오른손 법칙 노멀이 -Y 인 게 앞면이므로, 그걸 그대로 쓰면 빛을 등져 새까매진다).
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := -(b - a).cross(c - a).normalized()
	for v in [a, b, c]:
		st.set_normal(n)
		st.add_vertex(v)


func _run() -> void:
	# 액체가 흘러나와 퍼진다 — 감속하며 (액체는 처음에 빠르고 끝에 느리다)
	scale = Vector3(0.12, 1.0, 0.12)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE, GROW) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(HOLD)
	tw.tween_callback(_begin_fade)
	tw.tween_interval(FADE)
	tw.tween_callback(queue_free)


func _begin_fade() -> void:
	_fade_mat = ShaderMaterial.new()
	_fade_mat.shader = FadeShader
	_fade_mat.set_shader_parameter("light_tone", COL_LIGHT)
	_fade_mat.set_shader_parameter("dark_tone", COL_DARK)
	_fade_mat.set_shader_parameter("threshold", CEL_THRESHOLD)
	_fade_mat.set_shader_parameter("alpha_mul", 1.0)
	_pool.set_surface_override_material(0, _fade_mat)
	_rim_mat = _rim_mat.duplicate()
	_rim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rim.set_surface_override_material(0, _rim_mat)
	for i in _glints.size():
		var gm := _glint_mats[i].duplicate() as StandardMaterial3D
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glints[i].set_surface_override_material(0, gm)
		_glint_mats[i] = gm
	var tw := create_tween()
	tw.tween_method(func(a: float) -> void:
		_fade_mat.set_shader_parameter("alpha_mul", a)
		_rim_mat.albedo_color.a = a
		for gm in _glint_mats:
			gm.albedo_color.a = a, 1.0, 0.0, FADE)
