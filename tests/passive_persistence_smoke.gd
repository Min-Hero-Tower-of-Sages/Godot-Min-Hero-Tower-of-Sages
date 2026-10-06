extends "res://tests/ten_floor_campaign_handoff_smoke.gd"

func _run() -> void:
	await process_frame
	var catalog: ContentCatalog = root.get_node("CampaignRuntime").catalog
	var species := catalog.get_definition(&"base:minion/fire_pig_1") as MinionDefinition
	var moves: Array[StringName] = []
	var globals: Array[StringName] = []
	for definition in catalog._by_id.values():
		if definition is not MoveDefinition or definition.tier != 1: continue
		if not definition.effects.any(func(effect: EffectDefinition) -> bool: return effect.kind == EffectDefinition.Kind.STAT_PERCENT and effect.stat_type_id in [&"base:stat/health", &"base:stat/energy"]): continue
		if definition.is_passive: moves.append(definition.id)
		elif definition.is_global_passive: globals.append(definition.id)
	assert(not moves.is_empty() and not globals.is_empty())
	var state := CampaignState.new()
	state.campaign_id = &"base:campaign/standard_tower"
	state.current_room_id = &"base:room/level_1_1_a"
	for slot in 2:
		var owned := OwnedMinionState.new()
		owned.instance_id = StringName("persist-slot-%d" % slot)
		owned.definition_id = species.id
		owned.level = 20
		owned.experience = 20000
		owned.learned_move_ids.assign(species.initial_move_ids + (moves if slot == 0 else globals))
		state.party.append(owned)
	var selected: OwnedMinionState = state.party[0]
	var expected := CampaignProgressionService.owned_display_stats(selected, species, catalog, state)
	var base := CampaignProgressionService.owned_stats(selected, species)
	assert(expected.health > base.health and expected.energy > base.energy)
	assert(CampaignProgressionService.rest_party(state, catalog).ok)
	assert(selected.persistent_health == expected.health and selected.persistent_energy == expected.energy, "Rest truncated passive maxima")
	var encounter := catalog.get_definition(&"base:encounter/grass_floor1_room1_normal") as EncounterDefinition
	var prepared := CampaignProgressionService.prepare_battle(state, encounter)
	var setup := CampaignProgressionService.build_battle_setup(state, catalog, encounter)
	assert(setup.ok and setup.combatants[0].health == expected.health and setup.combatants[0].energy == expected.energy, "Preparation lost passive refill")
	var result := BattleResult.new()
	result.battle_id = StringName(prepared.battle_id)
	result.winning_team = 0
	result.reason = &"elimination"
	result.participants = [
		{"instance_id": selected.instance_id, "team": 0, "max_health": expected.health, "max_energy": expected.energy + 20, "persistent_changes": {"health": expected.health + 4, "energy": expected.energy + 5}},
		{"instance_id": state.party[1].instance_id, "team": 0, "persistent_changes": {"health": 1, "energy": 1}},
	]
	var settled := CampaignProgressionService.apply_battle_result(state, result, encounter, catalog)
	assert(settled.ok and selected.level == 20)
	assert(selected.persistent_health == expected.health + 4, "Transfer clamps health despite source getter retaining it")
	assert(selected.persistent_energy == expected.energy + 5, "Transfer drops native stage/passive energy")
	var saved := state.to_dictionary(catalog.content_version)
	var reloaded := CampaignState.new()
	reloaded.load_dictionary(saved)
	assert(reloaded.validation_errors(catalog).is_empty())
	assert(reloaded.party[0].persistent_health == selected.persistent_health and reloaded.party[0].persistent_energy == selected.persistent_energy)
	assert(CampaignProgressionService.apply_battle_result(state, result, encounter, catalog).already_applied)
	# Legacy/synthetic energy caps must use FINAL provider health, even when the
	# dead provider occurs later in the participant list.
	state.pending_battle.clear()
	prepared = CampaignProgressionService.prepare_battle(state, encounter)
	result.battle_id = StringName(prepared.battle_id)
	result.participants[0].erase("max_energy")
	result.participants[1].persistent_changes.health = 0
	settled = CampaignProgressionService.apply_battle_result(state, result, encounter, catalog)
	var dead_provider_stats := CampaignProgressionService.owned_display_stats(selected, species, catalog, state)
	assert(settled.ok and selected.persistent_energy == dead_provider_stats.energy, "Fallback cap used stale living global provider")
	# Slot-order refill: a dead global provider revives, so subsequent members
	# include its aura. Do not silently replace the source loop with all-at-once.
	state.party.reverse()
	assert(CampaignProgressionService.rest_party(state, catalog).ok)
	assert(state.party[0].persistent_health > 0)
	expected = CampaignProgressionService.owned_display_stats(selected, species, catalog, state)
	assert(selected.persistent_health == expected.health and selected.persistent_energy == expected.energy)
	selected.level = 5
	selected.experience = 5990
	selected.persistent_health = 3
	var old_health: int = CampaignProgressionService.owned_display_stats(selected, species, catalog, state, 5).health
	var awards := CampaignProgressionService._award_experience(state, encounter, catalog, true)
	var new_health: int = CampaignProgressionService.owned_display_stats(selected, species, catalog, state).health
	assert(selected.level > 5 and awards[String(selected.instance_id)].health_increase == new_health - old_health)
	assert(selected.persistent_health == 3 + new_health - old_health, "Level-up HP delta excluded passives")
	# Exercise the production transaction boundary without touching disk saves.
	var session := MemorySession.new()
	session.catalog = catalog
	session.campaign = catalog.get_definition(state.campaign_id) as CampaignDefinition
	session.state = state
	session.state.pending_battle.clear()
	prepared = session.prepare_battle(encounter.id)
	assert(prepared.ok)
	result.battle_id = StringName(prepared.battle_id)
	var before: Dictionary = session.state.to_dictionary()
	session.reject_save = true
	assert(not session.apply_battle_result(result).ok and session.state.to_dictionary() == before, "Rejected settlement mutated passive state")
	print("PASS: passive-aware rest/preparation, native health/energy transfer, final-provider fallback caps, save roundtrip/idempotence, source slot-order revival, XP health deltas and rejected-save rollback")
	quit()
