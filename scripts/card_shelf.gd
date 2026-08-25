class_name CardShelf
extends CanvasLayer

## 획득한 카드 보관함. **창(panel)** 한 겹 — Tab 으로 여는 상세 목록.
## 이름·설명·중첩 수·분류까지 전부. 여기선 시간이 멈추므로 읽어도 된다.
##
## 경험치 바 위에 항상 떠 있던 축소 타일 줄(띠)은 유저 지시로 제거했다 (2026-08-13).
## 상시 표시가 필요해지면 _tile() 이 아직 있으므로 되살리기는 쉽다 — 다만 그때는
## **마우스를 통과시켜야**(MOUSE_FILTER_IGNORE) 한다. 화면 위 Control 이 클릭을 먹으면
## `HammerStrike._unhandled_input` 까지 안 내려가서 그 자리가 **공격 사각지대**가 된다.

var _ui: CardUI
var _panel_root: Control
var _list: VBoxContainer
var _open := false
var _font: SystemFont
var _font_bold: SystemFont

func _ready() -> void:
	layer = 9                                   # CardUI(10) 아래
	process_mode = Node.PROCESS_MODE_ALWAYS     # 멈춘 동안에도 열고 닫혀야 한다
	_font = CardUI.make_font()
	_font_bold = CardUI.make_font(true)
	_ui = get_parent().get_node_or_null("CardUI") as CardUI
	_build()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode != KEY_TAB:
		return
	# 드래프트가 떠 있으면 무시한다 — 두 화면이 같은 pause 를 두고 다투면
	# 한쪽을 닫는 순간 게임이 풀려버린다.
	if _ui != null and _ui._open:
		return
	if _open:
		_close()
	else:
		_show()
	get_viewport().set_input_as_handled()

func _show() -> void:
	_open = true
	_fill_list()
	_panel_root.visible = true
	get_tree().paused = true

func _close() -> void:
	_open = false
	_panel_root.visible = false
	get_tree().paused = false

# --- 데이터 -----------------------------------------------------------------

## [{card = 정의, count = 중첩 수}] — 처음 얻은 순서를 유지한다.
## 순서를 유지하는 이유: 빌드는 **이야기**다. 왼쪽부터 읽으면 이 판이 어떻게 흘러왔는지 보인다.
func _owned() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var index := {}
	if _ui == null:
		return out
	for id in _ui.picked:
		if index.has(id):
			out[index[id]].count += 1
			continue
		var card := CardCatalog.by_id(id)
		if card.is_empty():
			continue
		index[id] = out.size()
		out.append({card = card, count = 1})
	return out

# --- UI 조립 ---------------------------------------------------------------

func _build() -> void:
	_panel_root = Control.new()
	_panel_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel_root.visible = false
	add_child(_panel_root)

	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.1, 0.14, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP   # 열려 있는 동안엔 뒤로 가는 클릭을 막는다
	_panel_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.add_child(center)

	var book := PanelContainer.new()
	var bs := StyleBoxFlat.new()
	bs.bg_color = CardUI.PAPER
	bs.set_corner_radius_all(int(CardUI.ROUND_PANEL) + 6)
	bs.set_border_width_all(5)
	bs.border_color = CardUI.INK
	bs.shadow_color = Color(0, 0, 0, 0.35)
	bs.shadow_size = 10
	bs.shadow_offset = Vector2(0, 6)
	bs.set_content_margin_all(22)
	book.add_theme_stylebox_override("panel", bs)
	book.custom_minimum_size = Vector2(520, 0)
	center.add_child(book)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	book.add_child(col)

	var title := _label("획득한 권능", 26, CardUI.INK, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	col.add_child(_list)

	var hint := _label("[Tab] 닫기", 14, CardUI.MUTED, false)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)

## 카드 한 장의 축소 타일. 드래프트 카드와 같은 문법 — 등급색 바탕 + 먹선 + 같은 아이콘.
## 지금은 Tab 창 목록에서만 쓴다.
func _tile(card: Dictionary, count: int, side: float) -> Control:
	var rare: bool = card.rarity == &"rare"
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(side, side)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = CardUI.GOLD if rare else CardUI.PAPER
	sb.set_corner_radius_all(int(CardUI.ROUND_PANEL))
	sb.set_border_width_all(3)
	sb.border_color = CardUI.INK
	sb.set_content_margin_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	holder.add_child(panel)

	var icon := CardUI.CardIcon.new()
	icon.kind = card.id
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(icon)

	# 중첩 배지 — 같은 카드를 또 먹으면 타일이 늘지 않고 숫자만 오른다
	if count > 1:
		var badge := Label.new()
		badge.text = "×%d" % count
		badge.add_theme_font_override("font", _font_bold)
		badge.add_theme_font_size_override("font_size", int(side * 0.31))
		badge.add_theme_color_override("font_color", CardUI.CREAM)
		# 먹선 테두리를 글자에 둘러 어느 바탕에서도 읽히게 한다
		badge.add_theme_constant_override("outline_size", 6)
		badge.add_theme_color_override("font_outline_color", CardUI.INK)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
		badge.offset_left = -side
		badge.offset_top = -side * 0.46
		badge.offset_right = 3.0
		badge.offset_bottom = 3.0
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		holder.add_child(badge)
	return holder

## Tab 창 목록 채우기.
func _fill_list() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	# 비어 있으면 아무것도 안 적는다 (유저 지시 2026-08-13) — 제목과 [Tab] 닫기만 남는다.
	# 한 장도 없는 시점은 런 시작 직후뿐이라 굳이 설명할 게 없다.
	for row in _owned():
		_list.add_child(_row(row.card, row.count))

## 목록 한 줄: 타일 + (이름 ×N / 설명) + 등급·분류.
func _row(card: Dictionary, count: int) -> Control:
	var rare: bool = card.rarity == &"rare"
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	line.add_child(_tile(card, count, 54.0))

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title: String = card.cname if count <= 1 else "%s  ×%d" % [card.cname, count]
	text.add_child(_label(title, 19, CardUI.INK, true))
	var desc := _label(String(card.desc).replace("\n", " "), 14, Color("#734c44"), false)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(300, 0)
	text.add_child(desc)
	line.add_child(text)

	var tag := _label("%s · %s" % ["희귀" if rare else "일반", card.cat], 13,
		CardUI.GOLD_DEEP if rare else CardUI.MUTED, true)
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(tag)
	return line

func _label(text: String, size: int, color: Color, bold: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font_bold if bold else _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
