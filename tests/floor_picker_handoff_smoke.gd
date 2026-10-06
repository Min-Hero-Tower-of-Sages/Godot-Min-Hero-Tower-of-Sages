extends "res://tests/ten_floor_campaign_handoff_smoke.gd"

func _run() -> void:
	await process_frame
	var runtime := root.get_node("CampaignRuntime")
	var session := MemorySession.new()
	session.catalog = runtime.catalog
	session.campaign = session.catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
	session.state = CampaignState.new()
	session.state.campaign_id = session.campaign.id
	session.state.current_room_id = session.campaign.starting_room_id
	session.state.character = {"name": "Floor picker fixture", "gender": "male"}
	session.state.progression["unlocked_floor_indices"] = [0, 1, 2]
	var starter := OwnedMinionState.new()
	starter.instance_id = &"floor-picker-starter"
	starter.definition_id = &"base:minion/fire_pig_1"
	starter.level = 5
	var definition := session.catalog.get_definition(starter.definition_id) as MinionDefinition
	starter.learned_move_ids.assign(definition.initial_move_ids)
	session.state.party.append(starter)
	runtime.session = session
	var shell: Node = (load("res://scenes/application_shell.tscn") as PackedScene).instantiate()
	root.add_child(shell)
	for floor_index in [1, 2]:
		_check(session.enter_tower_lobby().ok, "Cannot enter Lobby")
		shell.call("_show_room_from_state")
		shell.call("_show_floor_picker")
		var picker: CampaignFloorSelectView = shell.interaction_dialog
		_check(not shell.current_room._controls_enabled, "Picker must block room movement")
		var before: Dictionary = session.state.to_dictionary()
		session.reject_save = true
		picker.call("_choose_floor", floor_index)
		_check(session.state.to_dictionary() == before, "Rejected floor selection changed campaign")
		session.reject_save = false
		# Reopen after the expected rejection notice, then use the actual signal.
		shell.call("_show_floor_picker")
		picker = shell.interaction_dialog
		picker.call("_choose_floor", floor_index)
		_check(int(session.state.progression.floor_index) == floor_index, "Picker did not load requested floor")
		_check(not bool(session.state.progression.in_tower_lobby), "Floor entry retained Lobby flag")
		_check(shell.interaction_dialog == null and shell.interaction_dialog_canvas == null, "Floor picker overlay survives entry")
		_check(not picker.visible and not picker.floor_selected.is_connected(Callable(shell, "_select_tower_floor")), "Retired selector still accepts input")
		_check(shell.current_room.room.id == session.state.current_room_id, "Room view did not follow selection")
		_check(shell.current_room._controls_enabled, "Floor movement stays blocked after selection")
		var committed: Dictionary = session.state.to_dictionary()
		picker.floor_selected.emit(floor_index)
		_check(session.state.to_dictionary() == committed and shell.interaction_dialog == null, "Stale selector produced another selection/notice")
		_check(session.select_tower_floor(0).get("code") == "not_in_tower_lobby", "Lobby-only selection guard was removed")
		await process_frame
	shell.queue_free()
	await process_frame
	print("%s: actual Lobby picker to Floors 2/3, overlay teardown, restored movement, stale input and rejected-save rollback" % ["PASS" if failures.is_empty() else "FAIL"])
	quit(0 if failures.is_empty() else 1)
