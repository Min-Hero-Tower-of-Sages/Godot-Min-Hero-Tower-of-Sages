extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var sample := preload("res://content/sample/sample_content_factory.gd")
	var catalog := sample.build_catalog()
	catalog.rebuild_index()
	var move := catalog.get_definition(&"foundation:move/strike/tier1") as MoveDefinition
	# Deliberately scramble execution order: presentation must use source groups.
	for probe in [{"scope": EffectDefinition.TargetScope.ENEMY_TARGETS, "amount": -1, "stat": "speed"}, {"scope": EffectDefinition.TargetScope.ACTOR, "amount": -1, "stat": "attack"}, {"scope": EffectDefinition.TargetScope.ACTOR, "amount": 1, "stat": "healing"}]:
		var effect := EffectDefinition.new()
		effect.kind = EffectDefinition.Kind.STAT_STAGE
		effect.roll_scope = EffectDefinition.RollScope.SHARED_MOVE
		effect.target_scope = probe.scope
		effect.phase = EffectDefinition.Phase.ACTOR_AFTER_TARGETS if probe.scope == EffectDefinition.TargetScope.ACTOR else EffectDefinition.Phase.ENEMY_TARGET
		effect.amount = probe.amount
		effect.stat_type_id = StringName("base:stat/" + probe.stat)
		effect.executor = preload("res://src/domain/battle/stat_stage_effect_executor.gd")
		move.effects.append(effect)
	var engine := BattleEngine.new()
	assert(engine.start(sample.battle_setup(), catalog, sample.build_rules(), BattleRng.new(1, [0, 0, 0, 0, 0, 0])).accepted)
	var decision := engine.get_decision()
	var response := engine.submit(BattleCommand.new(StringName(decision.actor_id), BattleCommand.Kind.USE_MOVE, move.id, [&"enemy-1"], int(decision.revision)))
	var metadata: Array = []
	for event in response.events:
		if event.kind == &"move_used": metadata = event.values.stat_callouts
	assert(metadata.size() == 3)
	assert(metadata.map(func(item: Dictionary) -> String: return item.stat_type_id) == ["base:stat/healing", "base:stat/attack", "base:stat/speed"])
	assert(metadata.map(func(item: Dictionary) -> float: return item.lead_seconds) == [0.1, 0.1, 0.0])
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	root.add_child(main)
	await main._start_battle()
	main.busy = true
	var actor := main.combatant_views["player-1"] as BattleCombatantView
	var enemy := main.combatant_views["enemy-1"] as BattleCombatantView
	var callouts: Array[Dictionary] = []
	for view in [actor, enemy]:
		view.child_entered_tree.connect(func(child: Node) -> void:
			if String(child.name) in ["visualMove_statIncrease", "visualMove_statDecrease"]:
				callouts.append({"node": child, "time": Time.get_ticks_usec()})
		)
	var applied: Array[int] = []
	main.presenter.event_presented.connect(func(event: BattleEvent) -> void:
		if event.kind in [&"damage", &"stat_stage_changed"]: applied.append(Time.get_ticks_usec())
	)
	await process_frame
	var events: Array[BattleEvent] = [BattleEvent.new(0, &"move_used", &"player-1", &"", {"move_id": "base:move/burn/tier1", "hit": true, "target_ids": ["enemy-1"], "stat_callouts": metadata}), BattleEvent.new(1, &"damage", &"player-1", &"enemy-1", {"amount": 1, "health": int(enemy.state_cache.health) - 1})]
	for index in [2, 0, 1]:
		var stat: Dictionary = metadata[index]
		events.append(BattleEvent.new(events.size(), &"stat_stage_changed", &"player-1", StringName(stat.target_id), {"stat_type_id": stat.stat_type_id, "amount": stat.amount, "stage": stat.amount}))
	await main._present(events)
	assert(callouts.size() == 3 and applied.size() == 4, "Stat gameplay events duplicated their queued visuals")
	assert(int(callouts[1].time) - int(callouts[0].time) >= 380000)
	assert(int(callouts[2].time) - int(callouts[1].time) >= 280000)
	assert(applied[0] - int(callouts[2].time) >= 280000, "Damage applied before final stat queue step")
	assert(applied.back() - applied[0] < 50000, "Stat/HP effects staggered instead of applying together")
	for callout in callouts:
		assert(not is_instance_valid(callout.node), "Stat artwork survived actor handoff")
	main.queue_free()
	await process_frame
	print("PASS: source stat group order/leads, pre-effect .3s callout steps, grouped HP/stat application, no duplicates and cleanup")
	quit()
