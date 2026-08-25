class_name CameraTuner
extends Node

## 카메라 시점을 **게임을 돌린 채로** 만져보는 개발 도구 (유저 요청 2026-08-16:
## "Taur·Thronefall 처럼 아주 높은 데서 내려다보고, 지상 몹은 작게").
## 시점은 눈으로 봐야 정해지는 문제라 수치를 코드에 박아두고 껐다 켜는 대신
## 키로 돌려보고 마음에 드는 값을 P 로 찍어 main.tscn 에 옮겨 적는 방식이다.
##
## 키:
##   ⚠️ 전부 **Alt 를 누른 채로** — 방향키는 카메라 이동이 쓴다.
##   C        직교 <-> 원근 전환 (원근이 '높이'를 만든다 — 아래 주석 참고)
##   ↑ / ↓    줌 아웃 / 인   (직교=size, 원근=거리)
##   ← / →    피치 낮추기 / 높이기 (내려다보는 각도)
##   [ / ]    원근 화각(FOV) — 좁을수록 원근이 약해져 직교에 가까워진다
##   P        지금 값을 콘솔에 출력 (main.tscn 에 옮겨 적을 형태로)
##
## ⚠️ **직교 카메라는 아무리 높이 올려도 시점이 안 변한다** — 평행 투영이라 거리와 무관하게
##    크기가 같다. "높은 데서 본다"는 느낌은 **원근 + 좁은 화각 + 먼 거리**가 만든다.
##    Thronefall/Taur 이 그 조합이다: 살짝 수렴하는 수직선이 높이를 읽히게 한다.

const FOCUS := Vector3.ZERO      ## 항상 이 지점을 바라본다 (기지와 전장 사이)
const PITCH_MIN := -85.0
const PITCH_MAX := -25.0

var cam: Camera3D
var yaw := 45.0                  ## Main.VIEW_YAW 와 반드시 같아야 한다 (화면축 규약)
var pitch := -50.0
var ortho_size := 30.0
var dist := 60.0                 ## 원근일 때 초점까지의 거리
var fov := 28.0

func _ready() -> void:
	if cam == null:
		return
	# 씬에 적혀 있는 현재 값에서 출발한다 — 도구를 켰다고 화면이 튀면 비교가 안 된다.
	yaw = Main.VIEW_YAW
	pitch = rad_to_deg(cam.rotation.x)
	ortho_size = cam.size
	fov = cam.fov
	dist = cam.global_position.distance_to(FOCUS)
	# ⚠️ **조합키(Alt)를 안내문에 반드시 적는다.** "C 직교/원근" 이라고만 찍어놨더니
	#    C 만 눌러보고 "안 먹는다"가 됐다 (유저 문의 2026-08-17). 방향키를 카메라 이동에
	#    내주면서 시점 조정을 전부 Alt 조합으로 옮긴 게 안내문에 반영이 안 돼 있었다.
	print("[camera] Alt+C 직교/원근  Alt+↑↓ 줌  Alt+←→ 각도  Alt+[ ] 화각  Alt+P 값 출력")

func _unhandled_input(event: InputEvent) -> void:
	if cam == null or not (event is InputEventKey and event.pressed):
		return
	# ⚠️ 방향키는 이제 **카메라 이동**이 쓴다 (유저 요청 2026-08-16). 개발용 시점 조정은
	#    Alt 를 누른 채로만 듣는다 — 둘이 같은 키를 먹으면 화면이 움직이면서 각도까지 바뀐다.
	if not event.alt_pressed:
		return
	match event.keycode:
		KEY_C:
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE \
				if cam.projection == Camera3D.PROJECTION_ORTHOGONAL \
				else Camera3D.PROJECTION_ORTHOGONAL
			print("[camera] ", "원근(perspective)" if cam.projection == 1 else "직교(orthogonal)")
		KEY_UP:
			ortho_size *= 1.08
			dist *= 1.08
		KEY_DOWN:
			ortho_size /= 1.08
			dist /= 1.08
		KEY_RIGHT:
			pitch = maxf(pitch - 2.0, PITCH_MIN)     # 더 수직으로
		KEY_LEFT:
			pitch = minf(pitch + 2.0, PITCH_MAX)
		KEY_BRACKETLEFT:
			fov = maxf(fov - 2.0, 8.0)
		KEY_BRACKETRIGHT:
			fov = minf(fov + 2.0, 60.0)
		KEY_P:
			_print_values()
			return
		_:
			return
	_apply()

func _apply() -> void:
	cam.size = ortho_size
	cam.fov = fov
	# 화각이 좁아지면 같은 거리에서 화면이 좁아진다 — 거리를 보정해 **보이는 폭을 유지**한다.
	# 안 그러면 [ ] 를 누를 때마다 줌까지 같이 변해서 무엇이 달라졌는지 못 읽는다.
	# 원근 거리는 **보이는 세로 폭이 직교 size 와 같아지도록** 역산한다. 그래야 C 로 전환하거나
	# 화각을 바꿔도 줌이 안 변해서 "무엇이 달라졌는지"가 하나씩 읽힌다.
	# Godot 의 Camera3D.size 는 세로 **전체** 폭이라 반폭은 size/2.
	var d: float = dist if cam.projection == Camera3D.PROJECTION_ORTHOGONAL \
		else (ortho_size * 0.5) / tan(deg_to_rad(fov * 0.5))
	# ⚠️ 화각을 좁히면 거리가 400 을 넘는다 — far 를 안 밀면 지면이 통째로 잘려 화면이 빈다.
	cam.far = maxf(500.0, d * 2.0)
	var basis := Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0),
		EULER_ORDER_YXZ)
	cam.global_transform = Transform3D(basis, FOCUS + basis.z * d)  # 카메라는 -Z 를 본다
	# 그림자 최대 거리도 같이 밀어준다 — 안 밀면 줌 아웃했을 때 먼 쪽 그림자가 뚝 끊긴다.
	var sun := cam.get_parent().get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.directional_shadow_max_distance = maxf(120.0, ortho_size * 4.0)
	# 스폰 존도 같이 밀어낸다 — 안 밀면 넓힌 시야 안에서 적이 튀어나온다.
	Main.view_scale = ortho_size / Main.VIEW_SIZE

func _print_values() -> void:
	var ortho: bool = cam.projection == Camera3D.PROJECTION_ORTHOGONAL
	print("[camera] --- main.tscn 에 옮겨 적을 값 -----------------------------")
	print("  projection = %d   # 0 원근 / 1 직교" % (1 if ortho else 0))
	print("  pitch %.1f°  yaw %.1f°  (Main.VIEW_YAW 와 yaw 는 같아야 한다)" % [pitch, yaw])
	if ortho:
		print("  size = %.1f" % ortho_size)
	else:
		print("  fov = %.1f   초점까지 거리 %.1f" % [fov, cam.global_position.length()])
	print("  transform = Transform3D%s" % [cam.global_transform])
	# Camera3D.size 는 세로 **전체** 폭이다 (반폭이 아니다 — 처음에 ×2 로 찍어서 틀렸다).
	print("  ⚠️ 보이는 세로 폭이 %.1f 유닛이다. Main.VIEW_SIZE 를 같은 값으로 맞춰야"
		% ortho_size)
	print("     스폰 존이 화면 밖에 남는다 (안 맞추면 적이 화면 안에서 튀어나온다).")
