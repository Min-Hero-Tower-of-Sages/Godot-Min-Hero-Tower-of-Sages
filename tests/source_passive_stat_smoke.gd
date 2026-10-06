extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var catalog: ContentCatalog = root.get_node("CampaignRuntime").catalog
	var species := catalog.get_definition(&"base:minion/fire_pig_1") as MinionDefinition
	var local_ids: Array[StringName] = []
	var global_ids: Array[StringName] = []
	for definition in catalog._by_id.values():
		if definition is not MoveDefinition or definition.tier != 1: continue
		if not definition.effects.any(func(effect: EffectDefinition) -> bool: return effect.kind == EffectDefinition.Kind.STAT_PERCENT): continue
		if definition.is_passive: local_ids.append(definition.id)
		elif definition.is_global_passive: global_ids.append(definition.id)
	assert(not local_ids.is_empty() and not global_ids.is_empty())
	var state := CampaignState.new()
	state.progression["star_upgrades"] = {"health": 2, "energy": 3, "healing": 2}
	for slot in 3:
		var owned := OwnedMinionState.new()
		owned.instance_id = StringName("passive-slot-%d" % slot)
		owned.definition_id = species.id
		owned.level = 7
		owned.stat_bonus = &"energy"
		owned.ivs = {"health": 2, "energy": 3, "speed": 1}
		owned.learned_move_ids.assign(species.initial_move_ids + (local_ids if slot == 0 else global_ids))
		state.party.append(owned)
	var selected: OwnedMinionState = state.party[0]
	var checks := 0
	for all_dead in [false, true]:
		state.party[1].persistent_health = 0 if all_dead else 1
		state.party[2].persistent_health = 0 if all_dead else 1
		var displayed := CampaignProgressionService.owned_display_stats(selected, species, catalog, state)
		var raw := CampaignProgressionService.owned_stats(selected, species, -1, [], state.progression.star_upgrades, false)
		var summed: Dictionary = {}
		for move_id in local_ids + ([] if all_dead else global_ids):
			var move := catalog.get_definition(move_id) as MoveDefinition
			for effect in move.effects:
				if effect.kind != EffectDefinition.Kind.STAT_PERCENT: continue
				var stat := String(effect.stat_type_id).get_file()
				summed[stat] = float(summed.get(stat, 0.0)) + effect.amount
				break # source only reads its first stat type
		for stat in displayed:
			assert(displayed[stat] == int(float(raw[stat]) * (1.0 + float(summed.get(stat, 0.0)) / 100.0)), "Menu passive/global/dedup calculation differs")
			checks += 1
		var encounter := catalog.get_definition(&"base:encounter/grass_floor1_room1_normal") as EncounterDefinition
		state.pending_battle = {"battle_id": "passive-stats", "encounter_id": String(encounter.id)}
		var setup := CampaignProgressionService.build_battle_setup(state, catalog, encounter)
		var rules := RuleSetDefinition.new()
		rules.configuration = {"ai_teams": [], "refill_on_activation": true}
		var engine := BattleEngine.new()
		assert(engine.start(setup, catalog, rules, BattleRng.new(71)).accepted)
		# Activation refills party members. Exercise loss of global providers
		# during combat, not a pre-battle death state that activation heals.
		if all_dead:
			for slot in [1, 2]:
				var provider := engine._state.combatants[state.party[slot].instance_id] as CombatantState
				provider.health = 0
				provider.defeated = true
			engine._refresh_derived_maxima()
		var actor := engine._state.combatants[selected.instance_id] as CombatantState
		assert(actor.max_health == displayed.health and actor.max_energy == displayed.energy, "Battle and menu maxima disagree")
		assert(LegacyCombatModifiers.effective_speed(actor, catalog, engine._state.combatants) == displayed.speed)
		for stage in [-2, -1, 0, 1, 2]:
			for stat in ["health", "energy", "attack", "healing", "speed"]:
				actor.stat_stages[StringName("base:stat/%s" % stat)] = stage
				var factor: float = [0.51, 0.8, 1.0, 1.25, 1.5][stage + 2]
				var key: String = "max_attack_stat" if stat == "attack" else "max_healing_stat" if stat == "healing" else stat
				var expected := int(float(actor.source_raw_stats[key]) * factor * (1.0 if stat == "health" else factor) * (1.0 + float(summed.get(stat, 0.0)) / 100.0))
				var actual: float
				match stat:
					"health": actual = LegacyCombatModifiers.effective_max_health(actor, catalog, engine._state.combatants)
					"energy": actual = LegacyCombatModifiers.effective_max_energy(actor, catalog, engine._state.combatants)
					"attack": actual = LegacyCombatModifiers.effective_attack(actor, catalog, engine._state.combatants)
					"healing": actual = LegacyCombatModifiers.effective_healing(actor, catalog, engine._state.combatants)
					"speed": actual = LegacyCombatModifiers.effective_speed(actor, catalog, engine._state.combatants)
				assert(actual == expected, "Native source stat rounded before its stage/passive scaling")
				checks += 1
		var snapshot := engine.snapshot()
		engine.restore(snapshot)
		assert(engine._state.combatants[selected.instance_id].source_raw_stats == actor.source_raw_stats)
	var explicit := CombatantState.from_setup({"max_attack_stat": 17.5, "speed": 9, "team": 0})
	assert(is_equal_approx(LegacyCombatModifiers.effective_attack(explicit, catalog, {}), 17.5), "Explicit extension power was forcibly rounded")
	print("PASS: %d source passive/stat cases; party display/battle agreement, unique living-team globals, dead providers, final-stage rounding, raw-stat snapshots and explicit extension arithmetic" % checks)
	quit()
