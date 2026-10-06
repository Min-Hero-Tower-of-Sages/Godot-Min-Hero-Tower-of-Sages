extends SceneTree

class MemorySession extends CampaignSession:
	var reject_save := false
	func _save_candidate(_candidate) -> Dictionary:
		return {"ok": not reject_save}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var catalog: ContentCatalog = root.get_node("CampaignRuntime").catalog
	var campaign := catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
	var door_count := 0
	var corrected_hallways := 0
	for floor_data in campaign.floors:
		for room_id in floor_data.room_ids:
			var room := catalog.get_definition(StringName(room_id)) as RoomDefinition
			var door_sprites: Array[String] = []
			for attributes in room.payload.objects:
				if String(attributes.get("spriteName", "")) in ["regularDoor", "regularDoor_eggery"]: door_sprites.append(String(attributes.spriteName))
			if door_sprites.is_empty():
				for exit_data in room.exits:
					assert(String(exit_data.get("requires_progression_flag", "")) not in ["boss_door_unlocked", "eggery_door_unlocked"], "Door-free hallway must not retain a misplaced door gate")
				corrected_hallways += 1
				continue
			for door_sprite in door_sprites:
				var eggery := door_sprite == "regularDoor_eggery"
				var kind := &"unlock_eggery_door" if eggery else &"unlock_boss_door"
				var door_kind := &"eggery" if eggery else &"boss"
				var flag := "eggery_door_unlocked" if eggery else "boss_door_unlocked"
				var interactions := room.interactions.filter(func(item: Dictionary) -> bool: return StringName(item.get("kind", "")) == kind)
				assert(interactions.size() == 1 and int(interactions[0].source_zone_id) == 2)
				var guarded := room.exits.filter(func(item: Dictionary) -> bool: return String(item.get("requires_progression_flag", "")) == flag)
				assert(guarded.size() == 1, "Expected one source-gated exit for %s/%s, found %s" % [room.id, door_kind, room.exits])
				var session := MemorySession.new()
				session.catalog = catalog
				session.campaign = campaign
				session.state = CampaignState.new()
				session.state.campaign_id = campaign.id
				session.state.current_room_id = room.id
				session.state.progression = {"floor_index": int(floor_data.floor_index), "floor_keys": 0, "eggery_keys": 0, "eggery_picks_remaining": 1}
				assert(session.interact(StringName(interactions[0].id)).kind == &"door_locked")
				assert(not session.enter_room(StringName(guarded[0].target_room_id), int(guarded[0].transition_id)).ok)
				var view := CampaignRoomView.new()
				root.add_child(view)
				view.set_physics_process(false)
				assert(view.configure(room, room.spawn_ids[0], room.spawn_positions[String(room.spawn_ids[0])], {}, {"progression": session.state.progression, "tower_mode": "standard"}))
				view.set_physics_process(false)
				var contacts: Array[Dictionary] = []
				view.interaction_requested.connect(func(item: Dictionary) -> void: contacts.append(item))
				var contact: Dictionary = view._room_interactions.filter(func(item: Dictionary) -> bool: return StringName(item.get("kind", "")) == kind)[0]
				view._player.position = contact._zone_center - view.PLAYER_COLLISION_TOP_LEFT - view.PLAYER_COLLISION_SIZE * 0.5
				var space := InputEventKey.new()
				space.pressed = true
				space.keycode = KEY_SPACE
				view._unhandled_input(space)
				assert(contacts.any(func(item: Dictionary) -> bool: return item.id == interactions[0].id), "Space must reach the actual source door contact")
				var shapes := view._collision.get_children().filter(func(node: Node) -> bool: return node is CollisionShape2D and StringName(node.get_meta("door_kind", "")) == door_kind)
				assert(shapes.size() == 1 and not shapes[0].disabled)
				session.state.progression.floor_keys = 3
				session.state.progression.eggery_keys = 1 if eggery else 0
				var before: Dictionary = session.state.to_dictionary()
				session.reject_save = true
				assert(not session.interact(StringName(interactions[0].id)).ok and session.state.to_dictionary() == before)
				session.reject_save = false
				assert(session.interact(StringName(interactions[0].id)).kind == &"door_unlocked")
				assert(int(session.state.progression.floor_keys) == 0)
				if eggery: assert(int(session.state.progression.eggery_keys) == 0)
				view._campaign_context["progression"] = session.state.progression
				view.animate_source_door_unlock(door_kind)
				await process_frame
				assert(shapes[0].disabled)
				var transitions: Array[Dictionary] = []
				view.transition_requested.connect(func(exit_data: Dictionary) -> void: transitions.append(exit_data))
				view._on_transition_entered(view._player, guarded[0])
				assert(transitions.size() == 1, "Unlocked source portal must work without room reconstruction")
				assert(session.enter_room(StringName(guarded[0].target_room_id), int(guarded[0].transition_id)).ok)
				view.queue_free()
				await process_frame
				door_count += 1
	assert(door_count == 48, "All 24 standard non-Gym floors must have their two source doors")
	var presenter := BattleRewardPresenter.new()
	root.add_child(presenter)
	for kind in ["TrainerType.HARD_TRAINER", "TrainerType.EXPERT_TRAINER"]:
		var items := presenter._source_reward_items({"source_trainer_type": kind, "money": 50.0, "eggery_keys": 1, "gems": [{}]})
		assert(items.size() == 2 and items[0].kind == "key" and items[1].kind == "gem")
	var boss_items := presenter._source_reward_items({"source_trainer_type": "TrainerType.BOSS_TRAINER", "money": 50.0, "eggery_keys": 1, "sage_seal_pieces": 1})
	assert(boss_items.size() == 2 and boss_items[0].kind == "seal" and boss_items[1].kind == "key" and is_equal_approx(float(boss_items[1].start_after), 1.9))
	assert(presenter._source_reward_items({"source_trainer_type": "TrainerType.TRAINER_GYM_1", "money": 50.0, "sage_seals": 1}).is_empty())
	presenter.queue_free()
	await process_frame
	print("PASS: %d authored floor-1–30 doors, Space contact, locked/unlocked portals, save rejection, key consumption and money-upgrade-safe gem/seal pickups (%d door-free rooms)" % [door_count, corrected_hallways])
	quit(0)
