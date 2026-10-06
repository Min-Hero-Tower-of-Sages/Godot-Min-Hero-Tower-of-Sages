extends SceneTree

const Dialogue = preload("res://src/application/source_trainer_dialogue.gd")
class MemorySession extends CampaignSession:
	func _save_candidate(_candidate) -> Dictionary:
		return {"ok": true}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var runtime := root.get_node("CampaignRuntime")
	var session := MemorySession.new()
	session.catalog = runtime.catalog
	session.campaign = runtime.catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
	session.state = CampaignState.new()
	session.state.campaign_id = session.campaign.id
	session.state.character = {"name": "Return fixture", "gender": "male"}
	var encounter_id := &"base:encounter/grass_floor1_room1_normal"
	var trainer_room: RoomDefinition
	var trainer: Dictionary
	for definition in runtime.catalog._by_id.values():
		if definition is RoomDefinition:
			for interaction in definition.interactions:
				if StringName(interaction.get("encounter_id", "")) == encounter_id:
					trainer_room = definition
					trainer = interaction
	assert(trainer_room != null)
	session.state.current_room_id = trainer_room.id
	runtime.session = session
	var first := session.interact(StringName(trainer.id))
	assert(first.ok and first.dialog_text.contains("fellow student"))
	var sage := runtime.catalog.get_definition(&"base:encounter/floor10_fire_sage") as EncounterDefinition
	assert(Dialogue.for_encounter(sage).after_win_text.contains("combine gems"))
	session.state.progression["completed_encounters"] = {String(encounter_id): true}
	session.state.progression["encounter_star_ratings"] = {String(encounter_id): 2}
	assert(session.interact(StringName(trainer.id)).dialog_text.contains("Retry for three stars"))
	var shell := (load("res://scenes/application_shell.tscn") as PackedScene).instantiate()
	root.add_child(shell)
	shell.call("_show_room_from_state")
	await process_frame
	shell.call("_show_trainer_dialog", trainer, encounter_id, session.interact(StringName(trainer.id)).dialog_text, "Trainer")
	await create_timer(0.3).timeout
	while shell.call("_source_dialogue_can_scroll"):
		shell.call("_advance_source_dialogue")
		await create_timer(0.4).timeout
	assert(shell._source_dialogue_choices.size() == 2)
	assert(not shell._source_dialogue_on_complete.is_valid(), "Advancing rematch dialogue must not start a battle")
	assert(shell.interaction_dialog.get_node("TrainerStars").text == "Stars: 2/3")
	shell.call("_clear_dialog")
	session.state.progression.encounter_star_ratings[String(encounter_id)] = 3
	assert(session.interact(StringName(trainer.id)).dialog_text.contains("Replay me for exp"))
	shell._trainer_return_location = {"room_id": String(trainer_room.id), "encounter_id": String(encounter_id), "first_visit": true, "position": shell.current_room.player_position()}
	shell.call("_on_campaign_return_requested")
	await create_timer(0.2).timeout
	assert(shell._room_transition_active and shell.room_transition_curtain.visible)
	assert(shell.room_transition_curtain.color.a > 0.0 and shell.room_transition_curtain.color.a < 1.0, "Victory return must fade the old screen before switching")
	assert(shell._source_dialogue_label == null, "After-win dialogue must not appear before the opaque handoff")
	await create_timer(0.38).timeout
	assert(shell.room_transition_curtain.color.a > 0.99, "Destination must be held behind black before reveal")
	await create_timer(0.3).timeout
	assert(shell.room_transition_curtain.color.a > 0.0 and shell.room_transition_curtain.color.a < 1.0, "Room must reveal through a fade rather than an immediate swap")
	await create_timer(0.45).timeout
	assert(not shell._room_transition_active and not shell.room_transition_curtain.visible)
	assert(shell._source_dialogue_label.text == "You did fantastic!", "First victory must restore the source trainer dialogue before pickups")
	assert(not shell.current_room._controls_enabled)
	shell.call("_clear_dialog")
	assert(shell.current_room._controls_enabled)
	# CampaignRoomView is reused by room changes, so node identity is not enough
	# to scope the delayed third-key tutorial or seal-completion dialogue.
	var previous_room: CampaignRoomView = shell.current_room
	session.state.progression["floor_keys"] = 3
	shell.call("_schedule_boss_room_tutorial", previous_room, trainer_room.id)
	session.state.current_room_id = &"base:room/level_1_1_h1"
	shell.call("_show_room_from_state")
	assert(shell.current_room == previous_room)
	shell.call("_show_return_trainer_dialogue", trainer, "stale trainer dialogue", {}, previous_room, trainer_room.id)
	assert(shell.interaction_dialog == null, "Seal callbacks must not show old dialogue in a reused destination room")
	await create_timer(3.0).timeout
	assert(shell.interaction_dialog == null, "Third-key tutorial must not follow the player into another room")
	shell.queue_free()
	await process_frame
	runtime.session = null
	print("PASS: source floor-10 Sage text, first victory dialogue, optional rematch and 2/3 vs 3/3 wording")
	quit(0)
