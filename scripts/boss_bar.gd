class_name BossBar
extends Control

## 화면 상단 보스 체력 바. 보스가 살아 있을 때만 나타난다.
##
## 경험치 바(아래)와 같은 문법이되 **반대 방향으로 읽힌다**: 경험치는 차오르는 것(내 성장),
## 체력은 줄어드는 것(내가 깎아낸 몫). 그래서 색도 반대 계열 — 금색 대신 붉은색.
##
## 상태를 색으로 함께 말한다: **기절 중엔 바가 금색으로 번쩍인다** — 지금이 피해 +50% 창이라
## 숫자를 못 봐도 "지금 때려라"가 읽혀야 한다.

## UX 가이드 2.1 (2026-08-13): 상단 전폭 바가 시야를 가린다 -> 폭 40%로 줄여 중앙 정렬,
## 수치는 바 **안** 중앙에, 보스명은 위 중앙에, 왼쪽엔 둥근 프레임의 약식 초상화.
const H := 15.0            ## 체력 바 높이 (22 -> 15 슬림)
const STUN_H := 8.0        ## 기절 게이지 높이 (체력보다 얇게 — 부차적인 정보다)
const TOP := 34.0          ## 화면 위에서 띄우는 거리 (보스명이 위로 오므로 그만큼 내린다)
const SIDE := 0.30         ## 좌우 여백 (화면 폭 비율) — 0.18 에서 축소
const BORDER := 3.0
const PORTRAIT_R := 19.0   ## 초상화 원 반지름

var _boss: Enemy
var _shown := 1.0          ## 실제 비율을 뒤따라가는 값 — 큰 피해가 한 번에 깎이는 게 보이게
var _font: SystemFont

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # 화면 위 UI 가 클릭을 먹으면 공격 사각지대가 된다
	_font = CardUI.make_font(true)

func _process(delta: float) -> void:
	var b := get_tree().get_first_node_in_group("boss") as Enemy
	if b != null and b.dying:
		b = null
	_boss = b
	if _boss == null:
		if visible:
			visible = false
		return
	visible = true
	var target: float = clampf(_boss.health / maxf(_boss.stats.get_v(Stats.HEALTH), 1.0), 0.0, 1.0)
	_shown = move_toward(_shown, target, delta * 0.55)
	queue_redraw()

func _draw() -> void:
	if _boss == null:
		return
	var w := size.x * (1.0 - SIDE * 2.0)
	var box := Rect2(size.x * SIDE, TOP, w, H)
	var stunned: bool = _boss is Boss and (_boss as Boss).state == Boss.State.STUN

	CardUI.draw_round(self, box.grow(BORDER), CardUI.INK, CardUI.ROUND_BAR + BORDER)
	CardUI.draw_round(self, box, Color(0.24, 0.28, 0.34, 0.92), CardUI.ROUND_BAR)
	if _shown > 0.001:
		var fill := Rect2(box.position, Vector2(w * _shown, H))
		# 기절 중엔 금색 — "지금 때리면 1.5배" 라는 신호를 색으로 말한다
		var lo := CardUI.GOLD_DEEP if stunned else CardUI.RED
		var hi := CardUI.GOLD if stunned else CardUI.ORANGE
		CardUI.draw_round(self, fill, lo, CardUI.ROUND_BAR)
		CardUI.draw_round(self, Rect2(fill.position, Vector2(fill.size.x, H * 0.45)),
			hi, CardUI.ROUND_BAR)

	# 보스명 — 바 위 중앙. 기절 문구가 붙으면 금색으로 (지금이 기회라는 신호)
	var label := "거대 사슴벌레"
	if stunned:
		label += "   기절!  받는 피해 +50%"
	var lsz := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
	var at := Vector2(box.position.x + (w - lsz.x) * 0.5, TOP - 9.0)
	draw_string_outline(_font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 5, CardUI.INK)
	draw_string(_font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
		CardUI.GOLD if stunned else CardUI.CREAM)

	# 수치 — 바 안 중앙 (가이드: 바 내부 볼드). 바가 얇아도 윤곽선 덕에 읽힌다.
	var hp := "%d / %d" % [roundi(maxf(_boss.health, 0.0)), roundi(_boss.stats.get_v(Stats.HEALTH))]
	var sz := _font.get_string_size(hp, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	var hp_at := Vector2(box.position.x + (w - sz.x) * 0.5,
		box.position.y + H * 0.5 - sz.y * 0.5 + _font.get_ascent(13))
	draw_string_outline(_font, hp_at, hp, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 5, CardUI.INK)
	draw_string(_font, hp_at, hp, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, CardUI.CREAM)

	_portrait(Vector2(box.position.x - PORTRAIT_R - 12.0, box.position.y + H * 0.5), stunned)
	_draw_stun(box)

## 약식 초상화 — 둥근 프레임 안에 사슴벌레 머리(집게 두 개 + 머리통) 실루엣.
## 기절 중엔 테두리가 금색으로 바뀐다 (바·문구와 같은 신호를 삼중으로).
func _portrait(c: Vector2, stunned: bool) -> void:
	draw_circle(c, PORTRAIT_R + 3.0, CardUI.GOLD if stunned else CardUI.INK)
	draw_circle(c, PORTRAIT_R, Color(CardUI.PAPER, 0.95))
	# 머리통 (아래쪽 반원 느낌의 타원)
	draw_circle(c + Vector2(0.0, 4.5), 8.5, CardUI.INK)
	# 집게 — 좌우로 벌어진 호 두 개 (스태그의 정체성은 집게다)
	for sgn in [-1.0, 1.0]:
		draw_arc(c + Vector2(sgn * 5.0, -3.0), 8.0,
			PI * 0.5 + (0.15 if sgn > 0 else -0.15) - (PI * 0.9 if sgn > 0 else 0.0),
			PI * 1.4 - (PI * 0.9 if sgn > 0 else 0.0),
			12, CardUI.INK, 3.4, true)
	# 눈 한 쌍
	draw_circle(c + Vector2(-3.2, 3.0), 1.6, Color(CardUI.PAPER, 0.95))
	draw_circle(c + Vector2(3.2, 3.0), 1.6, Color(CardUI.PAPER, 0.95))

## 기절 게이지 — 체력 바 바로 아래 얇은 줄. **안 보이면 스택은 없는 것과 같다.**
## 세 가지 상태를 색으로 구분한다: 쌓이는 중(푸른빛) / 기절 중(금색, 남은 시간) / 면역(회색).
func _draw_stun(hp_box: Rect2) -> void:
	var b := _boss as Boss
	if b == null:
		return
	var box := Rect2(hp_box.position + Vector2(0.0, H + BORDER * 2.0 + 2.0),
		Vector2(hp_box.size.x, STUN_H))
	CardUI.draw_round(self, box.grow(2.0), CardUI.INK, CardUI.ROUND_BAR)
	CardUI.draw_round(self, box, Color(0.2, 0.24, 0.3, 0.9), CardUI.ROUND_BAR)

	var ratio := 0.0
	var fill_col := CardUI.GRAY_BLUE
	var text := ""
	if b.state == Boss.State.STUN:
		ratio = clampf(b._timer / Boss.STUN_TIME, 0.0, 1.0)   # 남은 기절 시간
		fill_col = CardUI.GOLD
		text = "기절 %.1f초" % b._timer
	elif b.stun_immune > 0.0:
		ratio = clampf(b.stun_immune / Boss.STUN_IMMUNE, 0.0, 1.0)
		fill_col = CardUI.MUTED
		text = "기절 면역 %.1f초" % b.stun_immune
	else:
		ratio = clampf(b.stun_stack / Boss.STUN_STACK_MAX, 0.0, 1.0)
		# 흘러내리는 중이면 색과 문구로 알린다 — 모르면 "왜 안 차지?"가 된다
		var draining: bool = b._since_hit > Boss.STACK_GRACE and b.stun_stack > 0.0
		fill_col = CardUI.WOOD if draining else CardUI.GRAY_BLUE
		text = "기절 %d%%%s" % [roundi(ratio * 100.0), "  (식는 중)" if draining else ""]
	if ratio > 0.001:
		CardUI.draw_round(self, Rect2(box.position, Vector2(box.size.x * ratio, STUN_H)),
			fill_col, CardUI.ROUND_BAR)

	var at := Vector2(box.position.x + 6.0, box.end.y + 14.0)
	draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, CardUI.INK)
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, fill_col)
