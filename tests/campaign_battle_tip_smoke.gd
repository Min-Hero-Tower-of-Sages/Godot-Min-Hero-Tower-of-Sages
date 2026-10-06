extends SceneTree

class MemorySession extends CampaignSession:
	func _save_candidate(candidate) -> Dictionary:
		var errors: PackedStringArray = candidate.validation_errors(catalog)
		return {"ok": errors.is_empty(), "message": "\n".join(errors)}

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	await process_frame
	var runtime := root.get_node("CampaignRuntime")
	var original_session: CampaignSession = runtime.session
	var session := MemorySession.new()
	session.catalog = runtime.catalog
	session.campaign = session.catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
	session.state = CampaignState.new()
	session.state.campaign_id = session.campaign.id
	session.state.current_room_id = session.campaign.starting_room_id
	var owned := OwnedMinionState.new()
	owned.instance_id = &"tip-starter"
	owned.definition_id = &"base:minion/fire_pig_1"
	owned.level = 5
	owned.experience = 5350
	owned.learned_move_ids.assign((session.catalog.get_definition(owned.definition_id) as MinionDefinition).initial_move_ids)
	session.state.party.append(owned)
	session.state.progression["battle_basics_tutorial_seen"] = true
	session.state.progression["focus_targets_tutorial_seen"] = true
	runtime.session = session
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	root.add_child(main)
	main.catalog = session.catalog
	main.source_encounter = session.catalog.get_definition(&"base:encounter/grass_floor1_room1_normal") as EncounterDefinition
	var zapig := session.catalog.get_definition(&"base:minion/fire_pig_1") as MinionDefinition
	var ticub := session.catalog.get_definition(&"base:minion/tiger_1") as MinionDefinition
	var rules := RuleSetDefinition.new()
	rules.id = &"fixture:rules/battle_tips"
	rules.party_size = 5
	main.controller = BattleController.new()
	var response: BattleResponse = main.controller.start({"battle_id": "fixture-battle-tips", "combatants": [main._make_combatant(zapig, &"player-1", 0, 0, 5, zapig.initial_move_ids), main._make_combatant(ticub, &"player-2", 0, 1, 5, ticub.initial_move_ids), main._make_combatant(ticub, &"enemy-1", 1, 0, 5, ticub.initial_move_ids)]}, session.catalog, rules, BattleRng.new(4))
	_check(response.accepted, "Tip fixture battle failed to initialize")
	main._sync_from_engine()
	main.start_overlay.visible = false
	main.campaign_mode = true
	main.busy = true
	main.active_battle_modifiers = {"shield": {"player": 1}, "move_timer": {"turns": 3}, "extra_minions": {"player": []}, "resurrection": {"turns": 3}}
	var intro_pairs := [["shield", "shield_modifier"], ["move_timer", "move_timer_modifier"], ["extra_minions", "extra_minions_modifier"], ["resurrection", "resurrection_modifier"]]
	for pair in intro_pairs:
		_check(main._campaign_intro_tutorial_id(session) == pair[1], "Modifier introduction priority mismatch: %s" % pair[1])
		main.call("_run_campaign_intro_tutorial", Time.get_ticks_usec() - 3500000)
		await process_frame
		var tutorial: Control = main.get_node_or_null("CampaignIntroTutorial")
		_check(tutorial != null and tutorial.tutorial_id == pair[1], "Modifier tutorial not presented: %s" % pair[1])
		if tutorial != null:
			_check(tutorial._background.texture == SourceMenuArt.texture("tutorial_backgroundLarge"), "Modifier uses incorrect small background")
			tutorial._advance()
			await create_timer(1.0).timeout
		_check(bool(session.state.progression.get(String(pair[1]) + "_tutorial_seen", false)), "Modifier tutorial was not persisted")
	_check(main._campaign_intro_tutorial_id(session).is_empty(), "Seen modifier tutorials repeat")
	var decision: Dictionary = main.controller.engine.get_decision().duplicate(true)
	decision["actor_id"] = "player-1"
	_check(StringName(main._combatant_state(&"player-1").get("definition_id", "")) == &"base:minion/fire_pig_1", "Fixture Zapig binding missing")
	for keys in [1, 2]:
		session.state.progression["floor_keys"] = keys
		var expected := "energy" if keys == 1 else "type_effectiveness"
		_check(main._decision_tutorial_id(session, decision) == expected, "Floor-key decision tutorial trigger mismatch")
		main.call("_run_decision_tutorial", decision)
		await create_timer(0.9).timeout
		var tutorial: Control = main.get_node_or_null("CampaignDecisionTutorial")
		_check(tutorial != null and tutorial.tutorial_id == expected, "Decision tutorial not presented")
		_check(main.busy and main.forfeit_button.disabled, "Decision tutorial did not guard move/forfeit input")
		main._choose_move({"move_id": "base:move/claw/tier1", "target_ids": ["enemy-1"]})
		_check(main.pending_move.is_empty(), "Move input leaked behind decision tutorial")
		if tutorial != null:
			_check(tutorial._background.texture == SourceMenuArt.texture("tutorial_backgroundLarge"), "Decision tutorial uses wrong background")
			tutorial._advance()
			await create_timer(0.6).timeout
		_check(not main.busy and not main.forfeit_button.disabled, "Decision input not restored after tutorial")
		_check(main._decision_tutorial_id(session, decision).is_empty(), "Seen decision tutorial repeated")
		main.busy = true
	session.state.progression["type_effectiveness_tutorial_seen"] = false
	decision["actor_id"] = "player-2"
	_check(main._decision_tutorial_id(session, decision).is_empty(), "Type tip shown for non-Zapig actor")
	main.busy = false
	var live_decision: Dictionary = main.controller.engine.get_decision()
	main._build_move_buttons(live_decision)
	await create_timer(1.1).timeout
	_check(is_instance_valid(main._move_selection_hint) and main._move_selection_hint.visible and main._move_selection_hint.position == Vector2(306, 33), "Source choose-a-move guidance missing/misplaced")
	main._choose_move(live_decision.legal_moves[0].duplicate(true))
	_check(bool(session.state.progression.get("move_select_tutorial_seen", false)), "Move selection did not persist guide acknowledgement")
	await create_timer(0.6).timeout
	_check(not main._move_selection_hint.visible, "Move guide remains after selector exit")
	main.queue_free()
	await process_frame
	runtime.session = original_session
	print("%s: six native battle tips, modifier priority/one-time persistence, source key/Zapig conditions, move/forfeit guards and restored decision input" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
