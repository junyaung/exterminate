extends SceneTree
## 스태그 보스 모델 와이어링 검증 (헤드리스)
## godot --headless --path . --script tools/verify_boss_model.gd
## 확인: ①애니 4종 임포트/루프 플래그 ②파트 메시·머티리얼 ③상태 전이 애니
##       ④사망 시 3조각 스폰 ⑤조각이 착지 후 소멸

func _init() -> void:
	_run()

func _corpse_count(parent: Node) -> int:
	var n := 0
	for c in parent.get_children():
		if c is BossCorpse:
			n += 1
	return n

func _pool_count(parent: Node) -> int:
	var n := 0
	for c in parent.get_children():
		if c is BloodPool:
			n += 1
	return n

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.set_physics_process(false)

	var boss = main.spawn_boss()
	boss.global_position = Vector3(30, 0, 0)
	await process_frame
	var ok := true

	# 1) 애니메이션 임포트
	var anim: AnimationPlayer = boss._anim
	if anim == null:
		print("FAIL: AnimationPlayer 를 못 찾음")
		ok = false
	else:
		var names := anim.get_animation_list()
		print("애니메이션: ", names)
		for want in ["walk", "telegraph", "charge", "smash", "stun", "stun_wake"]:
			if not (want in names):
				print("FAIL: '%s' 없음" % want)
				ok = false
		if "stun_wake" in names and anim.get_animation("stun_wake").loop_mode != Animation.LOOP_NONE:
			print("FAIL: 'stun_wake' 가 루프임")
			ok = false
		for lp in ["walk", "telegraph", "charge", "stun"]:
			if lp in names and anim.get_animation(lp).loop_mode != Animation.LOOP_LINEAR:
				print("FAIL: '%s' 가 루프가 아님" % lp)
				ok = false
		if "smash" in names and anim.get_animation("smash").loop_mode != Animation.LOOP_NONE:
			print("FAIL: 'smash' 가 루프임")
			ok = false
		print("스폰 직후 재생: ", anim.current_animation, " (기대 walk)")
		if anim.current_animation != "walk":
			ok = false

	# 2) 파트 메시 + 머티리얼
	print("파트 메시: %d (기대 3)" % boss._part_meshes.size())
	if boss._part_meshes.size() != 3:
		ok = false
	for mi: MeshInstance3D in boss._part_meshes:
		var m := mi.get_surface_override_material(0)
		if not (m is ShaderMaterial):
			print("FAIL: %s 서피스0 셀 머티리얼 아님" % mi.name)
			ok = false

	# 3) 상태 전이 애니
	boss._begin_telegraph()
	await process_frame
	if anim != null:
		print("예고 전이 후 재생: ", anim.current_animation, " (기대 telegraph)")
		if anim.current_animation != "telegraph":
			ok = false
	boss._enter_stun()
	await process_frame
	if anim != null:
		print("기절 전이 후 재생: ", anim.current_animation, " (기대 stun)")
		if anim.current_animation != "stun":
			ok = false
	# 깨어나기 직전 머리 털기 원샷
	boss._timer = 0.5
	await physics_frame
	await process_frame
	if anim != null:
		print("기절 종료 직전 재생: ", anim.current_animation, " (기대 stun_wake)")
		if anim.current_animation != "stun_wake":
			ok = false

	# 4) 일반 사망 -> 3조각 주저앉기(납작) + 보라 웅덩이 1개
	# die() 는 연출을 한 프레임 미룬다(폭연이 같은 프레임에 가로채러 오므로) —
	# 조각·웅덩이는 다음 프레임에 생긴다. 그 뒤 boss 는 freed, 만지면 안 된다.
	var parent = boss.get_parent()
	var before := _corpse_count(parent)
	var pools_before := _pool_count(parent)
	boss.die(boss.global_position + Vector3(5, 0, 0))
	await process_frame
	await process_frame
	var spawned := _corpse_count(parent) - before
	var pools := _pool_count(parent) - pools_before
	print("일반 사망: 조각 %d (기대 3), 웅덩이 %d (기대 1), 보스 해제: %s" % [
		spawned, pools, str(not is_instance_valid(boss))])
	if spawned != 3 or pools != 1 or is_instance_valid(boss):
		ok = false

	# 4b) 폭연 사망 -> 부풀기(조각 없음) -> 터지며 3조각 공중 발사
	paused = false
	var b2 = main.spawn_boss()
	b2.global_position = Vector3(-30, 0, 15)
	await process_frame
	var before2 := _corpse_count(parent)
	b2.die(b2.global_position + Vector3(3, 0, 0))
	b2.combust(0.4)                      # 게임과 같은 순서: die 직후 같은 프레임에 가로챔
	await process_frame
	await process_frame
	var during := _corpse_count(parent) - before2
	print("폭연 사망: die+combust 직후 조각 %d (기대 0 — 아직 부푸는 중)" % during)
	if during != 0:
		ok = false
	for i in 40:                          # 0.66초 — 0.4초 부풀기가 끝난다
		paused = false
		await physics_frame
	var blasted := _corpse_count(parent) - before2
	var flying_up := 0
	for c in parent.get_children():
		if c is BossCorpse and not c._landed and c.vel.y > 0.0:
			flying_up += 1
	print("폭연 사망: 부풀기 후 조각 %d (기대 3), 상승 중 %d, 보스 해제: %s" % [
		blasted, flying_up, str(not is_instance_valid(b2))])
	if blasted != 3 or is_instance_valid(b2):
		ok = false

	# 5) 착지/박힘 -> 소멸 (양쪽 조각 + 웅덩이, 7초 시뮬)
	# 보스 경험치로 레벨업 카드가 열리면 트리가 pause 돼 전부 얼어붙는다(게임에선 의도된 동작).
	# 여기선 카드를 골라줄 사람이 없으므로 pause 를 강제로 푼다.
	var landed_seen := false
	for i in 420:
		paused = false
		await physics_frame
		if not landed_seen:
			for c in parent.get_children():
				if c is BossCorpse and c._landed:
					landed_seen = true
	var left := _corpse_count(parent) + _pool_count(parent)
	print("착지 관측: %s / 7초 후 남은 조각+웅덩이: %d (기대 0)" % [str(landed_seen), left])
	if not landed_seen or left != 0:
		ok = false

	print("결과: ", "PASS" if ok else "FAIL")
	quit()
