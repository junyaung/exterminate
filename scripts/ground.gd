class_name Ground
extends MeshInstance3D

## 절차 생성 지면 (유저 지시 2026-08-16: 지형부터).
##
## 컨셉: **벌레 눈높이의 숲 바닥.** 언덕·산이 아니라 흙바닥의 얼룩과 잔굴곡이다 —
## 젖은 흙, 마른 흙, 이끼 낀 자리, 모래가 드러난 자리가 패치로 섞이고,
## 그 위에 개미 키(1.34) 안팎의 완만한 두둑과 팬 자리가 있다.
##
## 로우폴리 패치 룩을 만드는 규칙 두 가지:
##   1) **정점을 공유하지 않는다** — 삼각형마다 정점 3개를 따로 굽고 색을 정점에 실어야
##      보간 없이 면 단위 단색이 된다. 공유하면 색이 뭉개져 수채화가 된다.
##   2) 색은 팔레트에서 **몇 색만** 고른다. 노이즈 값을 그대로 색에 넣으면 그라데이션이 된다.
##
## ⚠️ **전투 지역은 반드시 평평해야 한다.** 적은 y=0 평면 위를 걷고 망치·균열·분출도 전부
##    y=0 을 가정한다. 그래서 굴곡은 `play_mask()` 로 눌러 기지·행군 통로·스폰 존에서
##    정확히 0 이 되게 한다. 프롭(Scatter)은 `height_at()` 으로 높이를 물어 앉힌다.

const SEED := 20260816

## 격자 한 칸의 크기(유닛)와 전체 크기. 화면에 보이는 지면이 가로 ±67 / 세로 ±49 이므로
## 넉넉히 덮되, 칸을 너무 잘게 쪼개면 로우폴리 면이 안 읽힌다 (개미 3마리 폭이 기준).
const CELL := 4.0
const HALF := 160.0

## 잔굴곡 세기. ⚠️ 계단화(STEP 2.0)를 넣은 뒤로는 이 값이 STEP 의 절반보다 작아
## **전부 0 으로 반올림된다** — 즉 지금은 실질적으로 꺼져 있다. STEP 을 낮추거나
## 이 값을 STEP 절반 위로 올리면 다시 살아난다. 일부러 남겨둔 손잡이다.
const RELIEF := 0.9
## 굴곡이 0 -> 최대로 살아나는 완충 거리. 전투 지역 경계에서 갑자기 솟으면 벽처럼 보인다.
const BLEND := 22.0

## 지면 패치 색 (밝은 톤). 어두운 밴드는 셰이더가 그늘색 쪽으로 밀어 만든다.
## 비율은 아래 `_patch()` 의 문턱이 정한다 — 흙이 바탕이고 이끼·모래는 얼룩이다.
const C_SOIL := Color("#734c44")      ## 젖은 흙 (바탕)
const C_DRY := Color("#c28569")       ## 마른 흙 — 밝게 뜨는 얼룩
const C_MOSS := Color("#3e8948")      ## 이끼
const C_MOSS_DEEP := Color("#265c42") ## 그늘진 이끼
const C_SAND := Color("#bcad9f")      ## 모래가 드러난 자리
## 절벽 면(수직 벽)의 색 — 파헤쳐진 흙 단면. 윗면보다 어두워야 높이차가 읽힌다.
const C_CLIFF := Color("#593e47")

## 계단 한 칸의 높이 (유저 지적 2026-08-16: "지형이 낮아진 게 시각적으로 안 보인다").
## ⚠️ 부드러운 언덕은 **직교 카메라 + 2톤 셀** 조합에서 높이차가 거의 안 읽힌다 —
##    경사가 완만하면 법선이 거의 안 변해서 같은 밝기 밴드로 칠해지기 때문이다.
##    그래서 높이를 이 단위로 **양자화**해서 평평한 단 + 수직 절벽으로 만든다.
##    개미 키(1.34)보다 커야 한 단이 "턱"으로 읽힌다.
const STEP := 2.0

var seed_value := SEED
var _patch_noise := FastNoiseLite.new()
var _tone_noise := FastNoiseLite.new()
var _relief_noise := FastNoiseLite.new()
var _lanes: Array[Vector2] = []
var _base_screen := Vector2.ZERO
var _ready_done := false

# --- 유저가 직접 깎은 높이 (스컬프트) ------------------------------------------
## 절차 생성 위에 **더해지는** 높이 격자. 유저가 좌클릭으로 파고 우클릭으로 채운 값이
## 여기 쌓이고, 파일로 저장됐다가 다음 실행에서 그대로 살아난다.
## ⚠️ 격자 간격은 메시 칸(CELL)과 **같아야 한다.** 더 잘게 잡으면 메시가 표현을 못 해서
##    깎아도 화면이 안 변한다 (정점이 없는 자리를 깎는 셈).
const EDIT_PATH := "res://layout/terrain_edit.json"
## 블렌더에서 만든 지형 메시. 있으면 **이걸 그대로 쓴다** (유저 지시 2026-08-16:
## "색, 오브젝트 다 없애고 블렌더에서 만든 그대로 가져와줘").
## 절차 생성 색 얼룩이 지형을 뒤덮어 뭐가 뭔지 안 보였던 게 이유다.
## 게임 로직이 쓰는 높이(height_at)는 이 메시를 광선으로 찍어 구운 EDIT_PATH 격자라,
## 화면에 보이는 것과 벌레가 걷는 바닥이 같은 지형에서 나온다.
const MESH_PATH := "res://assets/models/map_terrain.glb"
## 블렌더 맵을 쓸 것인가. ⚠️ 지금은 **끔** (유저 지시 2026-08-16: "맵은 나중에 건드리자,
## 초록색 평평한 맵으로 되돌려줘"). 켜려면 true 로 바꾸고 layout/terrain_edit.json 을
## map_build.py 로 다시 구우면 된다 — 산·길·높이가 통째로 돌아온다.
const USE_BLENDER_MESH := false

## 색을 빼고 **한 가지 무채색**으로만 본다 (유저 지시 2026-08-16: "일단 색 좀 빼줘").
## 색이 섞이면 형태가 안 읽히므로, 지형 모양을 잡는 동안은 클레이 렌더처럼 두고
## 빛과 그림자만으로 높이를 읽는다. false 로 바꾸면 블렌더 머티리얼이 그대로 나온다.
const PLAIN_LOOK := true
## 평지 초록. **Endesga 32 의 밝은 잔디** (유저 선택 2026-08-17, 후보 6종 비교 후).
## 바꾼 이유: 예전 #899d77 은 채도가 낮아 카툰이 아니라 수채 배경으로 읽혔다. 이 게임 벌레는
## 거의 검정이라 **지면이 밝을수록 실루엣이 뜨고**, 물량이 몰려도 개체가 세어진다.
## ⚠️ mood.gd 의 낮 배경색(bg)과 **같은 값을 유지할 것** — 지면 판이 끝나는 자리가 안 튄다.
const PLAIN_COLOR := Color("#63c74d")
var _edit := PackedFloat32Array()
## **비탈길 마스크** (0~1). 1 인 자리는 계단화를 하지 않고 원래 높이를 그대로 쓴다.
## ⚠️ 이게 없으면 길도 계단이 되고, 계단 한 칸(2.0)이 오를 수 있는 높이라 벌레가
##    절벽을 계단처럼 밟고 올라간다 (길찾기 검증에서 잡힘: 길로 안 돌고 직진했다).
##    길만 매끈한 비탈로 두면 "길로만 오를 수 있다"가 지형만으로 성립한다.
var _smooth := PackedFloat32Array()
var _edit_n := 0
## 유저가 칠한 레이아웃 맵. 칠한 자리만 그 색이 되고, 안 칠한 곳은 절차 생성 그대로다.
var layout := LayoutMap.new()

func _ready() -> void:
	add_to_group(&"ground")      # Terrain.h() 가 이 그룹으로 찾는다
	# 그림자는 build() 가 지형 기복을 보고 켠다 (아래 참고).
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# ⚠️ **굽기는 한 프레임 미룬다.** 씬 트리 순서상 Ground 의 _ready 가 BaseBlock 보다
	#    먼저 도는데, 평평하게 눌러야 할 기지 위치를 group "base" 로 찾기 때문에
	#    지금 구우면 기지가 원점에 있는 것으로 알고 엉뚱한 자리를 눌러버린다.
	build.call_deferred()
	print("[ground] G 지형 다시 굽기")

## 노이즈·전투 지역은 처음 필요해질 때 한 번만 준비한다 — Scatter 가 굽기 전에
## height_at() 을 물어올 수 있어서(_ready 순서), 그때도 옳은 값이 나와야 한다.
func _ensure() -> void:
	if _ready_done:
		return
	_ready_done = true
	layout.load_map()
	_edit_n = int(HALF * 2.0 / CELL) + 1
	if _edit.size() != _edit_n * _edit_n:
		_edit.resize(_edit_n * _edit_n)
		_edit.fill(0.0)
		_smooth.resize(_edit_n * _edit_n)
		_smooth.fill(0.0)
		load_edits()
	_setup_noise()
	_setup_zones()

func build() -> void:
	_ready_done = false          # 시드가 바뀌었을 수 있으니 다시 준비한다
	_ensure()
	_height_tex = null            # 지형이 바뀌면 높이 텍스처도 다시 굽는다
	var blender_mesh := _load_blender_mesh()
	var from_blender := blender_mesh != null
	mesh = blender_mesh if from_blender else _bake()
	# 지형이 바뀌면 길 찾기도 다시 계산해야 한다 — 안 하면 벌레가 없어진 절벽을 피해 돈다.
	var nav := get_tree().get_first_node_in_group(&"navmap") as NavMap
	if nav != null:
		nav.rebuild()
	# ⚠️ 블렌더 메시를 쓸 땐 override 를 벗겨야 블렌더 머티리얼이 나온다.
	#    다만 지금은 색을 빼고 보는 중이라 무채색 한 장으로 덮는다.
	if PLAIN_LOOK:
		material_override = _plain_material()
	elif from_blender:
		material_override = null
	elif material_override == null:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/ground_cel.gdshader")
		material_override = mat
	var touched := 0
	var peak := 0.0
	for v in _edit:
		if absf(v) > 0.01:
			touched += 1
		peak = maxf(peak, v)
	# ⚠️ **평지에서는 지면 그림자를 끈다.** 산이 있으면 그림자가 높이를 읽게 하는 제일 큰
	#    단서지만, 평평한 판에서는 자기 그림자에 통째로 덮여 지면이 시커멓게 나온다
	#    (유저 화면: 성만 밝고 바닥이 전부 어두웠다). 기복이 있을 때만 켠다.
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if peak > 1.0 \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 평지 판정 — 높이가 하나도 없고 길 마스크도 없으면 지형 계산을 건너뛸 수 있다.
	is_flat = touched == 0
	if is_flat:
		for v in _smooth:
			if v > 0.01:
				is_flat = false
				break
	print("[ground] 시드 %d / 칸 %.1f / %d×%d 칸 / 손댄 칸 %d / 최고 %.1f" % [
		seed_value, CELL, int(HALF * 2.0 / CELL), int(HALF * 2.0 / CELL), touched, peak])

## 단색 지면 머티리얼 — **색은 고정, 그림자는 받는다**.
## ⚠️ 두 번 헛디딘 자리다 (2026-08-16):
##   1) 일반 셰이딩(StandardMaterial3D): 지면이 통째로 시커멓게 나왔다. 그림자를 꺼도,
##      법선이 전부 위를 봐도 그대로였다.
##   2) unshaded: 색은 정확해졌지만 **그림자가 통째로 사라졌다** (빛을 안 받으니 당연하다).
## 그래서 셰이더로 갈랐다 — 밝기는 고정하고 ATTENUATION(그림자)만 곱한다.
## 자세한 건 shaders/ground_flat.gdshader 주석에.
func _plain_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/ground_flat.gdshader")
	m.set_shader_parameter("col", PLAIN_COLOR)
	return m


## 블렌더에서 내보낸 지형 메시. 없으면 null (그러면 절차 생성으로 굽는다).
func _load_blender_mesh() -> Mesh:
	if not USE_BLENDER_MESH or not ResourceLoader.exists(MESH_PATH):
		return null
	var packed := load(MESH_PATH) as PackedScene
	if packed == null:
		return null
	var root := packed.instantiate()
	var found: Mesh = null
	for node in root.find_children("*", "MeshInstance3D", true, false):
		found = (node as MeshInstance3D).mesh
		break
	root.queue_free()
	if found != null:
		print("[ground] 블렌더 지형 메시 사용 — %s (서피스 %d)" % [
			MESH_PATH, found.get_surface_count()])
	return found

func _setup_noise() -> void:
	# 패치 = 어떤 흙인가. 큰 얼룩이라 주파수가 낮다.
	_patch_noise.seed = seed_value
	_patch_noise.frequency = 0.012
	_patch_noise.fractal_octaves = 3
	# 톤 = 같은 흙 안에서의 잔얼룩. 패치와 다른 시드를 줘야 경계가 겹치지 않는다.
	_tone_noise.seed = seed_value + 977
	_tone_noise.frequency = 0.055
	_tone_noise.fractal_octaves = 2
	# 굴곡. 두둑 하나가 개미 열댓 마리 폭이 되도록 낮은 주파수.
	_relief_noise.seed = seed_value + 4231
	_relief_noise.frequency = 0.018
	_relief_noise.fractal_octaves = 2

## 전투 지역(평평해야 하는 곳)을 화면 좌표로 모아둔다. Scatter 의 제외 영역과 같은 규칙이다.
func _setup_zones() -> void:
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
	var b := get_tree().get_first_node_in_group(&"base") as Node3D
	if b != null:
		var w := Basis(Vector3.UP, deg_to_rad(-Main.VIEW_YAW)) * b.global_position
		_base_screen = Vector2(w.x, w.z)

## 이 지점에서 굴곡을 얼마나 살릴 것인가. 0 = 완전 평평(전투 지역), 1 = 마음껏.
func play_mask(world: Vector3) -> float:
	_ensure()
	var s := Basis(Vector3.UP, deg_to_rad(-Main.VIEW_YAW)) * world
	var p := Vector2(s.x, s.z)
	# 기지 + 행군 통로 + 스폰 존까지의 거리 중 **가장 가까운 것**이 마스크를 정한다.
	var d := p.distance_to(_base_screen) - Scatter.BASE_KEEP
	for lane in _lanes:
		d = minf(d, Scatter._dist_to_segment(p, _base_screen, lane) - Scatter.LANE_HALF)
	for z in Main.SPAWN_ZONES:
		var zone: Vector4 = z * Main.view_scale
		var c := Vector2((zone.x + zone.y) * 0.5, (zone.z + zone.w) * 0.5)
		var half := Vector2((zone.y - zone.x) * 0.5, (zone.w - zone.z) * 0.5)
		# 사각형까지의 거리 (바깥은 양수, 안은 음수)
		var q := (p - c).abs() - half
		d = minf(d, Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()
			+ minf(maxf(q.x, q.y), 0.0) - Scatter.ZONE_PAD)
	return smoothstep(0.0, BLEND, d)

## 지면 높이. 프롭을 앉힐 때 이걸 물어본다.
func height_at(world: Vector3) -> float:
	_ensure()
	# 유저가 깎은 값은 **전투 지역 마스크를 타지 않는다** — 일부러 깎은 자리를
	# 시스템이 도로 평평하게 만들면 툴이 안 듣는 것처럼 보인다. 의도가 우선이다.
	return level_at(world)

## 이 자리의 **계단화된** 높이. 지형은 어디서나 STEP 의 배수라, 화면에는 평평한 단과
## 그 사이의 수직 절벽만 보인다. 프롭도 이 값을 물어 단 위에 앉는다.
## ⚠️ **계단화를 끈다** (유저 지시 2026-08-16: "Thronefall 처럼 매끈하게").
##    지형은 이제 블렌더에서 매끈하게 만들어 오고, 여기서 다시 계단으로 스냅하면
##    화면에 보이는 메시와 벌레가 걷는 높이가 어긋난다.
##    직접 깎는 스컬프트 툴도 같이 매끈해진다 — 지금 방향과 맞다.
const TERRACE := false

func level_at(world: Vector3) -> float:
	var raw := raw_at(world)
	if not TERRACE:
		return raw
	# 길(마스크 1)은 원래 높이 그대로 = 매끈한 비탈, 나머지는 계단.
	return lerpf(terrace(raw), raw, smooth_at(world))

## 계단화 전의 원래 높이 = **유저가 깎은 값이 전부**다.
## ⚠️ 절차 잔굴곡(노이즈 × play_mask)은 여기서 뺐다. 두 가지 이유다:
##   1) 계단화하면 어차피 전부 평평한 단 안으로 반올림돼 **화면에 안 나온다**
##   2) play_mask 는 샘플마다 통로 10개·존 2개와 거리 계산을 돌아서, 굽는 비용의
##      대부분을 차지했다 (지형을 깎는 동안 매번 다시 굽는데 369ms -> 체감 렉).
## 잔굴곡을 되살리려면 STEP 을 낮추고 여기에 노이즈 항을 다시 더하면 된다.
func raw_at(world: Vector3) -> float:
	return edit_at(world)

## 계단 프로파일. 대부분은 평평한 단이고, 단과 단 사이 **좁은 구간에서만 가파르게** 오른다.
## ⚠️ 예전엔 칸마다 하나의 값으로 딱 끊었는데(round), 그러면 절벽 윤곽이 **격자에 물려서**
##    네모난 블록 지형이 된다 (유저 지적 2026-08-16: "절벽을 매끔하게"). 프로파일로 바꾸면
##    경계가 지형의 실제 등고선을 따라가므로 비스듬하고 매끈한 절벽이 나온다.
## CLIFF_BAND 를 키우면 완만한 비탈, 줄이면 칼 같은 절벽이 된다.
## ⚠️ 처음엔 floor 기준으로 짰다가 크게 데였다: 잔노이즈(±0.45)가 floor 에서 -1 단으로
##    떨어져 **손도 안 댄 지형이 온통 경계**가 됐고, 경계 칸을 쪼개느라 삼각형이 10만 장,
##    굽는 데 2초가 걸렸다. round 기준으로 잡으면 잔노이즈는 평평한 단 안에 머문다.
const CLIFF_BAND := 0.16
func terrace(raw: float) -> float:
	var t := raw / STEP
	var l := floorf(t + 0.5)             # 가장 가까운 단
	var d := t - l                       # 그 단에서 얼마나 벗어났나 (-0.5 ~ 0.5)
	# 단 한가운데는 평평하고, 경계 근처에서만 가파르게 오른다. 경계에서 양쪽이 정확히
	# 중간 높이로 만나므로 면이 끊기지 않는다.
	var ramp := 0.5 * signf(d) * smoothstep(0.5 - CLIFF_BAND, 0.5, absf(d))
	return STEP * (l + ramp)

# --- 스컬프트 (유저가 직접 깎는 지형) -----------------------------------------

## 격자 색인. 범위를 벗어나면 -1.
func _edit_index(gx: int, gz: int) -> int:
	if gx < 0 or gz < 0 or gx >= _edit_n or gz >= _edit_n:
		return -1
	return gz * _edit_n + gx

## 이 자리의 깎인 높이. 격자 사이는 **쌍선형 보간** — 안 하면 4유닛 계단이 그대로 드러난다.
func edit_at(world: Vector3) -> float:
	_ensure()
	var fx := (world.x + HALF) / CELL
	var fz := (world.z + HALF) / CELL
	var gx := int(floor(fx))
	var gz := int(floor(fz))
	var tx := fx - float(gx)
	var tz := fz - float(gz)
	var h := 0.0
	for dz in 2:
		for dx in 2:
			var i := _edit_index(gx + dx, gz + dz)
			if i < 0:
				continue
			var w := (tx if dx == 1 else 1.0 - tx) * (tz if dz == 1 else 1.0 - tz)
			h += _edit[i] * w
	return h

## 높이를 담은 텍스처. 셰이더가 지면에 붙어야 할 때 쓴다 (조준 원이 경사를 타는 등).
## ⚠️ 격자를 그대로 굽는다 — 셰이더 쪽에서 (world.xz + HALF) / (HALF*2) 로 샘플링하면
##    height_at() 과 같은 값이 나온다 (선형 보간까지 같다).
var _height_tex: ImageTexture
## 이 판이 완전 평지인가 (높이도 길 마스크도 없다). 평지면 높이/법선/통행 계산을 통째로
## 건너뛴다 — 몹이 수백 마리일 때 이 계산들이 프레임의 대부분을 먹는다.
var is_flat := true

func height_texture() -> ImageTexture:
	if _height_tex != null:
		return _height_tex
	_ensure()
	var img := Image.create(_edit_n, _edit_n, false, Image.FORMAT_RF)
	for gz in _edit_n:
		for gx in _edit_n:
			var w := Vector3(float(gx) * CELL - HALF, 0.0, float(gz) * CELL - HALF)
			img.set_pixel(gx, gz, Color(height_at(w), 0.0, 0.0))
	_height_tex = ImageTexture.create_from_image(img)
	return _height_tex

## 이 자리의 지면 법선. 유한차분으로 낸다 — 벌레를 경사에 맞춰 눕힐 때 쓴다.
func normal_at(world: Vector3, step := 1.2) -> Vector3:
	var hx := height_at(world + Vector3(step, 0, 0)) - height_at(world - Vector3(step, 0, 0))
	var hz := height_at(world + Vector3(0, 0, step)) - height_at(world - Vector3(0, 0, step))
	return Vector3(-hx, 2.0 * step, -hz).normalized()

## 이 자리의 비탈길 마스크(0~1). 격자 사이는 쌍선형 보간.
func smooth_at(world: Vector3) -> float:
	_ensure()
	var fx := (world.x + HALF) / CELL
	var fz := (world.z + HALF) / CELL
	var gx := int(floor(fx))
	var gz := int(floor(fz))
	var tx := fx - float(gx)
	var tz := fz - float(gz)
	var v := 0.0
	for dz in 2:
		for dx in 2:
			var i := _edit_index(gx + dx, gz + dz)
			if i < 0:
				continue
			v += _smooth[i] * (tx if dx == 1 else 1.0 - tx) * (tz if dz == 1 else 1.0 - tz)
	return clampf(v, 0.0, 1.0)

## 붓질 한 번. amount 가 음수면 판다(깎기), 양수면 채운다.
## 가장자리로 갈수록 약해지는 부드러운 붓이라 여러 번 문지르면 경사가 생긴다.
func sculpt(center: Vector3, radius: float, amount: float) -> void:
	_ensure()
	var g0x := int(floor((center.x - radius + HALF) / CELL))
	var g1x := int(ceil((center.x + radius + HALF) / CELL))
	var g0z := int(floor((center.z - radius + HALF) / CELL))
	var g1z := int(ceil((center.z + radius + HALF) / CELL))
	for gz in range(g0z, g1z + 1):
		for gx in range(g0x, g1x + 1):
			var i := _edit_index(gx, gz)
			if i < 0:
				continue
			var wx := float(gx) * CELL - HALF
			var wz := float(gz) * CELL - HALF
			var d := Vector2(wx - center.x, wz - center.z).length()
			if d > radius:
				continue
			# smoothstep 붓 — 가장자리가 뚝 끊기면 붓 자국이 원으로 남는다
			_edit[i] += amount * (1.0 - smoothstep(0.0, radius, d))

## 다듬기 붓 — 이웃과 높이를 섞어 울퉁불퉁한 자국을 편다 (유저 요청 2026-08-16: "땅을 다듬고").
## ⚠️ 원본을 복사해두고 그걸 읽어야 한다. 제자리에서 고치면 먼저 처리한 칸의 새 값이
##    다음 칸 평균에 섞여서 붓이 지나간 방향으로 지형이 밀린다.
func smooth_brush(center: Vector3, radius: float, amount: float) -> void:
	_ensure()
	var src := _edit.duplicate()
	var g0x := int(floor((center.x - radius + HALF) / CELL))
	var g1x := int(ceil((center.x + radius + HALF) / CELL))
	var g0z := int(floor((center.z - radius + HALF) / CELL))
	var g1z := int(ceil((center.z + radius + HALF) / CELL))
	for gz in range(g0z, g1z + 1):
		for gx in range(g0x, g1x + 1):
			var i := _edit_index(gx, gz)
			if i < 0:
				continue
			var wx := float(gx) * CELL - HALF
			var wz := float(gz) * CELL - HALF
			var d := Vector2(wx - center.x, wz - center.z).length()
			if d > radius:
				continue
			var sum := 0.0
			var cnt := 0
			for o in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				var j := _edit_index(gx + o.x, gz + o.y)
				if j >= 0:
					sum += src[j]
					cnt += 1
			if cnt == 0:
				continue
			var avg := sum / float(cnt)
			var w: float = amount * (1.0 - smoothstep(0.0, radius, d))
			_edit[i] = lerpf(src[i], avg, clampf(w, 0.0, 1.0))

## 깎은 지형을 파일로. res:// 에 쓰므로 프로젝트 폴더에 그대로 남고, 내가 읽어서 다듬을 수 있다.
func save_edits() -> void:
	var f := FileAccess.open(EDIT_PATH, FileAccess.WRITE)
	if f == null:
		print("[ground] 저장 실패: ", EDIT_PATH)
		return
	var arr := []
	for v in _edit:
		arr.append(snappedf(v, 0.01))
	var sm := []
	for v in _smooth:
		sm.append(snappedf(v, 0.01))
	f.store_string(JSON.stringify({cell = CELL, half = HALF, n = _edit_n, h = arr, s = sm}))
	f.close()
	var touched := 0
	for v in _edit:
		if absf(v) > 0.01:
			touched += 1
	print("[ground] 지형 저장 — 손댄 칸 %d개 -> %s" % [touched, EDIT_PATH])

func load_edits() -> void:
	# ⚠️ 예전엔 파일이 없으면 **말없이** 넘어갔다. 그래서 "지형이 왜 안 보이지"를 확인할 때
	#    로그에 아무 단서가 없었다 (유저가 실제로 여기서 막혔다). 어느 경로를 봤는지 찍는다.
	if not FileAccess.file_exists(EDIT_PATH):
		print("[ground] 지형 파일 없음 -> 평지로 시작 (%s = %s)" % [
			EDIT_PATH, ProjectSettings.globalize_path(EDIT_PATH)])
		return
	var f := FileAccess.open(EDIT_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY or not data.has("h"):
		return
	# 격자 규격이 바뀌었으면 버린다 — 억지로 맞추면 엉뚱한 자리가 솟는다
	if int(data.get("n", 0)) != _edit_n or float(data.get("cell", 0.0)) != CELL:
		print("[ground] 저장된 지형의 격자 규격이 달라 무시한다")
		return
	var arr: Array = data.h
	for i in mini(arr.size(), _edit.size()):
		_edit[i] = float(arr[i])
	_smooth.fill(0.0)
	if data.has("s"):
		var sm: Array = data.s
		for i in mini(sm.size(), _smooth.size()):
			_smooth[i] = float(sm[i])
	print("[ground] 저장된 지형 불러옴 (%d칸)" % arr.size())

## 깎은 것을 전부 지운다.
func clear_edits() -> void:
	_ensure()
	_edit.fill(0.0)
	_smooth.fill(0.0)

## 이 자리의 흙 색. 패치 노이즈로 종류를 고르고, 잔얼룩으로 두 톤 중 하나를 고른다.
func _patch(x: float, z: float) -> Color:
	# 그림이 우선이다 — 칠한 자리는 노이즈를 무시하고 그 색을 그대로 쓴다.
	var s := Basis(Vector3.UP, deg_to_rad(-Main.VIEW_YAW)) * Vector3(x, 0.0, z)
	var painted = layout.terrain_at(Vector2(s.x, s.z))
	if painted != null:
		return painted
	var n := _patch_noise.get_noise_2d(x, z)          # -1 ~ 1
	var t := _tone_noise.get_noise_2d(x, z)
	if n < -0.28:
		# 이끼 — 잔얼룩으로 짙은 이끼가 섞인다
		return C_MOSS_DEEP if t < -0.1 else C_MOSS
	if n > 0.34:
		return C_SAND
	if n > 0.10:
		return C_DRY
	# 바탕 흙. 잔얼룩이 강한 자리는 마른 흙이 드문드문 비친다.
	return C_DRY if t > 0.45 else C_SOIL

## 격자를 굽는다.
##
## 기본은 4유닛 칸 하나 = 삼각형 두 장. 다만 **네 모서리 높이가 다른 칸**(= 절벽이 지나가는
## 칸)만 잘게 쪼갠다. 절벽은 좁은 구간에서 높이가 확 오르므로 굵은 칸으로는 그 모양을
## 담지 못해 계단이 네모나게 뭉개진다. 경계 칸만 쪼개니 삼각형 수는 조금밖에 안 는다.
##
## 규칙 두 가지는 그대로:
##   1) 정점을 공유하지 않는다 (면 단색)
##   2) 색은 팔레트에서 몇 색만 — 여기에 더해 **가파른 면은 절벽 색**으로 칠한다
const SUBDIV := 4          ## 경계 칸을 몇 등분할 것인가 (4 -> 1유닛 해상도)

func _bake() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := int(HALF * 2.0 / CELL)
	# 모서리 높이를 미리 다 구해둔다 — 칸마다 다시 구하면 같은 점을 네 번 계산한다.
	var hs := PackedFloat32Array()
	hs.resize((n + 1) * (n + 1))
	for ix in n + 1:
		for iz in n + 1:
			var x := -HALF + float(ix) * CELL
			var z := -HALF + float(iz) * CELL
			hs[iz * (n + 1) + ix] = level_at(Vector3(x, 0.0, z))
	for ix in n:
		for iz in n:
			var h00 := hs[iz * (n + 1) + ix]
			var h10 := hs[iz * (n + 1) + ix + 1]
			var h01 := hs[(iz + 1) * (n + 1) + ix]
			var h11 := hs[(iz + 1) * (n + 1) + ix + 1]
			var x0 := -HALF + float(ix) * CELL
			var z0 := -HALF + float(iz) * CELL
			var flat: bool = absf(h00 - h10) < 0.01 and absf(h00 - h01) < 0.01 \
				and absf(h00 - h11) < 0.01
			if flat:
				_quad(st, x0, z0, CELL, h00, h10, h01, h11)
			else:
				# 절벽이 지나가는 칸 — 잘게 쪼개서 등고선을 따라가게 한다
				var c := CELL / float(SUBDIV)
				for sx in SUBDIV:
					for sz in SUBDIV:
						var qx := x0 + float(sx) * c
						var qz := z0 + float(sz) * c
						_quad(st, qx, qz, c,
							level_at(Vector3(qx, 0.0, qz)),
							level_at(Vector3(qx + c, 0.0, qz)),
							level_at(Vector3(qx, 0.0, qz + c)),
							level_at(Vector3(qx + c, 0.0, qz + c)))
	return st.commit()

## 사각형 한 장(삼각형 두 장). 네 모서리 높이를 그대로 써서 절벽 면이 이어지게 한다.
func _quad(st: SurfaceTool, x: float, z: float, c: float,
		h00: float, h10: float, h01: float, h11: float) -> void:
	var p00 := Vector3(x, h00, z)
	var p10 := Vector3(x + c, h10, z)
	var p01 := Vector3(x, h01, z + c)
	var p11 := Vector3(x + c, h11, z + c)
	_tri(st, p00, p01, p11, _face_color(x + c * 0.33, z + c * 0.66, p00, p01, p11))
	_tri(st, p00, p11, p10, _face_color(x + c * 0.66, z + c * 0.33, p00, p11, p10))

## 이 면의 색. 가파르면 절벽 색, 아니면 흙 패치 색.
## 문턱 0.55 = 약 57도 — 그보다 서면 "벽"으로 읽힌다.
func _face_color(px: float, pz: float, a: Vector3, b: Vector3, c: Vector3) -> Color:
	var nrm := (b - a).cross(c - a).normalized()
	return C_CLIFF if absf(nrm.y) < 0.55 else _patch(px, pz)

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	# 면 법선 — 이 순서(b-a)×(c-a) 가 윗면에서 +Y 가 나오도록 감기를 맞춰둔 것이다.
	var nrm := (b - a).cross(c - a).normalized()
	# ⚠️ **정점 색은 직접 linear 로 바꿔서 넣어야 한다.** 셰이더 uniform 은 `source_color`
	#    힌트가 붙어 있으면 고돗이 변환해 주지만(cel.gdshader 가 그렇다), 정점 색(COLOR)에는
	#    그런 변환이 없다. 팔레트 hex 를 그대로 넣었더니 지면 전체가 허옇게 떠서
	#    이끼색이 연두 배경처럼 보였고, 산이 있는데도 "맵이 안 보인다"가 됐다.
	var lin := col.srgb_to_linear()
	for v in [a, b, c]:
		st.set_color(lin)
		st.set_normal(nrm)
		st.add_vertex(v)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_G:
		seed_value += 1
		build()
		# 지형이 바뀌면 그 위의 프롭도 다시 앉혀야 한다.
		var sc := get_parent().get_node_or_null("Scatter") as Scatter
		if sc != null:
			sc.rebuild()
