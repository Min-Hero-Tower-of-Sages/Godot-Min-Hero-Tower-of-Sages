extends SceneTree

class MemorySession extends CampaignSession:
	var reject_save := false
	func _save_candidate(_candidate) -> Dictionary:
		return {"ok": not reject_save}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var catalog: ContentCatalog = root.get_node("CampaignRuntime").catalog
	var species := catalog.get_definition(&"base:minion/fire_pig_1") as MinionDefinition
	var bonus_id: StringName
	for definition in catalog._by_id.values():
		if definition is MoveDefinition and definition.is_global_passive and definition.tier == 1:
			if LegacyCombatModifiers._first_stat_percent(definition, &"base:stat/health") > 0.0:
				bonus_id = definition.id
				break
	assert(not bonus_id.is_empty())
	var state := CampaignState.new()
	state.campaign_id = &"base:campaign/standard_tower"
	state.current_room_id = &"base:room/level_1_1_a"
	var owned := OwnedMinionState.new()
	owned.instance_id = &"finish-stat-original"
	owned.definition_id = species.id
	owned.level = 5
	owned.experience = 5990
	owned.persistent_health = 3
	owned.learned_move_ids.assign(species.initial_move_ids)
	state.party.append(owned)
	var encounter := (catalog.get_definition(&"base:encounter/grass_floor1_room1_normal") as EncounterDefinition).duplicate(true) as EncounterDefinition
	encounter.battle_modifier_configuration = {"move_timer": {"interval": 100, "buff_move_id": bonus_id, "move_id": &"base:move/claw/tier1", "actor": {"definition_id": species.id, "level": 5}}}
	CampaignProgressionService.prepare_battle(state, encounter)
	var setup := CampaignProgressionService.build_battle_setup(state, catalog, encounter)
	var rules := RuleSetDefinition.new()
	rules.configuration = {"ai_teams": [], "battle_modifiers": {"move_timer": {"interval": 100, "buff_move_id": bonus_id, "move_id": &"base:move/claw/tier1", "actor": {"definition_id": species.id, "level": 5}}}}
	var engine := BattleEngine.new()
	assert(engine.start(setup, catalog, rules, BattleRng.new(7)).accepted)
	var actor := engine._state.combatants[owned.instance_id] as CombatantState
	actor.stat_stages = {&"base:stat/health": 2, &"base:stat/energy": 1, &"base:stat/speed": -1}
	engine._refresh_derived_maxima()
	engine._finish(0, &"elimination")
	var result: BattleResult = engine.get_result()
	var context := CampaignProgressionService.battle_finish_stat_context(state, result)
	assert(context.stat_stages_by_id[String(owned.instance_id)][&"base:stat/health"] == 2)
	assert(context.battle_bonus_global_move_ids == [bonus_id])
	var before := CampaignProgressionService.owned_display_stats(owned, species, catalog, state, 5, context)
	assert(before.health == actor.max_health and before.energy == actor.max_energy)
	var after := CampaignProgressionService.owned_display_stats(owned, species, catalog, state, 6, context)
	var expected_delta := int(after.health) - int(before.health)
	var settled := CampaignProgressionService.apply_battle_result(state, result, encounter, catalog)
	assert(settled.ok and owned.level == 6)
	assert(settled.finish_stat_context == context and settled.experience_awards[String(owned.instance_id)].health_increase == expected_delta)
	assert(owned.persistent_health == 3 + expected_delta)
	var exploration := CampaignProgressionService.owned_display_stats(owned, species, catalog, state)
	var unrounded := CampaignProgressionService.owned_stats(owned, species, -1, [], {}, false)
	var aura_rate := 1.0 + LegacyCombatModifiers._first_stat_percent(catalog.get_definition(bonus_id) as MoveDefinition, &"base:stat/health") / 100.0
	assert(state.runtime_trainer_bonus_move_ids == [bonus_id] and exploration.health == int(float(unrounded.health) * aura_rate) and exploration.health < after.health, "Trainer aura/stage lifetimes were conflated")
	assert(not state.to_dictionary().has("runtime_trainer_bonus_move_ids"), "Runtime trainer aura was written to saves")
	var session := MemorySession.new()
	session.catalog = catalog
	session.campaign = catalog.get_definition(state.campaign_id) as CampaignDefinition
	session.state = state
	session.reject_save = true
	assert(not session.enter_tower_lobby().ok and session.state.runtime_trainer_bonus_move_ids == [bonus_id])
	session.reject_save = false
	assert(session.enter_tower_lobby().ok and session.state.runtime_trainer_bonus_move_ids == [bonus_id], "Room transaction lost current-trainer aura")
	assert(CampaignProgressionService.owned_display_stats(session.state.party[0], species, catalog, session.state).health == exploration.health)
	var next_state := CampaignState.new()
	next_state.load_dictionary(session.state.to_dictionary("", true))
	assert(next_state.runtime_trainer_bonus_move_ids == [bonus_id])
	CampaignProgressionService.prepare_battle(next_state, catalog.get_definition(&"base:encounter/grass_floor1_room1_normal") as EncounterDefinition)
	assert(next_state.runtime_trainer_bonus_move_ids.is_empty(), "Loading a plain trainer retained the previous aura")
	var restored := CampaignState.new()
	restored.load_dictionary(state.to_dictionary())
	assert(CampaignProgressionService.owned_display_stats(restored.party[0], species, catalog, restored) == CampaignProgressionService.owned_stats(restored.party[0], species))
	assert(not restored.progression.has("finish_stat_context"), "Battle stages leaked into persistent progression")
	# Retired originals preserve their own stages; a temporary minion's stages
	# must not be applied to the owned minion just because it occupied its slot.
	result.participants.append({"instance_id": "temporary-replacement", "team": 0, "slot_index": 0, "stat_stages": {&"base:stat/health": 10}, "battle_bonus_global_move_ids": [bonus_id]})
	assert(CampaignProgressionService.battle_finish_stat_context(state, result) == context)
	var presenter := BattleProgressionPresenter.new()
	root.add_child(presenter)
	presenter._display_stat_catalog = catalog
	presenter._display_stat_state.party.assign(state.party)
	presenter._display_stat_context = context.duplicate(true)
	var view := BattleCombatantView.new()
	root.add_child(view)
	view.setup({"instance_id": String(owned.instance_id), "team": 0, "slot_index": 0, "level": 5, "health": 3, "max_health": before.health, "shield": 0}, species, presenter._presentation_texture(species, catalog))
	var popup := presenter._create_level_popup(view, owned, species, 5, null)
	assert(popup.get_node("CurrentStat0").text == str(before.health), "Level card lost temporary stage/aura")
	presenter.cancel_sequence()
	assert(presenter._display_stat_context.is_empty(), "Cancelled finish leaked temporary stats to next menu")
	popup.queue_free()
	presenter.queue_free()
	view.queue_free()
	await process_frame
	print("PASS: native stage/timer-aura result context, XP health delta, level card stats, original/replacement isolation, save/exploration stage isolation and cancellation cleanup")
	quit()
