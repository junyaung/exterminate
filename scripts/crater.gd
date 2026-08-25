class_name Crater
extends Node3D

## 여진+불 조합의 분화구.
## **자체 지오메트리가 없다** — 갈라진 땅(AftershockFX) 그 자체가 분화구다.
## 원반+둔덕을 그리면 육각형 접시가 하나 얹힌 것처럼 보여서 없앴다(유저 지시).
##
## 하는 일은 타이밍뿐: **분화구 중심**에서 불덩이를 뿜는다.
## (생성 즉시 한 번만 뿜는다 — 개수는 balls 로 받는다)

## 균열이 벌겋게 남아있는 시간(AftershockFX.LAVA_LINGER)과 같아야 한다.
## 순환 참조를 피하려고 양쪽에 따로 적어둔다 — 한쪽만 바꾸면 어긋난다.
##
## ⚠️ **발리는 한 번뿐이다** (유저 지시 2026-08-18: "불덩이 N개 나오고 끝, 후속 추가 없음").
##    예전엔 2초 간격으로 2회 뿜었고(발리당 3발 + 차징 보너스 최대 +2), 총 6~10발이었다.
##    지금은 **개수를 부르는 쪽이 정하고 한 번에 다 뿜는다** — 평타 2발 / 특수 3발.
##    (시간 압축을 시도했다 되돌린 기록: 5초/3발리 -> 2초/2발리 로 줄였더니 명중률이
##     10% -> 8% 로 떨어졌다. 지금은 아예 한 번만 뿜으므로 그 실험과는 다른 축이다.)
##
## 노드 수명은 그대로 둔다 — 균열이 벌겋게 남아있는 시간(AftershockFX.LAVA_LINGER)과 맞춰야
## 하고, 분화구 개수를 세는 검증들이 이 수명에 기대고 있다.
const LIFETIME := 5.0

var balls_fired := 0      ## 지금까지 뿜은 불덩이 수 (검증/디버그용)
var balls := 3            ## 뿜을 불덩이 수. 부르는 쪽이 정한다 (평타 2 / 특수 3)

var _ball_damage := 40.0
var _ball_radius := 1.4
var _spec: ObjectSpec       ## 분화구 자신의 스펙 (ground+area)
var _ball_spec: ObjectSpec  ## 뿜는 불덩이의 스펙 (projectile)

## field 는 위치를 잡는 데만 쓴다 — 참조로 들고 있지 않는다.
## (예전엔 균열 선 위에서 뿜느라 들고 있었지만 지금은 중심에서만 나온다.)
## ⚠️ radius 는 이제 **안 쓴다** — 불덩이는 분화구 **중심 한 점**에서만 솟는다
##    (유저 확인 2026-08-18, 실측 발사점 오차 0.08 = 한 프레임 비행분).
##    인자는 호출부 호환을 위해 남겨둔다.
## spec 은 뿜을 불덩이의 오브젝트 스펙 — 모디파이어가 이미 먹은 완성품이다.
## 피해·반경·발수를 전부 여기서 읽는다 (예전처럼 인자로 흩어 받지 않는다).
## ⚠️ 스펙이 **두 개**다. 분화구는 카드 하나가 오브젝트 둘을 만드는 첫 사례다 —
##    분화구 자신(바닥에 남는 발사대, ground+area)과 그게 뿜는 불덩이(projectile)는
##    서로 다른 태그를 가져야 한다. 잔류는 분화구 수명을, 다중화는 불덩이 발수를 건드린다.
static func spawn(parent: Node, field: Node,
		spec: ObjectSpec, ball_spec: ObjectSpec) -> Crater:
	var c := Crater.new()
	c._spec = spec
	c._ball_spec = ball_spec
	c._ball_damage = ball_spec.damage
	c._ball_radius = ball_spec.radius
	c.balls = maxi(1, ball_spec.count)
	parent.add_child(c)
	c.global_position = Terrain.on(field.global_position)
	# ⚠️ **자리를 잡은 뒤에 뿜는다.** add_child 하는 순간 _ready 가 도는데 그때 transform 은
	#    아직 원점이라, _ready 에서 뿜으면 **불덩이가 맵 원점에서 튀어나온다**
	#    (2026-08-18 실제로 이렇게 나갔다 — 분화구는 (120,-80)인데 불덩이는 (0,0)).
	#    이 프로젝트의 단골 함정이다: CPUParticles3D 의 emitting 도 같은 이유로 나중에 켠다.
	c._volley()
	return c

func _ready() -> void:
	# ⚠️ 여기서 뿜지 않는다 — spawn() 이 **자리를 잡은 뒤에** 부른다 (위 주석 참고).
	#    발사는 여전히 충돌과 **같은 프레임**이다.
	var tw := create_tween()
	tw.tween_interval(LIFETIME * (_spec.lifetime if _spec != null else 1.0))
	tw.tween_callback(queue_free)

## 불덩이는 **분화구 중심 한 점에서** 솟아 적이 몰려오는 쪽으로 굴러간다(유저 지시).
## 균열 선 위 여기저기서 솟던 방식은 발사점이 흩어져 "분화구가 뿜는다"로 안 읽혔다.
## 방향은 사방으로 흩지 않는다 — 절반은 이미 지나간 빈 땅으로 가므로 스폰 존을 향해 굴린다.
func _volley() -> void:
	for i in balls:
		var toward := Main.random_spawn_point() - global_position
		toward.y = 0.0
		var dir := Vector2(toward.x, toward.z)
		if dir.length() < 0.01:
			dir = Vector2(1.0, 0.0)
		dir = dir.normalized().rotated(randf_range(-0.25, 0.25))  # 살짝 부챗살로
		# 불덩이는 분화구보다 오래 살아야 하므로 부모(HammerStrike)에 붙인다
		Fireball.spawn_roll(get_parent(), global_position, dir, _ball_damage, _ball_radius, _ball_spec)
		balls_fired += 1
