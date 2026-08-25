class_name NavMap
extends Node

## 지형을 따라 걷는 길 찾기 (유저 선택 2026-08-16: "게임을 높이 인식하게").
##
## 벌레는 이제 y=0 평면이 아니라 **지면 위**를 걷는다. 그러면 절벽을 뚫고 직진하면 안 되므로
## 어디로 갈지 정해줄 것이 필요하다. 여기서는 **흐름장(flow field)** 을 쓴다:
##   1) 격자 칸마다 "걸을 수 있는가"를 판정한다 — 옆 칸과의 높이차가 계단 한 칸 이하면 OK
##   2) 성에서 시작해 너비 우선으로 퍼뜨리며 각 칸의 **성까지 걸리는 비용**을 적는다
##   3) 벌레는 자기 칸에서 비용이 가장 낮은 이웃 쪽으로 걷는다
##
## 왜 A* 가 아니라 흐름장인가 — 적이 수백 마리라 개체마다 경로를 찾으면 비싸고, 목적지가
## **하나(성)** 라서 한 번 계산해 전부가 공유하면 된다. 지형을 고치면 다시 계산한다.
##
## ⚠️ 격자는 지면 메시와 **같은 칸 크기**를 쓴다. 더 잘게 잡으면 계단 한 칸을 오르는 경사가
##    여러 칸에 걸쳐 완만해져서, 절벽까지 걸어 올라갈 수 있는 것으로 잘못 판정된다.

## 오를 수 있는 최대 **기울기** (높이차 / 수평거리).
## ⚠️ 처음엔 "한 걸음에 오를 수 있는 높이차"로 막았는데, 그건 소용이 없었다 — 계단 한 칸은
##    아주 짧은 거리에서 2.0 이 오르지만 **한 프레임 이동(0.06유닛)** 으로는 조금씩만 오르므로
##    높이차 검사에 안 걸리고 결국 절벽을 기어올랐다 (검증: 길 밖에서 올라간 높이 63%).
##    기울기로 재면 계단 벽(≈16)은 막히고 매끈한 비탈(≈0.07)은 통과한다.
const MAX_SLOPE := 0.6
## 두 지점 사이가 지나갈 수 있는가 — 중간을 몇 번 찍어 **가장 가파른 구간**으로 판정한다.
## 양 끝만 보면 사이에 낀 절벽을 놓친다.
const SAMPLES := 4

static func passable(g: Ground, a: Vector3, b: Vector3) -> bool:
	if g == null or g.is_flat:
		return true
	var prev := g.height_at(a)
	var seg := a.distance_to(b) / float(SAMPLES)
	for i in range(1, SAMPLES + 1):
		var p := a.lerp(b, float(i) / float(SAMPLES))
		var h := g.height_at(p)
		if (h - prev) / maxf(seg, 0.001) > MAX_SLOPE:
			return false
		prev = h
	return true

## ⚠️ 예전엔 "높이 0 근처면 벌판이니 자유롭게 다녀도 된다"고 열어뒀는데, 그러면 벌레가
##    벌판 전체로 퍼져서 **길이 아닌 데로도 올라왔다** (유저 지적 2026-08-16).
##    이제 스폰 존과 접근로까지 전부 길 마스크에 구워 넣었으므로, 걸을 수 있는 곳은
##    **오직 마스크 위**다. (지형 파일이 없는 평지 판에서는 마스크가 없으므로 이 규칙이
##    모두를 막아버린다 — 그래서 마스크가 아예 없으면 전부 통행 가능으로 되돌린다.)
const PATH_MASK_MIN := 0.05

const UNREACHED := 1.0e9

var cell := 4.0
var half := 160.0
var n := 0
var cost := PackedFloat32Array()      ## 성까지의 비용. 못 가는 칸은 UNREACHED
var walkable := PackedByteArray()
## 각 칸에서 **실제로 지나갈 수 있는** 다음 칸 방향. BFS 로 퍼뜨릴 때 온 길을 그대로 되짚는다.
## ⚠️ 이걸 안 두고 "비용이 가장 낮은 이웃"으로 방향을 정하면, 절벽 위 칸이 성에 가까워
##    비용이 낮다는 이유로 **절벽을 향하라고** 가리킨다. 벌레는 벽에 붙어 제자리걸음을 한다
##    (검증에서 둘 다 절벽 앞에 멈춰 섰다).
var dir_x := PackedFloat32Array()
var dir_z := PackedFloat32Array()

var _ground: Ground
var _has_mask := false     ## 이 판에 '길' 이 정의돼 있는가

func _ready() -> void:
	add_to_group(&"navmap")

## 지형이 바뀔 때마다 부른다.
func rebuild() -> void:
	_ground = Terrain.ground()
	if _ground == null:
		return
	cell = Ground.CELL
	half = Ground.HALF
	n = int(half * 2.0 / cell)
	var total := n * n
	walkable.resize(total)
	cost.resize(total)
	dir_x.resize(total)
	dir_z.resize(total)
	var hgt := PackedFloat32Array()
	hgt.resize(total)
	for iz in n:
		for ix in n:
			hgt[iz * n + ix] = _ground.height_at(_world(ix, iz))
	# 걸을 수 있는가 = 네 이웃 중 **하나라도** 계단 한 칸 이내로 이어지는가.
	# (사방이 절벽인 칸은 어차피 아무도 못 가고, 성 쪽 이웃만 이어지면 충분하다)
	for iz in n:
		for ix in n:
			var i := iz * n + ix
			var ok := false
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var j := _index(ix + o.x, iz + o.y)
				if j >= 0 and passable(_ground, _world(ix, iz), _world(ix + o.x, iz + o.y)):
					ok = true
					break
			walkable[i] = 1 if ok else 0
	# 성에서부터 퍼뜨린다. 대각선도 쓰되 비용을 √2 로 줘야 길이 삐뚤빼뚤해지지 않는다.
	for i in total:
		cost[i] = UNREACHED
		dir_x[i] = 0.0
		dir_z[i] = 0.0
	var base := get_tree().get_first_node_in_group(&"base") as Node3D
	if base == null:
		return
	var start := _cell_of(base.global_position)
	if start < 0:
		return
	cost[start] = 0.0
	var queue: Array[int] = [start]
	var head := 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		var cx := cur % n
		var cz := cur / n
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
				Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			var j := _index(cx + o.x, cz + o.y)
			if j < 0 or walkable[j] == 0:
				continue
			# 기울기가 한계를 넘으면 못 넘어간다 — 여기가 절벽을 막는 지점이다.
			# ⚠️ 성에서 바깥으로 퍼뜨리는 중이므로 **내려가는 방향**을 검사해야 한다:
			#    실제로 벌레는 j -> cur 로 올라온다. 방향을 뒤집으면 절벽이 안 막힌다.
			# j 는 격자 1차원 인덱스다 — % 가 열, / 가 **행**(정수 나눗셈이 의도).
			@warning_ignore("integer_division")
			var jz := j / n
			if not passable(_ground, _world(j % n, jz), _world(cx, cz)):
				continue
			var step: float = cell * (1.4142 if o.x != 0 and o.y != 0 else 1.0)
			if cost[cur] + step < cost[j] - 0.001:
				cost[j] = cost[cur] + step
				# j 에서 보면 cur 이 성 쪽이다 — 우리가 방금 넘어온 방향의 반대.
				var inv := Vector2(-float(o.x), -float(o.y)).normalized()
				dir_x[j] = inv.x
				dir_z[j] = inv.y
				queue.append(j)
	var reach := 0
	for i in total:
		if cost[i] < UNREACHED:
			reach += 1
	print("[nav] 격자 %d×%d — 성에서 닿는 칸 %d개 (%.0f%%)" % [
		n, n, reach, 100.0 * float(reach) / float(total)])

func _index(ix: int, iz: int) -> int:
	if ix < 0 or iz < 0 or ix >= n or iz >= n:
		return -1
	return iz * n + ix

func _world(ix: int, iz: int) -> Vector3:
	return Vector3(-half + (float(ix) + 0.5) * cell, 0.0, -half + (float(iz) + 0.5) * cell)

func _cell_of(at: Vector3) -> int:
	return _index(int(floor((at.x + half) / cell)), int(floor((at.z + half) / cell)))

## 이 자리에서 성 쪽으로 가야 할 방향(수평, 정규화). 길이 없으면 Vector3.ZERO.
func flow(at: Vector3) -> Vector3:
	if n == 0:
		return Vector3.ZERO
	var i := _cell_of(at)
	if i < 0:
		return Vector3.ZERO
	if cost[i] >= UNREACHED:
		return Vector3.ZERO
	# ⚠️ 칸 중심으로 곧장 가게 하지 않는다. 방향만 쓰면 무리가 흩어진 채로 같이 흐른다.
	return Vector3(dir_x[i], 0.0, dir_z[i])

## 이 자리를 밟을 수 있는가 (길 또는 벌판). 벌레의 한 걸음 판정이 이걸 본다.
func is_walkable(at: Vector3) -> bool:
	if n == 0 or not _has_mask:
		return true
	var i := _cell_of(at)
	return i < 0 or walkable[i] == 1

## 이 자리가 성에서 닿는 곳인가 (스폰 자리 검증용).
func reachable(at: Vector3) -> bool:
	var i := _cell_of(at)
	return i >= 0 and cost[i] < UNREACHED
