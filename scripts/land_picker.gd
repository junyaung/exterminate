class_name LandPicker
extends RefCounted

## 투사체(바위·불덩이) 착지 지점 — 사방으로 **무작위 산개**.
##
## 유도하지 않는다. 솟구친 흙덩이와 분화구가 뿜는 불덩이는 조준하는 물건이 아니라
## 그냥 튀어나가는 것이다. 명중률이 낮으면 반경/개수/분포로 풀 문제지,
## 적을 쫓아가게 만들 문제가 아니다.
##
## 고르게 흩되 각도를 흔들어 기계적인 배치만 피한다.

## count 개의 착지 지점을 돌려준다.
##   near/far = 반경 대비 거리 범위
##   keepout  = 피해야 할 영역 (기지). 크기 0 이면 무시.
##
## ⚠️ **겹침은 막지 않는다** (유저 지시 2026-08-18). 한때 최소 간격을 강제했는데,
##    바위가 서로 겹쳐 보이는 건 문제가 아니었다 — 문제는 겹친 바위가 **공중에 뜨는** 것이고
##    그건 착지 높이 계산에서 고쳤다 (EruptRock._lowest_drop).
static func pick(center: Vector3, radius: float, count: int,
		near := 0.4, far := 1.3, keepout := Rect2()) -> Array[Vector3]:
	var spots: Array[Vector3] = []
	var spin := randf_range(0.0, TAU)
	for i in count:
		var ang := spin + TAU * i / count + randf_range(-0.35, 0.35)
		var d := radius * randf_range(near, far)
		var p := center + Vector3(cos(ang), 0.0, sin(ang)) * d
		if keepout.size != Vector2.ZERO:
			var q := _push_out(Vector2(p.x, p.z), keepout)
			p = Vector3(q.x, 0.0, q.y)
		spots.append(p)
	return spots

## 점이 사각형 안이면 가장 가까운 변으로 밀어낸다.
static func _push_out(p: Vector2, r: Rect2) -> Vector2:
	if not r.has_point(p):
		return p
	var d_left := p.x - r.position.x
	var d_right := r.end.x - p.x
	var d_top := p.y - r.position.y
	var d_bottom := r.end.y - p.y
	var m := minf(minf(d_left, d_right), minf(d_top, d_bottom))
	if is_equal_approx(m, d_left):
		return Vector2(r.position.x, p.y)
	if is_equal_approx(m, d_right):
		return Vector2(r.end.x, p.y)
	if is_equal_approx(m, d_top):
		return Vector2(p.x, r.position.y)
	return Vector2(p.x, r.end.y)
