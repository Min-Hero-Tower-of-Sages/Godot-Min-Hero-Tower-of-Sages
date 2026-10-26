extends SceneTree

class MemoryRepository extends SaveRepository:
	var payload: Dictionary = {}
	func save_slot(_slot: int, data: Dictionary) -> Dictionary:
		payload = data.duplicate(true)
		return {"ok": true}
	func load_slot(_slot: int) -> Dictionary:
		return {"ok": false, "code": "not_found"} if payload.is_empty() else {"ok": true, "state": payload.duplicate(true)}

var session: CampaignSession
var catalog: ContentCatalog

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var runtime := root.get_node("CampaignRuntime")
	catalog = runtime.catalog
	assert(catalog.ensure_index().is_empty())
	session = CampaignSession.new()
	session.catalog = catalog
	session.save_repository = MemoryRepository.new()
	assert(session.start_new(&"base:campaign/standard_tower", CampaignProgressionService.starter_party(catalog, "oct26-")).ok)
	session.state.progression.unlocked_floor_indices = [0, 3, 20]
	assert(session.enter_tower_lobby().ok and session.select_tower_floor(3).ok)
	assert(not CampaignDebugService.enabled(session.state, "full_keys"))
	# Earn the displayed three keys from actual trainer settlements, not from
	# directly assigning a key counter (which hid the previous wrong-room bug).
	for suffix in ["a", "b", "d"]:
		var room := catalog.get_definition(StringName("base:room/level_1_4_%s" % suffix)) as RoomDefinition
		var trainer := _trainer(room)
		var encounter := catalog.get_definition(trainer.encounter_id) as EncounterDefinition
		assert(encounter.source_trainer_type == &"TrainerType.NORMAL_TRAINER")
		_win(room, trainer)
	assert(session.state.progression.floor_keys == 3 and session.state.progression.eggery_keys == 0)
	var door_room := catalog.get_definition(&"base:room/level_1_4_h2") as RoomDefinition
	session.state.current_room_id = door_room.id
	var door: Dictionary = door_room.interactions.filter(func(i: Dictionary) -> bool: return i.kind == &"unlock_boss_door")[0]
	assert(session.interact(door.id).kind == &"door_unlocked")
	assert(session.state.progression.floor_keys == 0 and session.state.progression.boss_door_unlocked)
	var gate: Dictionary = door_room.exits.filter(func(i: Dictionary) -> bool: return i.get("requires_progression_flag", "") == "boss_door_unlocked")[0]
	assert(session.enter_room(gate.target_room_id, gate.transition_id).ok)
	var bonus_boss := catalog.get_definition(&"base:room/level_1_4_f") as RoomDefinition
	_win(bonus_boss, _trainer(bonus_boss))
	assert(session.state.progression.eggery_keys == 1)
	assert(session.interact(&"floor-4-eggery-door").kind == &"door_unlocked")
	var ratings: Dictionary = session.state.progression.encounter_star_ratings
	for encounter_id in ["grass_floor4_trainer_1", "grass_floor4_trainer_2", "grass_floor4_trainer_3", "grass_floor4_trainer_6_boss"]:
		assert(int(ratings.get("base:encounter/" + encounter_id, 0)) == 3, "All four normal-mode fights can award three stars")

	# Both omitted expert slots shifted every later source minimap identity.
	for floor_index in [20, 21]:
		assert(session.enter_tower_lobby().ok and session.select_tower_floor(floor_index).ok)
		var graph: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/base/campaigns/floor_%d_room_graph.json" % (floor_index + 1)))
		for index in graph.source_room_order.size():
			var indexed := catalog.get_definition(StringName(graph.source_room_order[index])) as RoomDefinition
			assert(indexed.minimap_metadata.room_index == index)
		var prefix := "base:room/level_5_%d_" % (floor_index - 19)
		var boss := catalog.get_definition(StringName(prefix + ("f" if floor_index == 20 else "d"))) as RoomDefinition
		assert(boss.minimap_metadata.room_index == 6)
		var trainer := _trainer(boss)
		var boss_encounter := catalog.get_definition(trainer.encounter_id) as EncounterDefinition
		assert(boss_encounter.source_trainer_type == &"TrainerType.BOSS_TRAINER")
		var expert := catalog.get_definition(StringName("base:room/floor_%d_expert" % (floor_index + 1))) as RoomDefinition
		assert(expert.minimap_metadata.room_index == 5 and not session._route_is_available(_trainer(expert)))
		var expert_origin := catalog.get_definition(expert.exits[0].target_room_id) as RoomDefinition
		assert(expert_origin.exits.any(func(i: Dictionary) -> bool: return int(i.transition_id) == 99 and i.target_room_id == expert.id))
		# Exercise the visible source NPC's contact and actual dialogue.
		var view := _view(boss)
		var contact: Dictionary = view._room_interactions.filter(func(i: Dictionary) -> bool: return i.id == trainer.id)[0]
		view._player.position = contact._zone_center - view.PLAYER_COLLISION_TOP_LEFT - view.PLAYER_COLLISION_SIZE * 0.5
		view._refresh_nearby_interactions(false)
		assert(view._nearby_interactions.any(func(i: Dictionary) -> bool: return i.interaction.id == trainer.id))
		session.state.current_room_id = boss.id
		assert(not String(session.interact(trainer.id).dialog_text).is_empty())
		view.queue_free()
		_win(boss, trainer)
		assert(floor_index + 1 in session.state.progression.unlocked_floor_indices, "Real sage victory unlocks the following floor")
		assert(session.state.progression.eggery_keys == 1)
		var map := CampaignMinimapView.new()
		root.add_child(map)
		map.configure(catalog, session.state, session.campaign, true)
		assert(map._room_by_source_index[6] == boss and map._room_by_source_index[5] == expert)
		await create_timer(0.65).timeout
		assert(map._map_piece_nodes.any(func(i: Dictionary) -> bool: return int(i.room_index) == 6 and i.node.modulate.is_equal_approx(Color8(51, 153, 255))))
		map.queue_free()
	# Reload retains the newly unlocked 5-2/5-3 floors.
	assert(session.load(1).ok and 21 in session.state.progression.unlocked_floor_indices and 22 in session.state.progression.unlocked_floor_indices)

	# Use the real shell's No callback, for entrance and hatchery exit doors.
	runtime.session = session
	var shell: Control = load("res://scenes/application_shell.tscn").instantiate()
	root.add_child(shell)
	await process_frame
	shell._clear_game_screen()
	for floor_index in [1, 3, 20, 21]:
		for suffix in ["h1", "eggery"]:
			var prefix := "level_1_2_" if floor_index == 1 else "level_1_4_" if floor_index == 3 else "level_5_%d_" % (floor_index - 19)
			var room_id := StringName("base:room/%s%s" % [prefix, suffix])
			if suffix == "h1": room_id = StringName(CampaignTowerModeService.mode_floor_data(session.campaign, floor_index, &"standard").start_room_id)
			var room := catalog.get_definition(room_id) as RoomDefinition
			session.state.current_room_id = room.id
			session.state.progression.floor_index = floor_index
			var view := _view(room)
			shell.current_room = view
			view.transition_requested.connect(shell._on_room_transition_requested)
			var exit_contact: Dictionary = view._room_transitions.filter(func(t: Dictionary) -> bool: return t.exit.get("target_route", "") == "lobby")[0]
			var area := exit_contact.area as Area2D
			var rectangle := (area.get_child(0) as CollisionShape2D).shape as RectangleShape2D
			var safe := area.position - view.PLAYER_COLLISION_TOP_LEFT - view.PLAYER_COLLISION_SIZE * 0.5 + Vector2(0, rectangle.size.y * 0.5 + view.PLAYER_COLLISION_SIZE.y * 0.5 + 11)
			view._player.position = safe
			view._source_movement_tick()
			view._arrival_contact_guards.clear()
			view._player.position = area.position - view.PLAYER_COLLISION_TOP_LEFT - view.PLAYER_COLLISION_SIZE * 0.5
			view._on_transition_entered(view._player, exit_contact.exit)
			assert(view._transition_locked and not view._controls_enabled and shell._source_dialogue_no.is_valid())
			shell._source_dialogue_no.call()
			assert(view.player_position() == safe and not view._transition_locked and view._controls_enabled)
			assert(not view._transition_area_overlaps_player(area))
			# Re-entering must ask again, not silently suppress the exit.
			view._player.position = area.position - view.PLAYER_COLLISION_TOP_LEFT - view.PLAYER_COLLISION_SIZE * 0.5
			view._check_transition_contacts()
			assert(view._transition_locked and shell._source_dialogue_no.is_valid())
			shell._source_dialogue_no.call()
			view.free()
			shell.current_room = null
	# Opposing directions stop and face the last press in all four orders.
	var facing_view := _view(catalog.get_definition(&"base:room/level_1_4_h1") as RoomDefinition)
	for pair in [["left", "right"], ["right", "left"], ["up", "down"], ["down", "up"]]:
		var before := facing_view.player_position()
		for direction in pair:
			var event := InputEventAction.new()
			event.action = StringName("move_%s" % direction)
			event.pressed = true
			facing_view._input(event)
			Input.action_press(event.action)
			facing_view._source_movement_tick()
			before = facing_view.player_position() if direction == pair[0] else before
		assert(facing_view.player_facing() == StringName(pair[1]) and facing_view.player_position() == before and not facing_view._walking)
		for direction in pair: Input.action_release(StringName("move_%s" % direction))
	facing_view.free()
	shell.queue_free()
	await process_frame
	print("PASS: earned Floor 1-4 door keys, Floor 5-1/5-2 sages + unlocks + source maps, eight exit No/re-entry paths, symmetric opposing-key facing; memory saves only")
	quit()

func _trainer(room: RoomDefinition) -> Dictionary:
	return room.interactions.filter(func(i: Dictionary) -> bool: return i.kind == &"trainer")[0]

func _view(room: RoomDefinition) -> CampaignRoomView:
	var view := CampaignRoomView.new()
	root.add_child(view)
	assert(view.configure(room, room.spawn_ids[0], room.spawn_positions[String(room.spawn_ids[0])], {}, {"progression": session.state.progression, "tower_mode": "standard"}))
	view.set_physics_process(false)
	return view

func _win(room: RoomDefinition, trainer: Dictionary) -> void:
	session.state.current_room_id = room.id
	var prepared := session.prepare_battle(trainer.encounter_id)
	assert(prepared.ok)
	var result := BattleResult.new()
	result.battle_id = StringName(prepared.battle_id)
	result.winning_team = 0
	result.reason = &"victory"
	assert(session.apply_battle_result(result).ok)
