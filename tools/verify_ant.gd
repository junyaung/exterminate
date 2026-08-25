extends SceneTree
## 몹 비주얼 검증 v2 (스켈레톤 glb): 모델 배정 / 애니메이션 / 색 / 크기 / 재생 속도.
## godot --headless --path . --script tools/verify_ant.gd

func _init() -> void:
	_run()

func _run() -> void:
	var scene := load("res://scenes/enemy.tscn") as PackedScene
	for id in [&"grunt", &"heavy", &"runner"]:
		var e = scene.instantiate()
		e.type_id = id
		root.add_child(e)
		await process_frame
		var ant: Node3D = e.get_node("VisualPivot/Ant")
		var pill: Node3D = e.get_node("VisualPivot/Pillbug")
		var rhino: Node3D = e.get_node("VisualPivot/Rhino")
		var blob: MeshInstance3D = e.get_node("VisualPivot/Blob")
		# 모델 넷 중 정확히 하나만 보여야 한다.
		# 상세 검증은 모델별 스크립트로 나뉜다: runner=verify_pillbug / heavy=verify_rhino
		var shown := int(ant.visible) + int(pill.visible) + int(rhino.visible) + int(blob.visible)
		assert(shown == 1)
		if rhino.visible:
			print("%-7s 장수풍뎅이  재생중=%s (%s) — 상세는 verify_rhino" % [
				id, str(e._anim != null and e._anim.is_playing()),
				e._anim.current_animation if e._anim != null else "-"])
			e.queue_free()
			continue
		if pill.visible:
			print("%-7s 콩벌레  재생중=%s (%s) — 상세는 verify_pillbug" % [
				id, str(e._anim != null and e._anim.is_playing()),
				e._anim.current_animation if e._anim != null else "-"])
			e.queue_free()
			continue
		if ant.visible:
			var body := ant.find_child("Body", true, false) as MeshInstance3D
			var outline := ant.find_child("Outline", true, false) as MeshInstance3D
			var anim := ant.find_child("AnimationPlayer", true, false) as AnimationPlayer
			var skel := ant.find_child("Skeleton3D", true, false) as Skeleton3D
			var m0 := body.get_surface_override_material(0) as ShaderMaterial
			var walk := anim.get_animation(&"walk")
			var aabb := body.get_aabb()
			var world_len: float = aabb.size.x * body.global_transform.basis.get_scale().x
			print("%-7s 개미  본 %d  애니 %s(%.2fs 루프=%s) 재생중=%s" % [
				id, skel.get_bone_count(), anim.current_animation,
				walk.length, walk.loop_mode == Animation.LOOP_LINEAR, anim.is_playing()])
			print("        셀 %s/%s  외곽선그림자 %d  인게임 길이 %.2f (기대 ~1.33)" % [
				(m0.get_shader_parameter("light_tone") as Color).to_html(false),
				(m0.get_shader_parameter("dark_tone") as Color).to_html(false),
				outline.cast_shadow, world_len])
			# 이동속도 -> 재생 속도 동기 확인
			e.target = null
			e._physics_process(0.016)
			print("        speed_scale=%.2f (기대 %.2f)" % [
				anim.speed_scale, e.stats.get_v(Stats.SPEED) / 3.5])
		else:
			var mo := blob.material_override as StandardMaterial3D
			print("%-7s 구체  단색 %s  스케일 %.2f  애니 없음=%s" % [
				id, mo.albedo_color.to_html(false), e.scale.x, e._anim == null])
		e.queue_free()
	print("")
	print("전 종류 통과")
	quit()
