class_name PropModels
extends Object

## 풀숲 프롭 모델 로더 (블렌더 → Godot, 2026-08-17).
##
## `assets/models/props/*.glb` 는 **Body / Outline 두 노드**로 구워져 있다 (개미·망치와 같은 규약).
##   Body    — 셀 셰이딩 대상. 서피스마다 블렌더 머티리얼 이름이 붙어 있다.
##   Outline — Solidify 역헐(먹선). 이미 뒤집힌 와인딩이라 기본 cull_back 으로 그대로 동작하고,
##             **그림자를 꺼야 한다** (역헐이 본체에 그림자를 드리워 새까매진다).
##
## 여기서 하는 일은 하나다: **머티리얼 이름 → 셀 톤 매핑.**
## ⚠️ 색을 glb 에서 읽어오지 않는다. 블렌더 머티리얼은 미리보기용이고, 게임 화면의 색은
##    `cel.gdshader` 가 확정한다. 이름만 계약으로 삼고 톤은 여기 표에서 준다 —
##    그래야 게임 안에서 색을 고칠 때 블렌더를 다시 열지 않아도 된다.
## ⚠️ 블렌더 쪽 문턱(threshold)과 **같은 값**을 쓴다. 양쪽 다 순수 N·L 기준이라 그대로 옮겨진다
##    (블렌더 셀 노드를 Shader to RGB 대신 노멀·태양 내적으로 짠 이유가 이것이다).

const DIR := "res://assets/models/props/"

## 블렌더 머티리얼 이름 → (밝은 톤, 그림자 톤, 문턱). props_build.py 의 팔레트와 같은 값.
const TONES := {
	&"Cel_Leaf":    ["#3e8948", "#193c3e", 0.50],
	&"Cel_Bark":    ["#734c44", "#3e2731", 0.45],
	&"Cel_BarkCut": ["#c28569", "#734c44", 0.45],
	&"Cel_Stone":   ["#87857c", "#405273", 0.45],
	&"Cel_StoneW":  ["#bcad9f", "#6c81a1", 0.45],
}
const INK_COL := Color("#14233a")

static var _cache := {}
static var _cel_shader: Shader
static var _ink_mat: StandardMaterial3D

## 프롭 하나를 읽어 {body = Mesh, outline = Mesh} 로 돌려준다. 없으면 빈 사전.
static func get_model(id: StringName) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var path := "%s%s.glb" % [DIR, id]
	var packed := load(path) as PackedScene
	var out := {}
	if packed != null:
		var root := packed.instantiate()
		for child in root.get_children():
			var mi := child as MeshInstance3D
			if mi == null:
				continue
			if mi.name.begins_with("Outline"):
				out["outline"] = _paint_ink(mi.mesh)
			else:
				out["body"] = _paint_cel(mi.mesh)
		root.queue_free()
	if out.is_empty():
		push_warning("[props] 모델을 못 읽었다: %s" % path)
	_cache[id] = out
	return out

## 서피스마다 블렌더 머티리얼 **이름**을 보고 셀 머티리얼을 꽂는다.
## ⚠️ `material_override` 를 쓰면 안 된다 — 나무는 껍질+잎 두 서피스라 한 장으로 덮으면
##    기둥까지 초록이 된다. 메시의 서피스 머티리얼로 넣어야 MultiMesh 에서도 따로 칠해진다.
static func _paint_cel(mesh: Mesh) -> Mesh:
	if _cel_shader == null:
		_cel_shader = load("res://shaders/cel.gdshader")
	for i in mesh.get_surface_count():
		var src := mesh.surface_get_material(i)
		var key := StringName(src.resource_name if src != null else "")
		var tone: Array = TONES.get(key, TONES[&"Cel_Stone"])
		if not TONES.has(key):
			push_warning("[props] 모르는 머티리얼 이름 '%s' — 돌 톤으로 대체" % key)
		var mat := ShaderMaterial.new()
		mat.shader = _cel_shader
		mat.set_shader_parameter("light_tone", Color(tone[0]))
		mat.set_shader_parameter("dark_tone", Color(tone[1]))
		mat.set_shader_parameter("threshold", tone[2])
		mesh.surface_set_material(i, mat)
	return mesh

static func _paint_ink(mesh: Mesh) -> Mesh:
	if _ink_mat == null:
		_ink_mat = StandardMaterial3D.new()
		_ink_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ink_mat.albedo_color = INK_COL
	for i in mesh.get_surface_count():
		mesh.surface_set_material(i, _ink_mat)
	return mesh
