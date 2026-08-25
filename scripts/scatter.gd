class_name Scatter
extends Node3D

## 전장 **바깥**을 채우는 지형 프롭 배치기.
##
## 컨셉(유저 지시 2026-08-16): **벌레들의 세계라 미시적으로 간다.**
## 숲을 그리는 게 아니라 **낙엽 밑 바닥**을 그린다 — 나무는 밑동만 화면 가장자리에 한두 그루
## 걸리고, 화면을 채우는 건 떨어진 나뭇가지·마른 잎사귀·돌멩이·자갈·풀포기다.
## 스케일 기준자: 개미 몸길이 **1.34**, 콩벌레 **1.87**, 성 5×5 유닛.
##
## 왜 고돗에서 배치하나 — 배치는 제일 자주 바뀌는 값이다. 블렌더에서 배치까지 구워 오면
## 잎사귀 하나 옮길 때마다 익스포트를 다시 해야 한다. **모델은 블렌더, 배치는 여기.**
## 지금 프롭은 전부 **임시 도형**이다. 밀도와 구도를 눈으로 잡은 뒤 블렌더 모델로 갈아끼운다 —
## `_build_parts()` 의 메시만 바꾸면 나머지(배치·제외·MultiMesh)는 그대로 쓴다.
## ⚠️ 진짜 모델은 Body/Outline 2노드 규약이라 **먹선 껍질도 같은 transform 으로 한 벌 더**
##    MultiMesh 를 깔아야 한다 (`_add_part` 를 한 번 더 부르면 된다).
##
## 배치 규칙: 시드 고정 난수 + **거절 샘플링**. 아래 세 가지를 피한다.
##   1) 기지 주변 원 — 성이 가려지면 안 된다
##   2) 스폰 존 — 프롭 사이에서 적이 튀어나오면 어디서 나왔는지 못 읽는다
##   3) 스폰 존 -> 기지 **행군 통로** — 적이 나뭇가지를 뚫고 걸어오면 안 된다
##
## 개발 키: `,` `.` 밀도 / `M` 시드 바꾸기 / `N` 제외 영역 보기

const SEED := 20260816
## 지금 보고 있는 맵을 그대로 다시 쓰기 위한 저장 파일 (유저 요청 2026-08-17:
## "지금 시드 저장해줘, 임시적으로 이 맵을 쓰고싶어").
## ⚠️ **시드만으로는 부족하다** — 같은 시드라도 밀도가 다르면 뽑는 개수가 달라져 배치가 통째로
##    바뀐다. 시드와 밀도를 **같이** 저장해야 그 화면이 재현된다.
## 지형 편집(res://layout/terrain_edit.json)과 같은 규약으로 프로젝트 폴더에 남긴다.
const SAVE_PATH := "res://layout/scatter_map.json"

## 배치 후보를 뽑는 화면 기준 범위. 카메라 세로 폭 75.5, 피치 -50 기준으로
## 실제로 보이는 지면은 가로 ±67 / 세로 ±49 이고, 화면 밖으로 조금 더 깔아
## 프레임 가장자리에서 뚝 끊기지 않게 한다.
const AREA_X := 84.0
const AREA_Z := 62.0

## 기지 반경 — 성과 그 앞마당은 비워둔다.
const BASE_KEEP := 26.0
## 행군 통로 반폭. 적은 스폰 존에서 기지로 **직선으로** 오므로 그 띠를 비운다.
const LANE_HALF := 16.0
## 스폰 존 바깥으로 더 비워둘 여유.
const ZONE_PAD := 8.0
## `edge` 프롭이 놓일 수 있는 바깥 테두리 (중심에서 이 비율 밖).
const EDGE_BAND := 0.62

## 후보를 몇 번까지 다시 뽑아볼 것인가. 제외 영역이 넓어 실패가 잦으므로 넉넉히.
const TRIES_PER_PROP := 60

## 프롭 종류 — 벌레 눈높이로 짠 표.
##   count    밀도 1.0 기준 개수 (cluster 가 있으면 '덩어리' 개수)
##   gap      같은 종류끼리 최소 간격
##   scale    크기 랜덤 범위
##   pad      제외 영역을 이만큼 더 넓게 본다 (덩치 큰 프롭용)
##   edge     화면 가장자리에만 놓는다
##   flat     바닥에 눕는 것 — 기울기 흔들림을 크게 준다 (누운 가지·잎사귀)
##   walk     **밟고 지나갈 수 있는 것** — 잎·자갈처럼 벌레 발밑에 깔리는 높이라
##            행군 통로·스폰 존 위에 놓아도 된다. 이게 없으면 통로가 화면을 다 먹어서
##            정작 전장 한복판이 맨바닥으로 남는다 (레이아웃 템플릿을 그려보고 알았다).
##            기지 자리만은 여전히 피한다.
##   cluster  한 자리에 이만큼 뭉쳐 놓는다 Vector2(최소, 최대) / cluster_r = 흩어지는 반경
const PROPS: Array[Dictionary] = [
	# ⚠️ 2026-08-17: 임시 도형을 **블렌더 실제 모델**로 전부 교체했다 (assets/models/props/*.glb).
	#    크기는 성(5×4×5) 기준으로 유저가 정한 값이라 여기 개수·간격은 그 크기에 맞춰 다시 잡았다 —
	#    예전 표는 자갈 0.6 짜리 미시 스케일 기준이라 그대로 두면 화면이 프롭으로 덮인다.
	# 나무 — 높이 **76.4** / 폭 43 (성의 15배, 유저 지시 2026-08-17 "3배"). 가장자리에만.
	# ⚠️ 간격·여백을 폭에 맞춰 같이 키웠다 — 38 짜리 간격에 폭 43 을 놓으면 나무끼리 겹쳐 심긴다.
	{id = &"tree", count = 4, gap = 70.0, scale = Vector2(0.8, 1.25), pad = 30.0, edge = true},
	# 나무 밑동 — 28.3. 벌레 기준 벽이라 통로에서 멀찍이.
	{id = &"stump", count = 3, gap = 45.0, scale = Vector2(0.8, 1.2), pad = 14.0},
	# 바위 — 10.3.
	{id = &"boulder", count = 5, gap = 22.0, scale = Vector2(0.8, 1.25), pad = 5.0},
	# 큰 돌 — 10.7.
	{id = &"stone_l", count = 7, gap = 17.0, scale = Vector2(0.8, 1.2)},
	# 중간 돌 — 7.0.
	{id = &"stone_m", count = 12, gap = 12.0, scale = Vector2(0.7, 1.3)},
	# 작은 돌 — 4.6. 무리로 흩어 놓아야 자갈밭처럼 읽힌다.
	{id = &"stone_s", count = 14, gap = 9.0, scale = Vector2(0.7, 1.3),
		cluster = Vector2(2, 4), cluster_r = 6.0},
	# 나뭇가지 — 8.5. 누워 있어야 '떨어진 가지'다.
	{id = &"branch", count = 9, gap = 16.0, scale = Vector2(0.7, 1.3), flat = true},
	# 낙엽 — 10.1. 바닥에 깔리므로 통로·스폰존 위에 있어도 된다(walk).
	# ⚠️ **개수를 80~90% 줄였다** (유저 지시 2026-08-18, 스크린샷: 화면이 잎으로 덮였다).
	#    잎 하나가 성(5)의 2배인 10 유닛이라, 다른 프롭과 같은 감각으로 개수를 잡으면
	#    바닥이 아니라 **잎 카펫**이 된다. 뭉치(cluster)도 2~5 -> 1~3 으로 같이 줄였다 —
	#    count 만 줄이면 뭉치가 그대로라 "드문드문 있는 큰 무더기"가 된다.
	{id = &"leaf", count = 6, gap = 10.0, scale = Vector2(0.7, 1.4), flat = true,
		walk = true, cluster = Vector2(1, 3), cluster_r = 9.0},
]

var density := 1.0
var seed_value := SEED
var _rng := RandomNumberGenerator.new()
var _placed: Array[Vector2] = []      ## 이미 놓은 자리 (화면 좌표)
## 그중 **밟고 지나갈 수 없는** 것만. 통로 침범 검증은 이쪽만 본다 —
## 잎·자갈은 통로 위에 있는 게 정상이라 같이 세면 매번 실패한다.
var _placed_tall: Array[Vector2] = []
var _overlay: Node3D
var _lanes: Array[Vector2] = []       ## 통로 끝점 (스폰 존 중심, 화면 좌표)
## 유저가 칠한 레이아웃 맵. 있으면 **칠한 프롭만** 그림을 따르고 나머지는 절차 생성 그대로다.
var layout := LayoutMap.new()

func _ready() -> void:
	load_map_seed()
	rebuild()
	print("[scatter] , . 밀도  M 시드  J 지금 맵 저장  N 제외영역")

func rebuild() -> void:
	layout.load_map()
	for c in get_children():
		c.queue_free()
	_overlay = null
	_placed.clear()
	_placed_tall.clear()
	_rng.seed = seed_value
	_lanes.clear()
	for z in Main.SPAWN_ZONES:
		var zone: Vector4 = z * Main.view_scale
		# ⚠️ 통로 끝점을 **존 중심 하나만** 잡으면 안 된다 — 적은 존 **아무 데서나** 태어나
		#    기지로 직선으로 오므로 실제 행군 경로는 부채꼴이다. 중심만 비우면 부챗살
		#    가장자리가 통로 밖으로 새서 그 위에 프롭·굴곡이 생긴다 (검증에서 걸렸다).
		#    네 모서리 + 중심을 끝점으로 두면 그 부채꼴 전체가 덮인다.
		_lanes.append(Vector2((zone.x + zone.y) * 0.5, (zone.z + zone.w) * 0.5))
		_lanes.append(Vector2(zone.x, zone.z))
		_lanes.append(Vector2(zone.x, zone.w))
		_lanes.append(Vector2(zone.y, zone.z))
		_lanes.append(Vector2(zone.y, zone.w))
	var report := ""
	for p in PROPS:
		report += " %s %d" % [p.id, _scatter_one(p)]
	print("[scatter] 밀도 %.2f / 시드 %d ->%s (총 %d)" % [
		density, seed_value, report, _placed.size()])

## 한 종류를 뿌린다. 놓은 개수를 돌려준다.
func _scatter_one(prop: Dictionary) -> int:
	# 그림에 이 프롭이 칠해져 있으면 **거기서만** 뽑는다. 개수는 칠한 넓이가 정한다 —
	# 점 하나 = 한 개, 넓게 칠하면 그만큼 채워진다.
	var painted: Array = layout.prop_spots(prop.id)
	var want := maxi(1, roundi(float(prop.count) * density))
	if not painted.is_empty():
		var area: float = float(painted.size()) / (LayoutMap.PX * LayoutMap.PX)
		want = maxi(1, roundi(area / (float(prop.gap) * float(prop.gap) * 0.75) * density))
	var spots: Array[Vector2] = []
	var angles: Array[float] = []
	var scales: Array[float] = []
	var tilts: Array[Vector2] = []
	var pad: float = prop.get("pad", 0.0)
	var edge: bool = prop.get("edge", false)
	var flat: bool = prop.get("flat", false)
	var walk: bool = prop.get("walk", false)
	var cluster: Vector2 = prop.get("cluster", Vector2.ZERO)
	var cluster_r: float = prop.get("cluster_r", 0.0)
	var gap: float = prop.gap
	var span: Vector2 = prop.scale
	# 눕는 것은 기울기를 크게 흔든다 — 잎사귀가 전부 수평이면 인쇄물처럼 보인다.
	var tilt_max := 0.22 if flat else 0.09
	for i in want:
		for t in TRIES_PER_PROP:
			var p: Vector2 = painted[_rng.randi() % painted.size()] if not painted.is_empty() \
				else _sample(edge)
			if _blocked(p, pad, walk) or _too_close(p, gap):
				continue
			var n := 1
			if cluster != Vector2.ZERO:
				n = _rng.randi_range(int(cluster.x), int(cluster.y))
			for k in n:
				var q := p
				if k > 0:
					q = p + Vector2(_rng.randf_range(-cluster_r, cluster_r),
						_rng.randf_range(-cluster_r, cluster_r))
					# 덩어리 안에서는 간격을 훨씬 좁게 본다 — 안 그러면 뭉치지를 못한다.
					if _blocked(q, pad, walk) or _too_close(q, cluster_r * 0.55):
						continue
				spots.append(q)
				_placed.append(q)
				if not walk:
					_placed_tall.append(q)
				angles.append(_rng.randf_range(0.0, TAU))
				scales.append(_rng.randf_range(span.x, span.y))
				tilts.append(Vector2(_rng.randf_range(-tilt_max, tilt_max),
					_rng.randf_range(-tilt_max, tilt_max)))
			break
	if spots.is_empty():
		return 0
	for part in _build_parts(prop.id):
		_add_part(prop.id, part, spots, angles, scales, tilts)
	return spots.size()

## 후보 한 점. edge 면 화면 바깥 테두리에서만 뽑는다.
func _sample(edge: bool) -> Vector2:
	var p := Vector2(_rng.randf_range(-AREA_X, AREA_X), _rng.randf_range(-AREA_Z, AREA_Z))
	if not edge:
		return p
	# 테두리 밖으로 밀어낸다 — 다시 뽑는 것보다 실패가 적다.
	if absf(p.x) < AREA_X * EDGE_BAND and absf(p.y) < AREA_Z * EDGE_BAND:
		if _rng.randf() < 0.5:
			p.x = AREA_X * EDGE_BAND * signf(p.x if p.x != 0.0 else 1.0) \
				+ p.x * (1.0 - EDGE_BAND)
		else:
			p.y = AREA_Z * EDGE_BAND * signf(p.y if p.y != 0.0 else 1.0) \
				+ p.y * (1.0 - EDGE_BAND)
	return p

## 프롭 하나가 몇 개의 메시로 이루어지는가. 각 파트가 MultiMesh 한 벌이 된다.
## y = 지면에서 띄울 높이(프롭 크기에 같이 곱해진다).
## ⚠️ 크기는 전부 **벌레 몸길이(개미 1.34)** 를 자로 재서 잡은 값이다. 숫자를 만질 땐
##    "개미 몇 마리 길이인가"로 생각할 것 — 유닛 감각으로 잡으면 금세 거인 세계가 된다.
func _build_parts(id: StringName) -> Array[Dictionary]:
	## 실제 모델을 Body / Outline 두 파트로 돌려준다 (`scripts/prop_models.gd`).
	## ⚠️ 원점이 **바닥 중심**이라 y 보정이 필요 없다 — 블렌더에서 그렇게 구웠다.
	## ⚠️ 먹선(Outline)은 **같은 transform 으로 한 벌 더** 깔아야 한다. MultiMesh 는 노드 하나에
	##    메시 하나라, 2노드 규약 모델은 파트를 둘로 나눠 같은 자리에 겹쳐 깐다.
	var model: Dictionary = PropModels.get_model(id)
	var parts: Array[Dictionary] = []
	if model.has("body"):
		parts.append({mesh = model.body, y = 0.0, model = true, shadow = true})
	if model.has("outline"):
		# 역헐은 그림자를 끈다 — 켜두면 본체에 자기 그림자를 드리워 새까매진다.
		parts.append({mesh = model.outline, y = 0.0, model = true, shadow = false})
	return parts

## 파트 하나를 MultiMesh 로 굽는다. 수백 개가 드로우콜 하나로 나간다.
func _add_part(id: StringName, part: Dictionary, spots: Array[Vector2],
		angles: Array[float], scales: Array[float], tilts: Array[Vector2]) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = part.mesh
	mm.instance_count = spots.size()
	var off: Vector3 = part.get("off", Vector3.ZERO)
	var extra_yaw: float = part.get("yaw", 0.0)
	for i in spots.size():
		var s: float = scales[i]
		var yaw: float = angles[i] + extra_yaw
		var t: Vector2 = tilts[i]
		# 기울임은 요 회전 **뒤에** 곱한다 — 먼저 곱하면 프롭마다 기우는 방향이 같아진다.
		var b := Basis(Vector3.UP, yaw) * Basis.from_euler(Vector3(t.x, 0.0, t.y))
		var pos := Main.to_world(spots[i].x, spots[i].y) + (Basis(Vector3.UP, yaw) * off) * s
		# 지면에 굴곡이 있으므로 **그 자리 높이를 물어서** 앉힌다. 안 물으면 두둑 위 프롭이
		# 땅에 반쯤 묻히고 팬 자리 프롭은 공중에 뜬다.
		pos.y = _ground_y(pos) + float(part.y) * s
		mm.set_instance_transform(i, Transform3D(b.scaled(Vector3.ONE * s), pos))
	var mi := MultiMeshInstance3D.new()
	mi.name = "%s_%d" % [id, get_child_count()]
	mi.multimesh = mm
	if part.get("model", false):
		# ⚠️ 실제 모델은 **material_override 를 쓰면 안 된다.** 나무는 껍질+잎 두 서피스라
		#    한 장으로 덮으면 기둥까지 초록이 된다. 색은 PropModels 가 서피스별로 이미 꽂았다.
		mi.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if part.get("shadow", true) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	else:
		# (임시 도형용 경로 — 셀 머티리얼 한 장을 전 인스턴스가 공유한다)
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/cel.gdshader")
		mat.set_shader_parameter("light_tone", Color(part.light))
		mat.set_shader_parameter("dark_tone", Color(part.dark))
		mat.set_shader_parameter("threshold", part.th)
		mi.material_override = mat
	# ⚠️ MultiMesh 는 AABB 를 스스로 못 넓힌다 — 인스턴스가 원점 주변에만 있는 것으로 보고
	#    화면 밖으로 통째로 컬링당한다. 배치 범위를 덮는 커스텀 AABB 를 준다.
	# ⚠️ 높이는 **가장 큰 프롭 기준**으로 잡는다 — 나무가 76(스케일 1.25 면 95)이라
	#    60 으로 두면 나무 윗동이 컬링 판정에서 빠진다.
	mi.custom_aabb = AABB(Vector3(-160, -4, -160), Vector3(320, 140, 320))
	add_child(mi)

## 이 자리의 지면 높이. 지형이 아직 없으면 0.
func _ground_y(world: Vector3) -> float:
	var g := get_parent().get_node_or_null("Ground") as Ground
	return 0.0 if g == null else g.height_at(world)

## 이 자리가 비워둬야 할 곳인가 (전부 화면 기준 좌표).
## pad = 덩치 큰 프롭이 제외 영역을 더 넓게 보는 여유.
func _blocked(p: Vector2, pad := 0.0, walk := false) -> bool:
	# 그림에서 '비워두기' 로 칠한 자리는 무조건 비운다 — 밟고 지나갈 수 있는 것도 안 놓는다.
	if layout.is_clear(p):
		return true
	var base := _base_screen()
	if walk:
		# 밟고 지나갈 수 있는 것 — 성 자리(5×5 + 여유)만 피하고 통로·존은 신경 쓰지 않는다.
		return p.distance_to(base) < 6.0
	if p.distance_to(base) < BASE_KEEP + pad:
		return true
	for z in Main.SPAWN_ZONES:
		var zone: Vector4 = z * Main.view_scale
		if p.x > zone.x - ZONE_PAD - pad and p.x < zone.y + ZONE_PAD + pad \
				and p.y > zone.z - ZONE_PAD - pad and p.y < zone.w + ZONE_PAD + pad:
			return true
	for lane in _lanes:
		if _dist_to_segment(p, base, lane) < LANE_HALF + pad:
			return true
	return false

func _too_close(p: Vector2, gap: float) -> bool:
	# 종류가 달라도 절반 간격은 지킨다 — 다른 종류끼리 겹치면 한 덩어리로 보인다.
	for q in _placed:
		if p.distance_to(q) < gap * 0.5:
			return true
	return false

## 기지의 화면 좌표. to_world 의 역변환이다.
func _base_screen() -> Vector2:
	var b := get_tree().get_first_node_in_group(&"base") as Node3D
	if b == null:
		return Vector2.ZERO
	var w := Basis(Vector3.UP, deg_to_rad(-Main.VIEW_YAW)) * b.global_position
	return Vector2(w.x, w.z)

static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_COMMA:
			density = maxf(density - 0.15, 0.1)
			rebuild()
		KEY_PERIOD:
			density = minf(density + 0.15, 3.0)
			rebuild()
		KEY_M:
			seed_value += 1
			rebuild()
		KEY_J:
			save_map_seed()
		KEY_N:
			_toggle_overlay()

## 지금 화면의 맵을 고정한다 — 시드와 밀도를 파일로 남긴다.
func save_map_seed() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[scatter] 저장 실패: %s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify({"seed": seed_value, "density": density}, "\t"))
	f.close()
	print("[scatter] 이 맵을 저장했다 — 시드 %d / 밀도 %.2f -> %s" % [
		seed_value, density, SAVE_PATH])

## 저장된 맵이 있으면 그 시드·밀도로 시작한다. 없으면 기본값(SEED / 1.0).
func load_map_seed() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("[scatter] 저장 파일이 깨졌다: %s" % SAVE_PATH)
		return
	seed_value = int(data.get("seed", SEED))
	density = float(data.get("density", 1.0))
	print("[scatter] 저장된 맵을 불러왔다 — 시드 %d / 밀도 %.2f" % [seed_value, density])

## 제외 영역을 바닥에 납작한 판으로 그린다 — 왜 저기가 비었는지 눈으로 확인하는 용도.
func _toggle_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
		_overlay = null
		return
	_overlay = Node3D.new()
	add_child(_overlay)
	var base := _base_screen()
	_disc(base, BASE_KEEP, Color(0.92, 0.59, 0.38, 0.25))
	for lane in _lanes:
		# 통로는 원 여러 개로 근사한다 — 판 하나를 회전시키는 것보다 코드가 짧다.
		for i in 12:
			var t := float(i) / 11.0
			_disc(base.lerp(lane, t), LANE_HALF, Color(0.92, 0.59, 0.38, 0.16))
	for z in Main.SPAWN_ZONES:
		var zone: Vector4 = z * Main.view_scale
		_disc(Vector2((zone.x + zone.y) * 0.5, (zone.z + zone.w) * 0.5),
			maxf(zone.y - zone.x, zone.w - zone.z) * 0.5 + ZONE_PAD,
			Color(0.75, 0.29, 0.18, 0.3))
	print("[scatter] 제외 영역 표시 ON — 기지 원 / 행군 통로 / 스폰 존")

func _disc(at: Vector2, r: float, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(r * 2.0, r * 2.0)
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.mesh.material = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_overlay.add_child(mi)
	mi.global_position = Main.to_world(at.x, at.y) + Vector3.UP * 0.06
