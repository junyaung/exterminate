class_name Enemy
extends Node3D

## 구(球)로 표시되는 적. 스폰 지점에서 기지(직육면체)로 직진해서 붙으면 공격한다.
## 체력이 0 이 되면 망치에 눌려 납작해지며 사라진다.
##
## 노드 구조: Enemy(로직) > VisualPivot(연출 전용) > Mesh
## 스쿼시는 VisualPivot 만 건드린다 — 나중에 구체를 진짜 벌레 모델로 갈아끼워도
## 로직은 그대로다. VisualPivot 은 바닥(y=0)에 있어야 아래로 눌린다.

signal died

# --- 업그레이드/등급으로 바뀌는 값 (기본치). 사용은 stats.get_v() 를 거친다 ---
@export var base_health := 100.0
@export var base_speed := 3.5
@export var base_attack_range := 4.0
@export var base_damage := 4.0        ## 기지에 주는 초당 피해. 잡졸은 chip damage — 위협은 물량으로.

## 몹 종류. **add_child 전에** 정해야 한다 — _ready() 에서 수치가 반영된다.
@export var type_id: StringName = &"grunt"

## 잡졸 한 마리 = 경험치 1. 나머지는 잡는 데 드는 품에 비례해 이 값의 배수로 적는다.
const XP_DEFAULT := 1.0

## 쓸 모델. 블렌더로 만든 몹은 ANT, 아직 없는 몹은 구체 placeholder(BLOB).
## **모델이 생기면 TYPES 의 model 키를 지우면 된다** — 기본이 개미다.
const MODEL_ANT := &"ant"
const MODEL_BLOB := &"blob"
const MODEL_PILLBUG := &"pillbug"
const MODEL_RHINO := &"rhino"

## 몹 도감. 새 몹을 추가하려면 여기에 한 줄만 넣으면 된다.
## 생략한 키는 위의 base_* 기본값을 그대로 쓴다.
##   health / damage : 절대값      speed_mult : 기본 속도 대비 배율
##   scale           : 크기 배율   color      : 없으면 씬 기본 색
##   model           : 생략하면 개미 모델    xp : 처치 경험치 (생략하면 XP_DEFAULT)
const TYPES := {
	&"grunt": {},   # 기본 잡졸 — 개미 모델. 나머지 값도 기본값 그대로
	&"heavy": {     # 평타(100) 3방 / 풀차징(250) 1방
		health = 220.0,
		speed_mult = 0.6,
		damage = 2.0,
		# 크기 4배 (유저 지시 2026-08-14, 1.4 -> 5.6) 후 **-20%** (같은 날 재지시, -> 4.48).
		# 인게임 길이 2.80 -> 8.95.
		# ⚠️ 크기만 바꾸면 두 가지가 조용히 깨진다 — 아래 attack_range / hit_radius 가 짝이다.
		scale = 4.48,
		# 모델 = 장수풍뎅이 (2026-08-14, 구체 placeholder 교체). 느리게 준비하고 뿔로
		# **들어올리는** 공격 — 탱커라 동작이 요란하지 않고 무겁다. 배색은 rhino_materials.
		model = MODEL_RHINO,
		# 사거리는 **뿔 끝이 성에 닿는 자리**로 잡는다. 판정은 중심점 거리인데 뿔이 원점보다
		# 5.65 앞에 있어서, 기본값 4.0 이면 몸통 절반이 성 안에 박힌 채로 멈춘다.
		#   뿔 끝 선행거리 5.65 + 예전에 뿔이 서 있던 자리(성 중심에서 2.23) = 7.9
		# ⚠️ 크기에 **비례하지 않는다** — 상수항(2.23)이 있어서 스케일 배율을 곱하면 틀린다.
		attack_range = 7.9,
		# 몸이 망치보다 커졌다 — 중심을 정확히 때려야만 맞는 이상한 일을 막는다(보스와 같은 이유).
		# 값 = 뿔을 뺀 **몸통 반길이** 2.88. 뿔까지 넣으면 허공을 때려도 맞는다.
		hit_radius = 2.88,
		color = Color(0.243, 0.153, 0.192),   # endesga #3e2731 (blob 폴백용으로 남긴다)
		dark = Color(0.094, 0.078, 0.145),    # #181425
		limb = Color(0.094, 0.078, 0.145),    # #181425 다리까지 어둡게 = 묵직한 덩어리
		knockback_resist = 1.0,               # 무거워서 뜨지 않는다
		xp = 3.0,                             # 잡는 데 3배의 품이 든다 (혹은 차징 한 번)
	},
	&"stag": {      # 보스: 거대 사슴벌레. 행동은 돌진 하나 (scripts/boss.gd)
		health = 7500.0,      # 5000 -> 7500 (유저 지시 2026-08-14). 밸런스는 카드가 다 모인 뒤에 재검토
		speed_mult = 0.5,     # 헤비(0.6)보다 약간 느리다
		damage = 30.0,
		# 크기 2배 (유저 지시 2026-08-17). hit_radius 도 같이 2배 — 몸이 커진 만큼
		# 가장자리 판정도 커져야 "맞았는데 안 맞는" 일이 없다.
		scale = 28.0,         # 헤비(1.4)의 20배
		model = MODEL_BLOB,   # 블렌더 모델이 생기면 이 줄만 지운다
		color = Color(0.227, 0.267, 0.4),   # endesga #3a4466 (blob 폴백용)
		hit_radius = 16.8,    # 구체 반지름 0.6 × scale 28 — 몸 가장자리도 맞아야 한다
		knockback_resist = 1.0,
		xp = 60.0,
	},
	&"runner": {    # 빠르고 약함. 먼저 도착해 기지를 갉는다 — 우선순위를 흔드는 역할.
		# 모델 = 콩벌레 (2026-08-13): 공처럼 말려 **굴러서** 들어와 성에 그대로 들이받고,
		# 그 충격을 한 번에 꽂은 뒤 펴져서 기본 공격으로 넘어간다 (유저 스펙 2026-08-13).
		# "빠른데 안 뛰는" 러너의 답이 구르기다. 배색은 pillbug_materials (endesga).
		health = 50.0,
		speed_mult = 2.7,   # 3.5 -> 9.45 (유저 지시 2026-08-13: 기존 1.8 에서 +50%)
		damage = 3.0,
		scale = 1.2,        # 0.75 -> 1.5 (2026-08-13) -> **-20%** (유저 지시 2026-08-14)
		# attack_range 는 스케일에 따라 _apply_type 이 몸 길이로 계산한다 (아래 PILL_REACH_*).
		model = MODEL_PILLBUG,
		color = Color(0.745, 0.29, 0.184),   # endesga #be4a2f (blob 폴백용으로 남긴다)
		knockback_resist = 0.0,
		xp = 1.0,           # 체력은 절반이지만 놓치면 기지를 갉는다 — 잡졸과 동급으로 친다
	},
}
## knockback_resist: 0 = 그대로 날아감, 1 = 뜨지 않고 뒤로 밀리기만 함. 생략하면 0.
# 색 규칙: 어두울수록 무겁다. heavy #3e2731 < grunt #68386c
# color 는 placeholder 면 구체의 단색, 개미 모델이면 셀 셰이더의 **밝은 면**이다.
# dark(어두운 면)는 생략하면 개미 기본값을 쓴다.

## 벌레 배색 = **endesga 32** (유저 지시 2026-08-13). 지면·성·UI 는 nice31 파스텔 그대로.
## 파스텔만으로는 카툰 채도가 안 나온다 — nice31 에는 C*>60 인 색이 하나도 없다.
## 두 팔레트의 회청/최암부 램프가 ΔE<12 로 이미 겹쳐서 먹선·그림자는 서로 충돌하지 않는다.
## 개미 기본 배색 (blender ant_v02_cute 와 같은 값): 몸통 자두, 다리는 한 단계 어둡게.
## ⚠️ 2026-08-15 아트 방향 전환으로 한 단계 **밝고 맑게** 올렸다 (#68386c -> #9a5fb5).
##    "실물 벌레 같아 징그럽다"는 반응의 절반은 어두운 색이었다 — 규칙은
##    gamedev/cute_bug_style_spec.md 4장.
const TONE_LIGHT := Color(0.604, 0.373, 0.710)  # #9a5fb5 몸통 밝은 면
const TONE_DARK := Color(0.427, 0.247, 0.525)   # #6d3f86 몸통 어두운 면
## 다리는 몸통과 **다른 쌍**을 쓴다 — 같은 색이면 다리 여섯 개가 몸에 묻힌다.
const LIMB_LIGHT := Color(0.373, 0.227, 0.447)  # #5f3a72
const LIMB_DARK := Color(0.271, 0.165, 0.329)   # #452a54
## 단추 눈. 서피스 2(흰자)/3(동공)은 셀 셰이딩을 **입히지 않는다** — 그늘이 지면
## 눈알처럼 보여서 귀여움이 깨진다 (블렌더 쪽과 같은 판단).
const EYE_WHITE := Color(0.969, 0.949, 0.937)   # #f7f2ef
const EYE_PUPIL := Color(0.165, 0.133, 0.188)   # #2a2230
## 먹선·눈동자 = endesga 최암부. nice31 #14233a 와 ΔE 10 이라 육안으로는 같게 읽힌다.
const INK := Color(0.094, 0.078, 0.145)         # #181425
## 피격 플래시 색 — **색이 곧 피해의 종류**다.
##   불(폭연·불덩이) = 주홍, 물리 타격(분출 바위) = 흰색.
## 순백(1,1,1) 대신 nice31 의 최명색을 쓴다(팔레트 규칙).
const FLASH_BURN := Color(0.922, 0.588, 0.38)    # #eb9661
const FLASH_HIT := Color(0.945, 0.965, 0.941)    # #f1f6f0
const FLASH_ENERGY := 2.2
## 셀 밴드 경계. 원통(다리)은 각진 몸통보다 높여야 어두운 면이 보인다 (망치에서 얻은 규칙).
const CEL_THRESHOLD := [0.17, 0.34]

## 이 몹을 잡았을 때 주는 경험치.
static func xp_of(id: StringName) -> float:
	return float(TYPES.get(id, {}).get("xp", XP_DEFAULT))

const CelShader := preload("res://shaders/cel.gdshader")

## 종류별 머티리얼 캐시. 인스턴스마다 새로 만들면 배칭이 깨진다.
static var _materials := {}
static var _blob_materials := {}

## 개미 몸통(0)/다리(1) 두 서피스용 셀 머티리얼 한 쌍.
## 서피스마다 **색쌍이 다르다** — 예전엔 한 쌍을 경계값만 바꿔 돌려썼는데,
## 그러면 다리가 몸통과 같은 색이라 여섯 개가 실루엣 안에서 뭉친다.
static func type_materials(id: StringName) -> Array:
	if not _materials.has(id):
		var d: Dictionary = TYPES.get(id, {})
		var tones := [
			[d.get("color", TONE_LIGHT), d.get("dark", TONE_DARK)],
			[d.get("limb", LIMB_LIGHT), d.get("limb_dark", LIMB_DARK)],
		]
		var pair: Array[ShaderMaterial] = []
		for i in CEL_THRESHOLD.size():
			var m := ShaderMaterial.new()
			m.shader = CelShader
			m.set_shader_parameter("light_tone", tones[i][0])
			m.set_shader_parameter("dark_tone", tones[i][1])
			m.set_shader_parameter("threshold", CEL_THRESHOLD[i])
			pair.append(m)
		_materials[id] = pair
	return _materials[id]

## 단추 눈용 무광 unshaded 머티리얼 [흰자, 동공]. 모든 개미가 공유한다 (배칭 유지).
static var _eye_materials: Array = []

static func eye_materials() -> Array:
	if _eye_materials.is_empty():
		for c in [EYE_WHITE, EYE_PUPIL]:
			var m := StandardMaterial3D.new()
			m.albedo_color = c
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_eye_materials.append(m)
	return _eye_materials

## 아직 모델이 없는 몹의 구체 placeholder 색.
static func blob_material(id: StringName) -> StandardMaterial3D:
	if not _blob_materials.has(id):
		var m := StandardMaterial3D.new()
		m.albedo_color = TYPES[id].color
		m.roughness = 1.0
		m.metallic_specular = 0.0
		_blob_materials[id] = m
	return _blob_materials[id]

## 콩벌레(러너) 셀 머티리얼 — 서피스 순서는 블렌더 슬롯:
##   0 등갑 / 1 얼굴·배·다리 / 2 흰자 / 3 동공 / 4 마디 먹선
## ⚠️ 슬롯 4(마디 먹선)는 **셀 음영을 입히지 않는다.** 역헐 먹선은 실루엣에만 생기므로
##    등 위의 마디선은 재질로 칠해 넣는데, 여기에 셀 음영이 걸리면 그늘진 쪽에서
##    선이 배경색과 붙어 사라진다 — 그러면 등이 통짜 덩어리로 보인다
##    (유저 지적 2026-08-16: "먹선 주름이 안 보여서 segment 로 인식이 안 돼").
## ⚠️ v01 은 눈이 어두운 점 하나라 서피스가 3개였다. v02 에서 **단추 눈**이 되며
##    흰자와 동공이 갈라져 4개가 됐다. 3개짜리 배열을 그대로 두면 흰자 자리에
##    동공용 검정이 칠해져 눈이 통째로 까매진다 (유저 지적 2026-08-15).
## 배색(endesga 32, 유저 지시 "얼굴까지 모두 다"): 등갑·연질부 모두 #be4a2f/#733e39.
## 색은 하나지만 경계값을 0.17 / 0.30 으로 달리 둬 다리·머리에만 그늘이 더 남는다.
static var _pill_materials: Array = []

static func pillbug_materials() -> Array:
	if _pill_materials.is_empty():
		var mk := func(light: Color, dark: Color, th: float) -> ShaderMaterial:
			var m := ShaderMaterial.new()
			m.shader = CelShader
			m.set_shader_parameter("light_tone", light)
			m.set_shader_parameter("dark_tone", dark)
			m.set_shader_parameter("threshold", th)
			return m
		var eyes := eye_materials()     # [흰자, 동공] — 개미와 같은 것을 공유한다
		_pill_materials = [
			mk.call(Color(0.745, 0.29, 0.184), Color(0.451, 0.243, 0.224), 0.17),  # #be4a2f/#733e39
			mk.call(Color(0.745, 0.29, 0.184), Color(0.451, 0.243, 0.224), 0.30),  # #be4a2f/#733e39
			eyes[0],
			eyes[1],
			ink_material(),             # 마디 먹선 — 실루엣 먹선과 같은 색·같은 무광
		]
	return _pill_materials

## 장수풍뎅이(헤비) 파트. Ink 사본은 이름 + "Ink" 로 짝을 이룬다 (사슴벌레와 같은 규약).
const RHINO_PARTS: Array[StringName] = [
	&"Head", &"Thorax", &"Abdomen", &"LegFront", &"LegMid", &"LegRear"]

## 블렌더 재질 이름 -> rhino_materials() 의 몇 번째인가.
## ⚠️⚠️ **서피스 번호로 꽂으면 안 된다.** glTF 는 그 파트가 실제로 쓰는 재질만 프리미티브로
##    만들기 때문에, 블렌더에서 슬롯이 4개라도 임포트 후 서피스는 1~2개다. 실측:
##      Head   s0 = Cel_RhinoDark   (슬롯 2인데 서피스 0)
##      Thorax s0 = Cel_RhinoPron   (슬롯 1인데 서비스 0)  <- 뿔이 여기 있다
##      Abdomen s0 = Elytra / s1 = Hair (슬롯 0, 3)
##    예전엔 rmats[i] 를 서피스 i 에 꽂아서 **뿔이 딱지날개색(어두운색)으로 칠해졌다.**
##    상아뿔 배색이 인게임에 한 번도 안 나온 이유가 이것 (유저 제보 2026-08-14).
## ⚠️ v02 에서 슬롯이 셋 늘었다 (마디 먹선 / 흰자 / 동공). 이름으로 찾으므로 번호가
##    밀릴 걱정은 없지만, 여기에 등록하지 않으면 rhino_slot_of 가 -1 을 돌려주고
##    그 서피스는 glb 원본 재질(밝은 회색)로 남는다.
const RHINO_SLOT := {
	"Cel_RhinoElytra": 0, "Cel_RhinoPron": 1, "Cel_RhinoDark": 2, "Cel_RhinoHair": 3,
	"Cel_RhinoSeg": 4, "Cel_RhinoEye": 5, "Cel_RhinoPupil": 6,
}

## 서피스의 glb 재질 이름으로 슬롯 번호를 찾는다. 못 찾으면 -1.
## 임포터가 이름 뒤에 접미사를 붙이는 경우가 있어 begins_with 로 본다.
static func rhino_slot_of(mat_name: String) -> int:
	for key in RHINO_SLOT:
		if mat_name.begins_with(key):
			return int(RHINO_SLOT[key])
	return -1

## 장수풍뎅이 셀 머티리얼 — 서피스 순서는 블렌더 슬롯:
##   0 딱지날개 / 1 전흉배판+가슴뿔 / 2 머리·다리 / 3 털 술.
## 배색 = "상아뿔" 안 (유저 선택 2026-08-14, 시안 5종 렌더 비교 후).
## 몸통은 헤비의 선언색(#3e2731/#181425)으로 어둡게 깔고 **전흉배판+가슴뿔만** 밝게 올린다 —
## 무기가 어디인지 색으로 지목하는 배색이다. 한 색으로 다 깔면 실루엣 덩어리가 되어
## 뿔도 다리도 안 보인다.
## ⚠️ 뿔의 밝기를 #e4a672(L*72.9)에서 **#c28569(L*61.0)로 내렸다.** 이유 둘 —
##    (a) L* 72.9 는 지면(#89a477, L*64.3)보다 밝아서, 네 유닛 중 헤비만 배경보다 밝았다.
##        크기까지 잡졸의 6배라 화면에서 보스보다 먼저 눈에 들어왔다.
##    (b) "어두운 몸 + 밝고 따뜻한 뿔"은 **보스(남색+금)의 디자인 문법**이다. 밝기를 낮춰
##        금(ΔE 43 -> 58)과 거리를 벌려야 그 액센트 역할이 보스에게 남는다.
## ⚠️ 가슴뿔은 **전흉배판과 같은 슬롯**이다 (블렌더 규약). 색을 갈라 놓으면 뿔이 몸에
##    얹힌 별개 부품으로 읽힌다 — 실물은 한 덩어리 키틴이다.
## ⚠️ 보스(사슴벌레)의 네이비+금과 겹치지 않게 갈색·자두 계열로 묶었다.
static var _rhino_mats: Array = []

static func rhino_materials() -> Array:
	if _rhino_mats.is_empty():
		var mk := func(light: Color, dark: Color, th: float) -> ShaderMaterial:
			var m := ShaderMaterial.new()
			m.shader = CelShader
			m.set_shader_parameter("light_tone", light)
			m.set_shader_parameter("dark_tone", dark)
			m.set_shader_parameter("threshold", th)
			return m
		_rhino_mats = [
			mk.call(Color(0.243, 0.153, 0.192), INK, 0.17),                         # #3e2731/#181425
			mk.call(Color(0.761, 0.522, 0.412), Color(0.451, 0.243, 0.224), 0.24),  # #c28569/#733e39
			mk.call(Color(0.243, 0.153, 0.192), INK, 0.34),  # 머리·다리 — 같은 쌍, 경계만 높여 그늘을 남긴다
			mk.call(Color(0.149, 0.169, 0.267), INK, 0.30),                         # #262b44 털 술
			ink_material(),                 # 4 마디 먹선 — 실루엣 먹선과 같은 무광 먹색
			eye_materials()[0],             # 5 흰자
			eye_materials()[1],             # 6 동공
		]
	return _rhino_mats

## --- 인위적 접지 그림자 -------------------------------------------------------
## ⚠️ 태양 그림자는 **켜져 있고 정상 동작한다**. 실측(tools/verify_shadows.gd):
##    Sun.shadow_enabled=true / 개미 Body.cast_shadow=ON / 지면은 StandardMaterial3D 라 받는다.
##    그런데도 눈에 잘 안 띄는 이유는 설정이 아니라 **조건**이다:
##      · 태양 고도가 약 50° 라 그림자 길이가 키의 0.84 배뿐 — 대부분 몸 밑에 깔린다
##      · 카메라가 직교 pitch -50 이라, 그 짧은 그림자를 몸통이 그대로 가린다
##      · 환경광이 0.55 로 세서 그늘과 양지의 명도차가 작다
##    셋 다 화면 전체의 룩을 정하는 값이라 손대면 다른 게 깨진다. 그래서 진짜 그림자는
##    그대로 두고, **접지감 전용 타원**을 발밑에 따로 깐다 (유저 지시 2026-08-14).
const DropShadowShader := preload("res://shaders/drop_shadow.gdshader")
## nice31 최암부 #14233a. 먹선(endesga #181425)과 ΔE 10 이라 육안으론 같게 읽히지만,
## 지면 위에 까는 것이니 팔레트 규칙대로 nice31 쪽을 쓴다.
const SHADOW_COL := Color(0.078, 0.137, 0.227)
const SHADOW_STRENGTH := 0.30
const SHADOW_Y := 0.02        ## 지면과의 z-fighting 을 피하는 최소 높이
const SHADOW_FIT := 0.80      ## 발자국 대비 타원 크기. 1.0 이면 다리 끝까지 덮어 넓다
## ⚠️ 길이는 폭의 이 배수까지만 늘어난다. 장수풍뎅이는 **가슴뿔이 몸 길이의 36%** 라
##    AABB 를 그대로 쓰면 공중에 뜬 뿔까지 그림자가 깔려 "거대한 타원 위에 앉은 벌레"가 된다.
const SHADOW_LEN_CAP := 1.2

var _ground_shadow: MeshInstance3D

## 유닛 발밑 타원. 모델 종류를 묻지 않고 **실제 메시 발자국**에서 크기를 뽑는다 —
## 그래야 크기 배율을 바꿔도(헤비 4.48, 러너 1.2) 따로 손볼 곳이 없다.
func _add_ground_shadow(model: Node3D) -> void:
	var inv := global_transform.affine_inverse()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for mi in _shadow_meshes(model):
		var ab := mi.get_aabb()
		var rel := inv * mi.global_transform
		for c in 8:
			var p: Vector3 = rel * (ab.position + ab.size * Vector3(
				float(c & 1), float((c >> 1) & 1), float((c >> 2) & 1)))
			lo = lo.min(Vector2(p.x, p.z))
			hi = hi.max(Vector2(p.x, p.z))
	if lo.x > hi.x:
		return
	var w := hi.x - lo.x
	var l := minf(hi.y - lo.y, w * SHADOW_LEN_CAP)
	var plane := PlaneMesh.new()
	plane.size = Vector2(w, l) * SHADOW_FIT
	var m := ShaderMaterial.new()
	m.shader = DropShadowShader
	m.set_shader_parameter("col", SHADOW_COL)
	m.set_shader_parameter("strength", SHADOW_STRENGTH)
	plane.material = m
	_ground_shadow = MeshInstance3D.new()
	_ground_shadow.name = "GroundShadow"
	_ground_shadow.mesh = plane
	_ground_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# ⚠️ VisualPivot 이 아니라 **루트**에 붙인다. 피벗은 사망 스쿼시로 눌리고 폭연으로 떠오르는데,
	#    그걸 따라가면 그림자가 지면에서 분리돼 공중에 뜬다.
	#    중심을 (0,0) 으로 두는 것도 같은 이유 — 모델 원점이 곧 몸 중심이라 뿔·머리로 안 쏠린다.
	add_child(_ground_shadow)
	_ground_shadow.position = Vector3(0.0, SHADOW_Y, 0.0)

func _shadow_meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_shadow_meshes(c))
	return out

## 먹선 헐 머티리얼 (전 개체 공유).
static var _ink_material: StandardMaterial3D

static func ink_material() -> StandardMaterial3D:
	if _ink_material == null:
		_ink_material = StandardMaterial3D.new()
		_ink_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ink_material.albedo_color = INK
	return _ink_material

# --- 사망 연출 타이밍 ---
const SQUASH_TIME := 0.06     ## 눌리는 순간. 짧을수록 타격감이 산다.
const SPLAT_HOLD := 0.28      ## 납작한 채 남아있는 시간 (학살의 증거)
const FADE_TIME := 0.14       ## 사라지는 시간

var stats: Stats
var health := 0.0
var target: Node3D
## --- 애니메이션 LOD ---------------------------------------------------------
## 화면에서 멀리 있는 벌레는 다리를 안 움직여도 티가 안 난다. 애니메이션이 프레임 비용의
## 대부분이라(측정: 300마리에서 애니 끄면 물리 195ms -> 4.8ms), 보이는 것만 움직인다.
## ⚠️ 매 프레임 검사하면 그 자체가 비용이다. 개체마다 시작 프레임을 흩어서 드문드문 본다.
const ANIM_LOD_RADIUS := 95.0    ## 카메라가 보는 지점에서 이만큼 안쪽만 애니메이션
const ANIM_LOD_EVERY := 18       ## 몇 프레임마다 검사할 것인가
var _lod_tick := 0

func _anim_lod() -> void:
	if _anim == null:
		return
	_lod_tick -= 1
	if _lod_tick > 0:
		return
	_lod_tick = ANIM_LOD_EVERY
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# 카메라가 내려다보는 지면 지점 — 직교라 위치에서 시선 방향으로 내려 찍으면 된다.
	var o := cam.global_position
	var d := -cam.global_transform.basis.z
	var focus := o if absf(d.y) < 0.01 else o - d * (o.y / d.y)
	var far: bool = Vector2(global_position.x - focus.x,
		global_position.z - focus.z).length() > ANIM_LOD_RADIUS
	if _anim.active == far:
		_anim.active = not far

## ⚠️ 길찾기 노드를 **매 프레임 그룹에서 찾지 않는다.** get_first_node_in_group 은 호출마다
## 배열을 만들어, 몹 600마리 × 프레임당 두 번이면 그것만으로 프레임을 먹는다.
static var _nav_cached: NavMap

func _nav() -> NavMap:
	if _nav_cached != null and is_instance_valid(_nav_cached):
		return _nav_cached
	_nav_cached = get_tree().get_first_node_in_group(&"navmap") as NavMap
	return _nav_cached

var _up := Vector3.UP      ## 지금 몸이 향한 위쪽 (경사를 따라 천천히 눕는다)
var _body_scale := 1.0     ## 이 종류의 몸 크기 (경사에 눕힐 때 basis 를 다시 세우므로 따로 보관)

## 죽는 중. 스웜 카운트/망치 타격 대상에서 제외된다 (그룹에서도 빠진다).
var dying := false

## 몸통 반경. 판정은 전부 "중심점 거리"라 기본 0(점)이면 충분하지만,
## **보스처럼 큰 몹은 몸이 망치보다 커서** 중심을 정확히 때려야만 맞는 이상한 일이 생긴다.
## 모든 피해원이 `거리 <= 판정반경 + hit_radius` 로 검사하므로 몸 가장자리도 맞는다.
var hit_radius := 0.0

## 망치에 맞았다 — ratio 는 그 스윙의 차징 비율(0 평타 ~ 1 풀차징).
## 기본 몹은 무시한다. 보스가 "풀차징으로 예고를 끊는" 규칙에 쓰려고 뚫어둔 통로.
func on_hammer(_ratio: float) -> void:
	pass

var _attacking := false

# 분출에 날아가는 중(포물선). 착지하면 풀린다.
var _airborne := false
var _air_vel := Vector3.ZERO
# 감쇠하며 뒤로 밀리는 수평 속도. 무거운 적의 분출 반응 + 균열을 밟았을 때의 비틀거림.
var _slide := Vector3.ZERO

const AIR_GRAVITY := 38.0
const SLIDE_DAMP := 9.0        ## 클수록 빨리 멎는다
## 균열을 처음 밟았을 때. 이동속도(3.5)보다 세게 밀어야 실제로 "뒤로" 간다.
const STUMBLE_PUSH := 4.5
const STUMBLE_STAGGER := 0.14  ## 이 동안은 전진을 멈춘다 — 밀림이 전진에 묻히지 않도록

var _stagger := 0.0            ## 남은 비틀거림 시간

@onready var _pivot: Node3D = $VisualPivot
## 실제로 보이는 쪽. 종류에 따라 개미 모델이나 구체 placeholder 중 하나가 들어온다.
var _mesh: Node3D
## 모델이 바뀌어도 들썩임이 제 높이에서 시작하도록 시작 높이를 기억해둔다
## (구체는 0.6 — 중심이 원점이라 반지름만큼 띄워야 한다. 개미는 발이 원점이라 0.)
var _mesh_y := 0.0
## 개미 걷기 재생기 (blob 이면 null). 재생 속도는 _physics_process 가 이동속도에 맞춘다.
var _anim: AnimationPlayer
## 걷기 한 주기가 실제로 나아가는 거리(초당, **모델 스케일 1.0 기준**).
## = 블렌더에서 잰 보폭 × 노드 스케일 ÷ 주기. 각 리깅 스크립트가 [보폭] 으로 찍어 준다.
##
## ⚠️ 예전엔 세 모델이 상수 하나(3.5)를 같이 썼다. 3.5 는 **이동속도**였지 보폭이 아니라
##    아무 모델과도 맞지 않았다 — 개미는 34배, 콩벌레는 84배 어긋나 다리가 헛돌았다
##    (유저 지적 2026-08-16: "애니메이션이랑 이동속도랑 불일치해서 gliding").
## ⚠️ scale 을 **곱해야 한다**. 큰 개체는 같은 애니로도 보폭이 그만큼 길다.
const WALK_DESIGN_SPEED := {
	MODEL_ANT: 0.304,
	MODEL_PILLBUG: 0.249,
	MODEL_RHINO: 0.195,
}
const WALK_DESIGN_FALLBACK := 0.304
## 초당 최대 걸음 주기. 넘어가면 다리가 진동으로 보여 미끄러짐보다 나쁘다.
## 콩벌레는 다리가 발끝뿐이라 보폭이 짧고, 정확히 맞추면 초당 32걸음이 나온다 —
## 어차피 펴진 직후 잠깐만 걷는 구간이라 여기서 잘라낸다.
const WALK_RATE_MAX := 15.0

## 사거리 판정의 여유. **부동소수점 칼날 위에 서지 않기 위한 것**이다.
## 전진은 사거리를 넘지 않게 잘라내므로 거리가 사거리에 정확히 붙는데, 그 값이
## 한 톨 바깥으로 떨어지면 "공격 사거리 밖"이면서 "전진 거리 0" 이 되어 영영 멈춘다.
## 콩벌레는 펴진 뒤 그 자리로 물러나므로 매번 이 경계에 선다 —
## 실제로 일부 개체가 펴지고도 공격을 안 했다 (유저 지적 2026-08-16).
const RANGE_EPS := 0.02

## 이 개체가 쓰는 모델 (걷기 배율 계산에 쓴다).
var _model: StringName = MODEL_ANT

## 다리 회전수를 실제 이동속도에 맞춘 재생 배율.
func _walk_scale() -> float:
	if _anim == null or not _anim.has_animation(&"walk"):
		return 1.0
	var design: float = WALK_DESIGN_SPEED.get(_model, WALK_DESIGN_FALLBACK) * scale.x
	var want: float = stats.get_v(Stats.SPEED) / maxf(design, 0.0001)
	return minf(want, WALK_RATE_MAX * _anim.get_animation(&"walk").length)

## --- 콩벌레(러너) 전용 상태: 말린 채 굴러오다 성 앞에서 펴진다 (유저 스펙) ---
var _pill := false          ## 이 개체가 콩벌레 모델인가
var _rhino := false         ## 이 개체가 장수풍뎅이(헤비) 모델인가
## 피격 플래시를 걸 셀 메시들. 모델마다 개수가 다르다 (개미·콩벌레 1 / 장수풍뎅이 6).
var _flash_bodies: Array[MeshInstance3D] = []
var _uncurling := false     ## curl 역재생 중 (펴는 동안 제자리)
var _curled := true         ## 말린 채 굴러오는 중. 성에 닿는 순간 일격을 넣고 풀린다.
## 구르기 표면 속도 = 공 둘레 ÷ roll 루프 길이. 이 값이 틀리면 공이 굴러가면서 **미끄러진다**.
##   공 지름 = 블렌더 1.472 × 노드 0.9981 = 1.469 (스케일 1.0 기준)
##   둘레 4.615 ÷ (24f / 24fps = 1.000s) = 4.615
## ⚠️ 예전엔 러너 스케일(0.75)을 곱해 넣은 **상수 5.13** 이었다. 크기를 바꾸는 순간
##    조용히 미끄러지므로, 스케일은 상수에서 빼고 아래 _roll_ups() 가 곱하게 했다.
## ⚠️ 이 세 값은 손으로 짐작하지 말 것. pillbug_v02_export.py 가 변형된 메시를 실측해
##    [enemy.gd 상수] 로 찍어 준다 — 모델을 고치면 그 출력을 그대로 옮긴다.
const PILL_ROLL_UPS_UNIT := 4.615   ## 스케일 1.0 기준 표면 속도 (유닛/초)
## 펴진 뒤 이만큼 밀려나면 도로 말린다. 경계에서 말렸다 펴졌다 하지 않도록 둔 여유분.
const PILL_RECURL_DIST := 1.6
## 굴러와 들이받는 순간의 일격 = 초당 피해의 몇 배인가.
## ⚠️ 자리표시자 — 밸런스는 카드가 다 모인 뒤에 (health 와 같은 취급).
const PILL_SLAM_MULT := 3.0

## 이 개체의 실제 구르기 표면 속도. scale 은 _apply_type 이 루트에 준다.
func _roll_ups() -> float:
	return PILL_ROLL_UPS_UNIT * scale.x

## 적 원점에서 **앞(코 방향)으로 뻗은 몸 길이**. 스케일 1.0 기준, 블렌더 변형 메시 실측:
##   말린 공 0.735 / 펴져서 들이받는 순간 1.377 (둘 다 × 노드 0.9981)
## ⚠️ 말린 몸과 펴진 몸은 길이가 다르므로 **정지 거리도 달라야 한다.** 하나로 맞추면
##    공이 벽에 박히거나(가까우면) 펴진 뒤 머리가 성 안에 꽂힌다 (유저 지적 2026-08-13).
## v02 에서 대소 관계가 뒤집혔다: 공(0.72)이 펴진 몸(1.38)보다 **짧다**. v01 은 공이
## 몸 앞쪽에 치우쳐 생겨 반대였는데, v02 는 가운데에서 양쪽이 같이 말려 원점에 생긴다.
const PILL_REACH_CURLED := 0.735
const PILL_REACH_UNCURLED := 1.377
const PILL_BASE_HALF := 2.5       ## 성 상자(5×4×5) 의 반폭
const PILL_CLEARANCE := 0.05      ## 스치기만 하고 겹치지는 않도록 남기는 틈

## 말린 채 굴러와 멈추는 거리 — 공 앞면이 성 벽에 딱 닿는다.
func _curled_range() -> float:
	return PILL_BASE_HALF + PILL_REACH_CURLED * scale.x + PILL_CLEARANCE

## 펴지는 동안 뒤로 물러나는 속도 (유닛/초, 스케일 1.0 기준).
## ⚠️ v02 부터 필요해졌다. v01 은 공(1.649)이 펴진 몸(1.253)보다 **길어서** 공이 닿는
##    자리가 이미 펴진 몸보다 멀었다. v02 는 공(0.735)이 펴진 몸(1.377)보다 짧다 —
##    공이 벽에 닿은 자리에서 그대로 펴면 머리가 성 안 0.77 까지 꽂힌다.
##    멀찍이 서서 부딪히게 하는 대신, **부딪힌 뒤 튕겨 물러나며 펴지게** 했다.
const PILL_UNCURL_BACKOFF := 2.4

## 굴러온 힘을 성에 한 번에 꽂는다. 펴지기 직전 딱 한 번만 불린다.
func _slam() -> void:
	if target != null and target.has_method("take_damage"):
		target.take_damage(stats.get_v(Stats.DAMAGE) * PILL_SLAM_MULT)

## 콩벌레 애니 상태 전이. true 를 돌려주면 이번 프레임 이동을 멈춘다 (펴는 동안).
##
## 흐름(유저 스펙 2026-08-13): 말린 채 굴러온다 -> **성에 닿는 순간 일격** -> 펴진다
## -> 기본 공격. 예전엔 공격 범위 앞 1.6 에서 미리 펴져서 "부딪힌다"가 없었다.
func _pill_update(dist: float, delta: float) -> bool:
	if _anim == null:
		return false
	if _uncurling:
		if _anim.is_playing():
			# 펴는 동안 전진은 없고, 몸이 길어지는 만큼 **뒤로 물러난다**.
			# 제자리에서 펴면 머리가 성 안에 박힌다 (PILL_UNCURL_BACKOFF 주석 참고).
			# 사거리에 **정확히** 맞추지 않고 한 톨 안쪽을 노린다 — 경계에 딱 서면
			# 아래 공격 판정이 부동소수점 반올림에 따라 갈린다.
			var want: float = stats.get_v(Stats.ATTACK_RANGE) - RANGE_EPS
			if dist < want and target != null:
				var away := global_position - target.global_position
				away.y = 0.0
				if away.length() > 0.001:
					global_position += away.normalized() * minf(
						want - dist, PILL_UNCURL_BACKOFF * scale.x * delta)
			return true                    # "부딪혀서 멈췄다"가 읽힌다
		_uncurling = false
	var arange := stats.get_v(Stats.ATTACK_RANGE)
	if _curled:
		# 말린 동안은 공 크기에 맞춘 **다른** 거리에서 멈춘다 — 벽에 박히지 않고 '닿는다'.
		if dist > _curled_range():
			if _anim.current_animation != "roll":
				_anim.play(&"roll")
			_anim.speed_scale = stats.get_v(Stats.SPEED) / _roll_ups()
			# ⚠️ 굴러오는 동안의 **이동은 여기서 직접 한다.** 아래 공용 코드는
			#    ATTACK_RANGE(= 펴진 몸 기준 4.20)에서 멈추는데, v02 는 그게 공의 정지
			#    거리(3.43)보다 **멀다**. 공용 코드에 맡기면 공이 4.20 에서 그대로 서 버려
			#    3.43 에 영영 못 닿고 — 일격도, 펴지기도 시작되지 않는다.
			#    말린 채로 성만 계속 갉는다 (유저 지적 2026-08-15: "아직 안 펴져").
			#    v01 은 공이 더 길어서(4.53 > 4.05) 우연히 맞아떨어졌던 것뿐이다.
			if target != null:
				var to := target.global_position - global_position
				to.y = 0.0
				if to.length() > 0.001:
					# ⚠️ 여기도 **길찾기와 지형 판정을 거쳐야 한다.** 예전엔 성으로 직진하며
					#    좌표를 직접 더해서, 굴러오는 콩벌레만 산을 뚫고 지나갔다.
					var dir := _steer_dir(to, to.length())
					var step := dir.normalized() * stats.get_v(Stats.SPEED) * delta
					global_position = _walk(global_position, step)
					global_position.y = Terrain.h(global_position)
					_face_and_tilt(dir, delta)
			return true
		# 충돌. 일격을 넣고 curl 을 거꾸로 감아 편다.
		_slam()
		# 블렌드를 준다 — 구르던 각도에서 곧게 선 자세로 **부드럽게** 넘어가야 한다.
		# 0 이면 공이 한 프레임 만에 홱 바로 서서 튄 것처럼 보인다.
		_anim.play_backwards(&"curl", 0.12)
		_anim.speed_scale = 1.6
		_uncurling = true
		_curled = false
		return true
	# 펴진 뒤 넉백 등으로 충분히 밀려나면 도로 말려 다시 굴러온다 — 일격도 다시 들어간다.
	if dist > arange + PILL_RECURL_DIST:
		_curled = true
		return false
	if dist <= arange + RANGE_EPS:
		if _anim.current_animation != "attack":
			_anim.play(&"attack")          # 젖혔다 머리로 들이받기 (범용 들썩임 대체)
			_anim.speed_scale = 1.2
	elif _anim.current_animation != "walk":
		_anim.play(&"walk")
		_anim.speed_scale = _walk_scale()
	return false

## 장수풍뎅이 애니 전이. 걷기/공격 둘뿐이라 콩벌레처럼 상태기계가 필요 없다.
##
## ⚠️ 공격 애니는 **재생 속도를 이동속도에 묶지 않는다**. walk 는 다리 회전수를 실제
##    이동에 맞춰야 미끄러져 보이지 않지만, attack 은 "준비 1.42초 / 들어올리기 0.79초"로
##    **초 단위로 설계된 텔레그래프**다. 속도 배율이 걸리면 그 예고 시간이 무너진다.
func _rhino_anim(attacking: bool) -> void:
	if _anim == null:
		return
	if attacking:
		if _anim.current_animation != "attack":
			_anim.play(&"attack")
			_anim.speed_scale = 1.0
		return
	if _anim.current_animation != "walk":
		_anim.play(&"walk")
	_anim.speed_scale = _walk_scale()

func _ready() -> void:
	stats = Stats.new({
		Stats.HEALTH: base_health,
		Stats.SPEED: base_speed,
		Stats.ATTACK_RANGE: base_attack_range,
		Stats.DAMAGE: base_damage,
	})
	_apply_type()
	health = stats.get_v(Stats.HEALTH)
	add_to_group("enemies")

func _apply_type() -> void:
	var d: Dictionary = TYPES.get(type_id, {})
	if d.has("health"):
		stats.set_base(Stats.HEALTH, d.health)
	if d.has("damage"):
		stats.set_base(Stats.DAMAGE, d.damage)
	if d.has("speed_mult"):
		stats.set_base(Stats.SPEED, base_speed * d.speed_mult)
	if d.has("scale"):
		# 크기는 루트에 준다. VisualPivot 은 사망 스쿼시가 절대값으로 덮어쓰므로 건드리면 안 된다.
		scale = Vector3.ONE * d.scale
		_body_scale = float(d.scale)
	# 모델 선택: 쓰지 않는 쪽은 숨긴다. 지우지 않는 이유는 나중에 blender 모델이 생기면
	# TYPES 의 model 키만 지우면 되게 하려는 것 — 씬 구조는 그대로 둔다.
	if d.has("attack_range"):
		stats.set_base(Stats.ATTACK_RANGE, d.attack_range)
	if d.has("hit_radius"):
		hit_radius = d.hit_radius
	# ⚠️ 보스 씬처럼 한쪽만 있는 경우가 있으므로 get_node_or_null 로 받는다.
	var ant: Node3D = _pivot.get_node_or_null("Ant")
	var pill: Node3D = _pivot.get_node_or_null("Pillbug")
	var rhino: Node3D = _pivot.get_node_or_null("Rhino")
	var blob: MeshInstance3D = _pivot.get_node_or_null("Blob")
	var model: StringName = d.get("model", MODEL_ANT)
	_model = model          # 걷기 배율이 모델별 보폭을 찾는 데 쓴다
	var use_ant: bool = model == MODEL_ANT and ant != null
	var use_pill: bool = model == MODEL_PILLBUG and pill != null
	var use_rhino: bool = model == MODEL_RHINO and rhino != null
	if ant != null:
		ant.visible = use_ant
	if pill != null:
		pill.visible = use_pill
	if rhino != null:
		rhino.visible = use_rhino
	if blob != null:
		blob.visible = not use_ant and not use_pill and not use_rhino
	_mesh = ant if use_ant else (pill if use_pill else (rhino if use_rhino else blob))
	# ⚠️ **안 쓰는 모델은 지운다** (2026-08-16 최적화). 씬 하나에 개미·콩벌레·장수풍뎅이가
	#    전부 들어 있어서, 숨겨만 두면 한 마리당 **스켈레톤 3개(본 68개) + 애니플레이어 3개**가
	#    그대로 남는다. 몹이 수백이면 그게 프레임의 대부분을 먹는다 (측정: 300마리 물리
	#    195ms 중 대부분이 애니메이션). 종류는 스폰 시 정해지고 도중에 안 바뀌므로 지워도 된다.
	for spare in [ant, pill, rhino, blob]:
		if spare != null and spare != _mesh:
			spare.queue_free()
	if _mesh == null:
		return
	_mesh_y = _mesh.position.y
	_flash_bodies.clear()

	# 색은 반드시 override 로 덮는다 — 메시/glb 안의 머티리얼은 씬 인스턴스끼리
	# 공유되므로, 직접 칠하면 한 종류의 색이 다른 종류까지 물들인다.
	# Body/Outline 은 스켈레톤 밑에 있어 경로가 임포터 사정에 따라 변한다 — find_child 로 찾는다.
	if use_ant:
		var body := ant.find_child("Body", true, false) as MeshInstance3D
		if body != null:
			var pair := type_materials(type_id)
			for i in mini(pair.size(), body.mesh.get_surface_count()):
				body.set_surface_override_material(i, pair[i])
			# 서피스 2/3 = 단추 눈. 조명을 안 받는 평면 색으로 덮는다 (2026-08-15).
			var eyes := eye_materials()
			for i in eyes.size():
				var s := 2 + i
				if s < body.mesh.get_surface_count():
					body.set_surface_override_material(s, eyes[i])
			# 서피스 4 = 배의 마디 먹선. 셀 음영을 입히지 않는다 — 그늘진 쪽에서 선이
			# 바탕색과 붙어 사라지면 마디가 안 읽힌다 (콩벌레와 같은 판단).
			if body.mesh.get_surface_count() > 4:
				body.set_surface_override_material(4, ink_material())
			_flash_bodies.append(body)
		var outline := ant.find_child("Outline", true, false) as MeshInstance3D
		if outline != null:
			outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			outline.set_surface_override_material(0, ink_material())
		_anim = ant.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if _anim != null:
			# 블렌더 액션명은 "walk-loop"지만 Godot 임포터가 -loop 접미사를 **루프 플래그로
			# 소비하고 떼어낸다** — 임포트 후 이름은 "walk"고 루프는 이미 켜져 있다.
			_anim.play(&"walk")
	elif use_pill:
		var pbody := pill.find_child("Body", true, false) as MeshInstance3D
		if pbody != null:
			var mats := pillbug_materials()
			for i in mini(mats.size(), pbody.mesh.get_surface_count()):
				pbody.set_surface_override_material(i, mats[i])
			_flash_bodies.append(pbody)
		var poutline := pill.find_child("Outline", true, false) as MeshInstance3D
		if poutline != null:
			poutline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			poutline.set_surface_override_material(0, ink_material())
		_anim = pill.find_child("AnimationPlayer", true, false) as AnimationPlayer
		_pill = true
		# 펴진 몸이 성을 뚫지 않는 거리에서 멈춘다. 크기를 바꿔도 따라오도록 scale 로 계산한다.
		stats.set_base(Stats.ATTACK_RANGE,
			PILL_BASE_HALF + PILL_REACH_UNCURLED * scale.x + PILL_CLEARANCE)
		if _anim != null:
			_anim.play(&"roll")     # 콩벌레는 말린 채 굴러서 등장한다 (유저 스펙)
	elif use_rhino:
		# 파트가 6개(머리/가슴/배/다리 앞·중간·뒤)라 사슴벌레와 같은 방식으로 순회한다.
		var rmats := rhino_materials()
		for part in RHINO_PARTS:
			var mi := rhino.find_child(String(part), true, false) as MeshInstance3D
			if mi != null:
				for i in mi.mesh.get_surface_count():
					var src := mi.mesh.surface_get_material(i)
					var slot := rhino_slot_of(src.resource_name if src != null else "")
					if slot >= 0:
						mi.set_surface_override_material(i, rmats[slot])
				_flash_bodies.append(mi)
			var rink := rhino.find_child(String(part) + "Ink", true, false) as MeshInstance3D
			if rink != null:
				rink.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				rink.set_surface_override_material(0, ink_material())
		_anim = rhino.find_child("AnimationPlayer", true, false) as AnimationPlayer
		_rhino = true
		if _anim != null:
			_anim.play(&"walk")
	elif d.has("color"):
		blob.material_override = blob_material(type_id)
	# ⚠️ 인위적 접지 그림자는 **개미에게만** 준다 (유저 지시 2026-08-14).
	#    콩벌레·장수풍뎅이는 몸집이 커서 태양 그림자가 그 자체로 충분히 읽힌다 —
	#    거기까지 타원을 깔면 그림자가 두 겹으로 겹쳐 지저분해진다.
	#    개미만 작고 납작해서 진짜 그림자가 몸 밑에 통째로 숨는다.
	if use_ant:
		_add_ground_shadow(_mesh)

func _physics_process(delta: float) -> void:
	# 날아가는 동안은 이동/공격을 하지 않는다
	if _airborne:
		_air_vel.y -= AIR_GRAVITY * delta
		global_position += _air_vel * delta
		rotation.y += delta * 6.0
		var floor_y := Terrain.h(global_position)
		if global_position.y <= floor_y:
			global_position.y = floor_y
			_airborne = false
			# ⚠️ **더한다.** 예전엔 `=` 였는데, 그러면 공중에 떠 있는 동안 걸린 이동 효과가
			#    착지하는 순간 통째로 지워진다. 충격파(띄움) + 인력(끌기)을 같이 쓰면
			#    잡졸에게 인력이 **아예 안 걸리는** 걸로 나타났다 (2026-08-25 실측:
			#    인력만 -5.99 / 충격파+인력 +6.34). 앞으로 만들 이동 효과 전부가 같은 함정에 빠진다.
			_slide += Vector3(_air_vel.x, 0.0, _air_vel.z) * 0.25   # 착지 후 조금 미끄러진다
		return

	# 밀림은 걷기와 동시에 일어난다 (걸으면서 뒤로 밀리는 느낌)
	if _slide.length_squared() > 0.0025:
		global_position += _slide * delta
		_slide = _slide.lerp(Vector3.ZERO, clampf(SLIDE_DAMP * delta, 0.0, 1.0))
	else:
		_slide = Vector3.ZERO

	# 비틀거리는 동안은 전진하지 않는다 (밀림만 적용된다)
	if _stagger > 0.0:
		_stagger -= delta
		return

	if target == null:
		return
	_anim_lod()

	var to_target := target.global_position - global_position
	to_target.y = 0.0
	var dist := to_target.length()
	# ⚠️ 방향 결정은 **한 곳에서만** 한다 (_steer_dir). 예전엔 여기에 흐름장 섞는 코드가
	#    따로 있었는데, 콩벌레 쪽만 새 함수로 옮기고 이쪽이 남아서 **걷는 벌레만** 평지에서도
	#    8방향으로 꺾여 다녔다 (유저 지적 2026-08-16: "정해진 경로가 있는 것처럼 걷는다").
	to_target = _steer_dir(to_target, dist)

	# 걷기 재생 속도를 실제 이동속도에 묶는다 — 러너의 다리는 빨리, act 배율도 자동 반영.
	# 매 프레임 갱신: 스폰 직후 add_pct 로 속도가 바뀌므로 _ready 에서 한 번 읽으면 틀린다.
	# 콩벌레는 _pill_update 가 상태별(구르기/걷기/공격)로 직접 정한다.
	if _anim != null and not _pill and not _rhino:
		# ⚠️ **값이 실제로 바뀔 때만 쓴다.** AnimationMixer 는 속성을 건드리면 내부 캐시를
		#    다시 잡는 일이 있어서, 매 프레임 같은 값을 넣는 것만으로도 비싸다.
		var want := _walk_scale()
		if absf(want - _anim.speed_scale) > 0.01:
			_anim.speed_scale = want

	if _pill and _pill_update(dist, delta):
		return                             # 펴는 중 — 제자리

	_attacking = dist <= stats.get_v(Stats.ATTACK_RANGE) + RANGE_EPS
	if _rhino:
		_rhino_anim(_attacking)
	if not _attacking:
		# 사거리를 **넘어서 들어가지 않는다**. 그냥 한 프레임치를 더하면 마지막 한 걸음이
		# 사거리 안쪽으로 최대 (속도 × delta) 만큼 파고든다 — 러너는 9.45u/s 라 0.16 이고,
		# PILL_CLEARANCE(0.05)로는 못 덮는다. 그만큼 코가 성 벽을 뚫고 들어간다.
		var step: float = stats.get_v(Stats.SPEED) * delta
		var move := to_target / dist * minf(step, dist - stats.get_v(Stats.ATTACK_RANGE))
		global_position = _walk(global_position, move)
		# 지면 위를 걷는다 (2026-08-16). ⚠️ **움직인 뒤에** 높이를 읽어야 한다 —
		# 움직이기 전에 읽으면 그 프레임 이동거리만큼 지면과 어긋난 채로 남는다
		# (검증에서 0.19 만큼 떠 있었다).
		global_position.y = Terrain.h(global_position)
		# 진행 방향을 보면서 **경사에 눕는다**.
		# ⚠️ look_at 을 먼저 부르면 안 된다 — look_at 은 위쪽을 매 프레임 수직으로 되돌리므로
		#    그 뒤에 눕혀봐야 다음 프레임에 다시 세워진다 (실측: 27도 경사에서 몸은 0도).
		#    앞 방향과 지면 법선으로 **basis 를 통째로** 세운다.
		_face_and_tilt(to_target, delta)
	else:
		# 붙어서 때리는 동안 살짝 들썩이는 모션 (개미 키 0.7 기준 — 키의 30% 쯤)
		# 콩벌레·장수풍뎅이는 attack 애니가 대신한다 — 들썩임까지 겹치면 이중 모션.
		if not _pill and not _rhino:
			_mesh.position.y = _mesh_y + absf(sin(float(Time.get_ticks_msec()) * 0.012)) * 0.2
		if target.has_method("take_damage"):
			target.take_damage(stats.get_v(Stats.DAMAGE) * delta)

## 앞이 뚫렸는지 확인하는 거리. 짧으면 코앞의 벽만 보고 흐름장을 늦게 켜서 벽에 부딪히고,
## 길면 먼 지형 때문에 평지에서도 흐름장을 쓰게 된다.
const STRAIGHT_PROBE := 12.0

## 성 쪽으로 가야 할 방향. 절벽을 뚫고 직진하지 않도록 흐름장을 크게 싣는다.
## 성 가까이(사거리 3배)에서는 흐름장 대신 성을 직접 겨눈다 — 격자 해상도 때문에
## 마지막 한 칸이 어긋난다.
## ⚠️ **굴러오는 콩벌레도 이걸 써야 한다.** 예전엔 콩벌레가 자기 코드에서 성으로 직진해서
##    길도 지형도 무시하고 산을 뚫고 지나갔다 (유저 지적 2026-08-16).
func _steer_dir(to_target: Vector3, dist: float) -> Vector3:
	if dist <= stats.get_v(Stats.ATTACK_RANGE) * 3.0:
		return to_target
	# ⚠️ 흐름장은 **성으로 가는 길**만 안다. 목표가 성이 아니면(검증용 가짜 목표 등)
	#    흐름을 쓰면 엉뚱한 데로 간다 — 그땐 그냥 목표를 향한다.
	if target == null or not target.is_in_group(&"base"):
		return to_target
	var nav := _nav()
	if nav == null:
		return to_target
	# ⚠️ **앞이 뚫려 있으면 그냥 직진한다.** 흐름장은 8방향으로만 방향을 주기 때문에,
	#    평지에서까지 흐름을 크게 실으면 벌레가 있지도 않은 장애물을 피하듯 지그재그로
	#    꺾인다 (유저 지적 2026-08-16: "지형과 경사가 있는 것마냥 피해서 움직인다").
	#    길찾기는 **막혔을 때만** 쓰는 게 맞다.
	var g := Terrain.ground()
	var dir := to_target.normalized()
	var probe: float = minf(dist, STRAIGHT_PROBE)
	if NavMap.passable(g, global_position, global_position + dir * probe) \
			and nav.is_walkable(global_position + dir * probe):
		return to_target
	var f := nav.flow(global_position)
	if f == Vector3.ZERO:
		return to_target
	# 흐름을 크게 실어야 한다 — 성 방향을 세게 섞으면 벌레가 절벽에 붙어 제자리걸음을 한다.
	return (f * 4.0 + dir).normalized() * dist

## 지면 경사에 맞춰 눕힌다 (유저 지시 2026-08-16). 발만 지형을 따르고 몸이 수직으로 서 있으면
## 비탈길에서 벌레가 공중에 떠 보인다.
## ⚠️ 한 번에 확 눕히면 계단 한 칸을 넘을 때마다 홱홱 꺾인다. **천천히 따라가게** 섞는다.
## ⚠️ 눕힌 뒤에도 **앞 방향은 유지해야 한다** — 법선만 갈아끼우면 진행 방향이 틀어진다.
const TILT_RATE := 8.0        ## 초당 얼마나 빨리 경사를 따라가나
const TILT_MAX := 0.7         ## 최대 기울기 (cos). 절벽 옆을 지날 때 뒤집히지 않게 제한.

func _face_and_tilt(fwd_flat: Vector3, delta: float) -> void:
	var g := Terrain.ground()
	if g != null and g.is_flat:
		# 평지에서는 눕힐 게 없다 — 방향만 보고 끝낸다 (계산 절약).
		if fwd_flat.length() > 0.001:
			look_at(global_position + Vector3(fwd_flat.x, 0.0, fwd_flat.z), Vector3.UP)
			scale = Vector3.ONE * _body_scale
		return
	var n := Terrain.normal(global_position)
	if n.y < TILT_MAX:
		n = n.lerp(Vector3.UP, (TILT_MAX - n.y) / maxf(TILT_MAX, 0.001)).normalized()
	# 위쪽은 **따로 들고 있으면서** 천천히 지면 법선을 따라간다.
	_up = _up.slerp(n, clampf(TILT_RATE * delta, 0.0, 1.0)).normalized()
	var fwd := fwd_flat
	fwd.y = 0.0
	if fwd.length() < 0.001:
		return
	fwd = fwd.normalized()
	var right := fwd.cross(_up)
	if right.length() < 0.001:
		return
	right = right.normalized()
	var fwd2 := _up.cross(right).normalized()
	# ⚠️ 스케일을 basis 에서 다시 읽어 곱하면 프레임마다 조금씩 어긋나 결국 0 이 된다
	#    (실측: up 이 (0,0,0) 이 됐다). 종류별 스케일을 따로 들고 있다가 마지막에 준다.
	global_transform.basis = Basis(right, _up, -fwd2)
	scale = Vector3.ONE * _body_scale

## 한 걸음. **오를 수 없는 턱은 막는다** — 흐름장은 방향을 권할 뿐이라, 이게 없으면
## 벌레가 계단식 절벽으로 걸어 들어가 한 칸씩 순간이동하듯 올라간다 (검증에서 잡혔다).
## 정면이 막히면 X/Z 중 갈 수 있는 쪽으로 미끄러진다 — 벽을 따라 흐르게 하는 흔한 처리다.
func _walk(from: Vector3, move: Vector3) -> Vector3:
	# 한 프레임 이동은 아주 짧아서(≈0.06유닛) 높이차로 막으면 계단을 야금야금 오른다.
	# **기울기**로 재고, 이동 거리가 짧아도 판정이 흔들리지 않게 최소 거리를 준다.
	var g := Terrain.ground()
	var nav := _nav()
	var dist := move.length()   # ⚠️ 변수명 `len` 은 내장 함수를 가린다 — 쓰지 말 것
	if dist < 0.0001:
		return from
	var reach := maxf(dist, 0.6)
	var dir := move / dist
	# ⚠️ 이미 길 밖에 있는 경우(넉백으로 튕겨나갔거나, 길 밖에서 태어났거나)에는 통행 규칙을
	#    풀어준다. 안 그러면 영영 못 움직이고 그 자리에 굳는다 — 실제로 콩벌레 검증이
	#    그렇게 멈춰 섰다. 경사 제한은 그대로라 절벽은 여전히 못 오른다.
	var stuck_outside: bool = nav != null and not nav.is_walkable(from)
	# 정면이 막히면 좌우로 조금씩 틀어 본다 — 부챗살로 훑으면 벽을 따라 자연스럽게 흐른다.
	for deg in [0.0, 22.0, -22.0, 45.0, -45.0, 70.0, -70.0, 95.0, -95.0]:
		var d := dir.rotated(Vector3.UP, deg_to_rad(deg))
		var to := from + d * dist
		# 두 가지를 다 통과해야 발을 딛는다:
		#   1) 기울기 — 절벽을 기어오르지 못하게
		#   2) **걸을 수 있는 곳인가** — 길과 벌판만. 기울기만으로 막으면 완만한 산허리로
		#      새어 올라간다 (유저 지시 2026-08-16: "벌레가 이쪽 길로만 오도록").
		if not NavMap.passable(g, from, from + d * reach):
			continue
		if nav != null and not stuck_outside and not nav.is_walkable(to):
			continue
		return to
	return from

## 지면 분출에 튕겨나간다. knockback_resist 가 1이면 뜨지 않고 뒤로 밀리기만 한다.
func knockback(from: Vector3, power: float) -> void:
	if dying:
		return
	var dir := global_position - from
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.05 \
		else Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
	var resist: float = float(TYPES.get(type_id, {}).get("knockback_resist", 0.0))
	if resist >= 1.0:
		# 무거운 적: 뜨지 않고 뒤로 살짝 밀린다
		_slide = dir * power * 0.45
		_shake_visual(0.12)
		return
	_airborne = true
	_air_vel = dir * power * (1.0 - resist) * randf_range(0.8, 1.2) \
		+ Vector3.UP * power * randf_range(0.55, 0.85)

## 회오리 — **충격파 + 인력** 조합이 만드는 제3의 힘 (유저 결정 2026-08-25).
## 미는 힘과 당기는 힘이 만나면 남는 건 **접선 방향**이다: 적은 안으로도 밖으로도 아니라
## 착탄점 **주위를 돈다**. 도는 동안 성으로 가지 못하므로 이 조합이 버는 것은 피해가 아니라 **시간**이다.
##
## ⚠️ `inward` 는 비율이 아니라 **거리**다. 회오리는 인력과 **똑같이 중심까지 끌어온다**
##    (유저 지시 2026-08-25) — 돌기만 하고 안 모이면 조합이 인력보다 약해진다.
##    도는 건 연출이고, 모으는 건 인력이 하던 일 그대로다.
func swirl(center: Vector3, arc: float, inward: float) -> void:
	if dying or arc <= 0.0:
		return
	var out := global_position - center
	out.y = 0.0
	var gap := out.length()
	if gap < 0.05:
		return
	out /= gap
	# 접선 = 위 × 바깥. 부호가 도는 방향을 정한다 (전부 같은 방향이라야 회오리로 읽힌다).
	var tangent := Vector3.UP.cross(out)
	var resist: float = float(TYPES.get(type_id, {}).get("knockback_resist", 0.0))
	var soften := 1.0 - resist * 0.5
	# ⚠️ 도착할 반경을 **직접 푼다.** 접선으로 옆으로 가면 거리가 다시 벌어지므로
	#    "안쪽으로 얼마" 를 그냥 빼면 실제로는 덜 모인다 (실측: 8.00 에서 6 을 끌었는데
	#    5.14 에서 멈췄다 — 기대는 2.00). 최종 위치가 out·(gap−p) + tangent·d 이므로
	#    (gap−p)² + d² = target² 을 p 에 대해 풀면 정확히 그 반경에 앉는다.
	var target := maxf(gap - inward * soften, PULL_MIN_GAP)
	# 접선 이동이 목표 반경보다 크면 그 자리에 앉을 방법이 없다 — 접선을 줄인다.
	# 중심 가까이 있는 적만 해당하고, 멀리 있는 적이 도는 양은 그대로다.
	var d := minf(arc * soften, target)
	var pull_in := gap - sqrt(maxf(target * target - d * d, 0.0))
	_slide += (tangent * d - out * pull_in) * SLIDE_DAMP
	_shake_visual(0.08)

## 끌어당김 — knockback 의 반대편. 망치가 지면을 가격한 **그 순간** 중심으로 끌려온다.
## 순수 유틸이라 피해는 없다 (유저 지시 2026-08-25).
##
## ⚠️ 넉백과 달리 **띄우지 않는다.** 뜬 적은 공중에서 방향을 잃어 어디로 모였는지 안 읽히고,
##    착지 산란 때문에 "모았다"가 화면에서 사라진다. 바닥을 끌려오는 게 이 카드의 전부다.
## ⚠️ 거리를 지정하고 그걸 낼 속도를 역산한다. 속도를 직접 주면 SLIDE_DAMP 를 건드릴 때마다
##    끌리는 거리가 같이 변해서, 카드 수치가 무관한 상수에 묶인다.
##    감쇠가 지수라 총 이동거리 ≈ v0 / SLIDE_DAMP → v0 = 거리 × SLIDE_DAMP.
func pull(to: Vector3, distance: float) -> void:
	if dying or distance <= 0.0:
		return
	var dir := to - global_position
	dir.y = 0.0
	var gap := dir.length()
	if gap < 0.05:
		return                      # 이미 중심이다 — 밀 방향이 없다
	dir /= gap
	# knockback_resist 를 그대로 쓴다. 0 = 온전히 끌려옴, 1 = 절반만 (장수풍뎅이).
	# 안 끌려오게 막지 않는 건 유저 결정이다 — 탱커도 오되 덜 온다.
	var resist: float = float(TYPES.get(type_id, {}).get("knockback_resist", 0.0))
	var d := distance * (1.0 - resist * 0.5)
	# ⚠️ 중심을 넘어가지 않게 자른다. 넘어가면 반대편으로 튀어나가 오히려 흩어진다 —
	#    끌어모으는 카드가 적을 퍼뜨리는 그림이 된다.
	d = minf(d, gap - PULL_MIN_GAP)
	if d <= 0.0:
		return
	_slide += dir * d * SLIDE_DAMP
	_shake_visual(0.1)

## 끌려와도 이만큼은 중심에서 떨어져 선다. 0 이면 전부 한 점에 겹쳐 한 마리처럼 보인다.
const PULL_MIN_GAP := 1.2

## 균열을 처음 밟았을 때. 진행 방향 반대로 한 번 휘청 밀리고 — 그 뒤론 그냥 지나간다.
func stumble(from: Vector3) -> void:
	if dying or _airborne:
		return
	# "뒤로" = 가던 방향의 반대. 지대 중심 반대쪽으로 밀면 옆이나 앞으로 갈 수 있다.
	var back := Vector3.ZERO
	if target != null:
		back = global_position - target.global_position
	if back.length() < 0.05:
		back = global_position - from      # 목표가 없으면 지대 중심 반대쪽
	back.y = 0.0
	if back.length() > 0.05:
		_slide = back.normalized() * STUMBLE_PUSH
	_stagger = STUMBLE_STAGGER
	_shake_visual(0.16)

## 순수 시각 흔들림. 이동/AI 는 건드리지 않는다.
func _shake_visual(amount: float) -> void:
	var tw := create_tween()
	tw.tween_property(_pivot, "rotation:z", randf_range(-amount, amount), 0.05)
	tw.tween_property(_pivot, "rotation:z", 0.0, 0.14).set_trans(Tween.TRANS_SINE)

## 여진에 들려 짧게 들썩인다. 살아남은 적에게만 보이는 시각 반응 — AI 는 건드리지 않는다.
func hop() -> void:
	if dying:
		return
	var tw := create_tween()
	tw.tween_property(_pivot, "position:y", randf_range(0.35, 0.6), 0.09) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_pivot, "position:y", 0.0, 0.14) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

## 피해를 받는다. 체력이 다하면 from 방향에서 눌린 것처럼 납작해진다.
## src 는 이 피해가 **어디서 왔는가** (DamageSource). 없으면 null —
## 성벽 궁수처럼 오브젝트 시스템 밖에서 오는 피해는 아직 안 넘긴다.
## ⚠️ 기본값을 둔 건 호출부를 한 번에 다 고치지 않으려는 게 아니라, **오브젝트 시스템에
##    속하지 않는 피해가 실제로 있기 때문**이다. 오브젝트가 주는 피해는 반드시 넘길 것.
var last_src: DamageSource       ## 마지막으로 맞은 피해의 출처. die() 뒤 규칙 판정용.

func take_damage(amount: float, from: Vector3, src: DamageSource = null) -> void:
	if dying:
		return
	last_src = src
	health -= amount
	if health <= 0.0:
		die(from)

## 사망 연출 트윈. 폭연이 시체를 가로챌 때(combust) 이걸 끊고 제 연출로 바꾼다.
var _die_tw: Tween

# --- 피격 플래시 ---
const FLASH_TIME := 0.24    ## 확 달았다가 식기까지
var _flash_tw: Tween
## 구체 placeholder 전용 머티리얼 사본. 처음 맞았을 때만 만든다 —
## StandardMaterial3D 는 instance uniform 을 못 쓰고, 공유 캐시에 쓰면 같은 종류가 다 번쩍인다.
var _flash_mat: StandardMaterial3D

## 불에 데었다 (폭연·불덩이).
func flash_burn() -> void:
	_flash(FLASH_BURN)

## 물리 타격을 맞았다 (분출 바위).
func flash_hit() -> void:
	_flash(FLASH_HIT)

## 개미는 셀 셰이더의 instance uniform, 구체 placeholder 는 emission 사본.
## 죽는 중이어도 켠다 — 맞아 죽는 순간이 보여야 그 피해가 "때렸다"로 읽힌다.
func _flash(col: Color) -> void:
	if _flash_tw != null and _flash_tw.is_valid():
		_flash_tw.kill()         # 연달아 맞으면 다시 처음부터 (겹치면 서로 값을 되돌린다)
	var tw := create_tween()
	_flash_tw = tw
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var blob := _mesh as MeshInstance3D
	if blob != null:
		if _flash_mat == null:
			var src := blob.material_override as StandardMaterial3D
			_flash_mat = src.duplicate() if src != null else StandardMaterial3D.new()
			_flash_mat.emission_enabled = true
			blob.material_override = _flash_mat
		_flash_mat.emission = col
		_flash_mat.emission_energy_multiplier = FLASH_ENERGY
		tw.tween_property(_flash_mat, "emission_energy_multiplier", 0.0, FLASH_TIME)
		return
	# ⚠️ 예전엔 "Body" 자식 하나만 찾았다. 장수풍뎅이(헤비)는 파트가 6개라 그 규칙으로는
	#    **맞아도 안 번쩍인다** — 모델을 갈아끼우면서 조용히 사라질 뻔한 반응이다.
	#    셀 셰이더를 쓰는 파트 전부에 건다 (먹선 헐은 unshaded 라 대상이 아니다).
	if _flash_bodies.is_empty():
		return
	for b in _flash_bodies:
		b.set_instance_shader_parameter(&"flash_col", col)
		b.set_instance_shader_parameter(&"flash", 1.0)
	tw.tween_method(func(v: float) -> void:
		for b in _flash_bodies:
			b.set_instance_shader_parameter(&"flash", v), 1.0, 0.0, FLASH_TIME)

## 망치에 눌려 납작해지며 죽는다.
func die(from := Vector3.INF) -> void:
	if dying:
		return
	dying = true
	died.emit()

	# 즉시 그룹에서 뺀다: 시체를 또 때리거나 SWARM 수에 세지 않도록.
	remove_from_group("enemies")
	set_physics_process(false)
	if _anim != null:
		_anim.pause()      # 납작해진 시체가 계속 걸으면 곤란하다

	# 충격 지점 반대쪽으로 살짝 밀려나며 퍼진다
	var slide := Vector3.ZERO
	if from != Vector3.INF:
		var away := global_position - from
		away.y = 0.0
		if away.length() > 0.01:
			slide = away.normalized() * randf_range(0.15, 0.45)
	_pivot.rotation.y = randf_range(0.0, TAU)   # 퍼진 모양이 매번 다르게

	var tw := create_tween()
	_die_tw = tw
	tw.set_parallel(true)
	# 눌림: 위아래로 찌부, 옆으로 퍼짐
	tw.tween_property(_pivot, "scale", Vector3(randf_range(1.25, 1.5), 0.08, randf_range(1.25, 1.5)),
		SQUASH_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_pivot, "position", _pivot.position + slide,
		SQUASH_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 납작한 채로 잠깐 남았다가, 옆으로 오므라들며 소멸
	tw.chain().tween_interval(SPLAT_HOLD)
	tw.chain().tween_property(_pivot, "scale", Vector3(0.05, 0.05, 0.05),
		FADE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(queue_free)

## 불에 타 사라지는 시체 — **종이가 타듯이** 구멍이 번지며 재가 되어 날아간다.
## 분화구 불덩이에 죽은 적이 이 죽음을 쓴다 (유저 지시 2026-08-14).
##
## ⚠️ 우클릭 망치가 소각되는 연출(_evaporate)과 **같은 셰이더**를 쓴다. 불에 사라지는
##    문법이 게임 안에서 하나여야 "같은 불"로 읽힌다.
## ⚠️ 재질을 종류로 갈아끼운다 (셀 -> cel_burn / 먹선 -> ink_burn). 모델마다 파트 수와
##    이름이 다르므로 **현재 꽂혀 있는 재질의 타입**을 보고 판단한다 — 이름 규칙에
##    기대면 개미(Body/Outline)와 장수풍뎅이(6파트+Ink)에서 각각 따로 짜야 한다.
## ⚠️ burn 은 discard 기반이라 불투명 파이프라인에 남는다 — 타는 동안에도 그림자가
##    유지되고 뚫린 구멍이 그림자에도 그대로 뚫린다 (알파 페이드로는 안 되는 부분).
const CelBurnShader := preload("res://shaders/cel_burn.gdshader")
const InkBurnShader := preload("res://shaders/ink_burn.gdshader")
const BURN_TIME := 1.2   ## 0.75 -> 1.2 (유저 지시 2026-08-14)

func burn_away() -> void:
	if _die_tw != null and _die_tw.is_valid():
		_die_tw.kill()          # 납작 트윈을 가로챈다 (queue_free 예약까지 같이 죽는다)
	_pivot.scale = Vector3.ONE
	# ⚠️ die() 가 **이미 몸을 랜덤한 방향으로 돌려놨다** (납작해진 시체가 매번 다른 모양으로
	#    퍼지게 하려는 것). 그 죽음을 가로채는 연출은 회전을 반드시 되돌려야 한다 —
	#    안 그러면 걷던 방향 그대로 죽는 게 아니라 **몸이 홱 돌아간 뒤** 연출이 시작된다
	#    (장수풍뎅이처럼 길고 뿔 달린 몸에서 특히 티가 난다, 유저 제보 2026-08-14).
	#    위치도 같이 되돌린다 — die() 의 밀림 트윈이 중간까지 갔을 수 있다.
	_pivot.rotation = Vector3.ZERO
	_pivot.position = Vector3.ZERO
	var burns: Array[ShaderMaterial] = []
	for node in _mesh.find_children("*", "MeshInstance3D", true, false):
		_swap_surface_to_burn(node as MeshInstance3D, burns)
	if _mesh is MeshInstance3D:                 # 구체 placeholder
		_swap_surface_to_burn(_mesh as MeshInstance3D, burns)
	_spawn_ash()
	var tw := create_tween()
	_die_tw = tw
	tw.tween_method(func(d: float) -> void:
		for m in burns:
			m.set_shader_parameter("dissolve", d),
		0.0, 1.0, BURN_TIME)
	tw.tween_callback(queue_free)

func _swap_surface_to_burn(mi: MeshInstance3D, burns: Array[ShaderMaterial]) -> void:
	if mi == null or mi.mesh == null:
		return
	for i in mi.mesh.get_surface_count():
		var src: Material = mi.get_surface_override_material(i)
		if src == null:
			src = mi.material_override
		if src == null:
			src = mi.mesh.surface_get_material(i)
		var bm := ShaderMaterial.new()
		if src is ShaderMaterial:
			# 셀 서피스 — 색·경계를 그대로 물려받아 타기 전과 룩이 같다
			bm.shader = CelBurnShader
			for k in ["light_tone", "dark_tone", "threshold"]:
				bm.set_shader_parameter(k, (src as ShaderMaterial).get_shader_parameter(k))
		elif src is StandardMaterial3D:
			bm.shader = InkBurnShader
			bm.set_shader_parameter("col", (src as StandardMaterial3D).albedo_color)
		else:
			continue
		bm.set_shader_parameter("dissolve", 0.0)
		mi.set_surface_override_material(i, bm)
		burns.append(bm)

## 타는 경계에서 피어오르는 재. 몸 크기에 맞춰 방출 상자를 잡는다 —
## 고정값으로 두면 개미(1.3)와 장수풍뎅이(9)에서 양이 전혀 안 맞는다.
func _spawn_ash() -> void:
	var ab := AABB()
	var first := true
	for node in _mesh.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var a := mi.get_aabb()
		ab = a if first else ab.merge(a)
		first = false
	if first:
		return
	var sz := ab.size * scale.x * (_mesh as Node3D).scale.x
	var p := CPUParticles3D.new()
	p.name = "BurnAsh"
	p.emitting = false        # 자리를 잡기 전에 켜면 원점에서 터진다 (ImpactDust 와 같은 함정)
	p.amount = clampi(int(sz.length() * 26.0), 24, 220)
	p.lifetime = 1.2
	p.one_shot = true
	p.explosiveness = 0.15    # 한 번에 터지지 않고 타들어가는 동안 계속 올라온다
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(sz.x * 0.45, sz.y * 0.25, sz.z * 0.45)
	p.direction = Vector3.UP
	p.spread = 40.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.9
	p.gravity = Vector3(0.4, 1.9, 0.4)   # 위로 + 옆으로 — 곧게 오르면 연기 기둥이 된다
	p.damping_min = 0.2
	p.damping_max = 0.8
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.25))
	p.scale_amount_curve = curve
	# 갓 태어난 재는 잉걸빛, 식으며 회색, 끝에서 투명
	var g := Gradient.new()
	g.set_color(0, Color(0.922, 0.588, 0.38, 0.95))   # #eb9661
	g.set_color(1, Color(0.529, 0.522, 0.486, 0.0))   # #87857c -> 투명
	g.add_point(0.18, Color(0.529, 0.522, 0.486, 0.9))
	g.add_point(0.65, Color(0.388, 0.4, 0.388, 0.7))  # #636663
	p.color_ramp = g
	var flake := BoxMesh.new()
	flake.size = Vector3(0.16, 0.04, 0.16) * maxf(0.35, sz.length() * 0.12)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flake.material = m
	p.mesh = flake
	add_child(p)
	p.position = Vector3(0.0, sz.y * 0.4, 0.0)
	p.emitting = true

## 폭연 예정 시체: 납작해지는 대신 **부풀어 오르다 터진다**.
## t초 뒤가 폭발 시점 — 실제 피해와 폭발 이펙트는 Deflagration 이 같은 타이밍에 일으키고,
## 여기는 몸뚱이 연출만 맡는다: ①점점 부풀고 ②금색으로 달아오르고(heat) ③균열 틈으로
## 빛줄기가 새어나오고 ④제자리 진동이 점점 빨라지다가, 끝나는 순간 사라진다(터졌으니까).
func combust(t: float) -> void:
	if _die_tw != null and _die_tw.is_valid():
		_die_tw.kill()          # 납작 트윈을 가로챈다 (queue_free 예약까지 같이 죽는다)
	_pivot.scale = Vector3.ONE
	# ⚠️ die() 가 **이미 몸을 랜덤한 방향으로 돌려놨다** (납작해진 시체가 매번 다른 모양으로
	#    퍼지게 하려는 것). 그 죽음을 가로채는 연출은 회전을 반드시 되돌려야 한다 —
	#    안 그러면 걷던 방향 그대로 죽는 게 아니라 **몸이 홱 돌아간 뒤** 연출이 시작된다
	#    (장수풍뎅이처럼 길고 뿔 달린 몸에서 특히 티가 난다, 유저 제보 2026-08-14).
	#    위치도 같이 되돌린다 — die() 의 밀림 트윈이 중간까지 갔을 수 있다.
	_pivot.rotation = Vector3.ZERO
	_pivot.position = Vector3.ZERO
	var heat_mats := _combust_heat_mats()
	var tw := create_tween()
	_die_tw = tw
	# 진동 위상을 p² 로 몰면 갈수록 빨라진다 — "곧 터진다"는 압박은 진동 가속이 만든다.
	var wob := randf_range(30.0, 40.0)
	tw.tween_method(func(p: float) -> void:
		var s := 1.0 + 0.85 * p * p
		var phase := wob * p * p * t             # 가속 진동 (t 를 곱해 실시간 기준으로)
		var amp := 0.05 * p
		_pivot.scale = Vector3(s * (1.0 + 0.06 * sin(phase)), s * (1.0 + 0.04 * sin(phase * 1.7)),
			s * (1.0 - 0.06 * sin(phase)))
		_pivot.position.x = sin(phase * 1.3) * amp
		_pivot.position.z = cos(phase) * amp
		_pivot.position.y = 0.12 * p * p
		_pivot.rotation.z = sin(phase * 0.6) * 0.08 * p
		# 달아오름은 후반에 몰아친다(p³) — 터지기 직전이 제일 밝다
		for m in heat_mats:
			if m is ShaderMaterial:
				m.set_shader_parameter("heat", p * p * p)
			else:
				m.emission_energy_multiplier = 3.0 * p * p * p,
		0.0, 1.0, maxf(t, 0.05))
	tw.tween_callback(queue_free)

## 달아오를 머티리얼 사본을 만들어 이 개체에만 붙인다 (공유 캐시를 달구면 전 개미가 익는다).
## ⚠️ 예전엔 "Body" 자식 하나만 찾았다. 장수풍뎅이(헤비)는 파트가 6개라 그 규칙으로는
##    **부풀기만 하고 달아오르지 않았다** — 피격 플래시와 똑같은 함정이다.
##    셀 메시 목록(_flash_bodies)을 그대로 쓴다: 모델이 몇 조각이든 전부 달아오른다.
func _combust_heat_mats() -> Array:
	var out := []
	for body in _flash_bodies:
		for i in body.mesh.get_surface_count():
			var m := body.get_surface_override_material(i)
			if m is ShaderMaterial:
				var c := m.duplicate() as ShaderMaterial
				body.set_surface_override_material(i, c)
				out.append(c)
	if out.is_empty() and _mesh is MeshInstance3D:   # 구체 placeholder: 스탠다드 emission
		var mo := (_mesh as MeshInstance3D).material_override
		if mo is StandardMaterial3D:
			var c2 := mo.duplicate() as StandardMaterial3D
			c2.emission_enabled = true
			c2.emission = Color(0.992, 0.82, 0.475)   # nice31 #fdd179
			c2.emission_energy_multiplier = 0.0
			(_mesh as MeshInstance3D).material_override = c2
			out.append(c2)
	return out
