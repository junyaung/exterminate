class_name CardUI
extends CanvasLayer

## 레벨업 카드 선택 화면. `LevelSystem.leveled` 를 받아 자동으로 열린다 (3 키는 디버그용 강제 열기).
## 서지를 통째로 쓸어 한 번에 여러 레벨이 오르면 **대기열에 쌓아 한 장씩 순서대로** 고르게 한다.
##
## 스타일: Godot Control 만으로 만든 카툰 카드 — 망치 셀 셰이딩과 같은 문법으로,
## 두꺼운 먹선 테두리 + 단색 면 + 살짝 비뚤어진 각도 + 손그림 아이콘(_draw).
## 진짜 아트는 나중에 블렌더에서 뽑을 예정이라 여기선 레이아웃과 톤만 잡는다.
##
## 시선 순서(디자인 문서의 perception gap 테스트 기준): 등급 리본 → 아이콘 → 이름 → 숫자.
## "무엇이 희귀한가"가 첫눈에, "정확히 몇 %인가"는 마지막에 읽히면 성공.

# --- nice31 팔레트 ---
const INK := Color("#3d3333")        ## 먹선. 셀 셰이더의 어두운 톤과 같은 계열
const PAPER := Color("#f1f6f0")      ## 일반 카드 종이
const GOLD := Color("#fdd179")       ## 희귀 카드 금박
const GOLD_DEEP := Color("#de9f47")
const RED := Color("#b55945")
const ORANGE := Color("#eb9661")     ## 불·타격 계열 (게임 속 화염·피격 플래시와 같은 값)
## 조준 원 전용. ORANGE 와 갈라둔 이유: 조준 원만 endesga 로 옮겼고(2026-08-13),
## 불·플래시는 nice31 #eb9661 그대로다. 한 상수로 묶으면 카드 그림이 통째로 딸려간다.
## range_indicator.gdshader / main.tscn 의 shader_parameter/col 과 같은 값을 유지할 것.
const RING := Color("#f77622")
const CREAM := Color("#fee1b8")
const GRAY_BLUE := Color("#bbc3d0")
const WOOD := Color("#a57855")
const MUTED := Color("#87857c")

## --- 공용 모서리 규칙 (유저 지시 2026-08-13: 뾰족한 코너 금지) --------------------
## 카툰 셀 룩에서 직각은 '개발용 도형'처럼 읽힌다. 모든 UI 면은 살짝 둥글게 간다.
const ROUND_PANEL := 10.0   ## 카드·칩·창 같은 큰 면
const ROUND_BAR := 5.0      ## 체력·경험치처럼 얇은 바
const ROUND_PIP := 3.5      ## 대강타 사각 같은 작은 표시

## 둥근 모서리 사각형. draw_rect 대체용 — 매 프레임 StyleBoxFlat 을 새로 만들면 낭비라
## 하나를 돌려 쓴다 (그리기는 즉시 실행되므로 값을 덮어써도 안전하다).
## ⚠️ 반지름이 변의 절반을 넘으면 모양이 깨지므로 상자 크기로 잘라준다 — 진행 바의 채움은
##    0 에서 시작하니 이 처리가 없으면 게이지가 낮을 때 뭉개진다.
static var _round_sb: StyleBoxFlat

static func draw_round(ci: CanvasItem, box: Rect2, color: Color, radius: float) -> void:
	if _round_sb == null:
		_round_sb = StyleBoxFlat.new()
	_round_sb.bg_color = color
	_round_sb.set_corner_radius_all(
		int(minf(radius, minf(box.size.x, box.size.y) * 0.5)))
	_round_sb.draw(ci.get_canvas_item(), box)

const CARD_SIZE := Vector2(238, 330)

## 카드를 한 장 골랐다. 보관함(CardShelf)이 이걸 받아 갱신한다.
signal card_picked(id: StringName)

var picked: Array[StringName] = []   ## 지금까지 고른 카드 id (중복 상한·배타 판정 + 검증용)

## 기본 폰트(Open Sans)엔 한글이 없다 — OS 폰트를 직접 지정한다. 보관함도 같은 걸 쓴다.
static func make_font(bold := false) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(
		["Apple SD Gothic Neo", "Malgun Gothic", "Noto Sans KR", "NanumGothic"])
	if bold:
		f.font_weight = 800
	return f

var _hammer: HammerStrike
var _root: Control
var _hint: Label
var _reroll_btn: Button
var _row: HBoxContainer
var _hand: Array[Dictionary] = []
var _open := false
var _queued := 0        ## 아직 못 고른 레벨업 수 (한 번에 여러 레벨이 올랐을 때)
var _level_label: Label
var _font: SystemFont
var _font_bold: SystemFont

func _ready() -> void:
	layer = 10
	# 열려 있는 동안 트리를 멈추므로 이 노드만은 멈추면 안 된다
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hammer = get_tree().get_first_node_in_group(&"hammer")
	_font = make_font()
	_font_bold = make_font(true)
	_build()
	var main := get_parent() as Main
	if main != null:
		main.level_system.leveled.connect(_on_leveled)

## 레벨업과 카드 화면 사이의 틈. **0 이면 죽는 장면을 못 본다** —
## 카드 화면은 트리를 멈추므로, 그 순간 시작된 폭연(퓨즈 1초)·폭발 트윈이 통째로
## 얼어붙었다가 카드를 고른 뒤에야 재생된다. 보스처럼 한 방에 레벨이 오르는 적을 잡으면
## "터지는 걸 못 봤다"가 된다.
##
## ⚠️ 예전엔 이걸 **모든 레벨업에 1.2초 고정**으로 물었다. 그런데 폭연은 카드를 든
##    판에서만, 그것도 가끔 터진다 — 대부분의 레벨업은 기다릴 이유가 없는데 기다렸고,
##    그래서 창이 느리게 느껴졌다 (유저 지적 2026-08-13).
##    이제 기본은 짧게 두고, **아직 안 터진 폭연이 실제로 있을 때만** 그게 터질 때까지
##    더 기다린다. 폭연이 없으면 곧바로 열린다.
## 기본 틈. 0.3 은 좌클릭 연타 중에 창이 튀어나와 **누르던 클릭이 카드에 그대로 먹혔다**
## (유저 지적 2026-08-13). 조금 늘리고, 아래 DRAFT_INTRO 로 등장 자체를 부드럽게 한다.
const DRAFT_DELAY := 0.55         ## 기본 틈 — 마지막 타격이 눈에 남을 만큼
const DRAFT_DELAY_MAX := 1.8      ## 폭연을 기다리더라도 여기서 끊는다 (영원히 안 열리면 안 된다)
const DRAFT_POLL := 0.05
## 화면이 어두워지며 카드가 올라오는 시간. 이 동안은 **클릭을 안 받는다** —
## 시간을 늘리는 것만으로는 부족하다. 연타 중이면 언제 떠도 한 장이 먹힌다.
const DRAFT_INTRO := 0.28
## 연출이 끝난 뒤로도 잠깐 더 무시하는 여유. 사람 손이 클릭을 멈추는 데 걸리는 시간.
const DRAFT_GRACE := 0.14

## 드래프트 한 번에 다시 뽑을 수 있는 횟수. **영구 강화가 올릴 값**이라 상수가 아니라
## 프로퍼티다 (유저 계획 2026-08-13: 나중에 영구 강화에 '리롤 +1' 을 넣는다).
## 런 시작 시 한 번만 세팅하면 되고, 드래프트가 열릴 때마다 이 값으로 되채워진다.
var rerolls_per_draft := 1
var _rerolls_left := 0

var _pending_open := false
## 등장 연출 중. 이 동안 들어온 선택/리롤 입력은 전부 버린다.
var _intro := false

## 레벨업 한 번 = 카드 한 번. 고르는 중에 또 올랐으면 쌓아뒀다가 닫힐 때 이어서 연다.
func _on_leveled(new_level: int) -> void:
	_queued += 1
	if _level_label != null:
		_level_label.text = "LEVEL %d" % new_level
	# 기다리는 동안 게임은 계속 돈다 — 멈추는 건 카드 화면이 실제로 열리는 순간부터다.
	if _open or _pending_open:
		return
	_pending_open = true
	_open_after_blasts()

## 기본 틈만 쉬고, 부풀고 있는 폭연이 남아 있으면 그게 터지는 것까지 보고 연다.
func _open_after_blasts() -> void:
	await get_tree().create_timer(DRAFT_DELAY).timeout
	var waited := DRAFT_DELAY
	while waited < DRAFT_DELAY_MAX \
			and not get_tree().get_nodes_in_group(Deflagration.BLAST_PENDING).is_empty():
		await get_tree().create_timer(DRAFT_POLL).timeout
		waited += DRAFT_POLL
	_pending_open = false
	if not _open and _queued > 0:
		open_draft()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_3 and not _open:
		open_draft()
		get_viewport().set_input_as_handled()
	elif _open:
		if _intro:
			get_viewport().set_input_as_handled()
			return
		match event.keycode:
			KEY_1, KEY_2, KEY_3:
				var i: int = event.keycode - KEY_1
				if i < _hand.size():
					_pick(i)
			KEY_R:
				_reroll()
			KEY_ESCAPE:
				# 디버그용 탈출구. 실전 레벨업에선 선택이 강제되어야 하므로
				# 대기열까지 같이 버려야 곧바로 다시 열리지 않는다.
				_queued = maxi(_queued - 1, 0)
				_close()
		get_viewport().set_input_as_handled()

## 카드 3장을 펼치고 게임을 멈춘다.
func open_draft() -> void:
	if _open:
		return
	_hand = _make_hand()
	if _hand.is_empty():
		# max_stacks 를 다 채우면 풀이 마른다. 대기열을 안 버리면 레벨업마다 헛돈다.
		_queued = 0
		return
	_rerolls_left = rerolls_per_draft
	_open = true
	_intro = true
	get_tree().paused = true
	_populate()
	# 어둠막과 카드가 **같이** 페이드 인한다. 멈춤과 어두워짐이 동시에 와야
	# "게임이 멈췄다"가 한 동작으로 읽힌다 (툭 튀어나오면 사고처럼 보인다).
	_root.modulate.a = 0.0
	_root.visible = true
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, DRAFT_INTRO) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_interval(DRAFT_GRACE)
	tw.tween_callback(func() -> void: _intro = false)

func _close() -> void:
	_open = false
	_root.visible = false
	get_tree().paused = false
	# 밀린 레벨업이 남아 있으면 곧바로 다음 장. 같은 프레임에 다시 열면
	# 방금 누른 클릭이 새 카드에 그대로 먹히므로 한 프레임 쉬어간다.
	if _queued > 0:
		call_deferred("open_draft")

func _pick(i: int) -> void:
	if _intro:
		return          # 등장 연출 중 — 누르고 있던 클릭이 카드에 먹히지 않게
	var card := _hand[i]
	if card.has("stats"):                      # 스탯 여러 개를 한 장이 올리는 카드
		for e in card.stats:
			_hammer.stats.add_pct(e.stat, e.pct)
	elif card.has("flat"):
		# 초·거리처럼 **단위가 있는 값**은 배율이 아니라 고정값으로 깎는다. 기본값이 바뀌어도
		# 카드 문구("0.2초 감소")가 계속 참이어야 하기 때문이다.
		_hammer.stats.add_flat(card.stat, card.flat)
	elif card.has("stat"):
		_hammer.stats.add_pct(card.stat, card.pct)
	elif card.has("counter"):
		# 레벨이 오를수록 **동작 자체가 바뀌는** 카드 (연격 스택 수, 메아리 발수 등).
		# pct 로는 표현이 안 돼서 정수 레벨을 올리고, 해석은 HammerStrike 가 한다.
		_hammer.set(card.counter, int(_hammer.get(card.counter)) + 1)
	else:
		_hammer.set(card.flag, true)
	picked.append(card.id)
	_queued = maxi(_queued - 1, 0)
	card_picked.emit(card.id)
	print("[card] ", card.cname, " — ", String(card.desc).replace("\n", " "))
	_close()

# --- 카드 풀 ---------------------------------------------------------------

## 이 카드를 지금까지 몇 장 먹었나.
func stacks_of(id: StringName) -> int:
	var n := 0
	for p in picked:
		if p == id:
			n += 1
	return n

## 지금 뽑힐 수 있는 카드.
##   - 한 번만 얻는 카드(flag)는 보유하면 빠진다.
##   - 반복 카드는 max_stacks 를 채우면 빠진다 — 안 그러면 무한 중첩이다.
func _pool() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in CardCatalog.CARDS:
		# 상반된 계약은 같이 못 맺는다 — 반대쪽을 이미 골랐으면 이 카드는 안 나온다.
		if c.has("excludes") and stacks_of(c.excludes) > 0:
			continue
		if not c.repeat:
			if bool(_hammer.get(c.flag)):
				continue
		elif stacks_of(c.id) >= int(c.get("max_stacks", 0)):
			continue
		out.append(c)
	return out

## 손패 3장 — **완전 무작위**다 (유저 지시 2026-08-14).
##
## ⚠️ 예전엔 등장 보장이 있었다: 첫 선택엔 '공격 패턴', 3번째 선택까지는 '속성' 카드를
##    한 장 강제로 끼워 넣었다 (2026-08-13 기획). 유저 지시로 걷어냈다 —
##    보장이 걸리면 초반 세 번의 손패가 사실상 정해져 있어서 매판이 같게 시작한다.
## ⚠️ 리롤 전용이던 guaranteed 인자도 같이 없앴다. 그 인자의 존재 이유가 "리롤은 보장에서
##    빠져나오는 수단"이었는데, 보장이 사라졌으니 첫 손패와 리롤이 같은 규칙이 된다.
##
## 뽑기 자체는 Godot 4 의 전역 RNG 가 시작할 때 자동으로 무작위 시드를 잡는다 —
## randomize() 를 부를 필요가 없고, 실행마다 다른 손패가 나온다 (verify_card_random 로 실측).
func _make_hand() -> Array[Dictionary]:
	var pool := _pool()
	pool.shuffle()
	return pool.slice(0, mini(3, pool.size()))

# --- UI 조립 ---------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)

	# 어둡게 깔아 카드에 집중시키고, 뒤로 가는 클릭을 전부 먹는다
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.1, 0.14, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 30)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	# 제목 현판 — 금박 바탕에 먹선, 살짝 비뚤게 걸린 간판
	var banner := PanelContainer.new()
	var bs := StyleBoxFlat.new()
	bs.bg_color = GOLD
	bs.set_corner_radius_all(14)
	bs.set_border_width_all(5)
	bs.border_color = INK
	bs.shadow_color = Color(0, 0, 0, 0.3)
	bs.shadow_size = 6
	bs.shadow_offset = Vector2(0, 5)
	bs.set_content_margin_all(10)
	bs.content_margin_left = 34
	bs.content_margin_right = 34
	banner.add_theme_stylebox_override("panel", bs)
	banner.rotation = deg_to_rad(-1.4)
	# 현판에는 "무슨 일이 일어났는가"(레벨업)를 먼저 적는다. 지시문은 그 아래 작게.
	_level_label = _label("LEVEL 2", 32, INK, true)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_child(_level_label)
	var banner_wrap := CenterContainer.new()
	banner_wrap.add_child(banner)
	col.add_child(banner_wrap)

	var sub := _label("권능을 선택하세요", 19, Color(PAPER, 0.9), true)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 26)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_row)

	_hint = _label("[1~3] 또는 클릭으로 선택", 15, Color(PAPER, 0.75), false)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_hint)

	# 다시 뽑기 — 카드와 같은 문법(종이 바탕 + 먹선)의 작은 버튼. 키보드는 [R].
	# 드래프트는 트리를 멈추고 뒤를 어둠막이 막으므로, 여기 버튼이 클릭을 먹어도
	# 공격 사각지대 문제(CardShelf 주석 참고)는 생기지 않는다.
	_reroll_btn = Button.new()
	_reroll_btn.add_theme_font_override("font", _font_bold)
	_reroll_btn.add_theme_font_size_override("font_size", 15)
	_reroll_btn.add_theme_color_override("font_color", INK)
	_reroll_btn.add_theme_color_override("font_hover_color", INK)
	_reroll_btn.add_theme_color_override("font_pressed_color", INK)
	for st in ["normal", "hover", "pressed"]:
		var rs := StyleBoxFlat.new()
		rs.bg_color = CREAM if st == "hover" else PAPER
		rs.set_corner_radius_all(int(ROUND_PANEL))
		rs.set_border_width_all(3)
		rs.border_color = INK
		rs.set_content_margin_all(8)
		rs.content_margin_left = 18
		rs.content_margin_right = 18
		_reroll_btn.add_theme_stylebox_override(st, rs)
	_reroll_btn.pressed.connect(_reroll)
	var btn_wrap := CenterContainer.new()
	btn_wrap.add_child(_reroll_btn)
	col.add_child(btn_wrap)

func _populate() -> void:
	# ⚠️ queue_free 만 하면 이번 프레임엔 아직 살아 있어서 HBox 가 6장으로 자리를 잡는다.
	# 카드가 한 번 좁게 배치됐다가 튀는 것처럼 보이므로 트리에서 **먼저 뺀다**.
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	for i in _hand.size():
		_row.add_child(_make_card(_hand[i], i))
	# 다시 뽑을 수 없는 상황(횟수 소진 / 후보가 손패보다 적음)이면 버튼을 아예 숨긴다 —
	# 눌러도 아무 일 없는 버튼이 떠 있으면 고장으로 읽힌다.
	_reroll_btn.visible = _can_reroll()
	_reroll_btn.text = "다시 뽑기 [R] · %d회 남음" % _rerolls_left

## 다시 뽑을 수 있는가.
## ⚠️ 남은 횟수만 보면 안 된다 — max_stacks 로 풀이 말라 후보가 손패 수 이하가 되면
##    다시 뽑아도 **같은 카드가 그대로** 나온다. 그 상황에선 아예 안 보여주는 게 맞다.
func _can_reroll() -> bool:
	return _rerolls_left > 0 and _pool().size() > _hand.size()

func _reroll() -> void:
	if _intro or not _can_reroll():
		return
	_rerolls_left -= 1
	_hand = _make_hand()
	_populate()
	print("[card] 다시 뽑기 — %d회 남음" % _rerolls_left)

## 이 노드와 자손 전부가 마우스를 통과시키게 한다.
## ⚠️ `Control.mouse_filter` 기본값은 **STOP** 이다 — 리본·아이콘·컨테이너가 카드 패널보다
## 위에 있으므로 호버와 클릭을 전부 가로챈다. `Label` 만 기본이 IGNORE 라서
## 글씨가 있는 **아래쪽 절반만** 반응하는 증상이 나왔다.
static func _pass_through(node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in node.get_children():
		if c is Control:
			_pass_through(c)

## 카드 한 장. 슬롯(레이아웃용 고정 틀) 안에 패널을 띄워 패널만 기울이고 튀어오르게 한다 —
## 컨테이너가 잡은 자리는 그대로 두고 그림만 움직여야 이웃 카드가 밀리지 않는다.
func _make_card(card: Dictionary, index: int) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = CARD_SIZE
	# 슬롯은 자리만 잡는 빈 틀 — 마우스는 패널이 받는다
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var rare: bool = card.rarity == &"rare"
	var panel := PanelContainer.new()
	panel.size = CARD_SIZE
	panel.pivot_offset = CARD_SIZE * 0.5
	var base_rot := deg_to_rad(randf_range(-2.4, 2.4))
	panel.rotation = base_rot
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var sb := StyleBoxFlat.new()
	sb.bg_color = GOLD if rare else PAPER
	sb.set_corner_radius_all(16)
	sb.set_border_width_all(5)
	sb.border_color = INK
	sb.shadow_color = Color(0, 0, 0, 0.32)
	sb.shadow_size = 9
	sb.shadow_offset = Vector2(0, 7)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	slot.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)

	# 등급 리본 — 첫눈에 읽혀야 하는 것은 숫자가 아니라 "이게 희귀한가"다
	var ribbon := PanelContainer.new()
	var rs := StyleBoxFlat.new()
	rs.bg_color = RED if rare else GRAY_BLUE
	rs.set_corner_radius_all(int(ROUND_PANEL))
	rs.set_border_width_all(3)
	rs.border_color = INK
	rs.content_margin_left = 14
	rs.content_margin_right = 14
	rs.content_margin_top = 2
	rs.content_margin_bottom = 3
	ribbon.add_theme_stylebox_override("panel", rs)
	ribbon.add_child(_label("희귀" if rare else "일반", 15, CREAM if rare else INK, true))
	var ribbon_wrap := CenterContainer.new()
	ribbon_wrap.add_child(ribbon)
	v.add_child(ribbon_wrap)

	var icon := CardIcon.new()
	icon.kind = card.id
	icon.custom_minimum_size = Vector2(0, 118)
	icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(icon)

	var cname := _label(card.cname, 25, INK, true)
	cname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cname)

	var desc := _label(card.desc, 15, Color("#734c44"), false)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(desc)

	var cat := _label(card.cat, 13, GOLD_DEEP if rare else MUTED, true)
	cat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cat)

	# 카드 내용물은 전부 마우스를 통과시킨다 — 그래야 패널 하나가 카드 전체를 받는다
	_pass_through(v)

	# 등장: 아래에서 튀어오르며 자리를 잡는다 (한 장씩 시차)
	panel.position.y = 46.0
	panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(0.05 + 0.07 * index)
	tw.tween_property(panel, "modulate:a", 1.0, 0.1)
	tw.parallel().tween_property(panel, "position:y", 0.0, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 호버: 커지며 반듯해지고 **먹선 둘레가 빛난다**.
	# 테두리 색은 그대로 먹선으로 둔다 — 금박 카드에서 테두리를 금색으로 바꾸면 윤곽이 사라진다.
	# 대신 그림자를 발광색으로 바꾸고 오프셋을 0으로 당겨 **사방으로 번지는 후광**을 만든다.
	var glow := GOLD
	# 람다는 지역 변수를 **값으로** 캡처한다 — 트윈 핸들을 공유하려면 담을 그릇이 필요하다.
	# (호버를 빠르게 왕복하면 트윈이 겹쳐 크기·발광이 서로 되돌린다.)
	var hov := {tw = null}
	var hover := func(on: bool) -> void:
		if hov.tw != null and (hov.tw as Tween).is_valid():
			(hov.tw as Tween).kill()
		var t := create_tween().set_parallel(true)
		hov.tw = t
		t.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(panel, "scale", Vector2(1.07, 1.07) if on else Vector2.ONE, 0.11)
		t.tween_property(panel, "rotation", 0.0 if on else base_rot, 0.11)
		t.tween_property(sb, "shadow_color",
			Color(glow, 0.85) if on else Color(0, 0, 0, 0.32), 0.11)
		t.tween_property(sb, "shadow_size", 22 if on else 9, 0.11)
		t.tween_property(sb, "shadow_offset", Vector2.ZERO if on else Vector2(0, 7), 0.11)
	panel.mouse_entered.connect(hover.bind(true))
	panel.mouse_exited.connect(hover.bind(false))
	panel.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed \
				and ev.button_index == MOUSE_BUTTON_LEFT:
			_pick(index))
	return slot

func _label(text: String, size: int, color: Color, bold: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font_bold if bold else _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

# --- 손그림 아이콘 ----------------------------------------------------------

## 카드 그림. 진짜 일러스트가 생길 때까지 _draw 로 그리는 자리표시자 —
## 다만 톤은 진짜처럼: 굵은 먹선 + 팔레트 단색 면 (셀 셰이딩과 같은 문법).
class CardIcon extends Control:
	var kind := &""

	## 정사각 캔버스(0~100) 좌표 -> 실제 픽셀. 카드 폭이 달라져도 그림이 안 찌그러진다.
	func _p(x: float, y: float) -> Vector2:
		var s := minf(size.x, size.y)
		var off := (size - Vector2(s, s)) * 0.5
		return off + Vector2(s * x * 0.01, s * y * 0.01)

	func _w(u: float) -> float:
		return minf(size.x, size.y) * u * 0.01

	## 카툰 충격 별: 바깥/안쪽 반지름을 번갈아 도는 뾰족 다각형.
	func _star(center: Vector2, r_out: float, r_in: float, points: int, fill: Color) -> void:
		var pts: Array[Vector2] = []
		for i in points * 2:
			var r := r_out if i % 2 == 0 else r_in
			var a := TAU * float(i) / float(points * 2) - TAU * 0.25
			pts.append(center + Vector2(cos(a), sin(a)) * r)
		_poly(pts, fill)

	func _poly(pts: Array, fill: Color, outline := 4.5) -> void:
		var v := PackedVector2Array()
		for q in pts:
			v.append(_p(q.x, q.y))
		draw_colored_polygon(v, fill)
		v.append(v[0])
		draw_polyline(v, CardUI.INK, _w(outline), true)

	func _draw() -> void:
		match kind:
			&"damage":
				# 내리찍힌 망치 + 충격 별
				_star(Vector2(50, 72), 27.0, 12.0, 8, CardUI.ORANGE)
				_poly([Vector2(26, 8), Vector2(74, 8), Vector2(74, 34), Vector2(26, 34)],
					CardUI.GRAY_BLUE)
				draw_line(_p(50, 34), _p(50, 52), CardUI.INK, _w(11.0))
				draw_line(_p(50, 34), _p(50, 52), CardUI.WOOD, _w(5.5))
			&"radius":
				# 게임 속 조준 원과 같은 문법: 점선 링. 색도 같은 값(RING)을 쓴다.
				draw_circle(_p(50, 55), _w(36.0), Color(CardUI.RING, 0.16))
				for i in 10:
					var a0 := TAU * float(i) / 10.0
					draw_arc(_p(50, 55), _w(36.0), a0, a0 + TAU * 0.062,
						6, CardUI.INK, _w(7.5), true)
					draw_arc(_p(50, 55), _w(36.0), a0, a0 + TAU * 0.062,
						6, CardUI.RING, _w(4.5), true)
				draw_circle(_p(50, 55), _w(6.5), CardUI.INK)
			&"fire":
				# 두 겹 불꽃 — flame_jet 셰이더와 같은 뿌리 금색/끝 주홍 배색
				_poly([Vector2(50, 4), Vector2(64, 24), Vector2(58, 38), Vector2(74, 48),
					Vector2(79, 66), Vector2(71, 84), Vector2(56, 94), Vector2(44, 94),
					Vector2(29, 84), Vector2(21, 66), Vector2(26, 48), Vector2(42, 38),
					Vector2(36, 24)], CardUI.ORANGE)
				_poly([Vector2(50, 40), Vector2(60, 56), Vector2(64, 70), Vector2(57, 84),
					Vector2(43, 84), Vector2(36, 70), Vector2(40, 56)], CardUI.GOLD, 3.5)
				draw_circle(_p(50, 74), _w(8.0), CardUI.CREAM)
			&"restraint":
				# 억제 — 방패 안에 내려누르는 화살표. '막는다' 는 방어 계열 신호
				_poly([Vector2(50, 6), Vector2(84, 22), Vector2(80, 62),
					Vector2(50, 94), Vector2(20, 62), Vector2(16, 22)], CardUI.GRAY_BLUE)
				_poly([Vector2(42, 24), Vector2(58, 24), Vector2(58, 52),
					Vector2(70, 52), Vector2(50, 76), Vector2(30, 52), Vector2(42, 52)],
					CardUI.RING, 3.5)
			&"warcry":
				# 부름 — 뿔나팔에서 퍼지는 세 줄기. 적을 불러들인다
				_poly([Vector2(14, 34), Vector2(40, 44), Vector2(40, 66), Vector2(14, 76)],
					CardUI.WOOD)
				_poly([Vector2(40, 40), Vector2(72, 22), Vector2(72, 88), Vector2(40, 70)],
					CardUI.GOLD)
				for i in 3:
					var y8 := 34.0 + float(i) * 21.0
					draw_line(_p(78, y8), _p(94, y8 - 6.0 + float(i) * 6.0),
						CardUI.RED, _w(5.0))
			&"giant":
				# 세 공격 전부 — 위로 솟은 주먹/망치머리 위에 별 셋 (평타·차징·우클릭)
				_poly([Vector2(30, 40), Vector2(70, 40), Vector2(74, 78), Vector2(26, 78)],
					CardUI.GRAY_BLUE)
				draw_line(_p(50, 78), _p(50, 96), CardUI.INK, _w(11.0))
				draw_line(_p(50, 78), _p(50, 96), CardUI.WOOD, _w(5.5))
				for i in 3:
					_star(Vector2(26 + float(i) * 24, 20), 11.0, 4.5, 5, CardUI.ORANGE)
			&"reach":
				# 바깥으로 뻗는 화살표 넷 + 점선 링 — '넓어진다'
				draw_circle(_p(50, 52), _w(30.0), Color(CardUI.RING, 0.14))
				for i in 8:
					var a3 := TAU * float(i) / 8.0
					draw_arc(_p(50, 52), _w(30.0), a3, a3 + TAU * 0.075,
						6, CardUI.RING, _w(4.5), true)
				for i in 4:
					var a4 := TAU * float(i) / 4.0 + TAU * 0.125
					var d4 := Vector2(cos(a4), sin(a4))
					var c4 := Vector2(50, 52)
					_poly([c4 + d4 * 46.0, c4 + d4 * 30.0 + Vector2(-d4.y, d4.x) * 8.0,
						c4 + d4 * 30.0 - Vector2(-d4.y, d4.x) * 8.0], CardUI.INK, 3.0)
			&"cycle":
				# 재사용 대기 — 거의 다 찬 원호 + 화살촉
				draw_arc(_p(50, 52), _w(30.0), -TAU * 0.25, TAU * 0.55, 32,
					CardUI.INK, _w(11.0), true)
				draw_arc(_p(50, 52), _w(30.0), -TAU * 0.25, TAU * 0.55, 32,
					CardUI.GOLD, _w(6.0), true)
				_poly([Vector2(50, 6), Vector2(68, 22), Vector2(50, 38)], CardUI.GOLD, 3.5)
			&"swift_doom":
				# 짧아진 예고 — 납작한 그림자 타원 + 위에서 빠르게 꽂히는 화살 + 속도선
				draw_circle(_p(50, 74), _w(24.0), Color(CardUI.INK, 0.22))
				draw_arc(_p(50, 74), _w(24.0), 0.0, TAU, 32, Color(CardUI.INK, 0.5), _w(3.0), true)
				draw_line(_p(50, 8), _p(50, 56), CardUI.INK, _w(9.0))
				draw_line(_p(50, 8), _p(50, 56), CardUI.RED, _w(5.0))
				_poly([Vector2(38, 50), Vector2(62, 50), Vector2(50, 70)], CardUI.RED, 3.5)
				for i in 2:
					var sx9 := 30.0 + float(i) * 40.0
					draw_line(_p(sx9, 14), _p(sx9, 34), CardUI.MUTED, _w(4.0))
			&"combo":
				# 연격 — 불빛 다섯 개가 차오른다 (게임 HUD 의 ● 표시와 같은 문법)
				draw_line(_p(14, 74), _p(86, 74), CardUI.INK, _w(5.0))
				for i in 5:
					var x6 := 20.0 + float(i) * 15.0
					var lit := i < 3
					draw_circle(_p(x6, 74), _w(9.0), CardUI.INK)
					draw_circle(_p(x6, 74), _w(6.0), CardUI.ORANGE if lit else CardUI.MUTED)
				_star(Vector2(50, 32), 22.0, 9.0, 6, CardUI.ORANGE)
			&"beat":
				# 박자 — 작은 타격 셋 뒤에 큰 타격 하나
				for i in 3:
					var x7 := 20.0 + float(i) * 17.0
					_poly([Vector2(x7 - 6, 84), Vector2(x7 + 6, 84),
						Vector2(x7 + 6, 62), Vector2(x7 - 6, 62)], CardUI.GRAY_BLUE)
				_star(Vector2(76, 50), 26.0, 11.0, 8, CardUI.RED)
				_poly([Vector2(62, 60), Vector2(90, 60), Vector2(90, 36), Vector2(62, 36)],
					CardUI.GOLD)
			&"swift":
				# 평타 쿨감 — 망치 머리에 속도선. 'damage' 와 같은 망치 문법을 쓰되
				# 별(충격) 대신 잔상선을 둬서 "세기"가 아니라 "빠르기"로 읽히게 한다.
				for i in 3:
					var y := 26.0 + float(i) * 17.0
					draw_line(_p(6, y), _p(30 + float(i) * 6, y), CardUI.INK, _w(7.0))
					draw_line(_p(6, y), _p(30 + float(i) * 6, y), CardUI.ORANGE, _w(4.0))
				_poly([Vector2(46, 12), Vector2(92, 12), Vector2(92, 38), Vector2(46, 38)],
					CardUI.GRAY_BLUE)
				draw_line(_p(69, 38), _p(69, 88), CardUI.INK, _w(11.0))
				draw_line(_p(69, 38), _p(69, 88), CardUI.WOOD, _w(5.5))
			&"condense":
				# 응축 — 안으로 조여드는 화살표 넷 + 가운데 뭉친 핵. 차징이 빨리 찬다.
				draw_circle(_p(50, 50), _w(34.0), Color(CardUI.GOLD_DEEP, 0.16))
				for i in 4:
					var a2 := TAU * float(i) / 4.0 + TAU * 0.125
					var d := Vector2(cos(a2), sin(a2))
					var tip := Vector2(50, 50) + d * 20.0
					var tail := Vector2(50, 50) + d * 44.0
					var side := Vector2(-d.y, d.x) * 9.0
					_poly([tip, tail + side, tail - side], CardUI.GOLD_DEEP, 3.5)
				draw_circle(_p(50, 50), _w(13.0), CardUI.INK)
				draw_circle(_p(50, 50), _w(9.0), CardUI.CREAM)
			&"overcharge":
				# 과충전 — 꽉 찬 차징 링 + 번개. 링이 터질 듯 넘치는 그림.
				draw_circle(_p(50, 52), _w(37.0), Color(CardUI.RED, 0.18))
				draw_arc(_p(50, 52), _w(37.0), 0.0, TAU, 40, CardUI.INK, _w(9.0), true)
				draw_arc(_p(50, 52), _w(37.0), 0.0, TAU, 40, CardUI.GOLD, _w(5.5), true)
				_poly([Vector2(56, 16), Vector2(38, 54), Vector2(50, 54), Vector2(42, 88),
					Vector2(66, 46), Vector2(53, 46)], CardUI.GOLD)
			&"blessing":
				# 성장의 축복 — 위로 뻗는 새싹 + 빛. 전투가 아니라 성장 카드라는 신호.
				_star(Vector2(50, 30), 30.0, 12.0, 8, Color(CardUI.GOLD, 0.55))
				draw_line(_p(50, 92), _p(50, 40), CardUI.INK, _w(8.0))
				draw_line(_p(50, 92), _p(50, 40), CardUI.WOOD, _w(4.0))
				_poly([Vector2(50, 62), Vector2(28, 54), Vector2(22, 38), Vector2(44, 46)],
					CardUI.GOLD_DEEP, 3.5)
				_poly([Vector2(50, 52), Vector2(72, 44), Vector2(78, 28), Vector2(56, 36)],
					CardUI.GOLD, 3.5)
			&"aftershock":
				# 균열 — 게임 속 여진 자국의 축소판
				draw_circle(_p(50, 58), _w(30.0), Color(CardUI.RED, 0.18))
				var cracks := [
					[Vector2(50, 58), Vector2(31, 50), Vector2(17, 36)],
					[Vector2(50, 58), Vector2(63, 44), Vector2(72, 24)],
					[Vector2(50, 58), Vector2(68, 66), Vector2(84, 78)],
					[Vector2(50, 58), Vector2(41, 74), Vector2(26, 86)],
					[Vector2(50, 58), Vector2(48, 40), Vector2(55, 20)],
				]
				for line in cracks:
					var v := PackedVector2Array()
					for q in line:
						v.append(_p(q.x, q.y))
					draw_polyline(v, CardUI.INK, _w(4.8), true)
				_poly([Vector2(43, 54), Vector2(50, 49), Vector2(58, 53),
					Vector2(60, 61), Vector2(51, 66), Vector2(43, 62)], CardUI.INK, 0.5)
