extends SceneTree
## 풀차징 임팩트 연출 검증.
##   1) 평타는 위로 터지는 먼지, 풀차징은 바닥을 훑는 압축 고리 (방향이 반대인가)
##   2) 고리가 그 스윙의 실제 타격 반경까지 퍼지는가
##   3) 히트스톱이 걸렸다가 **반드시** 복구되는가 — 카드 화면이 트리를 멈춘 상태에서도
## godot --headless --path . --script tools/verify_charge_impact.gd
func _init() -> void: _run()

func ok(c: bool) -> String: return "OK" if c else "*** 실패 ***"

func particles(n: Node) -> Array:
	var out := []
	for c in n.get_children():
		if c is CPUParticles3D:
			out.append(c)
	return out

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var hs = main.get_node("HammerStrike")

	# --- 평타 ---
	hs._dust(Vector3.ZERO, 0.0)
	await process_frame
	var normal := particles(hs)
	print("[평타] 파티클 %d개" % normal.size())
	for p in normal:
		print("   spread=%.0f°  중력y=%.0f  radial_accel=%.1f" % [
			p.spread, p.gravity.y, p.radial_accel_max])
	var n_up: bool = normal.size() == 1 and normal[0].spread > 60.0 and normal[0].radial_accel_max == 0.0
	print("   위로 터지는가: %s" % ok(n_up))
	for p in normal:
		p.queue_free()
	await process_frame

	# --- 풀차징 ---
	var r: float = hs.strike_radius(1.0)
	hs._dust(Vector3.ZERO, 1.0)
	await process_frame
	var charged := particles(hs)
	print("\n[풀차징] 파티클 %d개 (수직 킥 + 압축 고리)  타격반경=%.1f" % [charged.size(), r])
	var ring: CPUParticles3D = null
	for p in charged:
		if p.radial_accel_max > 0.0:
			ring = p
	print("   고리 spread=%.0f°  중력y=%.0f  radial_accel=%.1f~%.1f  수명=%.2f" % [
		ring.spread, ring.gravity.y, ring.radial_accel_min, ring.radial_accel_max, ring.lifetime])
	# r = 0.5·a·t² 로 되짚어 도달 반경을 검산한다
	var reach: float = 0.5 * ring.radial_accel_min * ring.lifetime * ring.lifetime
	var reach_max: float = 0.5 * ring.radial_accel_max * ring.lifetime * ring.lifetime
	print("   도달 반경 %.1f ~ %.1f (타격반경 %.1f 를 감싸야 한다)  %s" % [
		reach, reach_max, r, ok(reach <= r and reach_max >= r)])
	print("   수평인가(spread<20°): %s" % ok(ring.spread < 20.0))
	# 수명 내내 지면 위에 남는가 — 가라앉으면 사라진 것처럼 보인다
	var y0: float = 0.12
	var vy: float = (ring.initial_velocity_min + ring.initial_velocity_max) * 0.5
	var t: float = ring.lifetime
	var y_end: float = y0 + vy * t + 0.5 * ring.gravity.y * t * t
	print("   수명 끝 높이 y=%.2f (0 이상이어야 지면 위)  %s" % [y_end, ok(y_end > 0.0)])
	# 알갱이가 둘레를 덮는가
	var circ: float = TAU * r
	var cover: float = float(ring.amount) * (ring.mesh as BoxMesh).size.x / circ
	print("   둘레 %.1f 유닛을 알갱이 %d개가 %.0f%% 덮음 (100%% 이상이면 이어져 보인다)  %s" % [
		circ, ring.amount, cover * 100.0, ok(cover >= 1.0)])

	# --- 히트스톱 ---
	print("\n[히트스톱]")
	print("   임팩트 전 time_scale=%.2f" % Engine.time_scale)
	hs._hitstop(hs.charge_hitstop, hs.charge_hitstop_scale)
	print("   임팩트 직후 time_scale=%.2f (기대 %.2f)  %s" % [
		Engine.time_scale, hs.charge_hitstop_scale,
		ok(is_equal_approx(Engine.time_scale, hs.charge_hitstop_scale))])
	# 최악의 경우 재현: 히트스톱 도중 카드 화면이 트리를 멈춘다
	paused = true
	await create_timer(hs.charge_hitstop * 3.0, true, false, true).timeout
	print("   트리 정지 상태로 대기 후 time_scale=%.2f (기대 1.00)  %s" % [
		Engine.time_scale, ok(is_equal_approx(Engine.time_scale, 1.0))])
	paused = false
	quit()
