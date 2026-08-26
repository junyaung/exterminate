class_name Main
extends Node3D

## 전투 공간 루트. 웨이브 스폰, HUD, 승패 판정을 담당한다.
##
## 웨이브 설계 (2026-08-10, 스웜 컨셉):
## - 총 20분 = 5분짜리 액트 4개. 액트 안에서 스폰율이 선형으로 상승한다.
## - 적은 pack(무리) 단위로 뭉쳐 스폰한다 — 한두 마리씩 흘러나오면 스웜 쾌감이 없다.
## - 잡졸 체력은 끝까지 한 방(100)을 유지하고, 난이도는 "물량"으로만 올린다.
## - 기지 체력 1000 = 누수 예산. 잡졸 DPS 4 기준 총 250 적·초의 누수를 허용한다.

const EnemyScene := preload("res://scenes/enemy.tscn")
const BossScene := preload("res://scenes/boss.tscn")

const ACT_LENGTH := 300.0            ## 액트 하나 = 5분
const RUN_LENGTH := ACT_LENGTH * 4   ## 총 20분
## 성능 보호용 동시 생존 상한.
## ⚠️ 600 -> 450 (2026-08-27). 웨이브 8~10 은 원래 이 상한에 붙어 평평해지는 구간이라,
##    이 값이 곧 후반 프레임을 정한다. 실측(웨이브 10, tools/bench_live.gd):
##      600 — 적 591 / 드로우콜 1455 / process 24~27ms / 26~29fps
##      450 — 적 443 / 드로우콜 1118 / process 18~24ms / 41~59fps
##      400 — 적 392 / 드로우콜 1001 / process 20~22ms / 47~49fps
##    450 과 400 의 차이는 **실행별 편차 안**이다 (자동 선택 카드가 매번 달라 이펙트 양이
##    달라진다 — 같은 450 을 두 번 재서 56~59fps 와 41~42fps 가 나왔다). 그래서 더 깎지 않았다.
## ⚠️ 이건 성능 값이자 **밸런스 값**이다. 웨이브 총량(1,300)은 그대로고 동시에 나오는 수만
##    줄므로, 후반 웨이브가 길어지고 한 번에 받는 압박은 낮아진다.
##    못 태어난 수는 `suppressed` 에 쌓여 run_log 로 나간다 — 밸런스 영향은 거기서 볼 것.
const MAX_ALIVE := 450

## SURGE — 주기적으로 한 지점에서 벽처럼 쏟아지는 메가팩.
## 지속 스폰율은 대기열이라 "처리량 미만 = 무결점 / 초과 = 사망 나선" 둘뿐이다
## (시뮬 4·5차로 확인). 긴장은 지속률이 아니라 이 변동성이 만든다.
const SURGE_MIN_GAP := 75.0
const SURGE_MAX_GAP := 105.0
const SURGE_BASE := 40               ## 액트 1 서지 크기. 액트마다 +20 (최대 100)
## 24 -> 40 / 액트당 +12 -> +20 (유저 지시 2026-08-14, 물량 증량)
const SURGE_STEP := 20

## 보스(거대 사슴벌레) 등장 시각(초) — **액트 경계**. 5분을 버텼다는 표식이자,
## 서지와 다른 종류의 변동성이다: 서지는 "물량이 벽처럼 온다", 보스는 "한 놈을 오래 상대한다".
## ⚠️ 20분(=RUN_LENGTH) 직전은 비워뒀다 — 마지막 보스를 넣으려면 여기에 한 줄 더.
const BOSS_TIMES: Array[float] = [300.0, 600.0, 900.0]

## --- 웨이브 (유저 결정 2026-08-18) --------------------------------------------
## 5분 액트 4개 -> **10 웨이브**. 액트는 단위가 너무 길어서 "지금 몇 번째 고비인지"가
## 안 읽혔다. 웨이브는 **정해진 수를 다 뱉고 남은 적을 전부 잡으면** 끝난다 —
## 시간이 아니라 결과가 진행을 정한다. 그래서 **런 길이는 고정이 아니다**
## (잘하면 짧고 밀리면 길다. 유저 결정: "길이는 결과에 맡김").
##
## ⚠️ 아래 수치는 **첫 판**이다. 예전 액트 곡선은 20분 내내 흘려보내는 전제라 총량이
##    2만 마리가 넘었는데, 전멸 조건에서는 그 물량을 다 잡아야 웨이브가 넘어간다.
##    그래서 총량을 5천 대로 줄여 잡았다. 시뮬(tools/sim_run.gd)로 재보고 조정할 것.
const WAVE_COUNT := 10
## 웨이브를 깬 뒤 숨 돌리는 시간. 0 이면 바로 다음 웨이브가 쏟아진다.
const WAVE_LULL := 4.0
## count      이 웨이브가 뱉을 총 마리 수 (이걸 다 뱉고 다 죽어야 웨이브 종료)
## rate_start/end  초당 스폰율 (웨이브 안에서 선형 보간 — 뒤로 갈수록 몰아친다)
## pack       한 번에 뭉쳐 나오는 무리 크기
## boss       이 웨이브 시작에 보스가 나오는가 (보스도 적이라 잡아야 웨이브가 끝난다)
const WAVES: Array[Dictionary] = [
	{count = 80,   rate_start = 2.5,  rate_end = 4.0,  pack_min = 6,  pack_max = 10, speed_mult = 1.00, boss = -1},
	{count = 120,  rate_start = 4.0,  rate_end = 6.0,  pack_min = 8,  pack_max = 13, speed_mult = 1.00, boss = -1},
	{count = 180,  rate_start = 6.0,  rate_end = 9.0,  pack_min = 10, pack_max = 16, speed_mult = 1.05, boss = -1},
	{count = 260,  rate_start = 9.0,  rate_end = 13.0, pack_min = 12, pack_max = 19, speed_mult = 1.05, boss = 0},
	{count = 360,  rate_start = 13.0, rate_end = 18.0, pack_min = 14, pack_max = 22, speed_mult = 1.10, boss = -1},
	{count = 480,  rate_start = 18.0, rate_end = 24.0, pack_min = 16, pack_max = 26, speed_mult = 1.10, boss = -1},
	{count = 640,  rate_start = 24.0, rate_end = 31.0, pack_min = 18, pack_max = 30, speed_mult = 1.15, boss = 1},
	{count = 820,  rate_start = 31.0, rate_end = 39.0, pack_min = 20, pack_max = 34, speed_mult = 1.20, boss = -1},
	{count = 1050, rate_start = 39.0, rate_end = 48.0, pack_min = 22, pack_max = 38, speed_mult = 1.25, boss = -1},
	{count = 1300, rate_start = 48.0, rate_end = 60.0, pack_min = 24, pack_max = 42, speed_mult = 1.30, boss = 2},
]
## 나중에 나올수록 단단하다. 체력과 경험치에 같이 곱한다.
const BOSS_SCALE: Array[float] = [1.0, 1.6, 2.4]

## 몹 등장 규칙. 위에서부터 검사해 **처음 맞는 것**을 쓰고, 아무것도 안 맞으면 grunt.
## 새 몹을 넣으려면 Enemy.TYPES 에 한 줄, 여기에 한 줄.
##   every    : N번째 스폰마다 (필수)
##   from_act : 이 액트(1-4)부터 등장 (없으면 처음부터)
## ⚠️ 위에서부터 첫 매치를 쓰므로 **순서가 곧 우선순위**다 (배수가 겹치면 위가 가져간다).
## 물량 조정 (유저 지시 2026-08-18: "개미 늘리고 탱커 줄이기") — heavy 5 -> 10.
## 20마리당 **grunt 12 / runner 4 / heavy 4 -> grunt 14 / runner 4 / heavy 2** (실측).
## ⚠️ 러너는 안 늘어난다 — 20번째는 4의 배수이자 10의 배수라 **위에 있는 heavy 가 계속 가져간다.**
##    (처음엔 러너가 5로 는다고 적었다가 계산해보고 고쳤다. 배수가 겹치는 자리는 눈으로 세지 말 것.)
const SPAWN_RULES: Array[Dictionary] = [
	{type = &"heavy", every = 10},
	{type = &"runner", every = 4},
]

## 액트별 스폰 테이블. rate = 초당 마리 수(액트 안에서 선형 보간),
## pack = 한 번에 뭉쳐 나오는 무리 크기, speed_mult = 이동속도 배율.
## ⚠️ 물량 대폭 증량 (유저 지시 2026-08-14). 밸런스를 **약화가 아니라 물량으로** 잡는 방향 —
##    떼로 나오면 잡는 맛이 살고, 경험치가 늘어 카드 회전이 빨라지고, 그만큼 다양한
##    공격 조합을 볼 수 있다. 특수에 여진까지 붙어 화력이 크게 오른 것도 여기서 받는다.
##    배율: 스폰율 ×1.8, 무리 크기 ×1.6 (초반은 조금 더 완만하게).
const ACTS: Array[Dictionary] = [
	{rate_start = 3.5, rate_end = 10.0, pack_min = 8, pack_max = 13, speed_mult = 1.00},
	{rate_start = 10.0, rate_end = 21.0, pack_min = 13, pack_max = 21, speed_mult = 1.05},
	{rate_start = 21.0, rate_end = 34.0, pack_min = 16, pack_max = 27, speed_mult = 1.15},
	{rate_start = 34.0, rate_end = 60.0, pack_min = 22, pack_max = 38, speed_mult = 1.25},
]

## 카메라 yaw. 아이소메트릭이라 월드 축과 화면 축이 45도 어긋나 있다.
## Camera3D 의 rotation_degrees.y 와 반드시 같아야 한다.
const VIEW_YAW := 45.0

# 배치는 화면 기준으로 적는다: +x = 화면 오른쪽, +z = 화면 아래. to_world() 로 변환.
# 화면 밖 스폰 존. Vector4 = (x_min, x_max, z_min, z_max)
# ⚠️ **스폰 자체는 이제 아크(SPAWN_ARC_*)가 정한다.** 아래 사각형은 프롭 배치 제외 영역과
#    블렌더 맵의 길 마스크(map_build.py)가 아직 참조하므로 남겨둔 것 — 둘 중 하나를 되살릴
#    때는 아크와 어긋나지 않는지 확인할 것.
## ⚠️ 시야 확대(2026-08-16, size 30 -> 75.5)에 맞춰 **전부 ×2.5167** 한 값이다.
## 원래 수치는 (29,36,4,16) / (-8,16,23,30) — 화면 폭 30 기준으로 손으로 잡았던 자리다.
const SPAWN_ZONES: Array[Vector4] = [
	Vector4(72.98, 90.60, 10.07, 40.27),    # 오른쪽 아래
	Vector4(-20.13, 40.27, 57.88, 75.50),   # 아래
]

## 위 스폰 존이 적힌 기준 시야 = Camera3D.size. 둘이 어긋나면 존이 화면 안으로 들어와
## 적이 눈앞에서 튀어나온다. CameraTuner 로 줌을 바꾸면 `view_scale` 이 그만큼 밀어준다.
## ⚠️ 존을 밀면 **행군 거리도 같이 늘어난다** — 지금 기준 도달 시간은
##    러너 12초 / 개미 22초 / 헤비 36초 (예전 4.8/8.6/14.3 의 2.5배).
const VIEW_SIZE := 75.5
static var view_scale := 1.0

## 스폰 존 하나를 현재 시야에 맞게 밀어낸 값.
static func _zone(z: Vector4) -> Vector4:
	return z * view_scale

# --- 스폰 아크 ---------------------------------------------------------------
## ⚠️ 예전엔 **사각형 존 두 개**였다. 그 사이(오른쪽 존과 아래쪽 존 사이의 모서리)가 비어서
##    벌레가 두 줄로만 몰려오고 가운데가 뻥 뚫려 보였다 (유저 지적 2026-08-16).
##    이제 **성을 중심으로 한 부채꼴 띠**에서 고르게 뽑는다 — 빈틈 없이 한 줄로 이어진다.
## 각도 0도 = 화면 오른쪽, 90도 = 화면 아래. 12~82도면 오른쪽부터 아래까지 감싼다.
const SPAWN_ARC_DEG := Vector2(12.0, 82.0)
## 성에서의 거리. 화면 반폭(가로 67 / 세로 49)보다 훨씬 멀어 **전부 화면 밖**이다.
const SPAWN_ARC_R := Vector2(105.0, 125.0)
## 성의 화면 좌표. ⚠️ main.tscn 의 BaseBlock 위치와 같아야 한다.
const BASE_SCREEN := Vector2(-25.0, -25.0)

## 아크 위의 임의 지점 (화면 좌표).
static func random_spawn_screen() -> Vector2:
	var a := deg_to_rad(randf_range(SPAWN_ARC_DEG.x, SPAWN_ARC_DEG.y))
	var r := randf_range(SPAWN_ARC_R.x, SPAWN_ARC_R.y) * view_scale
	return BASE_SCREEN + Vector2(cos(a), sin(a)) * r

@onready var _base: BaseBlock = $BaseBlock
@onready var _enemies: Node3D = $Enemies
@onready var _hud: Label = $HUD/Status
var _cooldown_hud: CooldownHud
## 스폰 배율을 읽을 통로 ('신의 억제' / '전쟁의 부름'). 망치 stats 에 얹히므로 여기로 받는다.
var _stats: Stats

## 처치 -> 경험치 -> 레벨업. 카드 UI 가 leveled 신호를 받아 드래프트를 연다.
## ⚠️ 변수 초기화식으로 만들어야 한다 — CardUI/XpBar 의 `_ready()` 가 Main 보다 먼저 돈다.
var level_system := LevelSystem.new()

## 판 기록. 액트를 깰 때마다, 그리고 끝날 때 user://runs/ 에 JSON 한 장씩 쌓인다.
## ⚠️ class_name 이 아니라 preload 로 받는다 — 새 스크립트의 전역 클래스 이름은 에디터가
##    한 번 스캔해야 등록되고, 그 전까지 `--script` 헤드리스 실행이 파스 에러로 죽는다.
const RunLogScript := preload("res://scripts/run_log.gd")
var run_log := RunLogScript.new()
var _act_logged := 0       ## 마지막으로 기록한 액트 인덱스 (경계를 넘었는지 판정)

var elapsed := 0.0
var kills := 0
var spawned := 0
var suppressed := 0        ## MAX_ALIVE 때문에 못 태어난 수 (밸런스 리포트용)
var game_over := false
var victory := false

## 적을 내보낼 것인가. **지형을 만드는 동안은 꺼둔다** (유저 지시 2026-08-16) —
## 벌레가 돌아다니면 깎은 지형이 안 보이고, 아직 y=0 평면을 걷기 때문에 언덕을 통과한다.
## V 키로 켜고 끈다. 끄면 이미 나와 있던 적도 치운다.
var spawning := false

var _spawn_debt := 0.0     ## rate 누적치. pack 크기만큼 쌓이면 무리 하나를 뱉는다.
var _surge_in := 90.0      ## 다음 서지까지 남은 시간
var _boss_index := 0       ## 다음에 내보낼 보스 번호 (BOSS_TIMES 의 인덱스)
## --- 웨이브 상태 ---
var wave := 0              ## 지금 웨이브 (0-based). 화면에는 +1 해서 보여준다.
var wave_spawned := 0      ## 이번 웨이브에서 뱉은 수
var wave_cleared := 0      ## 지금까지 깬 웨이브 수
var _lull := 0.0           ## 남은 소강 시간 (웨이브를 깬 직후)

## 화면 기준 평면 좌표를 월드 좌표로.
static func to_world(screen_x: float, screen_z: float) -> Vector3:
	return Basis(Vector3.UP, deg_to_rad(VIEW_YAW)) * Vector3(screen_x, 0.0, screen_z)

## 스폰 존 안의 임의 지점 (월드). 분화구 불덩이가 적이 몰려오는 쪽으로 굴러가는 데 쓴다.
static func random_spawn_point() -> Vector3:
	var p := random_spawn_screen()
	return to_world(p.x, p.y)

func _ready() -> void:
	_base.destroyed.connect(_on_destroyed)
	ProjectileStats.reset()
	# 경험치 배율('성장의 축복')은 망치 stats 에 얹히므로 레벨 시스템에 그 통로를 꽂아준다.
	var hs := get_tree().get_first_node_in_group(&"hammer")
	if hs != null:
		level_system.stats = hs.stats
		_stats = hs.stats
	# L/CHG/R 쿨타임 도넛 (오른쪽 아래). 쓸지 말지 정하는 중이라 H 키로 껐다 켤 수 있다 —
	# 옵션 화면이 생기면 _cooldown_hud.enabled 에 붙이면 된다.
	_cooldown_hud = CooldownHud.new()
	add_child(_cooldown_hud)
	# 우상단 아이콘 칩 (시간·적·처치·연격·대강타). 개발용 텍스트(Status)는 그 아래로 내린다.
	$HUD.add_child(HudModules.new())
	_hud.offset_top += 96.0
	_hud.add_theme_font_size_override(&"font_size", 15)
	# 지형 길찾기. ⚠️ Ground.build() 가 이 노드를 그룹으로 찾아 다시 계산하므로
	# **지면이 처음 구워지기 전에** 트리에 있어야 한다 (Ground 의 굽기는 한 프레임 미뤄져 있다).
	var nav := NavMap.new()
	nav.name = "NavMap"
	add_child(nav)
	# 성의 자동 사격 + 성 옆 횃불 (유저 요청 2026-08-17).
	# ⚠️ 화살은 성이 부서져도 날아가야 하므로 **성의 자식이 아니라** 여기(Main) 밑에 둔다.
	var archer := CastleArcher.new()
	archer.name = "CastleArcher"
	archer.position = _base.position
	add_child(archer)
	for side in [Vector3(4.2, 0.0, 0.0), Vector3(-4.2, 0.0, 0.0)]:
		var torch := Torch.new()
		torch.position = _base.position + side
		add_child(torch)
	# 시간대 무드 조명 (T 키). ⚠️ **지면·벌레 셰이더가 컴파일되기 전에** 전역 유니폼을
	# 등록해야 하므로 다른 것들보다 먼저 붙인다 (등록 전에 컴파일되면 셰이더가 깨진다).
	var mood := Mood.new()
	mood.name = "Mood"
	add_child(mood)
	# 오른쪽 위 시계 — 하루를 3등분해 낮/노을/밤을 보여준다 (유저 요청 2026-08-18).
	# ⚠️ **Mood 를 만든 뒤에** 붙인다 — 시계는 Mood.time 하나만 읽는다.
	var clock := MoodClock.new()
	clock.name = "MoodClock"
	clock.mood = mood
	$HUD.add_child(clock)
	# 카메라 이동 (WASD / 방향키). 시점 튜너보다 먼저 붙여 입력 우선권을 준다.
	var pan := CameraPan.new()
	pan.name = "CameraPan"
	pan.cam = $Camera3D
	add_child(pan)
	# 시점 튜너 (개발용). 값이 정해지면 main.tscn 에 굽고 이 두 줄을 지우면 된다.
	var tuner := CameraTuner.new()
	tuner.cam = $Camera3D
	add_child(tuner)
	# 지형 프롭(Scatter). 2026-08-16 에 "오브젝트 다 없애고" 지시로 꺼뒀다가,
	# 2026-08-17 블렌더 실제 모델(돌·바위·나무·밑동·가지·낙엽)이 들어오면서 다시 켰다.
	#    임시 도형 프롭이 지형을 뒤덮어 지형이 안 읽혔다. 되살리려면 아래 세 줄의 주석을 풀면 된다.
	var scatter := Scatter.new()
	scatter.name = "Scatter"
	add_child(scatter)
	# 지형 스컬프트 툴 (F 키). 유저가 직접 깎은 지형은 res://layout/terrain_edit.json 에 남는다.
	var editor := TerrainEditor.new()
	editor.name = "TerrainEditor"
	add_child(editor)
	print("[main] 적 스폰 OFF 로 시작한다 — V 키로 켠다 (지형 작업용)")

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	# 0 키: 투사체 효율 상세 리포트를 콘솔에 찍는다 (HUD 요약보다 자세하다)
	if event.keycode == KEY_0:
		print(ProjectileStats.report())
	# B 키: 보스 소환 (개발용). 웨이브 어디에 넣을지는 아직 정하지 않았다.
	elif event.keycode == KEY_B:
		spawn_boss()
	# V 키: 적 스폰 켜고 끄기. 지형 작업 중엔 꺼두는 게 편하다.
	elif event.keycode == KEY_V:
		set_spawning(not spawning)
	# H 키: 쿨타임 도넛 표시 토글. 정식 옵션 화면이 생기기 전까지의 임시 통로다.
	elif event.keycode == KEY_H and _cooldown_hud != null:
		_cooldown_hud.enabled = not _cooldown_hud.enabled
		print("[hud] 쿨타임 표시: ", "ON" if _cooldown_hud.enabled else "OFF")

## 적 스폰 스위치. 끄면 살아 있는 적도 전부 치운다 — 지형을 보려고 끄는 거라
## "껐는데 아직 화면에 남아 있다" 가 되면 끈 의미가 없다.
func set_spawning(on: bool) -> void:
	spawning = on
	if not on:
		for e in get_tree().get_nodes_in_group("enemies"):
			e.queue_free()
		var boss := get_tree().get_first_node_in_group("boss")
		if boss != null:
			boss.queue_free()
	print("[main] 적 스폰: ", "ON" if on else "OFF (V 로 켜기)")

## 거대 사슴벌레를 스폰 존에 불러낸다. 한 마리만 — 이미 있으면 null.
## scale 은 체력·경험치 배율 (나중 보스일수록 크다).
func spawn_boss(power := 1.0) -> Enemy:
	if get_tree().get_first_node_in_group("boss") != null:
		return null
	var b = BossScene.instantiate()
	_enemies.add_child(b)
	b.global_position = random_spawn_point()
	b.target = _base
	# ⚠️ 체력은 **_ready 이후에** 올려야 한다 — _ready 가 stats 를 만들고 health 를 채운다.
	if power != 1.0:
		b.stats.add_pct(Stats.HEALTH, power - 1.0)
		b.health = b.stats.get_v(Stats.HEALTH)
	var reward := Enemy.xp_of(b.type_id) * power
	b.died.connect(func() -> void:
		kills += 1
		level_system.add_xp(reward))
	spawned += 1
	# 큰 놈이 발을 디뎠다 — 화면 밖에서 나타나므로 소리 대신 진동으로 알린다
	var hs := get_tree().get_first_node_in_group("hammer")
	if hs != null:
		hs._shake = maxf(hs._shake, 0.9)
	print("[boss] 거대 사슴벌레 등장 (체력 %d, 경험치 %d)" % [
		roundi(b.stats.get_v(Stats.HEALTH)), roundi(reward)])
	return b

## ⚠️ 남겨둔 호환용. 예전엔 "5분마다 오르는 액트"였고 지금은 **웨이브**가 그 자리를 대신한다.
## 난이도 곡선을 참조하던 곳들(스폰 규칙의 from_wave, 기록)이 이 값을 쓴다.
func act_index() -> int:
	return clampi(wave, 0, WAVE_COUNT - 1)

## 지금 웨이브 데이터.
func wave_data() -> Dictionary:
	return WAVES[clampi(wave, 0, WAVES.size() - 1)]

## 일반 적 출현량 배율. 카드를 안 먹었으면 1.0.
## 보스에는 안 걸린다 — '신의 억제'/'전쟁의 부름' 은 일반 적만 건드린다 (스펙).
func spawn_mult() -> float:
	return _stats.get_v(Stats.SPAWN_RATE) if _stats != null else 1.0

## 현재 시점의 초당 스폰율. 런이 끝나면 0.
## 지금 시점의 초당 스폰율. 이번 웨이브 분량을 다 뱉었으면 0.
func current_rate() -> float:
	var w: Dictionary = wave_data()
	if wave_spawned >= int(w.count) or _lull > 0.0:
		return 0.0
	var f := clampf(float(wave_spawned) / maxf(float(w.count), 1.0), 0.0, 1.0)
	return lerpf(w.rate_start, w.rate_end, f) * spawn_mult()

## 아직 쫓아오고 있는 적 수. 죽는 순간 그룹에서 빠지므로 그룹 크기가 곧 생존 수다.
func alive_count() -> int:
	return get_tree().get_nodes_in_group("enemies").size()

func _physics_process(delta: float) -> void:
	if game_over:
		return
	elapsed += delta

	# 소강 — 웨이브를 깬 직후 숨 돌리는 구간. 이 동안은 아무것도 안 나온다.
	if _lull > 0.0:
		_lull -= delta
		return

	var w: Dictionary = wave_data()

	# 웨이브 시작에 보스가 있으면 먼저 내보낸다. 보스도 적이라 **잡아야 웨이브가 끝난다**.
	if int(w.boss) >= 0 and _boss_index == int(w.boss):
		if spawn_boss(BOSS_SCALE[_boss_index]) != null:
			_boss_index += 1

	if spawning and wave_spawned < int(w.count):
		# --- 아직 뱉는 중 ---
		_spawn_debt += current_rate() * delta
		var pack := randi_range(w.pack_min, w.pack_max)
		while _spawn_debt >= float(pack):
			_spawn_debt -= float(pack)
			# ⚠️ 웨이브 분량을 **넘겨 뱉지 않는다** — 넘치면 "다 잡았는데 안 끝난다"가 된다.
			var n := mini(pack, int(w.count) - wave_spawned)
			if n <= 0:
				break
			_spawn_pack(n, w)
			wave_spawned += n
			pack = randi_range(w.pack_min, w.pack_max)
		_surge_in -= delta
		if _surge_in <= 0.0:
			_surge_in = randf_range(SURGE_MIN_GAP, SURGE_MAX_GAP)
			# 서지도 이번 웨이브 분량 안에서 뱉는다 (총량은 웨이브가 정한다).
			var burst := mini(
				maxi(1, roundi((SURGE_BASE + wave * SURGE_STEP) * spawn_mult())),
				int(w.count) - wave_spawned)
			if burst > 0:
				_spawn_pack(burst, w, 4.0)
				wave_spawned += burst
	elif spawning and alive_count() == 0:
		# --- 다 뱉었고 다 죽었다 = 웨이브 클리어 ---
		wave_cleared = wave + 1
		run_log.record(self, "wave_clear")
		print("[wave] %d/%d 클리어 — %.1f초 (누적 처치 %d)" % [
			wave + 1, WAVE_COUNT, elapsed, kills])
		if wave + 1 >= WAVE_COUNT:
			_win()
			return
		wave += 1
		wave_spawned = 0
		_spawn_debt = 0.0
		_lull = WAVE_LULL

## 몇 번째 스폰인지로 몹 종류를 정한다.
func pick_type(index: int) -> StringName:
	for rule in SPAWN_RULES:
		if rule.has("from_wave") and wave + 1 < rule.from_wave:
			continue
		if (index + 1) % int(rule.every) == 0:
			return rule.type
	return &"grunt"

func _spawn_pack(count: int, act: Dictionary, scatter := 2.5) -> void:
	var alive := alive_count()
	# 무리 중심도 아크 위에서 고른다 — 존을 고르던 때는 두 곳에서만 뭉쳐 나왔다.
	var c := random_spawn_screen()
	var center := to_world(c.x, c.y)
	for i in count:
		if alive >= MAX_ALIVE:
			suppressed += 1
			continue
		var enemy := EnemyScene.instantiate() as Enemy
		# 종류는 _ready() 에서 반영되므로 반드시 add_child 전에 정한다
		enemy.type_id = pick_type(spawned)
		_enemies.add_child(enemy)
		# 무리 중심 주변에 흩뿌린다 — 뭉쳐서 행군하는 blob 이 된다
		enemy.global_position = center + Vector3(randf_range(-scatter, scatter), 0.0, randf_range(-scatter, scatter))
		enemy.target = _base
		enemy.stats.add_pct(Stats.SPEED, act.speed_mult - 1.0)
		# 경험치는 종류별로 다르다 — 잡는 데 드는 품에 비례한다 (Enemy.TYPES 의 xp)
		var reward := Enemy.xp_of(enemy.type_id)
		enemy.died.connect(func() -> void:
			kills += 1
			level_system.add_xp(reward))
		spawned += 1
		alive += 1

func _process(_delta: float) -> void:
	if game_over:
		return
	# 시간·적·처치·연격·대강타는 HudModules(아이콘 칩)가, 거점·LV·XP 는 좌하단 카드가
	# 맡는다 (UX 가이드 2.1/2.3, 2026-08-13). 이 라벨엔 개발용 투사체 효율만 남는다 —
	# 승패 문구는 여전히 여기 쓴다 (그때는 모듈이 그리기를 멈춘다).
	_hud.text = ""
	for row in [[&"rock", "ROCK"], [&"fire", "FIRE"], [&"blast", "BLAST"]]:
		var line := ProjectileStats.line(row[0], row[1])
		if line != "":
			_hud.text += line + "\n"

## 경과 초 -> "MM:SS".
## ⚠️ 정수 나눗셈이 **의도**다 (초를 분으로 자른다). 예전엔 부르는 쪽마다 t/60 을 적어
##    "소수점이 버려진다"는 경고가 두 군데서 났다 — 한 곳에 모으고 여기서만 무시한다.
##    @warning_ignore 는 **선언문 앞**에만 붙는다. 배열 리터럴 안에 끼워 넣으면 파스 에러가
##    나고, main.gd 가 깨지면 이걸 참조하는 card_ui/xp_bar/hammer_strike 까지 연쇄로 죽는다.
static func mmss(seconds: int) -> String:
	@warning_ignore("integer_division")
	var mins := seconds / 60
	return "%02d:%02d" % [mins, seconds % 60]

func _win() -> void:
	game_over = true
	victory = true
	run_log.record(self, "victory")
	_hud.text = "VICTORY\n%s   KILLS %d\nBASE %d / %d" % [
		mmss(int(elapsed)), kills, roundi(_base.health), roundi(_base.max_health)]

func _on_destroyed() -> void:
	game_over = true
	run_log.record(self, "defeat")
	_hud.text = "BASE DESTROYED\nsurvived %s   KILLS %d" % [mmss(int(elapsed)), kills]

## 창을 닫거나 에디터에서 멈춰 끝난 판도 남긴다 — 실제 플레이 테스트는 대부분
## 승패까지 안 가고 중간에 끊긴다. 그 기록이 빠지면 표본이 이긴 판 쪽으로 쏠린다.
func _exit_tree() -> void:
	if not game_over and elapsed > 5.0:
		run_log.record(self, "quit")
