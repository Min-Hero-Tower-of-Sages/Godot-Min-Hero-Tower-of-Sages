extends SceneTree

class MemorySession extends CampaignSession:
	var reject_save := false
	func _save_candidate(candidate) -> Dictionary:
		var errors: PackedStringArray = candidate.validation_errors(catalog)
		if reject_save or not errors.is_empty():
			return {"ok": false, "message": "Fixture save rejected"}
		return {"ok": true}

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
	var starter := OwnedMinionState.new()
	starter.instance_id = &"tutorial-starter"
	starter.definition_id = &"base:minion/fire_pig_1"
	starter.level = 5
	starter.experience = 5300
	starter.learned_move_ids.assign((session.catalog.get_definition(starter.definition_id) as MinionDefinition).initial_move_ids)
	session.state.party.append(starter)
	var first_encounter := &"base:encounter/grass_floor1_room1_normal"
	for definition in session.catalog._by_id.values():
		if definition is RoomDefinition and first_encounter in definition.encounter_ids:
			session.state.current_room_id = definition.id
	runtime.session = session
	var prepared: Dictionary = runtime.prepare_trainer_battle(first_encounter, Vector2.ZERO)
	_check(prepared.ok, "Tutorial battle could not prepare")
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	root.add_child(main)
	main.call("begin_campaign_battle")
	for attempt in 100:
		if main.get_node_or_null("CampaignIntroTutorial") != null:
			break
		_check(main.busy and not main.move_panel.visible, "Decision became active before first-battle tutorial")
		await create_timer(0.1).timeout
	var tutorial: Control = main.get_node_or_null("CampaignIntroTutorial")
	_check(tutorial != null, "Battle Basics missing after intro gate: %s / %s" % [main.event_text.text, main.get_children().map(func(child: Node) -> String: return String(child.name))])
	_check(main.busy and not main.move_panel.visible and not main.current_turn_indicator.visible, "Battle decision leaked into intro tutorial")
	if tutorial != null:
		_check(tutorial.page == 0 and tutorial._button.texture_normal == SourceMenuArt.texture("tutorial_nextButton"), "Battle Basics first page/button differs")
		tutorial._advance()
		tutorial._advance()
		await create_timer(0.6).timeout
		_check(tutorial.page == 1, "Double Next skipped Turn order")
		tutorial._advance()
		await create_timer(0.6).timeout
		_check(tutorial.page == 2 and tutorial._button.texture_normal == SourceMenuArt.texture("tutorial_okButton"), "Health Bar final page/button differs")
		session.reject_save = true
		tutorial._advance()
		_check(not bool(session.state.progression.get("battle_basics_tutorial_seen", false)) and main.busy, "Failed save acknowledged tutorial or unlocked battle")
		session.reject_save = false
		tutorial._advance()
		await create_timer(0.6).timeout
		_check(bool(session.state.progression.get("battle_basics_tutorial_seen", false)), "Battle Basics completion not persisted")
		_check(main.get_node_or_null("CampaignIntroTutorial") == null, "Tutorial did not close after exit fade")
	main.queue_free()
	await process_frame
	_check(runtime.cancel_unstarted_battle().ok, "Fixture battle context failed to clear")
	# Check the exact Floor 2 / trainer-room 1 gate using authored interactions.
	session.state.progression["floor_index"] = 1
	var focus_encounter: EncounterDefinition
	for definition in session.catalog._by_id.values():
		if definition is RoomDefinition:
			for interaction in definition.interactions:
				var encounter := session.catalog.get_definition(StringName(interaction.get("encounter_id", ""))) as EncounterDefinition
				if encounter != null and encounter.source_floor_index == 1 and int(interaction.get("trainer_room_id", -1)) == 1:
					session.state.current_room_id = definition.id
					focus_encounter = encounter
	_check(focus_encounter != null, "Source focus-target trainer binding missing")
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	root.add_child(main)
	main.campaign_mode = true
	main.catalog = session.catalog
	main.source_encounter = focus_encounter
	main.busy = true
	main.call("_run_campaign_intro_tutorial", Time.get_ticks_usec() - 3500000)
	await process_frame
	tutorial = main.get_node_or_null("CampaignIntroTutorial")
	_check(tutorial != null and tutorial.tutorial_id == "focus_targets", "Floor 2 focus tutorial not routed")
	if tutorial != null:
		tutorial._advance()
		await create_timer(0.6).timeout
	_check(bool(session.state.progression.get("focus_targets_tutorial_seen", false)), "Focus-target acknowledgement missing")
	main.queue_free()
	await process_frame
	# Boss guidance is scheduled after the three-key trainer return dialogue.
	session.state.progression["floor_index"] = 0
	session.state.progression["floor_keys"] = 3
	var shell := (load("res://scenes/application_shell.tscn") as PackedScene).instantiate()
	root.add_child(shell)
	shell.call("_show_room_from_state")
	shell.call("_present_return_rewards", {})
	await create_timer(3.0).timeout
	tutorial = shell.interaction_dialog
	_check(tutorial != null and tutorial.tutorial_id == "boss_room", "Three-key boss guidance missing")
	_check(not shell.current_room._controls_enabled, "Room movement active behind boss guidance")
	if tutorial != null:
		tutorial._advance()
		await create_timer(0.6).timeout
	_check(shell.current_room._controls_enabled and not is_instance_valid(shell.interaction_dialog), "Boss guidance did not restore room/menu input")
	_check(bool(session.state.progression.get("boss_room_tutorial_seen", false)), "Boss guidance acknowledgement missing")
	shell.queue_free()
	await process_frame
	runtime.session = original_session
	print("%s: actual campaign Battle Basics gate/pages, focus-target source trigger, three-key boss guidance, save retry and input restoration" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
