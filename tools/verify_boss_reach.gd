extends SceneTree
## 보스가 성을 때릴 때 **뿔이 실제로 성벽에 닿는지** 좌표로 검증한다.
## godot --headless --path . --script tools/verify_boss_reach.gd
##
## 뿔 끝 위치는 스킨 메시라 엔진에서 직접 못 읽는다 — 블렌더에서 잰 모델 좌표를
## Stag 노드의 global_transform 으로 옮겨 계산한다 (glTF Y-up: 블렌더 (x,y,z) -> (x, z, -y)).

## stag_v01.blend 실측 (블렌더 단위)
const TIP_REST := Vector3(2.138, 0.401, 0.0)     ## 휴식 자세 뿔 끝 (x, z, -y)
const TIP_SMASH := Vector3(2.410, 0.063, 0.0)    ## 내려찍는 순간(f29)
const HORN_LEN := 1.038                          ## 뿔 길이 (블렌더)

func _init() -> void:
	_run()

## 점이 성 사각형(XZ) 안으로 얼마나 들어갔는지. 양수 = 파고듦, 음수 = 떨어짐.
func _penetration(p: Vector3, r: Rect2) -> float:
	var dx: float = maxf(r.position.x - p.x, p.x - r.end.x)
	var dz: float = maxf(r.position.y - p.z, p.z - r.end.y)
	# 밖이면 사각형까지의 거리(음수로), 안이면 가장 가까운 변까지의 깊이(양수)
	if dx > 0.0 or dz > 0.0:
		return -Vector2(maxf(dx, 0.0), maxf(dz, 0.0)).length()
	return -maxf(dx, dz)

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.set_physics_process(false)
	var base = main.get_node("BaseBlock")
	var rect: Rect2 = base.footprint()

	var boss = main.spawn_boss()
	var ok := true
	var scale_checked := false

	# 두 방향에서 접근시켜 본다: 정면(월드 +X)과 대각선(스폰존과 비슷한 각도)
	for case in [{n = "정면", d = Vector3(1, 0, 0)}, {n = "대각", d = Vector3(0.707, 0, 0.707)}]:
		boss.state = Boss.State.WALK
		boss.global_position = base.global_position + case.d * 40.0
		boss.look_at(base.global_position, Vector3.UP)
		await process_frame

		# 성에 붙을 때까지 걷게 둔다 (도중에 예고/돌진 사이클이 도는 건 정상)
		main.set_physics_process(false)
		boss.set_physics_process(true)
		var steps := 0
		while boss.state != Boss.State.SMASH_WAIT and steps < 8000:
			await physics_frame
			steps += 1
		if steps >= 8000:
			print("FAIL: 성에 도달하지 못했다 (상태 %d)" % boss.state)
			ok = false
		var stag: Node3D = boss._stag
		var surf: float = boss._dist_to_base()
		var tip_rest: Vector3 = stag.global_transform * TIP_REST
		var tip_smash: Vector3 = stag.global_transform * TIP_SMASH
		var pen_rest := _penetration(tip_rest, rect)
		var pen_smash := _penetration(tip_smash, rect)
		var quarter: float = HORN_LEN * 0.25 * 5.04

		if not scale_checked:
			var reach: float = (tip_rest - boss.global_position).length()
			print("모델 스케일 확인: 휴식 뿔 끝이 보스 중심에서 %.2f유닛 (기대 %.1f)" % [reach, Boss.HORN_REACH])
			if absf(reach - Boss.HORN_REACH) > 0.5:
				ok = false
			scale_checked = true

		print("[%s] 정지 시 성벽까지 %.2f (기대 %.2f)" % [case.n, surf, Boss.HORN_REACH + Boss.STAND_GAP])
		print("   대기 자세 뿔 끝: %+.2f (음수=떨어짐, 겹치면 안 됨)" % pen_rest)
		print("   내려찍는 순간  : %+.2f (0 ~ %.2f = 끝~1/4 지점이 닿음)" % [pen_smash, quarter])
		print("   뿔 끝 높이 %.2f / 성벽 높이 4.0" % tip_smash.y)
		if pen_rest > 0.1:
			print("   FAIL: 대기 중에 뿔이 성벽을 뚫고 있다")
			ok = false
		if pen_smash < 0.0 or pen_smash > quarter:
			print("   FAIL: 내려찍을 때 접촉이 범위 밖")
			ok = false
		boss.set_physics_process(false)

	# --- 성 앞 애니메이션 순서: 대기 -> 내려찍기 -> 대기 ---
	# 예고(telegraph)는 **돌진 전용 신호**라 성을 때리는 사이클에 섞이면 안 된다.
	boss.set_physics_process(true)
	var anim: AnimationPlayer = boss._anim
	var seq: Array = []
	var last := ""
	for i in 420:                                  # 7초 = 내려찍기 사이클 1.4회
		await physics_frame
		# 원샷이 끝난 프레임은 current_animation 이 빈 문자열이다 (자세는 마지막 프레임 유지).
		var cur: String = anim.current_animation
		if cur != "" and cur != last:
			seq.append(cur)
			last = cur
	boss.set_physics_process(false)
	print("성 앞 애니 순서: ", seq)
	if seq.has("telegraph"):
		print("   FAIL: 성 앞에서 돌진 예고 애니가 나왔다")
		ok = false
	if not (seq.has("smash") and seq.has("idle")):
		print("   FAIL: 대기(idle)/내려찍기(smash) 애니가 안 나왔다")
		ok = false

	# --- 성 앞에서 폭연으로 죽으면 조각이 성 쪽으로 날아가지 않는다 ---
	# 시체는 바닥 착지만 판정하므로, 성 위로 떨어지면 벽을 통과해 성에 박힌 것처럼 보인다.
	var parent: Node = boss.get_parent()
	var to_base: Vector3 = base.global_position - boss.global_position
	to_base.y = 0.0
	to_base = to_base.normalized()
	boss.die(boss.global_position)
	boss.combust(0.1)
	for i in 24:
		paused = false
		await physics_frame
	var chunks: Array = []
	for c in parent.get_children():
		if c is BossCorpse:
			chunks.append(c)
	print("폭연 조각 %d개 — 성 방향 성분 (양수면 성쪽으로 날아감)" % chunks.size())
	if chunks.size() != 3:
		ok = false
	for c in chunks:
		var h := Vector3(c.vel.x, 0.0, c.vel.z)
		var toward: float = h.normalized().dot(to_base) if h.length() > 0.001 else 0.0
		print("   %+.2f  %s" % [toward, "OK" if toward <= 0.01 else "FAIL 성쪽!"])
		if toward > 0.01:
			ok = false

	# 착지 지점이 성 안이면 안 된다
	var landed := {}
	for i in 260:
		paused = false
		await physics_frame
		for c in chunks:
			if is_instance_valid(c) and c._landed and not landed.has(c.get_instance_id()):
				landed[c.get_instance_id()] = c.global_position
	print("착지 %d/3, 성 발자국 안에 떨어진 조각:" % landed.size())
	var inside := 0
	for pos: Vector3 in landed.values():
		if rect.has_point(Vector2(pos.x, pos.z)):
			inside += 1
	print("   %d개 (기대 0)" % inside)
	if landed.size() != 3 or inside != 0:
		ok = false

	print("결과: ", "PASS" if ok else "FAIL")
	quit()
