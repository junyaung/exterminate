class_name CooldownHud
extends CanvasLayer

## L / CHG / R 세 공격의 쿨타임 도넛 — 화면 오른쪽 아래 (유저 스펙 2026-08-13).
## 도넛 테두리를 쿨타임이 시계방향으로 한 바퀴 채우고, 다 차는 순간 한 번 반짝인다.
## 반짝임이 "지금 눌러도 된다" 신호다. 숫자를 안 쓰는 이유: 전투 중 눈은 구석의 숫자를
## 못 읽는다 — 채움과 번쩍임을 곁눈으로 스치면 충분하다 (연격 ● 표시와 같은 원칙).
##
## CHG 도넛은 두 얼굴이다: 평소엔 L 과 같은 쿨을 비추고, **차징하는 동안은 차징 게이지**가
## 된다 — 다 차면 반짝여서 "이제 놔라"를 알려준다.
##
## ⚠️ 전부 MOUSE_FILTER_IGNORE — 화면 위 Control 이 클릭을 먹으면
## HammerStrike._unhandled_input 까지 안 내려가 그 자리가 공격 사각지대가 된다 (CardShelf 참고).

const R := 22.0          ## 도넛 반지름
const W := 8.0           ## 도넛 두께
const GAP := 60.0        ## 도넛 중심 간격
const BOTTOM := 78.0     ## 화면 아래 여백 — 경험치 바(높이 16 + 여백 26) 위
const RIGHT := 42.0
const FLASH_TIME := 0.35

## 옵션에서 껐다 켜는 스위치. **옵션 화면이 생기면 여기 하나만 연결하면 된다** —
## 끄면 그리기뿐 아니라 _process 까지 멈춰서 완전히 없는 것과 같아진다.
## (아직 옵션 화면이 없어 개발용 H 키로 토글한다 — main.gd 참고)
var enabled := true:
	set(value):
		enabled = value
		set_process(value)
		if _canvas != null:
			_canvas.visible = value
		if value:
			_sync()      # 꺼져 있는 동안 쿨이 돌았을 테니 상태를 다시 맞춘다

var _hammer: Node
var _canvas: Control
var _font: SystemFont
var _ready_prev := [true, true, true]
var _flash := [0.0, 0.0, 0.0]

func _ready() -> void:
	layer = 8                               # CardShelf(9)/CardUI(10) 아래
	_font = CardUI.make_font(true)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_paint)
	add_child(_canvas)
	_canvas.visible = enabled
	set_process(enabled)

func _process(delta: float) -> void:
	if _hammer == null:
		_hammer = get_tree().get_first_node_in_group(&"hammer")
		if _hammer == null:
			return
	var readies := [_l_ready(), _chg_ready(), _r_ready()]
	for i in 3:
		_flash[i] = maxf(_flash[i] - delta, 0.0)
		if readies[i] and not _ready_prev[i]:
			_flash[i] = FLASH_TIME          # 준비 완료 순간에만 한 번 반짝
		_ready_prev[i] = readies[i]
	_canvas.queue_redraw()

## 지금 상태를 '이미 봤다'로 기록한다. 켜자마자 쿨이 다 차 있으면 반짝임이 한 번 터지는데,
## 그건 방금 준비된 게 아니라 꺼져 있는 동안 준비된 것이라 거짓 신호다.
func _sync() -> void:
	if _hammer == null:
		_hammer = get_tree().get_first_node_in_group(&"hammer")
		if _hammer == null:
			return
	_ready_prev = [_l_ready(), _chg_ready(), _r_ready()]
	_flash = [0.0, 0.0, 0.0]

# --- 도넛별 진행도/준비 (HUD 가 hammer 내부를 직접 읽는 건 main.gd 의 연격 표시와 같은 방식) ---

func _l_progress() -> float:
	if _hammer._cd <= 0.0:
		return 1.0
	return 1.0 - _hammer._cd / _hammer._cd_total

func _l_ready() -> bool:
	return _hammer._cd <= 0.0

func _chg_progress() -> float:
	if _hammer._charging:
		return _hammer.charge_ratio()
	return _l_progress()

func _chg_ready() -> bool:
	if _hammer._charging:
		return _hammer.charge_ratio() >= 1.0
	return _l_ready()

func _r_progress() -> float:
	if _hammer._special_cd <= 0.0:
		return 1.0
	return 1.0 - _hammer._special_cd / maxf(_hammer.stats.get_v(Stats.COOLDOWN_SPECIAL), 0.001)

func _r_ready() -> bool:
	return _hammer._special_cd <= 0.0 and not _hammer._special_active

# --- 그리기 -----------------------------------------------------------------

func _paint() -> void:
	if _hammer == null:
		return
	var sz := _canvas.size
	var cy := sz.y - BOTTOM
	var rows := [
		["L", _l_progress(), _l_ready(), CardUI.RING],
		["CHG", _chg_progress(), _chg_ready(), CardUI.GOLD_DEEP],
		["R", _r_progress(), _r_ready(), CardUI.RED],
	]
	for i in rows.size():
		_ring(Vector2(sz.x - RIGHT - GAP * float(rows.size() - 1 - i), cy),
			rows[i][0], rows[i][1], rows[i][2], rows[i][3], _flash[i])

func _ring(c: Vector2, label: String, progress: float, is_ready: bool,
		sweep: Color, flash: float) -> void:
	# 먹선 → 빈 트랙 → 채움 순서. 채움은 12시에서 시작해 시계방향 (아날로그 시계 문법).
	_canvas.draw_arc(c, R, 0.0, TAU, 48, Color(CardUI.INK, 0.9), W + 5.0, true)
	_canvas.draw_arc(c, R, 0.0, TAU, 48, Color(CardUI.MUTED, 0.55), W, true)
	if progress > 0.004:
		_canvas.draw_arc(c, R, -TAU * 0.25, -TAU * 0.25 + TAU * clampf(progress, 0.0, 1.0),
			48, sweep, W, true)
	# 픽토그램 — 글자 대신 '무슨 공격인지'를 그림으로 (UX 가이드 2.2). 준비 안 됐으면 흐리게.
	# 어느 버튼인지는 도넛 아래의 작은 글자 배지가 맡는다 (그림=기능, 배지=입력).
	var col := CardUI.INK if is_ready else Color(CardUI.INK, 0.4)
	match label:
		"L":
			_glyph_strike(c, col)
		"CHG":
			_glyph_charge(c, col)
		"R":
			_glyph_drop(c, col)
	var fs := 8
	var tsz := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	_canvas.draw_string_outline(_font, Vector2(c.x - tsz.x * 0.5, c.y + R + 14.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(CardUI.PAPER, 0.9))
	_canvas.draw_string(_font, Vector2(c.x - tsz.x * 0.5, c.y + R + 14.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	# 반짝 — 밝은 고리가 바깥으로 퍼지며 사라진다 (준비 완료의 '핑')
	if flash > 0.0:
		var t := flash / FLASH_TIME          # 1 -> 0
		_canvas.draw_arc(c, R + (1.0 - t) * 9.0, 0.0, TAU, 48,
			Color(CardUI.PAPER, t * 0.9), W * 0.7, true)

## L: 비스듬히 내려치는 망치 — 머리(사각) + 자루. 게임 속 평타의 축소판.
func _glyph_strike(c: Vector2, col: Color) -> void:
	var cv := _canvas
	var head := Transform2D(deg_to_rad(-34.0), c + Vector2(2.5, -3.5))
	cv.draw_set_transform_matrix(head)
	cv.draw_rect(Rect2(-6.5, -4.5, 13.0, 9.0), col, true)
	cv.draw_rect(Rect2(-1.8, 4.5, 3.6, 10.0), col, true)   # 자루 (머리에서 아래로)
	cv.draw_set_transform_matrix(Transform2D())
	# 타격점 스파크
	for i in 3:
		var a := PI * 0.6 + float(i) * 0.5
		cv.draw_line(c + Vector2(cos(a), sin(a)) * 6.0 + Vector2(-6.0, 8.0),
			c + Vector2(cos(a), sin(a)) * 10.5 + Vector2(-6.0, 8.0), col, 2.0)

## CHG: 위로 차오르는 파동 세 겹 — '기 모으기'.
func _glyph_charge(c: Vector2, col: Color) -> void:
	for i in 3:
		var r := 4.5 + float(i) * 4.0
		_canvas.draw_arc(c + Vector2(0.0, 6.0), r, PI + 0.5, TAU - 0.5, 12, col, 2.6, true)

## R: 수직 낙하 망치 — 세운 망치(자루 위, 머리 아래) + 아래 화살촉.
func _glyph_drop(c: Vector2, col: Color) -> void:
	var cv := _canvas
	cv.draw_rect(Rect2(c.x - 1.8, c.y - 11.0, 3.6, 10.0), col, true)   # 자루 (위)
	cv.draw_rect(Rect2(c.x - 6.0, c.y - 2.0, 12.0, 8.0), col, true)    # 머리 (아래)
	cv.draw_colored_polygon(PackedVector2Array([
		c + Vector2(-5.0, 8.5), c + Vector2(5.0, 8.5), c + Vector2(0.0, 13.5)]), col)
