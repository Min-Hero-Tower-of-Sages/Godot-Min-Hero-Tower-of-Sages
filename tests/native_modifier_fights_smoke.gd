extends SceneTree

const AUTOBUILDER = preload("res://src/domain/battle/legacy_minion_autobuilder.gd")
const ENCOUNTERS: Array[StringName] = [&"base:encounter/floor7_trainer_1", &"base:encounter/floor7_trainer_6_boss", &"base:encounter/floor8_trainer_1", &"base:encounter/floor8_trainer_2", &"base:encounter/floor8_trainer_3", &"base:encounter/floor8_trainer_6_boss", &"base:encounter/floor9_trainer_1", &"base:encounter/floor9_trainer_2", &"base:encounter/floor9_trainer_3", &"base:encounter/floor10_fire_sage"]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var catalog: ContentCatalog = root.get_node("CampaignRuntime").catalog
	var presentation_cases: Array[Dictionary] = []
	var action_count := 0
	var timer_casts := 0
	for encounter_id in ENCOUNTERS:
		var encounter := catalog.get_definition(encounter_id) as EncounterDefinition
		assert(encounter != null)
		var state := CampaignState.new()
		state.campaign_id = &"base:campaign/standard_tower"
		state.current_room_id = &"base:room/level_1_1_a"
		state.progression.floor_index = encounter.source_floor_index
		for index in 3:
			var species := catalog.get_definition(&"base:minion/fire_pig_1") as MinionDefinition
			var owned := OwnedMinionState.new()
			owned.instance_id = StringName("modifier-player-%d" % index)
			owned.definition_id = species.id
			owned.level = 30
			owned.experience = 30000
			owned.learned_move_ids = AUTOBUILDER.new().build(species, owned.level, [&"base:move/fire_ram/tier1", &"base:move/fire_bolt/tier5"], catalog, BattleRng.new(17 + index))
			state.party.append(owned)
		assert(CampaignProgressionService.prepare_battle(state, encounter).ok)
		var setup := CampaignProgressionService.build_battle_setup(state, catalog, encounter)
		var rules := RuleSetDefinition.new()
		rules.configuration = {"ai_teams": [0, 1], "battle_modifiers": encounter.battle_modifier_configuration.duplicate(true)}
		var engine := BattleEngine.new()
		assert(engine.start(setup, catalog, rules, BattleRng.new(144)).accepted)
		var captured := false
		var actions := 0
		while engine.get_result().is_empty() and actions < 600:
			var decision := engine.get_decision()
			assert(not decision.is_empty() and not decision.legal_moves.is_empty(), "Modifier fight stalled on a decision")
			var before := engine.snapshot()
			var response := engine.submit_ai_turn()
			assert(response.accepted)
			assert(not response.events.any(func(event: BattleEvent) -> bool: return event.kind == &"turn_skipped"), "AI skipped a turn rather than using a legal move/desperation")
			for index in response.events.size():
				if response.events[index].kind != &"battle_mod_timer_triggered": continue
				timer_casts += 1
				var timer_hit := response.events.any(func(event: BattleEvent) -> bool: return event.kind == &"move_used" and event.actor_id == response.events[index].actor_id and bool(event.values.get("hit", false)) and not event.values.get("target_ids", []).is_empty())
				if not captured and timer_hit:
					var timer_events: Array[BattleEvent] = []
					for event in response.events.slice(index): timer_events.append(event)
					presentation_cases.append({"encounter": encounter, "setup": setup, "before": before, "after": engine.snapshot(), "events": timer_events})
					captured = true
			actions += 1
		assert(not engine.get_result().is_empty(), "Native modifier fight exceeded 600 legal actions: %s" % encounter_id)
		action_count += actions
		var settled := CampaignProgressionService.apply_battle_result(state, engine.get_result(), encounter, catalog)
		assert(settled.ok and state.pending_battle.is_empty())
		if engine.get_result().winning_team != 0: assert(CampaignProgressionService.complete_defeat_return(state, catalog).ok)
		print("Native fight %s: %d actions, winner %d" % [encounter_id, actions, engine.get_result().winning_team])
		if not captured:
			# A short authored battle can finish before the first timer interval.
			# Keep the completed fight intact and separately exercise a real native
			# timer cast from its fresh setup; do not inflate the full-fight count.
			for attempt in 8:
				var probe := BattleEngine.new()
				assert(probe.start(setup, catalog, rules, BattleRng.new(200 + attempt)).accepted)
				probe._state.modifier_state.move_timer_counter = int(encounter.battle_modifier_configuration.move_timer.interval)
				var before := probe.snapshot()
				probe._current_events.clear()
				assert(probe._maybe_run_move_timer())
				var probe_events: Array[BattleEvent] = probe._current_events.duplicate()
				var timer_id := StringName(probe.snapshot().timer_actor.instance_id)
				if not probe_events.any(func(event: BattleEvent) -> bool: return event.kind == &"move_used" and event.actor_id == timer_id and bool(event.values.get("hit", false)) and not event.values.get("target_ids", []).is_empty()): continue
				presentation_cases.append({"encounter": encounter, "setup": setup, "before": before, "after": probe.snapshot(), "events": probe_events})
				captured = true
				break
			assert(captured, "Authored timer could not produce a native targeted cast: %s" % encounter_id)
	# Render every native timer cast configuration, not an empty-target synthetic
	# move. Production timer BMod stays hidden and outside normal party ordering.
	var main: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main.catalog = catalog
	main.busy = true
	for case in presentation_cases:
		main._clear_combatant_views()
		await process_frame
		var rules := RuleSetDefinition.new()
		rules.configuration = {"ai_teams": [0, 1], "battle_modifiers": case.encounter.battle_modifier_configuration.duplicate(true)}
		assert(main.controller.engine.start(case.setup, catalog, rules, BattleRng.new(1)).accepted)
		main.controller.engine.restore(case.before)
		main.active_battle_modifiers = case.encounter.battle_modifier_configuration.duplicate(true)
		main._sync_from_engine()
		main._sync_battle_modifier_visuals(main.active_battle_modifiers)
		var caster: Dictionary = case.before.timer_actor
		assert(not main.combatant_views.has(String(caster.instance_id)))
		var cast: BattleEvent
		for event in case.events:
			if event.kind == &"move_used" and event.actor_id == StringName(caster.instance_id):
				cast = event
				break
		assert(cast != null and not cast.values.target_ids.is_empty())
		var move := catalog.get_definition(StringName(cast.values.move_id)) as MoveDefinition
		var visual_id := int(main._resolved_visual_id(move))
		var family := String(main.vfx_catalog.profile_for(visual_id).get("family", ""))
		var visual_finish_usec := Time.get_ticks_usec()
		for target in cast.values.target_ids:
			main._last_move_visual_duration_seconds = 0.0
			var children_before: int = main.move_vfx_layer.get_child_count()
			var hit_delay := float(main._animate_move_visual(cast, StringName(target)))
			assert(main._last_move_visual_duration_seconds > 0.0 and hit_delay >= 0.0, "Hidden timer caster dropped its source animation: %s" % case.encounter.id)
			if family not in ["screen_shake", "test_white_flash"]:
				assert(main.move_vfx_layer.get_child_count() > children_before, "Hidden timer produced no target VFX")
			visual_finish_usec = maxi(visual_finish_usec, Time.get_ticks_usec() + int(main._last_move_visual_duration_seconds * 1000000.0))
		await main._wait_until_usec(visual_finish_usec)
		# Actual presentation order includes the .7s stone lead-in and health
		# events from the engine. Check the first native configuration end to end.
		if case == presentation_cases[0]:
			var started_usec := Time.get_ticks_usec()
			await main._present(case.events)
			assert(Time.get_ticks_usec() - started_usec >= 700000)
			assert(not main.current_turn_indicator.visible)
	main.queue_free()
	await process_frame
	print("PASS: ten complete native floor-7–10 modifier fights, %d legal actions/%d timer casts; real target VFX from hidden casters, source cast tail and presenter lead-in" % [action_count, timer_casts])
	quit(0)
