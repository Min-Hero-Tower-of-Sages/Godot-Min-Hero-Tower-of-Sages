extends SceneTree

const GOLDEN_MOVE_TIMES := {15: 0.61, 96: 1.65, 85: 0.8, 14: 2.05, 125: 1.26, 162: 1.02, 1: 1.2}
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	root.add_child(main)
	await main._start_battle()
	main.busy = true
	var target := main.combatant_views["player-1"] as BattleCombatantView
	var probes: Array[Dictionary] = []
	for visual_id in GOLDEN_MOVE_TIMES:
		var before: Array = main.move_vfx_layer.get_children()
		var cast_time := Time.get_ticks_usec()
		main._last_move_visual_duration_seconds = 0.0
		main._animate_visual_instance(visual_id, target)
		var expected: float = GOLDEN_MOVE_TIMES[visual_id]
		assert(is_equal_approx(main._last_move_visual_duration_seconds, expected), "Visual %d runtime lifetime disagrees with its recovered m_moveTime setter" % visual_id)
		var objects: Array = []
		for child in main.move_vfx_layer.get_children():
			if not before.has(child):
				objects.append(child)
		assert(not objects.is_empty())
		probes.append({"visual_id": visual_id, "objects": objects, "deadline": cast_time + roundi((expected + 0.09) * 1000000.0)})
	# Short rotation cleanup must not remove the still-active rise instance.
	await main._wait_until_usec(int(probes[0].deadline))
	assert(_alive_count(probes[0].objects) == 0, "Rotation impact outlived source cleanup")
	assert(_alive_count(probes[3].objects) > 0, "One move instance's cleanup erased another target effect")
	for probe in probes:
		await main._wait_until_usec(int(probe.deadline))
		assert(_alive_count(probe.objects) == 0, "Visual %d objects survived their source cleanup deadline" % probe.visual_id)
	# Independent formula samples include sampled random starts, staggered orbit
	# and repeated bounces, not only the seven fixed production profiles.
	var timing := preload("res://src/presentation/source_visual_move_timing.gd")
	assert(is_equal_approx(timing.move_time({"family": "fall_from_top", "count": 3, "delay": 0.1, "impact_speed": 0.7, "random_start_in_game": 0.25}), 1.4))
	assert(is_equal_approx(timing.move_time({"family": "fall_onto_target", "count": 2, "delay": 0.1, "impact_speed": 0.35, "pre_impact_bounces": 2, "up_down_speed": 0.3}), 2.1))
	assert(is_equal_approx(timing.move_time({"family": "orbit_into_target", "count": 8, "delay": 0.1, "final_hang_time": 0.3, "hang_time": 0.5, "movement_speed": 0.42, "all_enter_at_same_time": false}), 1.82))
	assert(main.move_vfx_layer.get_child_count() == 0)
	var move_start := [0]
	var damage_start := [0]
	var damage_had_visual := [false]
	main.presenter.event_presented.connect(func(event: BattleEvent) -> void:
		if event.kind == &"move_used":
			move_start[0] = Time.get_ticks_usec()
		elif event.kind == &"damage":
			damage_start[0] = Time.get_ticks_usec()
			damage_had_visual[0] = main.move_vfx_layer.get_child_count() > 0
	)
	var enemy := main.combatant_views["enemy-1"] as BattleCombatantView
	var health := int(enemy.state_cache.health)
	var events: Array[BattleEvent] = [BattleEvent.new(0, &"move_used", &"player-1", &"", {"move_id": "base:move/burn/tier1", "target_ids": ["enemy-1"], "hit": true}), BattleEvent.new(1, &"damage", &"player-1", &"enemy-1", {"health": health - 1, "amount": 1})]
	await main._present(events)
	var elapsed := float(damage_start[0] - move_start[0]) / 1000000.0
	assert(elapsed >= 1.05 and elapsed < 1.22, "Burn HP did not follow source m_moveTime-.1 ApplyEffects wait: %f" % elapsed)
	assert(damage_had_visual[0], "Health application started after source visual cleanup")
	assert(main.move_vfx_layer.get_child_count() == 0 and not enemy._health_tween.is_running())
	main.queue_free()
	await process_frame
	print("PASS: seven native-family golden m_moveTime deadlines, physical cleanup/isolation, fall/bounce/orbit formulas, source ApplyEffects wait and smooth HP completion")
	quit()

func _alive_count(objects: Array) -> int:
	var count := 0
	for object in objects:
		if is_instance_valid(object) and not object.is_queued_for_deletion():
			count += 1
	return count
