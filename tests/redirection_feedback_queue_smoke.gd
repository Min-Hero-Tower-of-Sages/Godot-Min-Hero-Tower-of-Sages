extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var sample := preload("res://content/sample/sample_content_factory.gd")
	var catalog := sample.build_catalog()
	var redirect_effect := EffectDefinition.new()
	redirect_effect.id = &"foundation:effect/redirect_fixture"
	redirect_effect.display_name = "Redirect fixture"
	redirect_effect.kind = EffectDefinition.Kind.REDIRECT_DAMAGE
	redirect_effect.amount = 10
	var redirect_move := MoveDefinition.new()
	redirect_move.id = &"foundation:move/redirect_fixture/tier1"
	redirect_move.display_name = "Redirect fixture"
	redirect_move.family_id = &"foundation:move_family/redirect_fixture"
	redirect_move.type_id = &"base:type/none"
	redirect_move.is_passive = true
	redirect_move.effects.append(redirect_effect)
	catalog.packs[0].definitions.append(redirect_move)
	var catalog_errors := catalog.rebuild_index()
	assert(catalog_errors.is_empty(), str(catalog_errors))
	var engine := BattleEngine.new()
	assert(engine.start(sample.battle_setup(), catalog, sample.build_rules(), BattleRng.new(1, [0, 0, 0, 0, 0, 0])).accepted)
	var enemy: CombatantState = engine._state.combatants[&"enemy-1"]
	enemy.move_ids.append(redirect_move.id)
	for entry in [{"id": "enemy-2", "slot": 2}, {"id": "shielded", "slot": 3}, {"id": "dead", "slot": 4}]:
		var redirector := CombatantState.from_setup({"instance_id": entry.id, "team": 1, "slot_index": entry.slot, "max_health": 500, "health": 500, "move_ids": [redirect_move.id]})
		redirector.battle_mod_shield_active = entry.id == "shielded"
		if entry.id == "dead":
			redirector.health = 0
			redirector.defeated = true
		engine._state.combatants[redirector.instance_id] = redirector
	var decision := engine.get_decision()
	var response := engine.submit(BattleCommand.new(StringName(decision.actor_id), BattleCommand.Kind.USE_MOVE, &"foundation:move/strike/tier1", [&"enemy-1"], int(decision.revision)))
	assert(response.accepted)
	var metadata: Array = []
	for event in response.events:
		if event.kind == &"move_used":
			metadata = event.values.redirection_callouts
	assert(metadata == ["enemy-1", "enemy-2"], "Cast snapshot must include each living, unshielded redirector once in slot order")
	var actor: CombatantState = engine._state.combatants[&"player-1"]
	assert(engine._source_redirection_callouts(actor, catalog.get_definition(&"foundation:move/mend/tier1")).is_empty(), "Non-damage moves must not invent redirect feedback")
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	root.add_child(main)
	await main._start_battle()
	main.busy = true
	var popups: Array = []
	var effects: Array[int] = []
	for id in ["enemy-1", "enemy-2"]:
		var view := main.combatant_views[id] as BattleCombatantView
		view.child_entered_tree.connect(func(child: Node) -> void:
			if child is Sprite2D and child.texture == BattleCombatantView.REDIRECTED_POPUP:
				popups.append({"owner": id, "time": Time.get_ticks_usec()})
		)
	main.presenter.event_presented.connect(func(event: BattleEvent) -> void:
		if event.kind == &"redirected_damage": effects.append(Time.get_ticks_usec())
	)
	var events: Array[BattleEvent] = [BattleEvent.new(0, &"move_used", &"player-1", &"", {"move_id": "base:move/titan_restore/tier2", "hit": true, "target_ids": ["player-1"], "redirection_callouts": metadata})]
	for id in ["enemy-1", "enemy-2", "enemy-1", "enemy-2"]:
		var view := main.combatant_views[id] as BattleCombatantView
		events.append(BattleEvent.new(events.size(), &"redirected_damage", &"player-1", StringName(id), {"amount": 0, "health": int(view.state_cache.health)}))
	var start := Time.get_ticks_usec()
	await main._present(events)
	assert(popups.size() == 2, "Multi-target redirected damage duplicated per-move feedback")
	assert(popups.map(func(popup: Dictionary) -> String: return popup.owner) == ["enemy-1", "enemy-2"])
	assert(int(popups[0].time) - start >= 370000, "Redirect feedback appeared before ApplyEffects")
	assert(effects.size() == 4 and int(popups[1].time) <= effects[0], "All redirector feedback must start before per-target damage application")
	main.queue_free()
	await process_frame
	print("PASS: source per-move redirection snapshots, native slot order, shield/death exclusions, non-damage suppression, one popup per redirector at ApplyEffects")
	quit(0)
