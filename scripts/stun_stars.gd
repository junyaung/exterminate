class_name StunStars
extends Node3D

## 만화식 기절 표시 — 머리 위를 빙글빙글 도는 별 3개 + 타원 고리 (유저 스펙, 2026-08-13).
## 별은 5각 별 프리즘(절차 생성), 고리는 납작 토러스. 전부 unshaded #fdd179(nice31).
## 탑다운 카메라라 별을 **바닥과 나란히 눕혀** 놓는다 — 서 있으면 옆모서리만 보인다.
##
## 보스 루트(scale 14)의 자식으로 붙는 걸 전제로 spawn() 이 스케일을 역보정한다.
## 치수는 전부 월드 단위로 썼다: 궤도 반지름 ~2.3, 큰 별 ~1.1.

const COL := Color(0.992, 0.82, 0.475)      # nice31 #fdd179
const SPIN := 3.6                            ## 궤도 각속도 (rad/s)
const BOB := 0.35                            ## 위아래 살랑임 (월드)

var _stars: Array[MeshInstance3D] = []
var _t := 0.0
var _base_y := 0.0
var _bob_local := 0.0        ## BOB 를 host 로컬 단위로 환산한 값


## host 의 자식으로 붙인다. local_pos 는 host 로컬(스케일 전) 좌표.
## world_size = 궤도 반지름(월드 유닛).
static func spawn(host: Node3D, local_pos: Vector3, world_size: float) -> StunStars:
	var s := StunStars.new()
	host.add_child(s)
	s.position = local_pos
	var host_scale: float = maxf(host.global_basis.get_scale().x, 0.001)
	s.scale = Vector3.ONE * (world_size / host_scale)
	s._bob_local = BOB / host_scale
	s._build()
	return s


func _build() -> void:
	_base_y = position.y
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = COL
	# 궤도 고리 — 별들이 그리는 길. 살짝 투명해야 별이 주인공으로 남는다.
	# ⚠️ 예전엔 이어진 토러스였는데, 별 뒤에 **끊김 없는 띠**가 붙어 보였다 (유저 지적).
	#    조준 원과 같은 문법으로 점선으로 끊는다 — 갭이 있어야 '돌고 있다'가 읽힌다.
	var ring := MeshInstance3D.new()
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.albedo_color = Color(COL, 0.5)
	ring.mesh = _ring_mesh()
	ring.set_surface_override_material(0, rmat)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	# 별 3개: 하나 크고 둘 작게 (레퍼런스 구도)
	var sizes := [1.0, 0.68, 0.55]
	for i in 3:
		var mi := MeshInstance3D.new()
		mi.mesh = _star_mesh()
		mi.set_surface_override_material(0, mat)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := TAU * float(i) / 3.0
		mi.position = Vector3(cos(a), 0.0, sin(a))
		mi.scale = Vector3.ONE * (0.48 * sizes[i])
		mi.rotation.y = randf_range(0.0, TAU)
		add_child(mi)
		_stars.append(mi)


## 점선 궤도 고리 — 납작한 띠를 DASHES 조각으로 끊어 만든다.
## 토러스를 눌러 쓰지 않고 평면 띠로 만드는 이유: 탑다운이라 두께가 안 보이는데
## 튜브를 유지하면 조각마다 마구리가 생겨 점선이 지저분해진다.
const RING_INNER := 0.965
const RING_OUTER := 1.0
const DASHES := 12          ## 조각 수
const DASH_DUTY := 0.55     ## 한 칸에서 실제로 그리는 비율 (나머지가 갭)

func _ring_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 4                            # 조각 하나를 몇 개로 쪼갤지 (곡률)
	for d in DASHES:
		var a0 := TAU * float(d) / float(DASHES)
		var a1 := a0 + TAU / float(DASHES) * DASH_DUTY
		for k in seg:
			var t0 := lerpf(a0, a1, float(k) / float(seg))
			var t1 := lerpf(a0, a1, float(k + 1) / float(seg))
			var d0 := Vector3(cos(t0), 0.0, sin(t0))
			var d1 := Vector3(cos(t1), 0.0, sin(t1))
			var i0 := d0 * RING_INNER
			var o0 := d0 * RING_OUTER
			var i1 := d1 * RING_INNER
			var o1 := d1 * RING_OUTER
			# 위/아래 양면 — 별 메시와 같은 규약 (어느 쪽에서 봐도 면이 보인다)
			for v in [i0, o0, o1, i0, o1, i1]:
				st.set_normal(Vector3.UP); st.add_vertex(v)
			for v in [i0, o1, o0, i0, i1, o1]:
				st.set_normal(Vector3.DOWN); st.add_vertex(v)
	return st.commit()


## 바닥에 눕힌 5각 별 프리즘 (단위 크기, 두께 0.16).
## 위/아래 면 모두 감아서 어느 쪽에서 봐도 면이 보이게 한다.
func _star_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = []
	for i in 10:
		var r := 1.0 if i % 2 == 0 else 0.42
		var a := -TAU * float(i) / 10.0 + TAU * 0.25
		pts.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
	var h := 0.08
	for i in 10:
		var j := (i + 1) % 10
		# 윗면 (위에서 앞면 = RHR 노멀 아래 규약)
		st.set_normal(Vector3.UP); st.add_vertex(Vector3(0, h, 0))
		st.set_normal(Vector3.UP); st.add_vertex(pts[i] + Vector3(0, h, 0))
		st.set_normal(Vector3.UP); st.add_vertex(pts[j] + Vector3(0, h, 0))
		# 아랫면
		st.set_normal(Vector3.DOWN); st.add_vertex(Vector3(0, -h, 0))
		st.set_normal(Vector3.DOWN); st.add_vertex(pts[j] + Vector3(0, -h, 0))
		st.set_normal(Vector3.DOWN); st.add_vertex(pts[i] + Vector3(0, -h, 0))
		# 옆면
		var n := (pts[j] - pts[i]).cross(Vector3.DOWN).normalized()
		var a0 := pts[i] + Vector3(0, h, 0)
		var b0 := pts[j] + Vector3(0, h, 0)
		var a1 := pts[i] + Vector3(0, -h, 0)
		var b1 := pts[j] + Vector3(0, -h, 0)
		for v in [a0, b1, b0, a0, a1, b1]:
			st.set_normal(n)
			st.add_vertex(v)
	return st.commit()


func _process(delta: float) -> void:
	_t += delta
	rotation.y += SPIN * delta
	position.y = _base_y + _bob_local * sin(_t * 2.2)
	for i in _stars.size():
		_stars[i].rotation.y -= 2.0 * delta          # 별 자전 (궤도와 반대라 더 어지럽다)
		_stars[i].position.y = 0.12 * sin(_t * 3.0 + float(i) * 2.1)
