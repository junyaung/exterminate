extends SceneTree
## 시간대 선택 검증 (유저 지시 2026-08-18: 자동 진행 빼고 낮/노을/밤 선택식).
##   1) 시간대마다 해 각도가 다르다
##   2) 3등분 — 위상 경계가 같은 간격
##   3) 위상 안에서 색이 **일정한 속도로** 섞인다 (gradual)
##   4) 고르면 그쪽으로 **서서히** 넘어간다 (즉시 아님)
##   5) 넘어가는 방향은 항상 앞으로 (밤 -> 낮 을 거꾸로 되감지 않는다)
##   6) 시계는 Mood 를 참조하고, **문자판 크기만큼만** 마우스를 먹는다
##      (화면 전체를 먹으면 망치를 못 휘두른다)
## godot --headless --path . --script tools/verify_mood_clock.gd

func _init() -> void:
	_run()

func _run() -> void:
	var fail := 0
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var mood := main.get_node("Mood") as Mood
	var sun := main.get_node("Sun") as DirectionalLight3D
	var clock := main.get_node("HUD/MoodClock") as MoodClock

	# --- 1) 시간을 옮기면 해가 움직인다 ---
	# ⚠️ 자동 진행 자체가 없어졌다 (선택식). time 을 직접 넣어 각 시간대를 재본다.
	mood.time = 0.0
	mood._apply_time()
	var rot_day := sun.rotation
	mood.time = 1.0
	mood._apply_time()
	var rot_sunset := sun.rotation
	mood.time = 2.0
	mood._apply_time()
	var rot_night := sun.rotation
	var moved := rad_to_deg(rot_day.angle_to(rot_sunset)) + rad_to_deg(rot_sunset.angle_to(rot_night))
	var ok1: bool = moved > 30.0
	fail += 0 if ok1 else 1
	print("1) 해 각도 이동 %.0f도 (낮->노을->밤, 기대 >30) %s" % [moved, "OK" if ok1 else "***"])

	# --- 2~3) 순서와 3등분 ---
	var order: Array[int] = []
	var bounds: Array[float] = []
	var prev := -1
	var steps := 300
	for i in steps + 1:
		mood.time = 3.0 * float(i) / float(steps)
		mood._apply_time()
		if int(mood.current) != prev:
			prev = int(mood.current)
			order.append(prev)
			bounds.append(mood.time)
	# ⚠️ 마지막 0 은 **한 바퀴 돌아 낮으로 돌아온 것**이라 정상이다 (처음에 이걸 빼먹고
	#    [0,1,2] 를 기대했다가 오탐이 났다).
	var ok2: bool = order.slice(0, 4) == [0, 1, 2, 0]
	fail += 0 if ok2 else 1
	print("2) 위상 순서 %s (기대 [0,1,2,0] — 한 바퀴) %s" % [order, "OK" if ok2 else "***"])

	# ⚠️ bounds[0] 은 시작값(0.0)이지 전환점이 아니다 — **전환점 사이**를 재야 한다.
	var len1 := bounds[2] - bounds[1]
	var len2 := bounds[3] - bounds[2]
	var ok3: bool = absf(len1 - len2) < 0.05 and absf(len1 - 1.0) < 0.06
	fail += 0 if ok3 else 1
	print("3) 위상 길이 %.2f / %.2f (기대 1.00씩 = 3등분) %s" % [
		len1, len2, "OK" if ok3 else "***"])

	# --- 4) 위상 내내 **일정한 속도로** 섞인다 (유저 지시: gradual) ---
	# ⚠️ 전역 셰이더 값은 헤드리스에서 못 읽는다 (렌더 디바이스가 없어 Nil — 실제로 크래시했다).
	#    같은 보간을 거치는 Environment 값으로 본다.
	var d0: Color = Mood.PRESETS[Mood.Phase.DAY].bg
	var d1: Color = Mood.PRESETS[Mood.Phase.SUNSET].bg
	var errs := 0.0
	for k in 11:
		var f := float(k) / 10.0
		mood.time = f
		mood._apply_time()
		# ⚠️ Color 에는 distance_to 가 없다 — 채널 차이의 최댓값으로 잰다.
		var got: Color = mood._env.background_color
		var exp: Color = d0.lerp(d1, f)
		errs = maxf(errs, maxf(absf(got.r - exp.r), maxf(absf(got.g - exp.g), absf(got.b - exp.b))))
	var ok3b: bool = errs < 0.02
	fail += 0 if ok3b else 1
	print("3b) 낮->노을 구간이 선형으로 섞인다 (최대 오차 %.4f, 기대 <0.02) %s" % [
		errs, "OK" if ok3b else "***"])

	# --- 4) 고르면 서서히 넘어간다 ---
	mood.apply(Mood.Phase.DAY)          # 즉시 초기화
	mood.transition = 0.5
	mood.select(Mood.Phase.SUNSET)
	await process_frame
	var mid: float = mood.time
	var ok4: bool = mid > 0.0 and mid < 1.0    # 한 프레임 만에 도착하면 "즉시"다
	fail += 0 if ok4 else 1
	print("4) 선택 직후 시각 %.3f (0<x<1 이어야 서서히) %s" % [mid, "OK" if ok4 else "***"])

	var t0 := Time.get_ticks_msec()
	while not is_equal_approx(mood.time, 1.0) and Time.get_ticks_msec() - t0 < 3000:
		await process_frame
	var ok4b: bool = is_equal_approx(mood.time, 1.0) and int(mood.current) == 1
	fail += 0 if ok4b else 1
	print("4b) 도착 시각 %.3f / 위상 %d (기대 1.0 / 노을) %s" % [
		mood.time, int(mood.current), "OK" if ok4b else "***"])

	# --- 5) 밤 -> 낮 은 앞으로 돈다 (거꾸로 되감지 않는다) ---
	mood.apply(Mood.Phase.NIGHT)
	mood.select(Mood.Phase.DAY)
	await process_frame
	# 2.0 에서 앞으로 가면 2.x, 거꾸로면 1.x 가 된다
	var ok5: bool = mood.time > 2.0
	fail += 0 if ok5 else 1
	print("5) 밤(2.0) -> 낮 전환 중 시각 %.3f (>2.0 이어야 앞으로) %s" % [
		mood.time, "OK" if ok5 else "***"])

	# --- 6) 시계가 화면 전체를 먹지 않는다 ---
	var ok6: bool = clock != null and clock.mood == mood \
		and clock.size.x < 200.0 and clock.mouse_filter == Control.MOUSE_FILTER_STOP
	fail += 0 if ok6 else 1
	print("6) 시계 크기 %s / 마우스 %d (문자판만 먹어야 한다) %s" % [
		clock.size if clock else Vector2.ZERO,
		clock.mouse_filter if clock else -1, "OK" if ok6 else "***"])

	print("")
	print("시간대 선택 검증 통과" if fail == 0 else "시간대 선택 검증 실패 %d 건" % fail)
	quit(0 if fail == 0 else 1)
