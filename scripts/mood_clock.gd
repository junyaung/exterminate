class_name MoodClock
extends Control

## 오른쪽 위 시간대 선택기 (유저 요청 2026-08-18).
## 원판을 **3등분**해서 낮·노을·밤을 보여주고, **클릭해서 고른다**.
##
## ⚠️ 자동으로 도는 시계가 아니다. 시간은 저절로 흐르지 않고, 고른 시간대로 Mood 가
##    서서히 넘어간다 (유저 지시: "자연스럽게 태양이 도는 건 빼고 선택식으로").
##
## ⚠️ **컨트롤 크기를 문자판에 딱 맞춘다.** 화면 전체(FULL_RECT)로 두고 마우스를 받으면
##    HUD 가 좌클릭을 전부 삼켜서 **망치를 못 휘두른다.** 문자판 위에서만 클릭을 먹어야 한다.

const R := 40.0            ## 문자판 반지름
const RIGHT := 22.0        ## 오른쪽 여백
const TOP_Y := 148.0       ## 위 여백 — HudModules 칩 더미 아래
const SEG := 26            ## 부채꼴 한 조각을 몇 각으로 그릴까

## 위상별 색. 하늘색이 아니라 **그 시간대를 한 색으로 요약한** 값이다.
const PHASE_COL := [
	Color("#fdd179"),      # 낮   — 밝은 금
	Color("#f77622"),      # 노을 — 주황
	Color("#405273"),      # 밤   — 남색
]
const LABEL := ["낮", "노을", "밤"]
## 안 고른 조각은 이만큼 죽인다 — 고른 것만 또렷해야 "지금 이거"가 읽힌다.
const DIM := 0.42

var mood: Mood

var _font: Font

func _ready() -> void:
	# 문자판 + 아래 이름표까지만 차지한다 (앵커는 오른쪽 위)
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	size = Vector2(R * 2.0, R * 2.0 + 26.0)
	position = Vector2(-RIGHT - R * 2.0, TOP_Y)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font

func _process(_delta: float) -> void:
	if mood != null:
		queue_redraw()

## 문자판 중심 (컨트롤 로컬 좌표).
func _center() -> Vector2:
	return Vector2(R, R)

## 각도 -> 위상. 12시에서 시계 방향으로 3등분.
func _phase_at(p: Vector2) -> int:
	var v := p - _center()
	var a := fposmod(atan2(v.y, v.x) + PI / 2.0, TAU)
	return clampi(int(a / (TAU / 3.0)), 0, 2)

func _gui_input(event: InputEvent) -> void:
	if mood == null:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var v: Vector2 = event.position - _center()
		if v.length() <= R:                 # 원 밖(모서리)은 무시한다
			mood.select(_phase_at(event.position) as Mood.Phase)
			accept_event()

func _draw() -> void:
	if mood == null:
		return
	var c := _center()
	var sel := int(mood._target)            # 고른 시간대 (도착점)
	# 12시 방향에서 시작해 시계 방향으로. 시계는 그래야 시계로 읽힌다.
	for i in 3:
		var a0 := -PI / 2.0 + TAU * (float(i) / 3.0)
		var a1 := -PI / 2.0 + TAU * (float(i + 1) / 3.0)
		var pts := PackedVector2Array([c])
		for k in SEG + 1:
			var a: float = lerpf(a0, a1, float(k) / float(SEG))
			pts.append(c + Vector2(cos(a), sin(a)) * R)
		var col: Color = PHASE_COL[i]
		if i != sel:
			col = col.lerp(Color("#bcad9f"), 1.0 - DIM)
		draw_colored_polygon(pts, col)
	# 조각 사이 칸막이 + 테두리 (먹선과 같은 색이라 HUD 의 다른 요소와 한 벌로 읽힌다)
	for i in 3:
		var a := -PI / 2.0 + TAU * (float(i) / 3.0)
		draw_line(c, c + Vector2(cos(a), sin(a)) * R, CardUI.INK, 2.0)
	draw_arc(c, R, 0.0, TAU, 48, CardUI.INK, 3.0)

	# 고른 조각의 가운데에 표식 — 넘어가는 중에는 바늘이 그쪽으로 따라간다
	var ang := -PI / 2.0 + TAU * ((mood.time + 0.5) / 3.0)
	var tip := c + Vector2(cos(ang), sin(ang)) * (R - 7.0)
	draw_line(c, tip, CardUI.INK, 4.0)
	draw_circle(c, 5.0, CardUI.INK)

	var name: String = LABEL[sel]
	var w := _font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	draw_string(_font, Vector2(c.x - w * 0.5, c.y + R + 18.0), name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, CardUI.INK)
