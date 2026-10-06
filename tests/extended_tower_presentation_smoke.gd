extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var catalog: ContentCatalog = root.get_node("CampaignRuntime").catalog
	var campaign := catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
	var checked_rooms := 0
	var teleports := 0
	for floor_index in [10, 12, 15, 20, 25, 29]:
		var floor_data: Dictionary = campaign.floors[floor_index]
		var room_id := StringName(floor_data.room_ids[1] if floor_data.room_ids.size() > 1 else floor_data.room_ids[0])
		var room := catalog.get_definition(room_id) as RoomDefinition
		var view := CampaignRoomView.new()
		root.add_child(view)
		var spawn_id: StringName = room.spawn_ids[0]
		assert(view.configure(room, spawn_id, room.spawn_positions[String(spawn_id)], {"name": "Rendered extension fixture", "gender": "male"}, {"progression": {"floor_index": floor_index, "eggery_picks_remaining": 1}, "tower_mode": "standard"}))
		view.set_physics_process(false)
		assert(view._art.get_child_count() > 0, "New room art is empty")
		for attributes in room.payload.objects:
			var sprite := String(attributes.get("spriteName", ""))
			if not sprite.begins_with("teleport_roomTransitionObject") and not sprite.begins_with("telport_roomTransitionObject"): continue
			var transition := int(sprite.trim_prefix("teleport_roomTransitionObject").trim_prefix("telport_roomTransitionObject"))
			var contacts := view._room_transitions.filter(func(item: Dictionary) -> bool: return int(item.exit.get("transition_id", -1)) == transition)
			assert(contacts.size() == 1 and bool(contacts[0].exit.get("source_teleport", false)), "Source teleport contact is missing")
			teleports += 1
		view.queue_free()
		await process_frame
		checked_rooms += 1
	var fusion := preload("res://src/presentation/source_sage_seal_presenter.gd").new()
	root.add_child(fusion)
	for family in range(1, 7):
		assert(fusion.play(family, null, Callable()), "Missing source Sage seal family %d" % family)
		var pieces := 0
		for child in fusion.get_children():
			if String(child.name).begins_with("SourceSealPiece"): pieces += 1
		assert(pieces == (4 if family >= 5 else 3), "Incorrect seal piece count")
		fusion.cancel()
	var fifth := catalog.get_definition(&"base:encounter/floor25_trainer_0") as EncounterDefinition
	var state := CampaignState.new()
	state.progression["sage_seals"] = 4
	var awards := CampaignProgressionService._grant_first_clear_rewards(state, fifth)
	assert(awards.sage_seals == 1 and awards.gems.size() == 1 and int(awards.gems[0].tier) == 10, "Fifth Sage bonus gem missing")
	var replay := CampaignProgressionService._grant_first_clear_rewards(state, fifth)
	assert(int(replay.sage_seals) == 0 and state.owned_gems.size() == 1, "Fifth Sage reward duplicated")
	for floor_index in [14, 19, 24, 29]:
		var room := catalog.get_definition(StringName(campaign.floors[floor_index].room_ids[0])) as RoomDefinition
		var encounter := catalog.get_definition(room.encounter_ids[0]) as EncounterDefinition
		var dialogue: Dictionary = preload("res://src/application/source_trainer_dialogue.gd").for_encounter(encounter)
		assert(not String(dialogue.get("after_win_text", "")).is_empty() and String(dialogue.get("trainer_name", "")) != "Trainer", "Later Sage dialogue/name missing")
	fusion.queue_free()
	print("PASS: %d representative later-floor rooms, %d source teleport contacts, all six seal fusions, fifth-Sage tier-10 gem/idempotence and later Sage dialogue" % [checked_rooms, teleports])
	quit()
