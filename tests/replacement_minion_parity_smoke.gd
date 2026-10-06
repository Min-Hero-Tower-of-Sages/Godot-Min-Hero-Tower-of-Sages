extends SceneTree

const AUTOBUILDER = preload("res://src/domain/battle/legacy_minion_autobuilder.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var catalog: ContentCatalog = root.get_node("CampaignRuntime").catalog
	var builds := 0
	for definition in catalog._by_id.values():
		if not definition is EncounterDefinition: continue
		var extras: Dictionary = definition.battle_modifier_configuration.get("extra_minions", {})
		for side in extras.values():
			for template in side.get("templates", []):
				if not bool(template.get("source_derive_stats", false)): continue
				var species := catalog.get_definition(StringName(template.definition_id)) as MinionDefinition
				var builder := AUTOBUILDER.new()
				var moves: Array[StringName] = builder.build(species, int(template.level), template.get("move_ids", []), catalog, BattleRng.new(71))
				assert(not moves.is_empty())
				assert(builder._known.size() - species.initial_move_ids.size() <= builder._budget, "Replacement exceeded level talent budget")
				var families: Dictionary = {}
				for move_id in moves:
					var move := catalog.get_definition(move_id) as MoveDefinition
					assert(not families.has(move.family_id), "Duplicate active/passive move tier")
					families[move.family_id] = true
				for initial_id in species.initial_move_ids:
					assert(families.has((catalog.get_definition(initial_id) as MoveDefinition).family_id), "Replacement lost a starting move")
				builds += 1
	var zapig := catalog.get_definition(&"base:minion/fire_pig_1") as MinionDefinition
	var novice_builder := AUTOBUILDER.new()
	var novice: Array[StringName] = novice_builder.build(zapig, 3, [&"base:move/fire_bolt/tier5"], catalog, BattleRng.new(7))
	assert(novice == zapig.initial_move_ids, "Level-three minion received free preference moves")
	var specialist_builder := AUTOBUILDER.new()
	specialist_builder.build(zapig, 6, [&"base:move/fire_ram/tier1", &"base:move/fire_bolt/tier5"], catalog, BattleRng.new(7))
	assert(specialist_builder._known.size() == zapig.initial_move_ids.size() + 1 and &"base:move/fire_ram/tier1" in specialist_builder._known)
	var encounter := catalog.get_definition(&"base:encounter/floor12_trainer_1") as EncounterDefinition
	assert(encounter != null)
	var state := CampaignState.new()
	var owned := OwnedMinionState.new()
	owned.instance_id = &"replacement-original"
	owned.definition_id = zapig.id
	owned.level = 6
	owned.experience = 6300
	state.party.append(owned)
	state.pending_battle = {"battle_id": "replacement-fixture", "encounter_id": String(encounter.id)}
	var prepared := CampaignProgressionService.build_battle_setup(state, catalog, encounter)
	assert(prepared.ok)
	var setup: Dictionary = prepared.duplicate(true)
	# Force one legal lethal native action to exercise replacement integration.
	# These explicit fixture overrides replace native source stat formulas.
	setup.combatants[0].source_raw_stats = {}
	setup.combatants[1].source_raw_stats = {}
	setup.combatants[0].health = 1
	setup.combatants[0].speed = 1
	setup.combatants[1].speed = 100000
	setup.combatants[1].attack = 100000
	setup.combatants[1].max_attack_stat = 100000
	setup.combatants[1].move_ids = [&"base:move/claw/tier1"]
	var rules := RuleSetDefinition.new()
	rules.id = &"fixture:replacement_rules"
	rules.party_size = 5
	rules.configuration = {"battle_modifiers": encounter.battle_modifier_configuration.duplicate(true)}
	var controller := BattleController.new()
	assert(controller.start(setup, catalog, rules, BattleRng.new(18)).accepted)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main.catalog = catalog
	main.controller = controller
	main._original_player_ids[String(owned.instance_id)] = true
	main.call("_sync_from_engine")
	var original_view: BattleCombatantView = main.combatant_views[String(owned.instance_id)]
	var decision := controller.engine.get_decision()
	assert(int(decision.team) == 1)
	var response := controller.engine.submit(BattleCommand.new(StringName(decision.actor_id), BattleCommand.Kind.USE_MOVE, &"base:move/claw/tier1", [owned.instance_id], int(decision.revision)))
	assert(response.accepted and response.events.any(func(event: BattleEvent): return event.kind == &"battle_mod_extra_spawned" and int(event.values.team) == 0))
	for event in response.events:
		if event.target_id == owned.instance_id:
			main.call("_apply_event_values", event)
	main.call("_sync_from_engine")
	await process_frame
	assert(is_instance_valid(original_view) and not original_view.visible)
	assert(main._retired_player_views[String(owned.instance_id)] == original_view)
	assert(not main.combatant_views.has(String(owned.instance_id)))
	assert(original_view.state_cache.health == 0)
	var replacement_view: BattleCombatantView
	for view in main.combatant_views.values():
		if view.team == 0: replacement_view = view
	assert(replacement_view != null and replacement_view.instance_id != owned.instance_id)
	var replacement_id := String(replacement_view.instance_id)
	var battle_snapshot: Dictionary = controller.engine.snapshot()
	main.call("_restore_player_replacement_views")
	await process_frame
	assert(main.combatant_views[String(owned.instance_id)] == original_view and original_view.visible)
	assert(is_equal_approx(original_view.modulate.a, 0.5) and original_view.state_cache.health == 0)
	assert(not main.combatant_views.has(replacement_id) and main._retired_player_views.is_empty())
	assert(controller.engine.snapshot() == battle_snapshot, "Finish visuals mutated settled combat state")
	main.call("_begin_battle_finish_presentation")
	var presenter: BattleProgressionPresenter = main.campaign_progression_presenter
	presenter.begin_sequence([owned], {String(owned.instance_id): {"old_level": 6, "new_level": 6, "old_experience": 6200, "new_experience": 6300}}, catalog, main.combatant_views, true, main.audio_controller)
	await create_timer(2.2).timeout
	assert(not presenter._bar_nodes.is_empty(), "Restored minion did not receive its XP presentation")
	assert(is_equal_approx(original_view.health_background_sprite.modulate.a, 0.0) and is_equal_approx(original_view.level_label.modulate.a, 0.0), "Finish interface alpha: health=%s level=%s" % [original_view.health_background_sprite.modulate.a, original_view.level_label.modulate.a])
	assert(is_equal_approx(original_view.modulate.a, 0.5), "Defeated original did not remain a finish-screen ghost")
	for view in main.combatant_views.values():
		if view.team == 1: assert(is_equal_approx(view.modulate.a, 0.0), "Finish screen left enemy combat visuals visible")
	presenter.cancel_sequence()
	var replaced_enemy: CombatantState = controller.engine._living_at_slot(1, 0)
	replaced_enemy.health = 0
	replaced_enemy.defeated = true
	controller.engine._inject_extra_minions()
	decision = controller.engine.get_decision()
	assert(controller.engine.submit(BattleCommand.new(StringName(decision.actor_id), BattleCommand.Kind.FORFEIT, &"", [], int(decision.revision))).accepted)
	var result: BattleResult = controller.engine.get_result()
	assert(result.participants.any(func(participant: Dictionary) -> bool: return participant.instance_id == String(owned.instance_id) and participant.retired))
	var final_entries: Array[Dictionary] = []
	for participant in result.participants:
		if int(participant.team) == 1 and not participant.retired:
			final_entries.append({"definition_id": participant.definition_id, "level": participant.level, "slot_index": participant.slot_index, "source_level_offset": 0})
	final_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.slot_index) < int(b.slot_index))
	assert(final_entries.size() == encounter.team_entries.size(), "Retired opponents were counted twice")
	var current_roster := encounter.duplicate(true) as EncounterDefinition
	current_roster.source_level_offset = 0
	current_roster.team_entries.assign(final_entries)
	var expected_state := CampaignState.new()
	expected_state.party.append(owned.duplicate_state())
	var result_state := CampaignState.new()
	result_state.party.append(owned.duplicate_state())
	var expected_awards := CampaignProgressionService._award_experience(expected_state, current_roster, catalog, true)
	var result_awards := CampaignProgressionService._award_experience(result_state, encounter, catalog, true, result)
	assert(expected_awards == result_awards, "Experience ignored final replacement roster/levels")
	main.queue_free()
	await process_frame
	print("PASS: %d source replacement talent builds, native lethal replacement, original-view/XP restoration, finish fades/ghosts and final-roster experience without double-counting retired minions" % builds)
	quit(0)
