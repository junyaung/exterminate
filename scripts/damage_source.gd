class_name DamageSource
extends RefCounted

## 이 피해가 **어디서 왔는가**. 오브젝트(공격 패턴이 만들어내는 생성물)가 자기를 낳은
## 공격을 기억하게 한다.
##
## ⚠️ 왜 지금 넣었나: 나중에 끼워 넣기가 제일 어려운 부분이기 때문이다
##    (근거: gamedev/poe_gem_system_build_variety_study.md §3.2). take_damage 호출 지점이
##    지금은 6곳뿐이라 반나절이지만, 카드가 20장 늘어난 뒤엔 며칠짜리가 된다.
##
## 이게 있어야 붙일 수 있는 규칙들:
##   · "망치에 **직접** 맞아 죽은 적만 폭연한다" (kind == &"direct")
##   · "메아리·분열이 자기를 무한히 만들지 않는다" (depth)
##   · "자식 효과는 점점 약해진다" (proc_coeff — RoR2 방식)

## 한 스윙에서 파생된 모든 오브젝트가 공유하는 번호. 나중에 "이 공격 한 번이 준 총 피해"
## 같은 걸 집계할 때 쓴다.
static var _next_root := 0

var root_id := 0
var action := &"normal"      ## &"normal" / &"charge" / &"special"
var kind := &"direct"        ## &"direct"(망치가 직접) / &"secondary"(파생) / &"triggered"(자동)
var object_id := &""         ## &"fireball" / &"shockwave" …
var depth := 0               ## 생성 깊이. 0 = 망치가 직접 만든 것.
var proc_coeff := 1.0        ## 깊이마다 곱해져 사그라드는 계수

## 재귀 하드 상한. 이걸 넘으면 자식 오브젝트를 아예 안 만든다 —
## 계수 감쇠(proc_coeff)만으로는 0 에 수렴할 뿐 **멈추지는 않는다.**
const MAX_DEPTH := 2

## 망치가 직접 만드는 루트. 스윙 한 번에 한 개.
static func root(action_: StringName, kind_ := &"direct") -> DamageSource:
	_next_root += 1
	var s := DamageSource.new()
	s.root_id = _next_root
	s.action = action_
	s.kind = kind_
	return s

## 이 출처에서 파생된 자식. coeff 는 그 파생이 얼마나 사그라드는가 (폭연 0.5, 분열 0.6 …).
func child(object_id_: StringName, coeff := 1.0) -> DamageSource:
	var s := DamageSource.new()
	s.root_id = root_id
	s.action = action
	s.kind = &"secondary" if kind == &"direct" else kind
	s.object_id = object_id_
	s.depth = depth + 1
	s.proc_coeff = proc_coeff * coeff
	return s

## 여기서 자식을 더 만들어도 되는가. 분열·메아리는 **반드시** 이걸 먼저 물어야 한다.
func can_spawn() -> bool:
	return depth < MAX_DEPTH

func _to_string() -> String:
	return "[%d] %s/%s %s d%d ×%.2f" % [root_id, action, kind, object_id, depth, proc_coeff]
