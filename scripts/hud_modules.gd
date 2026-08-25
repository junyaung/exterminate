class_name HudModules
extends Control

## 우상단 전투 통계 — 텍스트 줄글 대신 아이콘 모듈 (UX 가이드 2.1, 2026-08-13).
## **세로 한 줄**로 쌓는다 (유저 지시 2026-08-13):
##   ACT II      <- 지금 어느 막인가. 맨 위 = 가장 먼저 눈에 든다
##   [시계] 01:10
##   [해골] 42
## 눈은 전투에 있으므로 읽는 게 아니라 **스치듯 알아보는** 것이 목표다 — 아이콘이 항목명을
## 대신한다. 맵에 몇 마리 있는지(SWARM)는 뺐다 — 화면을 보면 이미 아는 정보였다.
## 그 아래 연격 ●●●●● / 대강타 ■■■□ 도 글자 없이 점·사각형으로만 그린다.
##
## 아이콘은 카드 아이콘과 같은 방식(_draw + 먹선 실루엣)이라 외부 에셋이 없다.
## 새 텍스트 수칙(스위치 휴대모드 기준): 숫자는 굵게 + 윤곽선 필수, 13pt 미만 금지.

const TOP := 14.0
const RIGHT := 20.0
const CHIP_H := 34.0
const CHIP_GAP := 7.0      ## 세로 간격
const FS := 17             ## 칩 숫자 크기
const ACT_FS := 20         ## 막 표시 — 이 줄이 가장 커야 위계가 선다
## 막은 로마 숫자로 (유저 표기 "ACT I"). 막 수가 늘면 여기만 늘리면 된다.
const ACT_ROMAN := ["I", "II", "III", "IV", "V", "VI"]

var _main: Main
var _hammer: Node
var _font: SystemFont
var _chip: StyleBoxFlat

func _ready() -> void:
	# ⚠️ set_anchors_preset 은 **현재 크기를 유지**하도록 오프셋을 보정한다. 코드로 만든
	#    Control 은 이미 트리에 들어온 뒤라 0×0 이 그대로 고정된다 (실측 — 칩이 전부
	#    화면 왼쪽 밖 음수 좌표에 그려졌다). 오프셋까지 리셋하는 버전을 써야 한다.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # 클릭을 먹으면 공격 사각지대가 된다
	_font = CardUI.make_font(true)
	_chip = StyleBoxFlat.new()
	_chip.bg_color = Color(CardUI.PAPER, 0.92)
	_chip.set_corner_radius_all(int(CardUI.ROUND_PANEL))
	_chip.set_border_width_all(3)
	_chip.border_color = CardUI.INK
	_main = get_parent().get_parent() as Main    # HudModules -> HUD -> Main

func _process(_delta: float) -> void:
	if _hammer == null:
		_hammer = get_tree().get_first_node_in_group(&"hammer")
	queue_redraw()

func _draw() -> void:
	if _main == null or _main.game_over:
		return                                   # 승패 화면은 Status 라벨이 맡는다
	# 위에서 아래로 쌓는다. 전부 오른쪽 끝 정렬이라 자릿수가 변해도 오른쪽이 안 흔들린다.
	# ⚠️ 액트(5분 고정) -> **웨이브**(전멸해야 넘어감)로 바뀌었다 (2026-08-18).
	#    로마 숫자를 쓰던 자리인데 10까지 가므로 "3/10" 이 더 빨리 읽힌다.
	var act := "WAVE %d/%d" % [_main.wave + 1, Main.WAVE_COUNT]
	var y := _stat_chip(TOP, act, Callable(), ACT_FS)
	# 시간 표기는 Main.mmss 하나로 모았다 — 세 군데서 t/60 을 따로 적고 있었다
	y = _stat_chip(y, Main.mmss(int(_main.elapsed)), _icon_clock, FS)
	y = _stat_chip(y, "%d" % _main.kills, _icon_skull, FS)

	# 연격/대강타 — 칩 아래. 카드를 가진 판에서만 그린다.
	y += 6.0
	if _hammer != null and _hammer.combo_level > 0:
		_combo_row(y)
		y += 22.0
	if _hammer != null and _hammer.has_beat:
		_beat_row(y)

## 칩 하나: [아이콘] 글자. icon 이 비어 있으면 글자만. **다음 칩의 위쪽 y** 를 돌려준다.
## 오른쪽 끝(size.x - RIGHT)에 붙여 그리므로 폭이 달라도 오른쪽 모서리가 일직선으로 선다.
func _stat_chip(top_y: float, text: String, icon: Callable, fs: int) -> float:
	var tsz := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var icon_w := 26.0 if icon.is_valid() else 0.0
	var w := tsz.x + icon_w + 24.0
	var box := Rect2(size.x - RIGHT - w, top_y, w, CHIP_H)
	_chip.draw(get_canvas_item(), box)
	if icon.is_valid():
		icon.call(Vector2(box.position.x + 12.0 + 7.0, box.position.y + CHIP_H * 0.5))
	var at := Vector2(box.position.x + 12.0 + icon_w,
		box.position.y + CHIP_H * 0.5 - tsz.y * 0.5 + _font.get_ascent(fs))
	draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, CardUI.PAPER)
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, CardUI.INK)
	return box.end.y + CHIP_GAP

## 시계 — 경과 시간. 테두리 원 + 12시 눈금 + 바늘 두 개.
func _icon_clock(c: Vector2) -> void:
	draw_arc(c, 7.6, 0.0, TAU, 24, CardUI.INK, 2.2, true)
	draw_line(c + Vector2(0.0, -7.6), c + Vector2(0.0, -5.2), CardUI.INK, 2.0)
	draw_line(c, c + Vector2(0.0, -4.6), CardUI.INK, 2.0)     # 긴 바늘 (12시)
	draw_line(c, c + Vector2(3.6, 1.2), CardUI.INK, 2.0)      # 짧은 바늘 (4시 방향)

## 해골 — 처치 수. 두개골 + 턱 + 눈구멍.
func _icon_skull(c: Vector2) -> void:
	draw_circle(c + Vector2(0.0, -1.5), 6.5, CardUI.INK)
	draw_rect(Rect2(c.x - 4.0, c.y + 2.0, 8.0, 5.0), CardUI.INK, true)
	draw_circle(c + Vector2(-2.6, -2.0), 1.7, Color(CardUI.PAPER, 0.95))
	draw_circle(c + Vector2(2.6, -2.0), 1.7, Color(CardUI.PAPER, 0.95))
	for i in 3:
		draw_line(c + Vector2(-3.0 + float(i) * 3.0, 4.0),
			c + Vector2(-3.0 + float(i) * 3.0, 6.5), Color(CardUI.PAPER, 0.95), 1.4)

## 연격 ●●●○○ — 찬 만큼 주황, 빈 칸은 홈만. 배율 텍스트는 마지막에 작게.
func _combo_row(y: float) -> void:
	var mx: int = _hammer.combo_max()
	var r := 7.0
	var gap := 20.0
	var x := size.x - RIGHT - r
	for i in mx:
		var filled: bool = (mx - 1 - i) < _hammer._combo   # 오른쪽 정렬이라 뒤에서부터 채운다
		draw_circle(Vector2(x, y + r), r, CardUI.INK)
		draw_circle(Vector2(x, y + r), r - 2.5,
			CardUI.ORANGE if filled else Color(CardUI.MUTED, 0.5))
		x -= gap
	if _hammer._combo > 0:
		var txt := "+%d%%" % roundi((_hammer.combo_mult() - 1.0) * 100.0)
		var tsz := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		var at := Vector2(x - tsz.x + 8.0, y + r - tsz.y * 0.5 + _font.get_ascent(14))
		draw_string_outline(_font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, CardUI.PAPER)
		draw_string(_font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, CardUI.INK)

## 대강타 ■■■□ — 다 차기 직전(다음 타가 대강타)이면 금색으로 전부 반짝.
func _beat_row(y: float) -> void:
	var need := HammerStrike.BEAT_EVERY - 1
	var s := 13.0
	var gap := 20.0
	var x := size.x - RIGHT - s
	var primed: bool = _hammer._beat >= need
	for i in need:
		var filled: bool = (need - 1 - i) < _hammer._beat
		var box := Rect2(x - s * 0.0, y, s, s)
		box.position.x = x - s
		CardUI.draw_round(self, box.grow(2.5), CardUI.INK, CardUI.ROUND_PIP + 2.0)
		CardUI.draw_round(self, box, CardUI.GOLD if primed else \
			(CardUI.RED if filled else Color(CardUI.MUTED, 0.5)), CardUI.ROUND_PIP)
		x -= gap
