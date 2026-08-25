class_name BaseBlock
extends Node3D

## 적들이 노리는 목표. 지금은 그냥 체력만 있는 직육면체.

signal health_changed(current: float, maximum: float)
signal destroyed

# --- 업그레이드로 바뀌는 값 (기본치) ---
## 1000 = 누수 예산. 잡졸 DPS 4 기준 "적이 기지에 붙어 있어도 되는 시간" 총 250 적·초.
@export var base_max_health := 1000.0

var stats: Stats
var health := 0.0
var damage_taken := 0.0   ## 런 전체 누적 피해 (RunLog 리포트용). 최대 체력이 늘어도 안 줄어든다.

var _alive := true

## 업그레이드가 반영된 최대 체력.
var max_health: float:
	get: return stats.get_v(Stats.HEALTH)

func _ready() -> void:
	stats = Stats.new({Stats.HEALTH: base_max_health})
	health = max_health
	health_changed.emit(health, max_health)
	add_to_group("base")

## XZ 평면에서 기지가 차지하는 사각형 (월드 좌표).
## 낙석 같은 것들이 기지에 박히지 않도록 피해갈 영역을 알려준다.
func footprint() -> Rect2:
	var mi := $Mesh as MeshInstance3D
	var s: Vector3 = (mi.mesh as BoxMesh).size
	return Rect2(global_position.x - s.x * 0.5, global_position.z - s.z * 0.5, s.x, s.z)

func take_damage(amount: float) -> void:
	if not _alive:
		return
	damage_taken += minf(amount, health)
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_alive = false
		destroyed.emit()

## 최대 체력이 늘어난 만큼 현재 체력도 같이 올려준다 (업그레이드로 즉시 회복되는 느낌).
func grant_max_health(flat: float) -> void:
	var before := max_health
	stats.add_flat(Stats.HEALTH, flat)
	health += max_health - before
	health_changed.emit(health, max_health)
