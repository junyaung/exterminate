class_name Boss
extends Enemy

## 거대 사슴벌레 — 첫 보스. **행동은 하나뿐이다**(유저 스펙): 성을 향해 걸어가다가
## 주기적으로 돌진한다. 여러 패턴을 섞지 않는 이유는 플레이어가 배울 게 하나여야
## "언제 풀차징을 아껴둘 것인가"라는 판단이 선명해지기 때문이다.
##
## 상태 흐름:
##   [멀리] WALK(5초) -> TELEGRAPH(0.8초) -> CHARGE(3배속) -> WALK ...
##                            └─ 이 동안 **풀차징 망치**로 맞으면 취소 -> STUN(1.5초, 받는 피해 +50%)
##   [성에 붙으면] SMASH_WAIT(4초) -> SMASH_WIND_UP(1초) -> 한 방 -> 반복 (타격 간격 5초)
##
## 성에 붙었을 때 잡졸처럼 매 프레임 갉지 않는 이유: 보스는 **한 방이 보여야** 보스다.
## 5초에 한 번 크게 내려찍으면 플레이어에게 "저걸 막을 시간이 5초 있다"가 읽힌다.
##
## 이 설계의 핵심은 **위험과 기회가 같은 순간에 있다**는 것: 예고 0.8초는 돌진이 온다는
## 경고이면서, 유일하게 보스를 무력화할 수 있는 창이기도 하다. 풀차징은 1초를 모아야
## 하므로 예고를 보고 시작해선 늦다 — 미리 모아두고 기다려야 한다.

const CYCLE := 5.0          ## 돌진 주기 (걷는 동안 재는 시간)
const TELEGRAPH := 0.8      ## 예고 동작
## 돌진 지속. 스펙엔 없어 1.1초로 잡았다가 **유저 요청으로 거리를 2배**로 늘렸다(2026-08-13).
## 배속(3.0)이 아니라 시간을 늘린 이유: 3배속은 유저가 정한 값이고, 배속을 6으로 올리면
## 러너(6.3)보다 빨라져 "육중한 돌진"이 아니라 순간이동처럼 보인다.
## 3배속 × 2.2초 ≈ 11.6유닛 전진 (성 앞 정지 거리 11.15보다 길어, 멀리서 시작해도 벽에서 멈춘다).
const CHARGE_TIME := 2.2
const CHARGE_MULT := 3.0    ## 돌진 중 이동속도 배율
## 기절은 한 방으로 걸리지 않는다 — **때릴수록 쌓이는 스택**이 다 차야 넘어간다.
## 한 번의 풀차징으로 즉시 무력화되면 보스가 "타이밍 퀴즈" 한 문제로 끝나지만,
## 스택이면 **꾸준히 두들긴 대가**가 되고, 면역 시간이 그 보상을 다시 벌게 만든다.
const STUN_TIME := 5.0         ## 기절 지속
const STUN_IMMUNE := 3.0       ## 회복 후 이 동안은 스택이 안 쌓인다
## 6 → 15 (2026-08-12 유저: "너무 빨리 찬다").
## 쿨다운 0.65 기준 **평타 15대 ≈ 9.8초 / 풀차징 5대 ≈ 8.3초**.
## 기절 5초 + 면역 3초를 합치면 한 사이클이 대략 17초 — 보스 한 마리(체력 5000, 처치까지
## 30초 남짓) 동안 두 번쯤 무력화할 수 있다. 6 이었을 땐 4초마다 차서 거의 상시 기절이었다.
const STUN_STACK_MAX := 15.0   ## 이만큼 차면 기절
const STACK_TAP := 1.0         ## 평타 한 대가 쌓는 양
const STACK_FULL := 3.0        ## 풀차징 한 대 (= 평타 3대분)

## 스택 감쇠 — 안 때리면 흘러내린다.
## 없으면 **아무리 띄엄띄엄 때려도 오래 끌기만 하면 결국 기절**해서, 스택이
## "집중해서 두들긴 대가"가 아니라 그냥 시간 문제가 된다.
## GRACE 를 두는 이유: 쿨다운(0.65초)마다 꾸준히 치는 동안엔 한 방울도 안 새야
## 위의 "15대" 라는 숫자가 정직해진다. 스웜을 상대하느라 잠깐 한눈파는 정도(2초)까진 봐준다.
const STACK_GRACE := 2.0       ## 마지막 타격 후 이만큼은 안 줄어든다
const STACK_DECAY := 1.5       ## 그 뒤 초당 감소량 (만충 15 -> 10초면 비워진다)
const STUN_DAMAGE_MULT := 1.5  ## 기절 중 받는 피해

## 성을 때릴 때: **5초마다 한 방**. 잡졸처럼 매 프레임 갉는 게 아니라
## 크게 휘둘러 한 번에 넣는다 — 보스는 "지금 맞았다"가 눈에 보여야 한다.
## SMASH_WIND 는 그 5초 안에 포함된다 (타격 간격이 정확히 5초).
const SMASH_CYCLE := 5.0
const SMASH_WIND := 1.0     ## 치켜드는 시간

## 스켈레탈 애니 재생 속도.
## smash 애니(37f/24fps=1.54s)는 타격이 f29(≈1.21s)에 있다 — 1.2배속이면 코드의
## 타격 시점(SMASH_WIND 1.0s)과 애니의 내리찍는 순간이 일치한다.
const SMASH_ANIM_SPEED := 1.2
## 걷기/돌진 애니 재생 속도 = **실제 이동속도 ÷ 그 사이클이 나아가는 거리**.
## 안 맞추면 다리가 헛돌아 미끄러져 보인다 (개미에서 34배 어긋나 있었다).
##   보폭 실측(stag_v02_export.py): walk 0.465 / charge 0.657 (블렌더)
##   × 노드 0.36 ÷ 주기 0.5초 × 보스 스케일 14 = walk 4.68 / charge 6.62 u/s
##   이동속도: walk 1.75 (3.5×0.5), charge 5.25 (×CHARGE_MULT 3)
## ⚠️ 모델이나 보폭을 바꾸면 이 두 값도 같이 다시 재야 한다.
const WALK_ANIM_SPEED := 0.374      ## 1.75 / 4.68
const CHARGE_ANIM_SPEED := 0.793    ## 5.25 / 6.62 (예전 1.5 는 1.9배 빨랐다)
## 깨어나기 직전, 머리를 좌우로 빠르게 흔들어 어지러움을 털어내는 원샷(stun_wake, 0.75s).
## 기절 타이머가 이만큼 남았을 때 시작해 기절 종료와 함께 끝난다.
const STUN_WAKE_TIME := 0.75

## 성 앞에서 멈추는 거리 = **뿔이 성벽에 닿는 거리**. 스탯이 아니라 모델의 기하학적 사실이라
## 여기 상수로 둔다 (stag_v01.blend 실측 × 모델 스케일 0.36 × 보스 스케일 14 = 5.04).
##   휴식/대기 자세 뿔 끝 = 중심에서 앞으로 10.8, 내려찍는 순간 = 12.1 (몸을 앞으로 밀어 넣는다).
## 그래서 대기 중엔 0.35 띄워 서서 겹치지 않고, 내려찍으면 뿔이 성벽을 약 1유닛
## (뿔 길이 5.2의 1/5) 파고든다 — 유저 요구 "뿔 끝이나 끝의 1/4 지점이 성에 닿을 것".
## ⚠️ 예전엔 `공격범위 12 + 피격반경 8.4 = 20.4`(중심 거리)에서 멈춰서 뿔이 성벽까지
## 7유닛 넘게 모자랐다 — 허공을 때리는 것처럼 보인 원인.
const HORN_REACH := 10.95     ## v02 실측 (블렌더 큰턱 끝 2.172 × 0.36 × 14)
const STAND_GAP := 0.35

enum State { WALK, TELEGRAPH, CHARGE, STUN, SMASH_WAIT, SMASH_WIND_UP }

var state: int = State.WALK
var stun_stack := 0.0           ## 0 ~ STUN_STACK_MAX (체력 바 아래 게이지가 읽는다)
var stun_immune := 0.0          ## 남은 면역 시간
var _since_hit := 999.0         ## 마지막 타격 이후 경과 (감쇠 유예 판정)
var _timer := CYCLE
var _lunge := Vector3.ZERO      ## 돌진 방향 (예고 시작 때 고정 — 도중에 안 꺾인다)
var _smash_damage := 0.0        ## 한 방에 넣는 피해
## 성을 내려찍는 도중에 스택이 다 찼다 — **그 한 방은 끝까지 나간다**(유저 지시).
var _pending_stun := false

## 스태그 모델(stag.glb 인스턴스)과 파트 메시 3개(머리/가슴/배).
## 파트별로 잡아두는 이유: 피격 플래시(instance uniform)와 사망 3조각 분리가 파트 단위다.
var _stag: Node3D
var _part_meshes: Array[MeshInstance3D] = []

## 조각별 무게중심 (glb 로컬 좌표, glTF Y-up). 시체 조각의 회전 피벗이 된다.
const PART_CENTROIDS := {
	&"Head": Vector3(1.05, 0.48, 0.0),
	&"Thorax": Vector3(0.17, 0.45, 0.0),
	&"Abdomen": Vector3(-0.65, 0.5, 0.0),
}

## 보스 배색 (endesga 32 "네이비+금", 2026-08-13). 전 보스 개체 공유 캐시.
## 서피스 순서 = 블렌더 슬롯 순서: 0 껍질 / 1 금 / 2 다리 / 3 눈(머리만).
## 등 문양의 청록. endesga 32 #2ce8f5 — 네이비 껍질과 명도가 가장 멀고 금과 색상이
## 반대쪽이라, 껍질·금·문양 셋이 서로를 잡아먹지 않는다.
const RUNE_COL := Color(0.173, 0.910, 0.961)
## 문양의 발광 세기. **bloom 문턱(main.tscn 1.1) 위**여야 번진다 — 아래로 내리면
## 그냥 밝은 청록이 된다. 너무 하얗게 뜨면 이 값만 낮추면 된다.
const RUNE_GLOW := 2.0
const RuneShader := preload("res://shaders/rune_glow.gdshader")

static var _stag_mats := {}

## 시체용 **비스킨 정적 메시** (stag_corpse.glb). 스킨 메시를 스켈레톤 없는
## MeshInstance3D 에 꽂으면 렌더 서버가 죽는다 — 그래서 정적판을 따로 굽는다.
const CorpseScene := preload("res://assets/models/stag_corpse.glb")
static var _corpse_meshes := {}    # &"Head" -> {mesh: Mesh, ink: Mesh}

static func corpse_meshes() -> Dictionary:
	if _corpse_meshes.is_empty():
		var sc := CorpseScene.instantiate()
		for part: StringName in PART_CENTROIDS:
			var mi := sc.find_child(String(part), true, false) as MeshInstance3D
			var ink := sc.find_child(String(part) + "Ink", true, false) as MeshInstance3D
			_corpse_meshes[part] = {
				mesh = mi.mesh if mi != null else null,
				ink = ink.mesh if ink != null else null,
			}
		sc.free()
	return _corpse_meshes

static func stag_materials() -> Dictionary:
	if _stag_mats.is_empty():
		var mk := func(light: Color, dark: Color, th: float) -> ShaderMaterial:
			var m := ShaderMaterial.new()
			m.shader = CelShader
			m.set_shader_parameter("light_tone", light)
			m.set_shader_parameter("dark_tone", dark)
			m.set_shader_parameter("threshold", th)
			return m
		var eye := StandardMaterial3D.new()
		eye.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		# ⚠️ 예전엔 endesga 최고 채도 #ff0044 였다 — "프레임에서 가장 강한 점 하나를 보스가
		#    독점한다"는 배색이었는데, v02 에서 눈이 점에서 **단추 눈**으로 커지면서
		#    그 빨강이 너무 무서워졌다 (유저 지적 2026-08-16). 다른 벌레와 같은 먹색으로 내린다.
		#    보스의 존재감은 크기와 금색 큰턱이 이미 충분히 지고 있다.
		eye.albedo_color = INK                                    # #181425
		# ⚠️ 금을 #feae34 쪽으로 내리면 **주황**으로 읽혀 콩벌레(#be4a2f)와 색상이 붙는다.
		#    한 단계 노란 #fee761 이어야 금으로 읽히고 러너와 확실히 갈린다 (블렌더 목업 실측).
		# ⚠️ limb 에 TONE_LIGHT 를 쓰면 안 된다 — 그건 이제 개미의 자두색이다.
		# 단추 눈의 흰자. ⚠️ 매핑에 없으면 stag_surface_mats 가 **껍질색으로 폴백**해서
		# 흰자가 네이비가 된다 — 눈이 통째로 사라진 것처럼 보인다.
		var white := StandardMaterial3D.new()
		white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		white.albedo_color = Color(0.969, 0.949, 0.937)           # #f7f2ef
		# 등의 문양 — 조명과 무관하게 일정하게 발광한다.
		# ⚠️ 예전엔 StandardMaterial3D 를 unshaded + emission 으로 만들었는데 **전혀 안 빛났다.**
		#    Godot 은 unshaded 에서 EMISSION 을 버리고 ALBEDO 만 출력한다 — 같은 함정이
		#    deflagration.gd 에 이미 메모돼 있었다 (유저 지적 2026-08-16 "glowing 하는 게 없는데").
		#    전용 셰이더에서 ALBEDO=0 + EMISSION 으로 간다.
		var rune := ShaderMaterial.new()
		rune.shader = RuneShader
		rune.set_shader_parameter("col", RUNE_COL)
		rune.set_shader_parameter("glow", RUNE_GLOW)
		_stag_mats = {
			shell = mk.call(Color(0.227, 0.267, 0.4), INK, 0.17),          # #3a4466/#181425
			gold = mk.call(Color(0.996, 0.906, 0.38), Color(0.996, 0.682, 0.204), 0.28),  # #fee761/#feae34
			limb = mk.call(Color(0.149, 0.169, 0.267), INK, 0.34),         # #262b44/#181425
			eye = eye,
			rune = rune,
			white = white,
		}
	return _stag_mats

## 그 메시의 **서피스 순서에 맞춰** 셀 머티리얼을 골라 배열로 돌려준다.
##
## ⚠️ 예전엔 [shell, gold, limb, eye] 를 서피스 0,1,2,3 에 그대로 꽂았다. glTF 는 그 파트가
##    실제로 쓰는 재질만 프리미티브로 만들기 때문에 **파트마다 서피스 개수가 다르다** —
##    지금은 사슴벌레 세 파트가 우연히 슬롯 순서대로 다 쓰고 있어서 맞아떨어졌을 뿐이다.
##    어느 파트가 금색을 안 쓰게 되는 순간 그 뒤가 통째로 한 칸씩 밀린다.
##    장수풍뎅이가 정확히 그렇게 터졌다 (뿔이 딱지날개색으로 칠해짐, 2026-08-14).
##    그래서 번호가 아니라 **재질 이름으로** 맞춘다.
static func stag_surface_mats(mesh: Mesh) -> Array:
	var mats := stag_materials()
	var by_name := {
		"Cel_StagShell": mats.shell,
		"Cel_StagGold": mats.gold,
		"Cel_StagLimb": mats.limb,
		"Stag_Eye": mats.eye,
		"Cel_StagRune": mats.rune,
		"Cel_StagWhite": mats.white,
		# 딱지날개 봉합선. ⚠️ 빠뜨리면 껍질색으로 폴백해 네이비 위 네이비가 되어
		# 선이 통째로 사라진다 (실측으로 잡았다).
		"Cel_StagSeg": ink_material(),
	}
	var out: Array = []
	for i in mesh.get_surface_count():
		var src := mesh.surface_get_material(i)
		var nm := src.resource_name if src != null else ""
		var pick: Material = null
		for key in by_name:
			if nm.begins_with(String(key)):
				pick = by_name[key]
		# 이름을 못 찾으면 껍질색으로 — 가장 넓은 면이라 틀려도 덜 튄다
		out.append(pick if pick != null else mats.shell)
	return out

## 부모가 Ant/Blob 을 고르고 나면, 보스는 자기 모델(Stag)을 얹는다.
func _apply_type() -> void:
	super()
	_stag = _pivot.get_node_or_null("Stag")
	if _stag == null:
		return                       # 모델 없는 씬(테스트 등)에서도 로직은 돈다
	_mesh = _stag
	_mesh_y = _stag.position.y
	_part_meshes.clear()
	for part: StringName in PART_CENTROIDS:
		var mi := _stag.find_child(String(part), true, false) as MeshInstance3D
		if mi == null:
			continue
		var order := stag_surface_mats(mi.mesh)
		for i in order.size():
			mi.set_surface_override_material(i, order[i])
		_part_meshes.append(mi)
		var ink := _stag.find_child(String(part) + "Ink", true, false) as MeshInstance3D
		if ink != null:
			ink.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ink.set_surface_override_material(0, ink_material())
	_anim = _stag.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_play_anim(&"walk", WALK_ANIM_SPEED)

## 상태 전이 때 부르는 재생 헬퍼. 걷기 속도는 부모가 매 프레임 이동속도에 맞추므로
## 여기서 넣는 speed 는 걷기 외 상태(돌진·내리찍기)에서만 의미가 있다.
func _play_anim(anim: StringName, speed := 1.0) -> void:
	if _anim == null:
		return
	_anim.speed_scale = speed
	_anim.play(anim)

## 피격 플래시 — 파트 3개의 셀 instance uniform 에 넣는다.
## (부모의 blob/Body 경로는 스태그 구조와 안 맞는다. instance uniform 이라 다른 보스/개미와 안 겹친다.)
func _flash(col: Color) -> void:
	if _part_meshes.is_empty():
		super(col)
		return
	if _flash_tw != null and _flash_tw.is_valid():
		_flash_tw.kill()
	for mi in _part_meshes:
		mi.set_instance_shader_parameter(&"flash_col", col)
	var tw := create_tween()
	_flash_tw = tw
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float) -> void:
		for mi in _part_meshes:
			mi.set_instance_shader_parameter(&"flash", v), 1.0, 0.0, FLASH_TIME)

## 보스는 두 가지로 죽는다 (유저 스펙, 2026-08-13). 어느 쪽이든 머리/가슴/배 3조각이다.
##   일반 — 조각들이 제자리에서 살짝 납작해지고, 보라색 액체가 흘러나와 웅덩이를 만든다.
##   폭연 — 부풀어 달아오르다, 보스 크기에 비례한 폭발과 함께 조각이 하늘 높이 솟았다
##          떨어져 바닥에 박힌다.
## die() 가 연출을 바로 시작하지 않고 한 프레임 미루는 이유: 폭연(combust)은
## _damage_area -> die 직후 **같은 프레임**에 시체를 가로채러 오기 때문이다.
var _combusting := false

func die(_from := Vector3.INF) -> void:
	if dying:
		return
	dying = true
	died.emit()
	remove_from_group("enemies")
	set_physics_process(false)
	if _anim != null:
		_anim.pause()              # 죽은 벌레가 계속 걸으면 곤란하다 (부풀 때도 마찬가지)
	_finish_death.call_deferred()

func _finish_death() -> void:
	if _combusting:
		return                     # 폭연이 시체를 가져갔다 — combust() 가 연출을 잇는다
	_collapse_death()
	queue_free()

## 일반 사망: 조각들이 그 자리에 힘없이 주저앉아 살짝 납작해지고,
## 밑에서 보라색 액체(nice31 #7a5859/#593e47, 셀 셰이딩)가 퍼진다.
func _collapse_death() -> void:
	if _stag != null and not _part_meshes.is_empty():
		BloodPool.spawn(get_parent(), global_position, hit_radius * 0.85)
	_spawn_chunks(func(dir: Vector3) -> Vector3:
		return dir * randf_range(0.5, 1.1) + Vector3.DOWN * 1.5,
		0.2, 0.5,
		{squash = true, bury = 0.05, linger = 2.2, dust = 6, dust_scale = 1.0})

## 폭연 사망: Enemy.combust 와 같은 문법 — t초 동안 부풀며 달아오르다 터진다.
## 폭발 자체(섬광·링·불꽃·피해)는 HammerStrike 가 예약한 Deflagration 이 같은 순간에
## 일으키고, 반경에 hit_radius 가 들어가므로 이미 보스 크기에 비례한다.
func combust(t: float) -> void:
	_combusting = true
	var heat := _heat_mats_stag()
	var tw := create_tween()
	var wob := randf_range(30.0, 40.0)
	tw.tween_method(func(p: float) -> void:
		var s := 1.0 + 0.38 * p * p           # Enemy(0.85)보다 낮게 — 보스는 이미 크다
		var phase := wob * p * p * t
		_pivot.scale = Vector3(s * (1.0 + 0.05 * sin(phase)),
			s * (1.0 + 0.035 * sin(phase * 1.7)), s * (1.0 - 0.05 * sin(phase)))
		_pivot.position.x = sin(phase * 1.3) * 0.04 * p
		_pivot.position.z = cos(phase) * 0.04 * p
		for m: ShaderMaterial in heat:
			m.set_shader_parameter("heat", p * p * p),
		0.0, 1.0, maxf(t, 0.05))
	tw.tween_callback(_blast_death)

## 터졌다 — 조각이 하늘 높이(정점 ~11유닛) 솟았다 떨어져 30~48% 깊이로 박힌다.
func _blast_death() -> void:
	_spawn_chunks(func(dir: Vector3) -> Vector3:
		return dir * randf_range(6.0, 11.0) + Vector3.UP * randf_range(20.0, 26.0),
		4.0, 9.0,
		{bury_range = Vector2(0.30, 0.48), linger = 2.3, dust = 20, dust_scale = 2.0})
	queue_free()

## 조각 3개를 스폰한다. vel_of(방향) 이 조각별 속도를, opts 가 착지 연출을 정한다.
## 방향 = 보스 중심에서 그 조각 무게중심을 향한 수평 방향 — 머리는 앞으로, 배는 뒤로,
## 해부학적으로 흩어져서 "한 몸이 쪼개졌다"로 읽힌다.
func _spawn_chunks(vel_of: Callable, spin_lo: float, spin_hi: float, opts: Dictionary) -> void:
	if _stag == null or _part_meshes.is_empty():
		return
	var base_x: Transform3D = _stag.global_transform
	for part: StringName in PART_CENTROIDS:
		var cm: Dictionary = corpse_meshes()[part]
		if cm.mesh == null:
			continue
		# 시체는 **비스킨 정적 메시**라 서피스 구성이 또 다를 수 있다 — 여기도 이름으로 맞춘다
		var sources := [{mesh = cm.mesh, mats = stag_surface_mats(cm.mesh), shadow = true}]
		if cm.ink != null:
			sources.append({mesh = cm.ink, mats = [ink_material()], shadow = false})
		var world_c: Vector3 = base_x * PART_CENTROIDS[part]
		var dir := world_c - global_position
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.05 \
			else Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
		# 흩어지는 각도에 편차를 준다 — 반사 **전에** 흔들어야 결과가 성 반대쪽으로 보장된다
		dir = _deflect_from_base(dir.rotated(Vector3.UP, randf_range(-0.5, 0.5)))
		var axis := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)).normalized()
		var o := opts.duplicate()
		if o.has("bury_range"):        # 조각마다 다른 깊이로 박혀야 자연스럽다
			o.bury = randf_range(o.bury_range.x, o.bury_range.y)
		BossCorpse.spawn(get_parent(), base_x, PART_CENTROIDS[part],
			sources, vel_of.call(dir), axis, randf_range(spin_lo, spin_hi), o)

## 성 근처에서 죽으면 조각이 **성 쪽으로는 날아가지 않는다** (유저 요청, 2026-08-13).
## 시체는 바닥 착지만 판정하므로(BossCorpse) 성 위로 떨어지면 벽을 통과해 내려가
## 성에 박힌 것처럼 보인다. 성을 피하는 착지 지점을 계산하는 대신 **아예 안 보내는** 쪽이 싸다.
##
## 성분을 지우지 않고 **반사**한다 — 지우면 전부 정확히 옆으로 날아가 세 조각이 한 줄로
## 뭉치지만, 반사는 좌우로 흩어진 폭을 그대로 두고 앞뒤만 뒤집는다.
const CHUNK_KEEPOUT := 20.0     ## 조각 최대 비행거리(수평 11 × 체공 1.7초 ≈ 19)보다 조금 넉넉히

func _deflect_from_base(dir: Vector3) -> Vector3:
	var base := get_tree().get_first_node_in_group("base") as Node3D
	if base == null:
		return dir
	var to_base := base.global_position - global_position
	to_base.y = 0.0
	var dist := to_base.length()
	# 멀리서 죽었으면 조각이 성까지 못 간다 — 해부학적 방향을 그대로 살린다
	if dist > CHUNK_KEEPOUT or dist < 0.01:
		return dir
	to_base /= dist
	var toward := dir.dot(to_base)
	if toward <= 0.0:
		return dir
	return (dir - to_base * (2.0 * toward)).normalized()

## 부풀 때 달아오를 셀 머티리얼 사본 — 파트 서피스(셀 셰이더만, 눈 제외)를 개체 전용으로.
## 공유 캐시를 달구면 화면의 다른 보스까지 익는다 (Enemy 와 같은 규칙).
func _heat_mats_stag() -> Array:
	var out := []
	for mi in _part_meshes:
		for i in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(i)
			if m is ShaderMaterial:
				var c := (m as ShaderMaterial).duplicate() as ShaderMaterial
				mi.set_surface_override_material(i, c)
				out.append(c)
	return out


func _ready() -> void:
	super()
	add_to_group("boss")        ## 체력 바가 이 그룹으로 찾는다
	# TYPES 의 damage 는 다른 몹과 같은 **초당 피해** 의미로 적혀 있다.
	# 보스는 그 5초치를 모아 한 방에 넣으므로 여기서 환산하고,
	# **스탯 자체는 0 으로 만든다** — 그래야 부모(Enemy)의 매 프레임 갉기가 안 겹친다.
	_smash_damage = stats.get_v(Stats.DAMAGE) * SMASH_CYCLE
	stats.set_base(Stats.DAMAGE, 0.0)

## 기지 타격 범위 안인가 = 뿔이 성벽에 닿는가.
func _in_range() -> bool:
	if target == null:
		return false
	return _dist_to_base() <= HORN_REACH + STAND_GAP

## 보스 중심에서 **바라보는 방향으로** 성 표면까지의 거리 (XZ 평면).
## 중심 거리로 재면 접근 각도에 따라 최대 1유닛 어긋난다 — 성은 5×5 사각기둥이고
## 스폰존이 화면 좌표라 보스는 대각선으로 오는 경우가 많다(대각 반지름 3.54 vs 정면 2.5).
## 그러면 방향에 따라 뿔이 박히기도 하고 뜨기도 한다. 표면까지 재면 어느 각도로 와도 같다.
func _dist_to_base() -> float:
	var to := target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	if dist < 0.001:
		return 0.0
	if not target.has_method("footprint"):
		return dist
	# 광선-사각형 진입 거리 (slab method). 성 안이면 0.
	var r: Rect2 = target.footprint()
	var d := to / dist
	var enter := 0.0
	for axis in 2:
		var dd: float = d.x if axis == 0 else d.z
		if absf(dd) < 0.0001:
			continue
		var p: float = global_position.x if axis == 0 else global_position.z
		var lo: float = r.position.x if axis == 0 else r.position.y
		var hi: float = r.end.x if axis == 0 else r.end.y
		enter = maxf(enter, minf((lo - p) / dd, (hi - p) / dd))
	return enter

## 기절 중엔 더 아프다. 취소에 성공한 플레이어에게 주는 보상 창이다.
func take_damage(amount: float, from: Vector3, src: DamageSource = null) -> void:
	super(amount * (STUN_DAMAGE_MULT if state == State.STUN else 1.0), from, src)

## 망치에 맞았다. 차징이 셀수록 기절 스택이 많이 쌓이고, 다 차면 기절한다.
## 상태를 가리지 않는다 — 걷든 예고하든, 스택이 차는 순간 넘어간다.
## (예고 중이면 그 결과로 **돌진이 취소된다**. 이게 원래의 취소 규칙을 대신한다.)
func on_hammer(ratio: float) -> void:
	if state == State.STUN or stun_immune > 0.0 or dying:
		return
	_since_hit = 0.0
	stun_stack += lerpf(STACK_TAP, STACK_FULL, clampf(ratio, 0.0, 1.0))
	if stun_stack < STUN_STACK_MAX:
		return
	# ⚠️ 성을 내려찍는 중이면 **그 한 방은 끝까지 나간다**(유저 지시: "끊지 말아줘").
	# 기절은 타격이 들어간 직후에 걸린다.
	if state == State.SMASH_WIND_UP:
		_pending_stun = true
	else:
		_enter_stun()

## 만화식 기절 표시 (머리 위 별+고리). 보스 자식이라 스케일 14 를 StunStars 가 역보정한다.
var _stun_fx: StunStars

func _enter_stun() -> void:
	state = State.STUN
	_timer = STUN_TIME
	stun_stack = 0.0
	_pending_stun = false
	_pivot.rotation.x = 0.0        # 치켜든 자세가 남아 있으면 기절 중에 굳는다
	_pivot.position.y = 0.0
	_play_anim(&"stun")            # 어지러움 — 머리가 위->오른쪽->아래->왼쪽 빙글빙글
	if _stun_fx == null:
		# 로컬 (0, 0.30, -0.30) = 월드 (위 4.2, 앞 4.2) — 도는 머리 바로 위
		_stun_fx = StunStars.spawn(self, Vector3(0, 0.30, -0.30), 2.3)
	# 휘청 — 예고 자세에서 풀려 뒤로 밀린다
	_slide = -_lunge * 3.0
	_shake_visual(0.25)

## 부모의 걷기/공격을 그대로 쓰되, 돌진 사이클을 얹는다.
## 부모 로직을 복사하지 않고 super() 에 맡기는 이유: 넉백·비틀거림·기지 공격 같은
## 공통 규칙이 나중에 바뀌어도 보스만 따로 낡지 않는다.
func _physics_process(delta: float) -> void:
	if dying or _airborne:
		super(delta)
		return
	# 면역은 상태와 무관하게 흐른다 (기절에서 풀린 직후 3초)
	if stun_immune > 0.0:
		stun_immune = maxf(stun_immune - delta, 0.0)
	# 스택 감쇠 — 유예 시간이 지나면 흘러내린다
	_since_hit += delta
	if stun_stack > 0.0 and _since_hit > STACK_GRACE and state != State.STUN:
		stun_stack = maxf(stun_stack - STACK_DECAY * delta, 0.0)

	match state:
		State.WALK:
			# 성에 닿으면 돌진 사이클을 접고 **때리는 사이클**로 넘어간다.
			# 붙어 있는데도 돌진을 하면 제자리에서 헛돌 뿐이다.
			if _in_range():
				state = State.SMASH_WAIT
				_timer = SMASH_CYCLE - SMASH_WIND
				_play_anim(&"idle")              # 성 앞에서 다음 타격까지 대기
				return
			_timer -= delta
			if _timer <= 0.0 and target != null:
				_begin_telegraph()
			super(delta)                     # 평소 걷기
		State.SMASH_WAIT:
			if not _in_range():              # 밀려났으면 다시 걸어간다
				state = State.WALK
				_timer = CYCLE
				_play_anim(&"walk", WALK_ANIM_SPEED)
				return
			_timer -= delta
			# 내리찍기 애니(원샷)가 끝나면 대기 자세로 돌아가 다음 타이밍을 잰다.
			# ⚠️ 여기서 telegraph 를 틀면 안 된다 — 그건 **돌진 예고** 전용이다.
			# 때린 직후마다 예고 동작이 나오면 "돌진이 온다"는 신호가 거짓말이 되고,
			# 플레이어는 오지 않을 돌진에 대비하게 된다 (유저 지적, 2026-08-13).
			if _anim != null and not _anim.is_playing():
				_play_anim(&"idle")
			if _timer <= 0.0:
				state = State.SMASH_WIND_UP
				_timer = SMASH_WIND
				# 치켜들기~내리찍기는 통째로 스켈레탈 애니 — 타격(f29)이 SMASH_WIND 에 온다
				_play_anim(&"smash", SMASH_ANIM_SPEED)
		State.SMASH_WIND_UP:
			_timer -= delta
			if _timer <= 0.0:
				_smash()
		State.TELEGRAPH:
			_timer -= delta
			if _timer <= 0.0:
				state = State.CHARGE
				_timer = CHARGE_TIME
				_play_anim(&"charge", CHARGE_ANIM_SPEED)
		State.CHARGE:
			_timer -= delta
			# 성벽에 닿으면 더 밀고 들어가지 않는다 — 안 막으면 돌진이 성 안으로 파고든다
			# (돌진 5.8유닛은 멈추는 거리보다 길다).
			if _dist_to_base() > HORN_REACH + STAND_GAP:
				# ⚠️ 돌진도 지형을 지켜야 한다 — 안 그러면 보스만 절벽을 뚫고 들어온다.
				var dash := _lunge * stats.get_v(Stats.SPEED) * CHARGE_MULT * delta
				global_position = _walk(global_position, dash)
				global_position.y = Terrain.h(global_position)
			if _timer <= 0.0:
				state = State.WALK
				_timer = CYCLE
				_play_anim(&"walk", WALK_ANIM_SPEED)
		State.STUN:
			_timer -= delta
			# 기절 중에도 밀림은 적용된다 (super 를 안 부르므로 여기서 직접)
			if _slide.length_squared() > 0.0025:
				global_position += _slide * delta
				_slide = _slide.lerp(Vector3.ZERO, clampf(SLIDE_DAMP * delta, 0.0, 1.0))
			# 깨어나기 직전: 머리 털기 원샷으로 전환 (한 번만 — 이미 틀었으면 재진입 안 함)
			if _timer <= STUN_WAKE_TIME and _anim != null and _anim.current_animation == "stun":
				_play_anim(&"stun_wake")
				# 정신이 돌아오니 별도 걷힌다 (털어내는 동작과 함께)
				if _stun_fx != null:
					_stun_fx.queue_free()
					_stun_fx = null
			# 비틀거림 — 털어내는 동안엔 잦아든다 ("정신 차렸다"가 몸으로도 보이게)
			_pivot.rotation.z = sin(_timer * 12.0) * 0.12 \
				* clampf(_timer / STUN_WAKE_TIME, 0.0, 1.0)
			if _timer <= 0.0:
				_pivot.rotation.z = 0.0
				stun_immune = STUN_IMMUNE      # 회복 직후엔 다시 안 쌓인다
				state = State.WALK
				_timer = CYCLE
				_play_anim(&"walk", WALK_ANIM_SPEED)
				if _stun_fx != null:           # 폴백 (_anim 없는 씬에선 위에서 못 걷는다)
					_stun_fx.queue_free()
					_stun_fx = null

## 내려찍는다. 치켜든 자세에서 한 번에 앞으로 꽂고, 그 순간 피해가 들어간다.
func _smash() -> void:
	state = State.SMASH_WAIT
	_timer = SMASH_CYCLE - SMASH_WIND
	if target != null and target.has_method("take_damage"):
		target.take_damage(_smash_damage)
	# 큰 놈이 내려찍었으니 화면이 울려야 한다
	var hs := get_tree().get_first_node_in_group("hammer")
	if hs != null:
		hs._shake = maxf(hs._shake, 0.7)
	# 먼지는 **뿔이 박힌 자리**에서 — 예전엔 보스와 성 중심의 55% 지점이라 허공에서 터졌다
	var at := global_position
	if target != null:
		var to := target.global_position - global_position
		to.y = 0.0
		if to.length() > 0.01:
			at = global_position + to.normalized() * HORN_REACH
	ImpactDust.burst(get_parent(), Vector3(at.x, 0.0, at.z), 22, 1.3)
	# 몸 연출은 smash 애니가 맡는다 (치켜들기->내리찍기->복귀까지 한 클립)
	# 내려찍는 도중에 스택이 다 찼다면, 타격이 나간 **뒤에** 기절한다
	if _pending_stun:
		_enter_stun()

func _begin_telegraph() -> void:
	state = State.TELEGRAPH
	_timer = TELEGRAPH
	var to := target.global_position - global_position
	to.y = 0.0
	_lunge = to.normalized() if to.length() > 0.01 else -global_basis.z
	# 예고는 **동작으로만** 한다 — 정지 + 머리 들기 + 뿔 벌리고 떨기.
	# 바닥에 깔던 붉은 경로 띠는 유저 지시로 삭제(2026-08-13): 예고 애니메이션이 생긴 뒤로는
	# 같은 말을 두 번 하는 셈이었고, 정작 무엇을 뜻하는지 읽히지 않았다.
	_play_anim(&"telegraph")
