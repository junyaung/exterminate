extends SceneTree
## 쿨타임 도넛 HUD 검증 — 진행도·준비·반짝 트리거를 상태별로 확인한다.
## godot --headless --path . --script tools/verify_cooldown_hud.gd
func _init() -> void: _run()
func ok(c: bool) -> String: return "OK" if c else "*** 실패 ***"
func near(a: float, b: float) -> bool: return absf(a - b) < 0.02

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var hs = main.get_node("HammerStrike")
	var hud: CooldownHud = null
	for c in main.get_children():
		if c is CooldownHud:
			hud = c
	print("HUD 생성=%s  %s" % [hud != null, ok(hud != null)])
	await process_frame   # _process 가 hammer 를 잡을 시간

	print("\n[초기 — 전부 준비]")
	print("  L=%.2f/%s  CHG=%.2f/%s  R=%.2f/%s  %s" % [
		hud._l_progress(), hud._l_ready(), hud._chg_progress(), hud._chg_ready(),
		hud._r_progress(), hud._r_ready(),
		ok(hud._l_ready() and hud._chg_ready() and hud._r_ready()
			and near(hud._l_progress(), 1.0) and near(hud._r_progress(), 1.0))])

	print("\n[평타 쿨 절반]")
	hs._cd = 0.325
	hs._cd_total = 0.65
	print("  L 진행도 %.2f (기대 0.50), 준비=%s  %s" % [hud._l_progress(), hud._l_ready(),
		ok(near(hud._l_progress(), 0.5) and not hud._l_ready())])
	print("  CHG 는 평소에 L 을 비춘다: %.2f  %s" % [hud._chg_progress(),
		ok(near(hud._chg_progress(), 0.5))])

	print("\n[차징 중 — CHG 는 차징 게이지]")
	hs._cd = 0.0
	hs._charging = true
	hs._charge = hs.charge_deadzone + (hs.charge_time() - hs.charge_deadzone) * 0.6
	print("  CHG 진행도 %.2f (기대 0.60), 준비=%s (아직)  %s" % [
		hud._chg_progress(), hud._chg_ready(),
		ok(near(hud._chg_progress(), 0.6) and not hud._chg_ready())])
	hs._charge = hs.charge_time() + 0.1
	print("  풀차징 -> 진행도 %.2f, 준비=%s (이제 놔라)  %s" % [
		hud._chg_progress(), hud._chg_ready(),
		ok(near(hud._chg_progress(), 1.0) and hud._chg_ready())])
	hs._charging = false

	print("\n[특수 쿨 40%% 지남]")
	hs._special_cd = hs.stats.get_v(Stats.COOLDOWN_SPECIAL) * 0.6
	print("  R 진행도 %.2f (기대 0.40), 준비=%s  %s" % [hud._r_progress(), hud._r_ready(),
		ok(near(hud._r_progress(), 0.4) and not hud._r_ready())])
	hs._special_cd = 0.0
	hs._special_active = true
	print("  쿨 0 이어도 낙하 진행중이면 준비 아님: %s  %s" % [hud._r_ready(),
		ok(not hud._r_ready())])
	hs._special_active = false

	print("\n[반짝 — 준비되는 순간 한 번]")
	hs._cd = 0.1
	hs._cd_total = 0.65
	hud._process(0.016)          # 준비 안 됨 상태를 기억시킨다
	hs._cd = 0.0
	hud._process(0.016)          # 이 프레임에 준비됨 -> 반짝 시작
	var f1: float = hud._flash[0]
	hud._process(0.016)
	print("  전이 직후 flash=%.2f (>0), 다음 프레임 %.2f (감소)  %s" % [
		f1, hud._flash[0], ok(f1 > 0.0 and hud._flash[0] < f1)])
	hud._process(0.016)
	var f2: float = hud._flash[0]
	hud._process(0.016)
	print("  준비 유지 중엔 다시 안 반짝인다 (계속 감소): %.2f -> %.2f  %s" % [
		f2, hud._flash[0], ok(hud._flash[0] < f2)])

	# --- 옵션 토글 ---
	print("\n[표시 끄기/켜기]")
	hud.enabled = false
	print("  끔 -> 보임=%s  _process 도는가=%s (둘 다 false 여야)  %s" % [
		hud._canvas.visible, hud.is_processing(),
		ok(not hud._canvas.visible and not hud.is_processing())])
	# 꺼진 동안 쿨이 다 돌았다고 치고 켰을 때 헛반짝이 없어야 한다
	hs._cd = 0.5
	hs._cd_total = 0.65
	hud._process(0.016)          # 안 도는 상태지만 강제로 한 번 — 껐으니 무시돼야 정상
	hs._cd = 0.0
	hud.enabled = true
	print("  켬 -> 보임=%s  _process=%s  %s" % [
		hud._canvas.visible, hud.is_processing(),
		ok(hud._canvas.visible and hud.is_processing())])
	print("  켜자마자 헛반짝 없음: flash=%.2f (0 이어야)  %s" % [
		hud._flash[0], ok(hud._flash[0] == 0.0)])
	# 켠 뒤엔 다시 정상 동작 — 쿨을 돌렸다가 끝내면 반짝인다
	hs._cd = 0.1
	hud._process(0.016)
	hs._cd = 0.0
	hud._process(0.016)
	print("  켠 뒤 정상 반짝: flash=%.2f (>0)  %s" % [hud._flash[0], ok(hud._flash[0] > 0.0)])
	quit()
