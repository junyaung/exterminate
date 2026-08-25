class_name Mood
extends Node

## 전투의 시간대별 무드 조명 (유저 요청 2026-08-17: 낮 / 밤 / 해뜨기 직전).
##
## ⚠️ **조명만 바꿔서는 이 게임의 화면이 안 바뀐다.** 지면(ground_flat)도 벌레(cel)도
##    빛 계산을 거의 안 하고 색을 직접 확정하는 셰이더라, 태양을 꺼도 대낮처럼 밝다.
##    그래서 무드는 네 갈래를 **한 번에** 움직인다:
##      1) 태양/달 — 색·세기·각도 (각도가 낮을수록 그림자가 길어져 시간대가 읽힌다)
##      2) 환경 — 배경색·앰비언트·안개·글로우
##      3) 전역 색조(mood_tint) — 셰이더가 확정한 색을 시간대 쪽으로 물들인다
##      4) 그늘 깊이(mood_shade) — 밤엔 그림자를 옅게 (달빛은 대비가 약하다)
##
## 색조는 **전역 셰이더 유니폼**으로 뿌린다. 머티리얼마다 찾아다니며 칠하면 새 머티리얼이
## 생길 때마다 빠뜨리는데, 전역이면 셰이더를 쓰는 모든 것이 자동으로 따라온다.
## ⚠️ 전역 유니폼은 **셰이더가 처음 컴파일되기 전에** 등록해야 한다. 안 그러면 컴파일이
##    깨져서 그 셰이더를 쓰는 게 통째로 화면에서 사라진다 (지면으로 이미 한 번 겪었다).

## ⚠️ enum 이름을 Time 으로 두면 안 된다 — Godot 의 네이티브 Time 클래스와 겹쳐 파스 에러가 난다.
enum Phase { DAY, SUNSET, NIGHT }

## 무드 한 벌. 색은 전부 팔레트 계열에서 골랐다 (endesga/nice31 톤).
const PRESETS := {
	Phase.DAY: {
		name = "낮",
		sun_color = Color("#fff3d6"), sun_energy = 1.35,
		sun_pitch = -52.0, sun_yaw = -35.0,
		ambient = Color("#5a6d96"), ambient_energy = 0.55,
		bg = Color("#63c74d"),   # ⚠️ ground.gd 의 PLAIN_COLOR 와 같은 값을 유지할 것
		fog = false, fog_color = Color("#a8b894"), fog_density = 0.0,
		glow = 0.9,
		# ⚠️ 낮도 그림자를 충분히 눌러야 한다 — 얕게 두면 대비 1.9배로 밋밋해진다(측정).
		tint = Color(1.0, 0.99, 0.94), shadow_tint = Color(0.58, 0.67, 0.90), shade = 0.45,
		ground_mul = 1.0, fire_mul = 0.3,
	},
	Phase.SUNSET: {
		name = "노을",
		# 해가 지평선에 걸린 순간 — 빛이 **주황으로 진해지고 그림자가 화면을 가로지른다.**
		# 여명(푸른 시간)과의 차이는 채도다: 여명은 빛이 창백하고, 노을은 빛 자체가 색을 갖는다.
		# ⚠️ 안개는 쓰지 않는다. 0.012 만으로도 화면이 회보라로 덮여 색이 탁해졌다(유저 지적).
		#    깊이감은 **긴 그림자 + 차가운 그림자색**이 만든다.
		# ⚠️ 앰비언트를 낮게 둔 건 나중에 들어올 **횃불** 때문이다 — 주변이 밝으면 불빛이 안 산다.
		# ⚠️ 고도 7도는 그림자가 화면을 가로질러 너무 길었다 (유저 지적) — 22도로 올려
		#    "길지만 읽히는" 정도로 맞췄다. 그림자 길이 ≈ 높이 / tan(고도).
		sun_color = Color("#ff8a3d"), sun_energy = 1.3,
		sun_pitch = -22.0, sun_yaw = -120.0,
		ambient = Color("#46375f"), ambient_energy = 0.45,
		bg = Color("#5e4257"),
		fog = false, fog_color = Color("#7a6a8c"), fog_density = 0.0,
		glow = 1.35,
		tint = Color(1.0, 0.72, 0.46), shadow_tint = Color(0.36, 0.34, 0.66), shade = 0.40,
		ground_mul = 0.92, fire_mul = 0.7,
	},
	Phase.NIGHT: {
		name = "밤",
		# 달빛: 푸르고 서늘하다. ⚠️ 안개는 아주 옅게만 — 짙게 깔면 낮처럼 탁해진다.
		#    밤은 "어둡게"가 아니라 **색으로** 만든다. 밝기를 너무 내리면 벌레가 안 보인다.
		sun_color = Color("#a9c2f2"), sun_energy = 0.75,
		sun_pitch = -62.0, sun_yaw = 25.0,
		ambient = Color("#131c2e"), ambient_energy = 0.35,
		bg = Color("#0c1220"),
		fog = true, fog_color = Color("#121c2e"), fog_density = 0.006,
		glow = 1.6,
		# 벌레(cel)는 0.62 까지만 내린다 — 더 내리면 거의 검정인 몸이 배경에 묻힌다.
		# 대신 **바닥만** 0.5 로 눌러서 벌레 실루엣이 떠오르게 한다.
		tint = Color(0.62, 0.74, 0.96), shadow_tint = Color(0.18, 0.24, 0.48), shade = 0.42,
		ground_mul = 0.5, fire_mul = 1.0,
	},
}

## ⚠️ **자동 진행은 뺐다** (유저 지시 2026-08-18). 시간이 저절로 흐르며 해가 도는 대신,
##    낮·노을·밤 **셋 중 하나를 고르는** 방식이다. 고른 시간대로 서서히 넘어간다.
## 시간대를 바꿀 때 넘어가는 데 걸리는 시간(초). 0 이면 즉시 갈아끼운다.
## ⚠️ 즉시 바꾸면 해가 순간이동해서 그림자가 툭 튄다 — 잠깐에 걸쳐 넘겨야 눈이 따라온다.
@export var transition := 1.2

## 지금 시각. **0.0 ~ 3.0** — 정수부가 위상(0 낮 / 1 노을 / 2 밤), 소수부가 그 안에서의 진행.
var time := 0.0

## 위상 안에서 **이 지점부터** 다음 위상으로 섞이기 시작한다.
## ⚠️ 0.7 로 뒀다가 **0.0 으로 바꿨다** (유저 지시 2026-08-18: "갑자기 바뀌는 게 아니라
##    gradual 하게"). 0.7 이면 앞 70%가 고정이고 뒤 30%에서 몰아서 바뀌어 그 30% 구간이
##    급하게 느껴진다. 0 이면 **위상 내내 일정한 속도로** 다음 시간대로 넘어간다 —
##    각 프리셋 색은 위상이 시작하는 순간에 정확히 한 번씩 지나간다.
const BLEND_FROM := 0.0

## 지금 고른 시간대(도착점). time 이 여기로 따라간다.
var _target := 0.0
var current: Phase = Phase.DAY
var _sun: DirectionalLight3D
var _env: Environment
## 지금 무드를 화면에 잠깐 띄우는 라벨. ⚠️ 콘솔에만 찍었더니 유저가 "밤은 어디 갔냐"고
## 물었다 — 세 무드가 다 있는데 **지금 어느 무드인지 화면에서 알 수 없었던** 게 문제였다.
var _toast: Label
var _toast_tw: Tween

func _ready() -> void:
	_register_globals()
	var parent := get_parent()
	_sun = parent.get_node_or_null("Sun") as DirectionalLight3D
	var we := parent.get_node_or_null("WorldEnvironment") as WorldEnvironment
	_env = we.environment if we != null else null
	_make_toast()
	apply(current)
	print("[mood] T 키 또는 오른쪽 위 시계 클릭으로 낮/노을/밤 선택")

## 무드 이름을 잠깐 띄우는 라벨을 만든다.
func _make_toast() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_toast = Label.new()
	_toast.add_theme_font_size_override(&"font_size", 34)
	_toast.add_theme_color_override(&"font_color", Color("#f7f2ef"))
	_toast.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.55))
	_toast.add_theme_constant_override(&"shadow_offset_y", 3)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 34.0
	_toast.offset_left = -160.0
	_toast.offset_right = 160.0
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0
	layer.add_child(_toast)

func _show_toast(text: String) -> void:
	if _toast == null:
		return
	_toast.text = text
	if _toast_tw != null and _toast_tw.is_valid():
		_toast_tw.kill()
	_toast.modulate.a = 1.0
	_toast_tw = create_tween()
	_toast_tw.tween_interval(1.1)
	_toast_tw.tween_property(_toast, "modulate:a", 0.0, 0.5)

## 전역 셰이더 유니폼 등록. 이미 있으면 그냥 둔다 (씬을 다시 로드해도 안전하게).
## 슬롯 초기화 — 전역 유니폼 **등록**은 여기서 하지 않는다.
## ⚠️ 예전엔 여기서 `global_shader_parameter_add` 로 만들었는데, 2026-08-17 에
##    project.godot `[shader_globals]` 에 정식 선언한 뒤로는 **중복 등록이라 에러가 난다**
##    ("Condition global_shader_uniforms.variables.has(p_name) is true").
##    게다가 존재 확인에 쓰던 `global_shader_parameter_get_list()` 는 **에디터 전용**이라
##    "should never be used outside the editor, it can severely damage performance" 경고까지
##    같이 떴다 (유저 로그 2026-08-18). 선언은 project.godot 이, 값은 이 스크립트가 맡는다.
static func _register_globals() -> void:
	FireLights.reset_slots()

## 시간이 흐른다. 3.0 을 한 바퀴로 보고 감는다.
## 고른 시간대로 **서서히** 넘어간다. 도착하면 아무것도 안 한다.
## ⚠️ 항상 **앞으로**(낮→노을→밤→낮) 돈다 — 밤에서 낮으로 갈 때 거꾸로 되감으면
##    해가 반대로 움직여서 "시간이 되돌아간다"로 보인다.
func _process(delta: float) -> void:
	if is_equal_approx(time, _target):
		return
	var step := 3.0 * delta / maxf(transition, 0.001)
	var left := fposmod(_target - time, 3.0)
	time = _target if left <= step else fposmod(time + step, 3.0)
	_apply_time()

## 지금 시각의 색·해 각도를 만든다. 위상 두 개를 섞어서 **연속적으로** 바뀐다 —
## 해가 실제로 움직이고 그림자가 같이 돌아간다.
func _apply_time() -> void:
	var i := int(time) % 3
	var f: float = time - floor(time)
	# ⚠️ smoothstep 이 아니라 **선형**이다. smoothstep 은 위상 가운데서 변화가 빨라져
	#    "천천히 → 확 → 천천히" 가 되는데, 유저가 원한 건 일정한 속도의 변화다.
	var w := clampf((f - BLEND_FROM) / maxf(1.0 - BLEND_FROM, 0.001), 0.0, 1.0)
	var a: Dictionary = PRESETS[i]
	var b: Dictionary = PRESETS[(i + 1) % 3]
	if _sun != null:
		_sun.light_color = a.sun_color.lerp(b.sun_color, w)
		_sun.light_energy = lerpf(a.sun_energy, b.sun_energy, w)
		# 각도는 **높이 유지한 채 방향만** 바꾼다 — 위치를 옮기면 그림자 범위가 어긋난다.
		_sun.rotation = Vector3(
			deg_to_rad(lerpf(a.sun_pitch, b.sun_pitch, w)),
			deg_to_rad(lerpf(a.sun_yaw, b.sun_yaw, w)), 0.0)
	if _env != null:
		_env.background_color = a.bg.lerp(b.bg, w)
		_env.ambient_light_color = a.ambient.lerp(b.ambient, w)
		_env.ambient_light_energy = lerpf(a.ambient_energy, b.ambient_energy, w)
		# ⚠️ 안개는 **켜짐/꺼짐이 아니라 밀도**로 섞는다. bool 을 중간에 뒤집으면
		#    안개가 한 프레임에 툭 나타난다.
		_env.fog_enabled = a.fog or b.fog
		_env.fog_light_color = a.fog_color.lerp(b.fog_color, w)
		_env.fog_density = lerpf(a.fog_density, b.fog_density, w)
		_env.glow_intensity = lerpf(a.glow, b.glow, w)
	RenderingServer.global_shader_parameter_set(&"mood_tint", a.tint.lerp(b.tint, w))
	RenderingServer.global_shader_parameter_set(&"mood_shadow_tint",
		a.shadow_tint.lerp(b.shadow_tint, w))
	RenderingServer.global_shader_parameter_set(&"mood_shade", lerpf(a.shade, b.shade, w))
	RenderingServer.global_shader_parameter_set(&"mood_ground_mul",
		lerpf(a.ground_mul, b.ground_mul, w))
	RenderingServer.global_shader_parameter_set(&"mood_fire_mul",
		lerpf(a.fire_mul, b.fire_mul, w))
	# 위상이 바뀌는 순간에만 알린다 (매 프레임 토스트가 뜨면 안 된다)
	var phase := (i + 1) % 3 if w > 0.5 else i
	if phase != int(current):
		current = phase as Phase
		_show_toast("%s  (%d/%d)" % [PRESETS[current].name, phase + 1, Phase.size()])
		print("[mood] %s" % PRESETS[current].name)

## 시간대를 **고른다** — 그쪽으로 서서히 넘어간다 (T 키 / 시계 클릭).
func select(t: Phase) -> void:
	_target = float(int(t))
	_show_toast("%s  (%d/%d)" % [PRESETS[t].name, int(t) + 1, Phase.size()])
	print("[mood] %s" % PRESETS[t].name)

## 즉시 그 시간대로 (초기화·디버그용). 전환 없이 갈아끼운다.
func apply(t: Phase) -> void:
	time = float(int(t))
	_target = time
	current = t
	_apply_time()

func cycle() -> void:
	# ⚠️ current 가 아니라 **도착점** 기준으로 다음을 고른다 — 넘어가는 중에 T 를 또 누르면
	#    current 는 아직 이전 위상이라 같은 곳으로 되돌아가 버린다.
	select(((int(_target) + 1) % Phase.size()) as Phase)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_T:
		cycle()
