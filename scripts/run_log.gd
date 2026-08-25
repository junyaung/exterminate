class_name RunLog
extends RefCounted

## 플레이 한 판의 기록. 액트를 깰 때마다, 그리고 판이 끝날 때(승/패/중도 종료)
## 스냅샷을 한 줄씩 쌓아 JSON 으로 남긴다 — 밸런스는 감이 아니라 이 숫자로 잡는다.
##
## 저장 위치: `user://runs/run_<날짜시각>.json`
##   macOS 기준 ~/Library/Application Support/Godot/app_userdata/project - exterminate/runs/
##
## 한 판 = 파일 하나. 스냅샷이 쌓일 때마다 **파일 전체를 다시 쓴다** — 중간에 게임을
## 강제 종료해도 그때까지의 액트 기록은 이미 디스크에 있다.
##
## ⚠️ Node 가 아니라 RefCounted 다 (LevelSystem 과 같은 이유). Main 의 변수 초기화식으로
##    만들어지므로 어떤 _ready() 보다도 먼저 존재한다.

const DIR := "user://runs"

## 파일 하나에 들어가는 스키마 번호. 필드를 바꾸면 올릴 것 — 나중에 여러 판을 모아
## 분석할 때 옛 파일과 섞이는 걸 막는다.
const VERSION := 1

var path := ""
var _events: Array = []
var _started := ""

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	# 파일 이름에 콜론이 들어가면 안 되는 파일 시스템이 있다 (Windows). 미리 바꿔 둔다.
	_started = Time.get_datetime_string_from_system()
	path = "%s/run_%s.json" % [DIR, _started.replace(":", "-")]

## 스냅샷 한 장을 쌓고 파일을 다시 쓴다.
##   event : "act_clear"(액트 하나 통과) / "victory" / "defeat" / "quit"(중도 종료)
func record(main: Main, event: String) -> void:
	_events.append(_snapshot(main, event))
	_flush()

func _snapshot(main: Main, event: String) -> Dictionary:
	var base: BaseBlock = main.get_node_or_null(^"BaseBlock")
	var cards: CardUI = main.get_node_or_null(^"CardUI")
	# 중도 종료("quit")는 트리가 해체되는 중에 불린다 — get_tree() 가 null 일 수 있다.
	var tree := main.get_tree()
	var hammer: HammerStrike = tree.get_first_node_in_group(&"hammer") if tree != null else null
	var lv := main.level_system
	var snap := {
		event = event,
		# ⚠️ 액트(시간) -> 웨이브(전멸)로 바뀌었다. wave_clear 는 **방금 깬** 웨이브 번호다.
		act = main.wave_cleared if event == "wave_clear" else main.wave + 1,
		t = snappedf(main.elapsed, 0.1),
		t_mmss = Main.mmss(int(main.elapsed)),
		kills = main.kills,
		spawned = main.spawned,
		suppressed = main.suppressed,   # 동시 생존 상한에 걸려 못 태어난 수
		alive = main.alive_count() if tree != null else 0,
		level = lv.level,
		total_xp = roundi(lv.total_xp),
	}
	if base != null:
		snap["base_hp"] = roundi(base.health)
		snap["base_max_hp"] = roundi(base.max_health)
		snap["base_damage_taken"] = roundi(base.damage_taken)
	if cards != null:
		# id 가 아니라 이름으로 남긴다 — 나중에 눈으로 읽을 기록이다.
		var names := PackedStringArray()
		for id in cards.picked:
			var c := CardCatalog.by_id(id)
			names.append(String(c.cname) if c.has("cname") else String(id))
		snap["cards"] = names
	if hammer != null:
		snap["swings"] = {
			normal = hammer.tap_swings,
			charged = hammer.charged_swings,
			special = hammer.special_swings,
		}
		# 최종 스탯 — 카드가 실제로 얼마나 올려줬는지는 이걸로만 알 수 있다.
		var st := {}
		for key in [Stats.DAMAGE, Stats.DAMAGE_NORMAL, Stats.COOLDOWN, Stats.RADIUS,
				Stats.RADIUS_ALL, Stats.COOLDOWN_CHARGED, Stats.CHARGE_TIME,
				Stats.CHARGE_DAMAGE, Stats.CHARGE_RADIUS, Stats.COOLDOWN_SPECIAL,
				Stats.SPECIAL_RADIUS, Stats.XP_GAIN, Stats.SPAWN_RATE]:
			st[String(key)] = snappedf(hammer.stats.get_v(key), 0.01)
		snap["stats"] = st
	return snap

func _flush() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("[run_log] 기록 파일을 열 수 없다: %s" % path)
		return
	f.store_string(JSON.stringify({
		version = VERSION,
		started = _started,
		events = _events,
	}, "\t"))
	f.close()
