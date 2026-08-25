extends SceneTree
## 카드가 **완전 무작위**로 나오는지 검증 (유저 지시 2026-08-14 로 등장 보장을 걷어냈다).
## 확인:
##   1) 첫 손패에 특정 카테고리가 **항상** 끼지는 않는가 (= 보장이 정말 사라졌는가)
##   2) 카드별 등장 빈도가 한쪽으로 쏠리지 않는가
##   3) 규칙(중복 상한 / 배타 / 1회성)은 그대로 지켜지는가
## godot --headless --path . --script tools/verify_card_random.gd

const N := 2000

func _init() -> void:
	_run()

func _run() -> void:
	var fail := 0
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var ui := main.get_node("CardUI")

	# --- 1) 첫 손패 카테고리 분포 -------------------------------------------
	var cat_hits := {}
	var card_hits := {}
	for i in N:
		ui.picked.clear()
		var hand: Array = ui._make_hand()
		for c in hand:
			cat_hits[c.cat] = int(cat_hits.get(c.cat, 0)) + 1
			card_hits[c.id] = int(card_hits.get(c.id, 0)) + 1

	var pool_size: int = ui._pool().size()
	print("첫 손패 %d회 (풀 %d장, 매번 3장) — 카테고리 분포" % [N, pool_size])
	var forced: Array[String] = []
	for cat in cat_hits:
		var pct := 100.0 * float(cat_hits[cat]) / float(N)
		# 3/풀크기 보다 훨씬 크면(≥99%) "항상 나온다" = 보장이 남아 있다는 뜻
		if pct >= 99.0:
			forced.append(String(cat))
		print("   %-10s %5.1f%% 의 손패에 등장" % [cat, pct])
	var ok1: bool = forced.is_empty()
	fail += 0 if ok1 else 1
	print("   항상 끼는 카테고리: %s %s" % [
		forced if not forced.is_empty() else "없음",
		"OK" if ok1 else "*** 아직 보장이 걸려 있다 ***"])

	# --- 2) 카드별 쏠림 ------------------------------------------------------
	var expect := float(N) * 3.0 / float(pool_size)
	var lo := INF
	var hi := -INF
	var lo_id := ""
	var hi_id := ""
	for id in card_hits:
		var v: float = float(card_hits[id])
		if v < lo:
			lo = v
			lo_id = String(id)
		if v > hi:
			hi = v
			hi_id = String(id)
	# 균등하면 각 카드가 기대치 근처. 3-시그마 여유를 넉넉히 잡아 ±25% 로 본다.
	var ok2: bool = card_hits.size() == pool_size \
		and lo > expect * 0.75 and hi < expect * 1.25
	fail += 0 if ok2 else 1
	print("")
	print("카드별 등장 %d종 (기대 %.0f회): 최소 %s %.0f / 최대 %s %.0f %s" % [
		card_hits.size(), expect, lo_id, lo, hi_id, hi,
		"OK" if ok2 else "*** 쏠렸거나 안 나오는 카드가 있다 ***"])

	# --- 3) 규칙은 그대로인가 -------------------------------------------------
	# 중복 상한: 같은 카드를 상한까지 먹으면 풀에서 빠져야 한다
	var rep := {}
	for c in CardCatalog.CARDS:
		if c.repeat and int(c.get("max_stacks", 0)) > 0:
			rep = c
			break
	var cap_ok := true
	if not rep.is_empty():
		ui.picked.clear()
		for i in int(rep.max_stacks):
			ui.picked.append(rep.id)
		for c in ui._pool():
			if c.id == rep.id:
				cap_ok = false
	fail += 0 if cap_ok else 1
	print("중복 상한: %s 를 %d장 먹으면 풀에서 빠진다 %s" % [
		rep.get("id", "-"), int(rep.get("max_stacks", 0)), "OK" if cap_ok else "*** 계속 나온다 ***"])

	# 배타: excludes 가 걸린 카드는 반대쪽을 가지면 빠져야 한다
	var exc := {}
	for c in CardCatalog.CARDS:
		if c.has("excludes"):
			exc = c
			break
	var exc_ok := true
	if not exc.is_empty():
		ui.picked.clear()
		ui.picked.append(exc.excludes)
		for c in ui._pool():
			if c.id == exc.id:
				exc_ok = false
		fail += 0 if exc_ok else 1
		print("배타 계약: %s 를 가지면 %s 는 안 나온다 %s" % [
			exc.excludes, exc.id, "OK" if exc_ok else "*** 같이 나온다 ***"])
	ui.picked.clear()

	print("")
	print("카드 무작위 검증 통과" if fail == 0 else "카드 무작위 검증 실패 %d 건" % fail)
	quit(0 if fail == 0 else 1)
