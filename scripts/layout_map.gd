class_name LayoutMap
extends RefCounted

## 유저가 칠한 **레이아웃 맵(PNG)** 을 읽는다 (유저 요청 2026-08-16: "글보다 그림").
##
## 그림 한 장이 지시서다. 캔버스 축 = 화면 축이라 게임에서 보이는 그대로 칠하면 되고,
## 임포터는 **범례에 있는 정확한 색만** 알아본다 — 안내선(회색)·눈금·프레임은 전부 무시된다.
##   지형 색을 면으로 칠하면  -> 그 자리 흙이 그 색이 된다 (Ground)
##   프롭 색을 칠하면        -> 칠한 면적을 그 프롭으로 채운다 (Scatter)
##   검정(#000000)          -> 그 자리엔 아무것도 놓지 않는다
##
## 파일이 없으면 전부 null 을 돌려주고, Ground/Scatter 는 종전대로 절차 생성으로 돈다 —
## 즉 **그림은 선택 사항**이고, 칠한 부분만 절차 생성을 덮어쓴다.
##
## ⚠️ 칠할 때 **안티에일리어싱을 끄고** 페인트 버킷/연필로 칠해야 한다. 흐린 경계는
##    범례 색과 정확히 일치하지 않아 무시된다 (허용 오차는 채널당 ±6 뿐이다).

const PATH := "res://layout/layout.png"
const PX := 3.0                 ## 1 유닛 = 3 픽셀 (tools/make_layout_template.py 와 같아야 함)
const X_HALF := 120.0
const Z_HALF := 85.0
const TOL := 6                  ## 채널당 허용 오차 (저장 과정의 미세한 색 변형 흡수)

## 지형 색 -> Ground 가 쓸 흙 색
const TERRAIN := {
	"734c44": Color("#734c44"),
	"c28569": Color("#c28569"),
	"3e8948": Color("#3e8948"),
	"265c42": Color("#265c42"),
	"bcad9f": Color("#bcad9f"),
}

## 프롭 색 -> Scatter 의 프롭 id
const PROP := {
	"ff0000": &"trunk",
	"ff8800": &"twig",
	"ffee00": &"leaf",
	"00e5ff": &"gravel",
	"ff00ff": &"grass",
	"ffffff": &"pebble",
}
const CLEAR := "000000"        ## 비워두기

var loaded := false
var _img: Image
var _prop_px := {}             ## 프롭 id -> Array[Vector2] (칠해진 픽셀의 화면 좌표)
var _clear_px: Array[Vector2] = []

func load_map() -> bool:
	loaded = false
	_prop_px.clear()
	_clear_px.clear()
	if not ResourceLoader.exists(PATH):
		return false
	var tex := load(PATH) as Texture2D
	if tex == null:
		return false
	_img = tex.get_image()
	if _img == null:
		return false
	# 칠해진 픽셀을 한 번만 훑어 분류해 둔다 — 배치할 때마다 다시 훑으면 느리다.
	for y in _img.get_height():
		for x in _img.get_width():
			var key := _img.get_pixel(x, y).to_html(false)
			var id := _match(key)
			if id == "":
				continue
			var p := _to_screen(x, y)
			if id == CLEAR:
				_clear_px.append(p)
			elif PROP.has(id):
				var arr: Array = _prop_px.get(PROP[id], [])
				arr.append(p)
				_prop_px[PROP[id]] = arr
	loaded = true
	var report := ""
	for k in _prop_px:
		report += " %s %d px" % [k, _prop_px[k].size()]
	print("[layout] %s 읽음 —%s / 비워두기 %d px" % [PATH, report, _clear_px.size()])
	return true

## 이 픽셀 색이 범례의 어떤 항목인가. 없으면 빈 문자열.
func _match(key: String) -> String:
	if _near(key, CLEAR):
		return CLEAR
	for k in PROP:
		if _near(key, k):
			return k
	for k in TERRAIN:
		if _near(key, k):
			return k
	return ""

static func _near(a: String, b: String) -> bool:
	if a.length() < 6 or b.length() < 6:
		return false
	for i in 3:
		var ca := a.substr(i * 2, 2).hex_to_int()
		var cb := b.substr(i * 2, 2).hex_to_int()
		if absi(ca - cb) > TOL:
			return false
	return true

func _to_screen(x: int, y: int) -> Vector2:
	return Vector2(float(x) / PX - X_HALF, float(y) / PX - Z_HALF)

func _to_px(p: Vector2) -> Vector2i:
	return Vector2i(roundi((p.x + X_HALF) * PX), roundi((p.y + Z_HALF) * PX))

## 이 자리에 칠해진 흙 색. 안 칠했으면 null (절차 생성에 맡긴다).
func terrain_at(screen: Vector2) -> Variant:
	if not loaded:
		return null
	var q := _to_px(screen)
	if q.x < 0 or q.y < 0 or q.x >= _img.get_width() or q.y >= _img.get_height():
		return null
	var key := _img.get_pixel(q.x, q.y).to_html(false)
	for k in TERRAIN:
		if _near(key, k):
			return TERRAIN[k]
	return null

## 이 프롭이 칠해진 픽셀들의 화면 좌표. 없으면 빈 배열.
func prop_spots(id: StringName) -> Array:
	return _prop_px.get(id, [])

## 여기가 '비워두기' 로 칠해졌는가.
func is_clear(screen: Vector2) -> bool:
	if not loaded:
		return false
	var q := _to_px(screen)
	if q.x < 0 or q.y < 0 or q.x >= _img.get_width() or q.y >= _img.get_height():
		return false
	return _near(_img.get_pixel(q.x, q.y).to_html(false), CLEAR)
