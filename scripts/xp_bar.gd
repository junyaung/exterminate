class_name XpBar
extends Control

## 좌하단 통합 플레이어 카드 — 성 아이콘 + 거점 체력 바 + LV + 경험치 바 (UX 가이드 2.3).
##
## 원래는 화면 전폭을 가로지르는 경험치 바 하나였고, 거점 체력·레벨은 우상단 텍스트에
## 흩어져 있었다. 셋을 한 카드로 모은 이유: 전부 "내 상태"라 눈이 한 곳만 보면 되고,
## 전폭 바가 사라져 전투 시야가 트인다. 이 게임엔 플레이어 캐릭터가 없으므로 가이드의
## '프로필 초상화' 자리는 **성**이 맡는다 — 지키는 대상이 곧 플레이어의 몸이다.
##
## 경험치 바의 원칙은 유지한다: 레벨업은 플레이어가 유일하게 기다리는 사건이라,
## 남은 양이 눈에 보여야 "한 무리만 더 잡으면 카드다"라는 긴장이 생긴다.
## (노드 이름은 tscn 호환 때문에 XpBar 그대로다)

const MARGIN := 22.0       ## 화면 구석 여백
const CARD_W := 252.0
const CARD_H := 78.0
const ICON_W := 54.0       ## 왼쪽 성 아이콘 칸
const BAR_H := 13.0
const BORDER := 3.0
## 바 안에 얹는 체력 수치 크기. BAR_H(13)보다 작아야 위아래로 안 넘친다.
const HP_FS := 11

var _level_system: LevelSystem
var _main: Main
var _font: SystemFont
var _panel: StyleBoxFlat
var _shown := 0.0          ## 실제 진행도를 뒤따라가는 값 — 뚝뚝 끊기지 않게 한 박자 늦게 찬다
var _hp_shown := 1.0       ## 거점 체력도 같은 방식 — 큰 피해가 한 번에 깎이는 게 보인다

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = CardUI.make_font(true)
	_panel = StyleBoxFlat.new()
	_panel.bg_color = Color(CardUI.PAPER, 0.92)
	_panel.set_corner_radius_all(int(CardUI.ROUND_PANEL))
	_panel.set_border_width_all(3)
	_panel.border_color = CardUI.INK
	_main = get_parent().get_parent() as Main   # XpBar -> HUD -> Main
	if _main != null:
		_level_system = _main.level_system

func _process(delta: float) -> void:
	if _level_system == null:
		return
	var target := _level_system.progress()
	# 레벨이 오르면 진행도가 1 에서 0 으로 떨어진다 — 그땐 따라가지 말고 즉시 되감는다
	_shown = target if target < _shown - 0.2 else move_toward(_shown, target, delta * 1.6)
	var hp: float = clampf(_main._base.health / maxf(_main._base.max_health, 1.0), 0.0, 1.0)
	_hp_shown = move_toward(_hp_shown, hp, delta * 0.8)
	queue_redraw()

func _draw() -> void:
	if _level_system == null:
		return
	var card := Rect2(MARGIN, size.y - MARGIN - CARD_H, CARD_W, CARD_H)
	_panel.draw(get_canvas_item(), card)
	_castle(Vector2(card.position.x + ICON_W * 0.5 + 4.0, card.position.y + CARD_H * 0.5))

	var bx := card.position.x + ICON_W + 12.0
	var bw := card.end.x - 14.0 - bx
	# 거점 체력 (위) — 체력 언어는 보스 바와 같은 붉은 계열. 낮을수록 위험이 색으로 온다.
	_bar(Rect2(bx, card.position.y + 14.0, bw, BAR_H), _hp_shown, CardUI.RED, CardUI.ORANGE)
	# 수치는 **바 한가운데**에 얹는다 (유저 지시 2026-08-14). 바 오른쪽 바깥에 두면
	# 카드 밖으로 삐져나가고, 무엇보다 "얼마 남았나"를 보려면 눈이 바에서 옆으로 튄다.
	# 현재/최대를 같이 보여야 452 가 많은 건지 적은 건지 판단이 된다.
	var hp_txt := "%d/%d" % [roundi(maxf(_main._base.health, 0.0)),
		roundi(_main._base.max_health)]
	_label_center(Rect2(bx, card.position.y + 14.0, bw, BAR_H), hp_txt, HP_FS)
	# 경험치 (아래) — 차오르는 것은 금색 (기존 언어 유지)
	_bar(Rect2(bx, card.end.y - 14.0 - BAR_H, bw, BAR_H), _shown, CardUI.GOLD_DEEP, CardUI.GOLD)
	# LV — 두 바 사이. 카드에서 가장 굵은 글자여야 한다 (레벨이 곧 진행도다)
	var lv := "LV %d" % _level_system.level
	var at := Vector2(bx, card.position.y + CARD_H * 0.5 + 6.0)
	draw_string_outline(_font, at, lv, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, CardUI.INK)
	draw_string(_font, at, lv, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, CardUI.CREAM)

func _bar(box: Rect2, ratio: float, lo: Color, hi: Color) -> void:
	CardUI.draw_round(self, box.grow(BORDER), CardUI.INK, CardUI.ROUND_BAR + BORDER)
	CardUI.draw_round(self, box, Color(0.24, 0.28, 0.34, 0.9), CardUI.ROUND_BAR)
	if ratio > 0.001:
		var fill := Rect2(box.position, Vector2(box.size.x * ratio, box.size.y))
		CardUI.draw_round(self, fill, lo, CardUI.ROUND_BAR)
		# 위쪽 절반만 밝게 — 단색 띠보다 부피가 생긴다
		CardUI.draw_round(self, Rect2(fill.position, Vector2(fill.size.x, box.size.y * 0.45)),
			hi, CardUI.ROUND_BAR)

## 바 안에 얹는 수치. 가로·세로 모두 가운데.
## ⚠️ 바탕이 밝은 붉은색이라 먹선(draw_string_outline)이 없으면 글자가 묻힌다.
##    외곽선을 굵게(5) 줘서 채워진 구간 위에서도 크림색 글자가 읽히게 한다.
func _label_center(box: Rect2, text: String, fs: int) -> void:
	var tsz := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var at := Vector2(box.position.x + (box.size.x - tsz.x) * 0.5,
		box.position.y + (box.size.y - tsz.y) * 0.5 + _font.get_ascent(fs))
	draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, CardUI.INK)
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, CardUI.CREAM)

## 성 실루엣 — 몸통 + 총안(요철) 두 개 + 문. 게임 속 거점은 흰 상자지만 아이콘은
## '성'으로 읽혀야 하므로 요철을 준다 (실물 재현이 아니라 기호다).
func _castle(c: Vector2) -> void:
	var w := 34.0
	var h := 30.0
	var top := c.y - h * 0.5
	CardUI.draw_round(self, Rect2(c.x - w * 0.5 - 2.5, top - 8.0 - 2.5, w + 5.0, h + 8.0 + 5.0),
		CardUI.INK, CardUI.ROUND_PIP + 2.0)
	CardUI.draw_round(self, Rect2(c.x - w * 0.5, top, w, h),
		Color("#f1f6f0"), CardUI.ROUND_PIP)
	for i in 3:                                  # 총안 세 개
		CardUI.draw_round(self, Rect2(c.x - w * 0.5 + float(i) * (w / 3.0) + 1.5, top - 8.0,
			w / 3.0 - 4.5, 9.0), Color("#f1f6f0"), 2.0)
	CardUI.draw_round(self, Rect2(c.x - 5.0, c.y + h * 0.5 - 12.0, 10.0, 12.0),
		CardUI.INK, 2.5)
