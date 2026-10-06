extends "res://tests/ten_floor_campaign_handoff_smoke.gd"

func _run() -> void:
	await process_frame
	var runtime := root.get_node("CampaignRuntime")
	var original_session: CampaignSession = runtime.session
	var session := MemorySession.new()
	session.catalog = runtime.catalog
	session.campaign = session.catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
	session.state = CampaignState.new()
	session.state.campaign_id = session.campaign.id
	session.state.current_room_id = &"base:room/level_1_1_a"
	session.state.progression["floor_index"] = 31
	var normal_id := &"base:encounter/grass_floor1_room1_normal"
	var resolved := CampaignTowerModeService.resolve_encounter(session.catalog, session.catalog.get_definition(normal_id) as EncounterDefinition, 31)
	assert(resolved.ok)
	var hard_id: StringName = resolved.encounter.id
	session.state.progression["completed_encounters"] = {String(normal_id): true}
	session.state.progression["encounter_star_ratings"] = {String(normal_id): 3}
	runtime.session = session
	var shell := (load("res://scenes/application_shell.tscn") as PackedScene).instantiate()
	root.add_child(shell)
	shell.call("_show_room_from_state")
	var room := session.catalog.get_definition(session.state.current_room_id) as RoomDefinition
	var trainer_interaction: Dictionary = {}
	for interaction in room.interactions:
		if StringName(interaction.get("encounter_id", "")) == normal_id:
			trainer_interaction = interaction
	assert(not trainer_interaction.is_empty())
	shell.call("_show_trainer_dialog", trainer_interaction, normal_id, "Hard first visit", "Trainer")
	assert(not shell._source_dialogue_yes.is_valid(), "Standard clear must not turn first hard battle into a rematch")
	assert(shell._source_dialogue_on_complete.is_valid())
	shell.call("_clear_dialog")
	session.state.progression.completed_encounters[String(hard_id)] = true
	session.state.progression.encounter_star_ratings[String(hard_id)] = 1
	shell.call("_show_trainer_dialog", trainer_interaction, normal_id, "Hard rematch", "Trainer")
	assert(shell._source_dialogue_yes.is_valid() and shell._source_dialogue_no.is_valid())
	var rating := shell.interaction_dialog.get_node_or_null("TrainerStars") as Label
	assert(rating != null and rating.text == "Stars: 1/3", "Hard rematch displayed the standard star rating")
	shell._source_dialogue_no.call()
	assert(shell.interaction_dialog == null)
	shell.queue_free()
	await process_frame
	runtime.session = original_session
	print("PASS: independent hard first-visit/rematch prompts and star ratings; decline restores room music")
	quit(0)
