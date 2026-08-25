extends SceneTree
## 웨이브 테이블 + 스폰 규칙을 그대로 돌려서 **런 하나에서 몇 레벨을 올리는가**를 잰다.
## 실제 전투를 돌리지 않고 "모든 몹을 다 잡는다"를 전제로 총 경험치만 센다 —
## 웨이브는 전멸이 조건이라 이 전제가 곧 정답이다.
##
## godot --headless --path . --script tools/sim_levels.gd
## 후보값 비교: XPF=18 XPC=1.3 godot --headless --path . --script tools/sim_levels.gd

const MainScript := preload("res://scripts/main.gd")

## 스폰 index 에서 몹 종류를 고른다 — main.gd 의 pick_type 과 같은 규칙.
func type_at(index: int) -> StringName:
	for rule in MainScript.SPAWN_RULES:
		if (index + 1) % int(rule.every) == 0:
			return rule.type
	return &"grunt"

## (웨이브별 누적 경험치, 총 경험치) 를 낸다.
func xp_schedule() -> Array:
	var per_wave: Array[float] = []
	var index := 0
	for w in range(MainScript.WAVE_COUNT):
		var wd: Dictionary = MainScript.WAVES[w]
		var sum := 0.0
		for i in int(wd.count):
			sum += Enemy.xp_of(type_at(index))
			index += 1
		if int(wd.boss) >= 0:
			sum += Enemy.xp_of(&"stag") * MainScript.BOSS_SCALE[int(wd.boss)]
		per_wave.append(sum)
	return per_wave

## 주어진 곡선으로 누적 경험치를 레벨로 환산한다.
func level_at(total: float, first: float, curve: float) -> int:
	var lv := 1
	var left := total
	while left >= first * pow(float(lv), curve):
		left -= first * pow(float(lv), curve)
		lv += 1
	return lv

func report(first: float, curve: float, per_wave: Array) -> void:
	print("── XP_FIRST=%.1f  XP_CURVE=%.2f" % [first, curve])
	var cum := 0.0
	var prev := 1
	for w in per_wave.size():
		cum += per_wave[w]
		var lv := level_at(cum, first, curve)
		print("   W%-2d  경험치 %6.0f (누적 %7.0f)   LV %2d   (이번 웨이브 +%d장)" % [
			w + 1, per_wave[w], cum, lv, lv - prev])
		prev = lv
	print("   → 런 전체 카드 %d장\n" % (prev - 1))

func _init() -> void:
	var per_wave := xp_schedule()
	var total := 0.0
	for v in per_wave:
		total += v
	var mobs := 0
	for w in MainScript.WAVES:
		mobs += int(w.count)
	print("몹 %d마리, 총 경험치 %.0f (마리당 평균 %.2f)\n" % [mobs, total, total / float(mobs)])

	print("[현재]")
	report(LevelSystem.XP_FIRST, LevelSystem.XP_CURVE, per_wave)

	var f := OS.get_environment("XPF")
	var c := OS.get_environment("XPC")
	if f != "" or c != "":
		print("[후보]")
		report(float(f) if f != "" else LevelSystem.XP_FIRST,
			float(c) if c != "" else LevelSystem.XP_CURVE, per_wave)
	quit()
