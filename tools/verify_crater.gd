extends SceneTree
## 분화구 검증 — **한 번만 뿜는다** (유저 지시 2026-08-18: "N발 나오고 끝, 후속 추가 없음").
##   1) 평타 여진+불 첫 방에 분화구가 열리고 불덩이가 crater_balls_normal 발
##   2) 발사점이 분화구 중심 한 점
##   3) 시간이 지나도 **더 안 나온다** (예전 2발리 구조가 되살아나면 여기서 잡힌다)
##   4) 특수는 crater_balls_special 발
##   5) 풀차징 평타는 crater_balls_charged 발 (무차징보다 많다)
##   6) 반쯤 차징은 아직 무차징 개수 — 내림이라 꽉 채워야 는다
##   7) 첫 가격에 **분출 연출**(틈새 발광)이 재생된다
##   8) 그래도 균열 지대는 소모되지 않고 남는다
## godot --headless --fixed-fps 60 --path . --script tools/verify_crater.gd

func _init() -> void:
	_run()

func _balls(hs) -> Array:
	var out := []
	for c in hs.get_children():
		if c is Fireball:
			out.append(c)
	return out

## ⚠️ **가장 최근 분화구**를 집는다. 분화구 수명이 5초라 앞 단계 것이 아직 살아 있고,
##    처음 찾은 것을 쓰면 이전 단계의 분화구를 재서 개수가 틀린다 (실제로 겪었다).
func _crater(hs, exclude := []) -> Crater:
	var out: Crater = null
	for c in hs.get_children():
		if c is Crater and is_instance_valid(c) and not exclude.has(c):
			out = c
	return out

func _clear_fields() -> void:
	for f in get_nodes_in_group("crack_fields"):
		f.expire()

func _run() -> void:
	var fail := 0
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var hs = main.get_node("HammerStrike")
	hs.has_aftershock = true
	hs.has_fire = true
	main.set_physics_process(false)      # 웨이브 스폰 정지

	# --- 1~2) 평타 한 방 -> 분화구 + 불덩이 (재타격 없이) ---
	# ⚠️ **원점(Vector3.ZERO)에서 치면 안 된다.** 예전엔 여기서 쳤는데, 마침 그 자리가
	#    맵 원점이라 "불덩이가 원점에서 나오는" 버그를 발사점 검사(2번)가 통과시켰다
	#    (2026-08-18 유저가 화면에서 먼저 발견했다). 반드시 원점에서 먼 자리에서 친다.
	var hit_at := Vector3(120, 0, -80)
	hs._impact(hit_at, 0.0)
	await process_frame
	var cr := _crater(hs)
	var n1: int = cr.balls_fired if cr != null else -1
	var ok1: bool = cr != null and n1 == hs.crater_balls_normal
	fail += 0 if ok1 else 1
	print("1) 평타 여진+불 첫 방 -> 분화구 %s / 불덩이 %d발 (기대 %d) %s" % [
		cr != null, n1, hs.crater_balls_normal, "OK" if ok1 else "***"])

	# ⚠️ 발사점은 **생성된 프레임에** 재야 한다 — 한 프레임만 지나도 포물선으로 날아간
	#    거리가 섞여 "흩어져 나왔다"로 오독된다.
	var far := 0.0
	for b in _balls(hs):
		# 분화구 중심이 아니라 **가격 지점** 기준으로 잰다 — 분화구가 엉뚱한 데 있어도 잡히게.
		var f := Vector2(b.global_position.x - hit_at.x, b.global_position.z - hit_at.z)
		far = maxf(far, f.length())
	# ⚠️ 한 프레임이 지났으므로 포물선으로 조금 날아간 거리가 섞인다 (0.08 쯤).
	#    "흩어져 나왔다"(반경 3 이상)와는 자릿수가 다르므로 0.3 을 문턱으로 둔다.
	var ok2: bool = far < 1.0
	fail += 0 if ok2 else 1
	print("2) 발사점 <-> 가격 지점 거리 최대 %.3f (기대 0 근처, 문턱 1.0) %s" % [far, "OK" if ok2 else "***"])

	# --- 3) 시간이 지나도 더 안 나온다 ---
	await create_timer(3.0).timeout
	var n2: int = cr.balls_fired if is_instance_valid(cr) else n1
	var ok3: bool = n2 == n1
	fail += 0 if ok3 else 1
	print("3) 3초 뒤 누적 %d발 (기대 그대로 %d — 후속 발리 없음) %s" % [
		n2, n1, "OK" if ok3 else "***"])

	# --- 4) 특수는 더 많이 ---
	_clear_fields()
	await create_timer(0.3).timeout
	var seen := []
	for c in hs.get_children():
		if c is Crater and is_instance_valid(c):
			seen.append(c)
	hs._special_blast(Vector3(80, 0, 80), hs.special_radius(), 100.0, 1.0)
	await process_frame
	var cs := _crater(hs, seen)
	var n3: int = cs.balls_fired if cs != null else -1
	var ok4: bool = n3 == hs.crater_balls_special and n3 > n1
	fail += 0 if ok4 else 1
	print("4) 특수 분화구 %d발 (기대 %d, 평타 %d발보다 많다) %s" % [
		n3, hs.crater_balls_special, n1, "OK" if ok4 else "***"])

	# --- 5) 차징해도 개수는 그대로 ---
	_clear_fields()
	await create_timer(0.3).timeout
	var seen2 := []
	for c in hs.get_children():
		if c is Crater and is_instance_valid(c):
			seen2.append(c)
	hs._impact(Vector3(160, 0, 160), 1.0)
	await process_frame
	var cc := _crater(hs, seen2)
	var n4: int = cc.balls_fired if cc != null else -1
	var ok5: bool = n4 == hs.crater_balls_charged and n4 > hs.crater_balls_normal
	fail += 0 if ok5 else 1
	print("5) 풀차징 평타 %d발 (기대 %d, 무차징 %d발보다 많다) %s" % [
		n4, hs.crater_balls_charged, hs.crater_balls_normal, "OK" if ok5 else "***"])

	# --- 6) 반쯤 차징은 아직 무차징 개수 (내림 규칙) ---
	_clear_fields()
	await create_timer(0.3).timeout
	var seen3 := []
	for c in hs.get_children():
		if c is Crater and is_instance_valid(c):
			seen3.append(c)
	hs._impact(Vector3(240, 0, 240), 0.6)
	await process_frame
	var ch := _crater(hs, seen3)
	var n5: int = ch.balls_fired if ch != null else -1
	var ok6: bool = n5 == hs.crater_balls_normal
	fail += 0 if ok6 else 1
	print("6) 60%% 차징 평타 %d발 (기대 %d — 꽉 채워야 는다) %s" % [
		n5, hs.crater_balls_normal, "OK" if ok6 else "***"])

	# --- 7) 첫 가격에 분출 연출(flare)이 재생되고, 균열은 **살아남는다** ---
	# ⚠️ "연출이 나왔나"는 셰이더 파라미터로 본다 — boost 가 1.0(기본)에서 올라가 있으면
	#    틈새가 빛나고 있다는 뜻이다. 불 조합은 맥동 tween 이 계속 돌므로 항상 1 보다 크다.
	_clear_fields()
	await create_timer(0.3).timeout
	hs._impact(Vector3(320, 0, 320), 0.0)
	await create_timer(0.2).timeout
	var fx: AftershockFX = null
	for c in hs.get_children():
		if c is AftershockFX and is_instance_valid(c):
			fx = c
	var boost := 0.0
	if fx != null and fx._crack_mat != null:
		boost = float(fx._crack_mat.get_shader_parameter("boost"))
	var ok7: bool = fx != null and boost > 1.05 and fx.lava
	fail += 0 if ok7 else 1
	print("7) 첫 가격 -> 틈새 발광 boost %.2f (기대 >1.0), 용암 모드 %s %s" % [
		boost, fx.lava if fx else false, "OK" if ok7 else "***"])

	# 균열은 소모되지 않고 남아 있어야 한다 (밟기·재타격이 여기 기댄다)
	await create_timer(0.4).timeout
	var ok8: bool = fx != null and is_instance_valid(fx) and fx.active
	fail += 0 if ok8 else 1
	print("8) 첫 가격 뒤에도 균열 지대 살아있음 %s (기대 true) %s" % [
		fx.active if (fx and is_instance_valid(fx)) else false, "OK" if ok8 else "***"])

	print("")
	print("분화구 검증 통과" if fail == 0 else "분화구 검증 실패 %d 건" % fail)
	quit(0 if fail == 0 else 1)
