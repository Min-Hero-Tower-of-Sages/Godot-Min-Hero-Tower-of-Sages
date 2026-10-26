extends SceneTree

class MemoryRepository extends SaveRepository:
	var payload: Dictionary = {}
	var reject := false
	func load_slot(_slot: int) -> Dictionary:
		return {"ok": false, "code": "not_found"} if payload.is_empty() else {"ok": true, "state": payload.duplicate(true)}
	func save_slot(_slot: int, data: Dictionary) -> Dictionary:
		if reject: return {"ok": false, "message": "Rejected fixture save"}
		payload = data.duplicate(true)
		return {"ok": true}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var catalog: ContentCatalog = root.get_node("CampaignRuntime").catalog
	assert(catalog.ensure_index().is_empty())
	var session := CampaignSession.new()
	session.catalog = catalog
	var repository := MemoryRepository.new()
	session.save_repository = repository
	assert(session.start_new(&"base:campaign/standard_tower", CampaignProgressionService.starter_party(catalog, "new-report-")).ok)
	var pool := {"candidates": ["base:minion/grasssnake_1", "base:minion/grassgorilla_1"], "weights": [60, 40]}
	assert(CampaignModService.egg_pool(session.state, 0, pool) == pool)
	session.state.active_mods.starter_eggs = true
	var expanded := CampaignModService.egg_pool(session.state, 0, pool)
	assert(expanded.weights == [48, 32, 10, 10] and expanded.candidates.size() == 4)
	assert(pool.weights == [60, 40] and pool.candidates.size() == 2, "Do not mutate shared hatchery data")
	assert(CampaignModService.egg_pool(session.state, 1, pool) == pool, "Other floors keep their existing pool")
	assert(CampaignModService.normalize({"starter_eggs": true}).starter_eggs)
	assert(CampaignModService.option_index("starter_eggs") >= 0)
	assert(not session.make_current_minions_shiny().ok, "Debug gate applies to actions too")
	session.state.active_mods.debug_mode = true
	var stored: OwnedMinionState = session.state.party[0].duplicate_state()
	stored.instance_id = &"stored-minion"
	session.state.storage.append(stored)
	var before: Dictionary = session.state.to_dictionary(catalog.content_version, true)
	repository.reject = true
	assert(not session.make_current_minions_shiny().ok)
	assert(session.state.to_dictionary(catalog.content_version, true) == before, "Rejected save changes no live appearances")
	repository.reject = false
	session.state.pending_battle = {"fixture": true}
	assert(not session.make_current_minions_shiny().ok)
	session.state.pending_battle.clear()
	var changed := session.make_current_minions_shiny()
	assert(changed.ok and changed.changed_count == 3)
	for member in session.state.party + session.state.storage:
		assert(member.is_shiny and not member.shiny_line_id.is_empty())
	assert(session.make_current_minions_shiny().changed_count == 0)
	assert(session.load(1).ok and session.state.storage[0].is_shiny)
	var later := OwnedMinionState.new()
	later.definition_id = &"base:minion/tiger_1"
	CampaignShinyService.initialize_new(later, session.state, catalog, 511)
	assert(not later.is_shiny, "One-time action does not turn on guaranteed future shinies")
	var settings := CampaignSettingsView.new()
	root.add_child(settings)
	settings.configure(CampaignSettingsService.new(), session)
	settings._open_debug()
	assert(settings.find_child("MakeCurrentMinionsShiny", true, false) != null)
	if DisplayServer.get_name() != "headless":
		await process_frame
		var description := settings.find_child("DebugDescription", true, false) as Label
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/current-shinies-debug-preview.png")
		assert(description.get_visible_line_count() == description.get_line_count(), "Debug explanation fits")
	settings.queue_free()
	await process_frame
	session.state.active_mods.clear()
	session.state.progression.unlocked_floor_indices = [0, 3, 8, 13, 18]
	for floor_index in [3, 8, 13, 18]:
		session.state.progression.floor_keys = 9
		session.state.progression.eggery_keys = 8
		session.state.progression.boss_door_unlocked = true
		session.state.progression.eggery_door_unlocked = true
		assert(session.enter_tower_lobby().ok)
		assert(session.select_tower_floor(floor_index).ok)
		assert(session.state.progression.floor_keys == 0 and session.state.progression.eggery_keys == 0)
		assert(not session.state.progression.boss_door_unlocked and not session.state.progression.eggery_door_unlocked)
		var data := CampaignTowerModeService.mode_floor_data(session.campaign, floor_index, &"standard")
		var fights := 0
		for room_id in data.room_ids:
			var room := catalog.get_definition(StringName(room_id)) as RoomDefinition
			for interaction in room.interactions:
				if interaction.kind == &"trainer" and session._route_is_available(interaction): fights += 1
		assert(fights == 4, "Every bonus floor has three regular fights and one hatchery boss")
	var regular := catalog.get_definition(&"base:room/level_1_4_d") as RoomDefinition
	var boss := catalog.get_definition(&"base:room/level_1_4_f") as RoomDefinition
	var empty := catalog.get_definition(&"base:room/level_1_4_e") as RoomDefinition
	assert(regular.minimap_metadata.room_index == 3 and boss.minimap_metadata.room_index == 6 and empty.minimap_metadata.room_index == 7)
	assert(regular.encounter_ids == [&"base:encounter/grass_floor4_trainer_3"])
	assert(empty.encounter_ids.is_empty())
	assert(session.enter_tower_lobby().ok and session.select_tower_floor(3).ok)
	for room in [regular, boss]:
		session.state.current_room_id = room.id
		var trainer: Dictionary = room.interactions.filter(func(item: Dictionary) -> bool: return item.kind == &"trainer")[0]
		var view := CampaignRoomView.new()
		root.add_child(view)
		view.configure(room, room.spawn_ids[0], room.spawn_positions[String(room.spawn_ids[0])], {}, {"progression": session.state.progression, "tower_mode": "standard"})
		view.set_physics_process(false)
		var triggers: Array = view._room_interactions.filter(func(item: Dictionary) -> bool: return item.id == trainer.id)
		assert(triggers.size() == 1)
		var trigger: Dictionary = triggers[0]
		view._player.position = trigger._zone_center - view.PLAYER_COLLISION_TOP_LEFT - view.PLAYER_COLLISION_SIZE * 0.5
		view._refresh_nearby_interactions(false)
		assert(view._nearby_interactions.any(func(item: Dictionary) -> bool: return item.interaction.id == trainer.id), "Standing by the visible NPC makes it interactable")
		var dialogue := session.interact(trainer.id)
		assert(dialogue.ok and not dialogue.dialog_text.is_empty())
		assert(session.prepare_battle(trainer.encounter_id).ok)
		assert(session.cancel_pending_battle().ok)
		view.queue_free()
		await process_frame
	var egg_door: Dictionary = boss.interactions.filter(func(item: Dictionary) -> bool: return item.kind == &"unlock_eggery_door")[0]
	assert(session.interact(egg_door.id).kind == &"door_locked")
	var boss_encounter := catalog.get_definition(&"base:encounter/grass_floor4_trainer_6_boss") as EncounterDefinition
	var award := CampaignProgressionService._grant_first_clear_rewards(session.state, boss_encounter)
	assert(award.eggery_keys == 1 and session.state.progression.eggery_keys == 1)
	assert(session.interact(egg_door.id).kind == &"door_unlocked" and session.state.progression.eggery_keys == 0)
	# Replenishment is explicitly a debug effect, not a floor-reset leak.
	session.state.active_mods.debug_mode = true
	assert(session.set_debug_option("full_keys", true).ok)
	assert(session.enter_tower_lobby().ok and session.select_tower_floor(3).ok)
	assert(session.state.progression.floor_keys == 3 and session.state.progression.eggery_keys == 1)
	assert(session.set_debug_option("full_keys", false).ok)
	assert(session.enter_tower_lobby().ok and session.select_tower_floor(3).ok)
	assert(session.state.progression.floor_keys == 0 and session.state.progression.eggery_keys == 0)
	print("PASS: starter egg opt-in, saved/atomic/gated current shinies, bonus-floor resets, Floor 1-4 visible trainer contacts/dialogue/battle preparation and earned hatchery key")
	quit()
