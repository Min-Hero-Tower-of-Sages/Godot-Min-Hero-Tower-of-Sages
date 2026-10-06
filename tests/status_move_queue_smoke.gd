extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var sample := preload("res://content/sample/sample_content_factory.gd")
	var catalog := sample.build_catalog()
	catalog.rebuild_index()
	var strike := catalog.get_definition(&"foundation:move/strike/tier1") as MoveDefinition
	for kind in [EffectDefinition.Kind.STUN, EffectDefinition.Kind.FREEZE]:
		var effect := EffectDefinition.new()
		effect.kind = kind
		effect.roll_scope = EffectDefinition.RollScope.SHARED_MOVE
		effect.executor = preload("res://src/domain/battle/condition_effect_executor.gd")
		strike.effects.append(effect)
	var reflect := EffectDefinition.new()
	reflect.kind = EffectDefinition.Kind.REFLECT
	reflect.phase = EffectDefinition.Phase.PASSIVE
	reflect.amount = 50
	strike.effects.append(reflect)
	var engine := BattleEngine.new()
	assert(engine.start(sample.battle_setup(), catalog, sample.build_rules(), BattleRng.new(1, [0, 0, 0, 0, 0, 0])).accepted)
	var recipient := engine._state.combatants[&"enemy-1"] as CombatantState
	recipient.statuses.append({"kind": "periodic", "move_id": String(strike.id)})
	var decision := engine.get_decision()
	var response := engine.submit(BattleCommand.new(StringName(decision.actor_id), BattleCommand.Kind.USE_MOVE, strike.id, [&"enemy-1"], int(decision.revision)))
	assert(response.accepted)
	var captured: BattleEvent
	for event in response.events:
		if event.kind == &"move_used": captured = event
	assert(captured != null and captured.values.visual_callouts.get("enemy-1", []) == ["stunned", "frozen", "reflection"], "Cast snapshot lost shared rolls or pre-damage reflect state")
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	root.add_child(main)
	await main._start_battle()
	main.busy = true
	var move := main.catalog.get_definition(&"base:move/burn/tier1") as MoveDefinition
	var enemy := main.combatant_views["enemy-1"] as BattleCombatantView
	var actor := main.combatant_views["player-1"] as BattleCombatantView
	var callouts: Array[Dictionary] = []
	var applications: Array[int] = []
	var cast_times: Array[int] = []
	enemy.child_entered_tree.connect(func(child: Node) -> void:
		if String(child.name) in ["visualMove_stunned", "visualMove_frozen", "ReflectedDamageCallout"]:
			callouts.append({"kind": String(child.name), "time": Time.get_ticks_usec()})
	)
	actor.child_entered_tree.connect(func(child: Node) -> void:
		assert(String(child.name) != "ReflectedDamageCallout", "Reflection callout appeared over the damaged attacker instead of reflector")
	)
	main.move_vfx_layer.child_entered_tree.connect(func(_child: Node) -> void:
		if cast_times.is_empty(): cast_times.append(Time.get_ticks_usec())
	)
	main.presenter.event_presented.connect(func(event: BattleEvent) -> void:
		if event.kind in [&"damage", &"reflected_damage", &"stunned", &"frozen"]:
			applications.append(Time.get_ticks_usec())
	)
	await process_frame
	for buffered in [true, false]:
		move.visuals_have_buffer = buffered
		callouts.clear()
		applications.clear()
		cast_times.clear()
		var events: Array[BattleEvent] = [
			BattleEvent.new(0, &"move_used", &"player-1", &"", {"move_id": String(move.id), "hit": true, "target_ids": ["enemy-1"], "visual_callouts": {"enemy-1": ["stunned", "frozen", "reflection"]}}),
			BattleEvent.new(1, &"reflected_damage", &"enemy-1", &"player-1", {"amount": 1, "health": int(actor.state_cache.health) - 1}),
			BattleEvent.new(2, &"damage", &"player-1", &"enemy-1", {"amount": 1, "health": int(enemy.state_cache.health) - 1}),
			BattleEvent.new(3, &"stunned", &"player-1", &"enemy-1"),
			BattleEvent.new(4, &"frozen", &"player-1", &"enemy-1"),
		]
		await main._present(events)
		assert(callouts.size() == 3 and applications.size() == 4, "Queue duplicated or dropped callouts/effects")
		assert(callouts.map(func(item: Dictionary) -> String: return item.kind) == ["visualMove_stunned", "visualMove_frozen", "ReflectedDamageCallout"])
		for index in [1, 2]:
			assert(int(callouts[index].time) - int(callouts[index - 1].time) >= 780000, "Status callouts ignored source .8s queue")
		var initial_delay := int(callouts[0].time) - cast_times[0]
		assert(initial_delay >= 1050000 if buffered else initial_delay < 50000, "Wrong buffered/unbuffered status insertion point")
		var final_delay := applications[0] - int(callouts[2].time)
		assert(final_delay >= (780000 if buffered else 1580000), "HP applied before source status and final visual waits")
		assert(applications.back() - applications[0] < 50000, "Gameplay effects did not apply together")
		assert(not actor._health_tween.is_running() and not enemy._health_tween.is_running())
		assert(main.move_vfx_layer.get_child_count() == 0)
	main.queue_free()
	await process_frame
	print("PASS: cast-time stun/freeze/reflect metadata, source buffered/unbuffered status queues, reflector placement, grouped HP and no duplicate callouts")
	quit()
