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
	var starter := OwnedMinionState.new()
	starter.instance_id = &"resume-starter"
	starter.definition_id = &"base:minion/fire_pig_1"
	starter.level = 5
	starter.experience = 5350
	starter.learned_move_ids.assign((session.catalog.get_definition(starter.definition_id) as MinionDefinition).initial_move_ids)
	session.state.party.append(starter)
	var trainer_room := session.catalog.get_definition(&"base:room/level_1_1_a") as RoomDefinition
	session.state.current_room_id = trainer_room.id
	session.state.safe_location = {"room_id": String(session.campaign.starting_room_id), "spawn_id": "start", "position": [111, 222]}
	runtime.session = session
	var shell := (load("res://scenes/application_shell.tscn") as PackedScene).instantiate()
	root.add_child(shell)
	shell.call("_show_room_from_state")
	var initial_spawn := trainer_room.spawn_ids[0]
	_check(shell.current_room.player_position().is_equal_approx(trainer_room.spawn_positions[String(initial_spawn)]), "Different-room checkpoint coordinates reused on resume")
	_check(StringName(shell.current_room.get_meta("spawn_id", "")) == initial_spawn, "Room arrival spawn ID not exposed")
	var checkpoint: Dictionary = session.state.safe_location.duplicate(true)
	var saved_position: Vector2 = shell.current_room.player_position() + Vector2(8, 0)
	shell.current_room._player.position = saved_position
	shell.current_room.restore_player_facing(&"left")
	shell.call("_process", 0.0)
	_check(session.state.safe_location == checkpoint, "Live exploration moved death checkpoint")
	var serialized: Variant = JSON.parse_string(JSON.stringify(session.state.to_dictionary(session.catalog.content_version)))
	session.state.load_dictionary(serialized)
	shell.call("_show_room_from_state")
	_check(shell.current_room.player_position().is_equal_approx(saved_position), "Exploration coordinates lost on JSON resume")
	_check(shell.current_room.player_facing() == &"left", "Exploration facing lost on resume")
	# Loss resets current exploration to the checkpoint, not the old battle room.
	var encounter_id: StringName = trainer_room.encounter_ids[0]
	var prepared: Dictionary = session.prepare_battle(encounter_id)
	_check(prepared.ok, "Resume fixture battle could not prepare")
	var result := BattleResult.new()
	result.battle_id = StringName(prepared.battle_id)
	result.winning_team = 1
	result.reason = &"elimination"
	_check(session.apply_battle_result(result).ok, "Loss could not settle")
	_check(int(session.state.progression.get("deaths_since_victory", 0)) == 1, "Loss counter not recorded")
	_check(session.state.room_state.current_location == session.state.safe_location, "Loss did not replace exploration resume location")
	_check(session.state.current_room_id == session.campaign.starting_room_id, "Loss did not return to checkpoint room")
	# Source contextual tips preserve priority and counter reset behavior.
	var key_room := session.catalog.get_definition(&"base:room/level_1_1_h0") as RoomDefinition
	session.state.current_room_id = key_room.id
	shell.call("_show_room_from_state")
	await create_timer(1.1).timeout
	var tutorial: Control = shell.interaction_dialog
	_check(tutorial != null and tutorial.tutorial_id == "key_keepers", "Sage-hall key-keeper guidance missing")
	_check(not shell.current_room._controls_enabled, "Room input active behind contextual guidance")
	if tutorial != null:
		tutorial._advance()
		await create_timer(0.6).timeout
	_check(shell.current_room._controls_enabled, "Key-keeper guidance did not restore room input")
	session.state.progression["floor_index"] = 9
	session.state.progression["deaths_since_victory"] = 2
	_check(CampaignProgressionService.room_tutorial_id(session.state, key_room) == "tank", "Late-floor tank tip lost source priority")
	_check(session.acknowledge_source_tutorial("tank").ok, "Tank tip acknowledgement failed")
	_check(CampaignProgressionService.room_tutorial_id(session.state, key_room) == "reset_talents_first", "Repeated-loss talent tip missing")
	_check(session.acknowledge_source_tutorial("reset_talents_first").ok and int(session.state.progression.deaths_since_victory) == 0, "First repeated-loss tip did not reset source counter")
	session.state.progression["deaths_since_victory"] = 5
	_check(CampaignProgressionService.room_tutorial_id(session.state, key_room) == "reset_talents_second", "Five-loss talent reminder missing")
	for id in ["tank", "reset_talents_first", "reset_talents_second"]:
		var view := preload("res://src/presentation/source_campaign_tutorial_view.gd").new()
		root.add_child(view)
		view.configure(session, id)
		_check(view._button != null and view._content.get_child_count() >= 4, "Context tip source art/text missing")
		view.queue_free()
		await process_frame
	shell.queue_free()
	await process_frame
	runtime.session = original_session
	print("%s: separate live/checkpoint locations, cross-room and JSON resume/facing, loss return/counter, key-keeper guidance, tank/reset priority and source artwork" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
