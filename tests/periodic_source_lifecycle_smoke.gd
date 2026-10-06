extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var catalog: ContentCatalog = root.get_node("CampaignRuntime").catalog
	var template := {"definition_id": "base:minion/fire_pig_1", "level": 20, "move_ids": [&"base:move/burn/tier1"], "max_health": 10000, "health": 10000, "max_energy": 10000, "energy": 10000, "attack": 100, "healing": 100, "max_attack_stat": 100, "max_healing_stat": 100, "speed": 20}
	var combatants: Array[Dictionary] = []
	for team in 2:
		for slot in 2:
			var member := template.duplicate(true)
			member.instance_id = "periodic-%d-%d" % [team, slot]
			member.team = team
			member.slot_index = slot
			combatants.append(member)
	var timer := template.duplicate(true)
	timer.instance_id = "hidden-periodic-caster"
	timer.team = 1
	var rules := RuleSetDefinition.new()
	rules.configuration = {"ai_teams": [], "battle_modifiers": {"move_timer": {"interval": 100, "move_id": "base:move/burn/tier1", "actor": timer}, "extra_minions": {"player": {"count": 1, "templates": [template]}}}}
	var engine := BattleEngine.new()
	assert(engine.start({"combatants": combatants}, catalog, rules, BattleRng.new(24)).accepted)
	var burn := catalog.get_definition(&"base:move/burn/tier1") as MoveDefinition
	var hot: MoveDefinition
	for definition in catalog._by_id.values():
		if definition is MoveDefinition and definition.effects.any(func(effect: EffectDefinition) -> bool: return effect.kind == EffectDefinition.Kind.PERIODIC_HEAL and effect.duration > 1):
			hot = definition
			break
	assert(hot != null)
	for move in [burn, hot]:
		var target := engine._state.combatants[&"periodic-0-1"] as CombatantState
		target.statuses.clear()
		target.health = 5000
		var effect: EffectDefinition
		for candidate in move.effects:
			if candidate.kind in [EffectDefinition.Kind.PERIODIC_DAMAGE, EffectDefinition.Kind.PERIODIC_HEAL]:
				effect = candidate
				break
		assert(effect != null)
		PeriodicEffectExecutor.new().execute(effect, {"actor": engine._timer_actor, "target": target, "move": move, "emit": Callable(engine, "_emit")})
		var saved := engine.snapshot()
		engine._current_events.clear()
		engine._tick_periodic_effects()
		var ticks := engine._current_events.filter(func(event: BattleEvent) -> bool: return event.kind == &"periodic_tick" and event.actor_id == &"hidden-periodic-caster")
		assert(not ticks.is_empty(), "Hidden timer DOT/HOT source was discarded")
		var health_after := target.health
		assert(health_after < 5000 if move == burn else health_after > 5000)
		engine.restore(saved)
		engine._current_events.clear()
		engine._tick_periodic_effects()
		target = engine._state.combatants[&"periodic-0-1"] as CombatantState
		assert(target.health == health_after, "Restored hidden timer source changed the periodic tick")
	# Native replacement removes the original from active slots, but source DOT
	# arrays retain that original OwnedMinion reference, not the new occupant.
	var original := engine._state.combatants[&"periodic-0-0"] as CombatantState
	var enemy := engine._state.combatants[&"periodic-1-0"] as CombatantState
	enemy.health = 9000
	var burn_effect: EffectDefinition
	for effect in burn.effects:
		if effect.kind == EffectDefinition.Kind.PERIODIC_DAMAGE: burn_effect = effect
	PeriodicEffectExecutor.new().execute(burn_effect, {"actor": original, "target": enemy, "move": burn, "emit": Callable(engine, "_emit")})
	original.health = 0
	original.defeated = true
	engine._inject_extra_minions()
	assert(not engine._state.combatants.has(original.instance_id) and engine._state.retired_combatants.size() == 1)
	var retired_snapshot := engine.snapshot()
	for reload in [false, true]:
		if reload: engine.restore(retired_snapshot)
		engine._current_events.clear()
		engine._tick_periodic_effects()
		assert(engine._current_events.any(func(event: BattleEvent) -> bool: return event.kind == &"periodic_tick" and event.actor_id == original.instance_id and event.target_id == enemy.instance_id), "Retired original's DOT vanished or was attributed to its replacement")
		assert((engine._state.combatants[enemy.instance_id] as CombatantState).health < 9000)
	assert(engine._periodic_source(&"missing-source") == null)
	print("PASS: hidden timer DOT/HOT and retired-original DOT keep their caster identity, damage/healing and RNG across snapshot/restore; unknown sources remain invalid")
	quit(0)
