extends SceneTree

class MemorySession extends CampaignSession:
	func _save_candidate(_candidate) -> Dictionary:
		return {"ok": true}

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var catalog: ContentCatalog = root.get_node("CampaignRuntime").catalog
	var campaign := catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
	_check(catalog.ensure_index().is_empty(), "catalog loads")
	var room_count := 0
	var portal_count := 0
	var heal_count := 0
	for definition in catalog._by_id.values():
		if not definition is RoomDefinition or definition.payload == null: continue
		var room := definition as RoomDefinition
		var heal_zones := 0
		var has_heal := false
		for attributes in room.payload.objects:
			var sprite := String(attributes.get("spriteName", ""))
			if sprite == "generalRoom_healStone": has_heal = true
			if sprite == "buttonZoneObject1": heal_zones += 1
			if not sprite.begins_with("teleport_roomTransitionObject") and not sprite.begins_with("telport_roomTransitionObject"): continue
			var suffix := sprite.trim_prefix("teleport_roomTransitionObject").trim_prefix("telport_roomTransitionObject")
			if not suffix.is_valid_int(): continue
			var transition := int(suffix)
			_check(room.exits.any(func(route: Dictionary) -> bool: return int(route.get("transition_id", -1)) == transition), "%s portal %d has a route" % [room.id, transition])
			portal_count += 1
		if has_heal and heal_zones > 0:
			_check(room.interactions.filter(func(item: Dictionary) -> bool: return StringName(item.get("kind", "")) == &"heal_party").size() == heal_zones, "%s retains every heal contact" % room.id)
			heal_count += heal_zones
		room_count += 1
	for room_id in [&"base:room/level_2_2_h2", &"base:room/level_2_3_h2", &"base:room/level_2_4_h2"]:
		var room := catalog.get_definition(room_id) as RoomDefinition
		if room == null:
			_check(false, "reported room exists: %s" % room_id)
			continue
		var view := CampaignRoomView.new()
		root.add_child(view)
		view.configure(room, room.spawn_ids[0], room.spawn_positions[String(room.spawn_ids[0])], {}, {"progression": {"floor_index": 6}, "tower_mode": "standard"})
		view.set_physics_process(false)
		var session := _session(catalog, campaign, room.id, 6)
		var owned := OwnedMinionState.new()
		owned.instance_id = &"checkpoint-owned"
		owned.definition_id = &"base:minion/fire_pig_1"
		owned.level = 5
		owned.persistent_health = 1
		owned.persistent_energy = 0
		session.state.party.append(owned)
		var contacts: Array[Dictionary] = []
		view.interaction_requested.connect(func(item: Dictionary) -> void: contacts.append(item))
		for interaction in view._room_interactions.duplicate():
			if StringName(interaction.kind) != &"heal_party": continue
			view._automatic_contact_ids.clear()
			view._player.position = interaction._zone_center - view.PLAYER_COLLISION_TOP_LEFT - view.PLAYER_COLLISION_SIZE * 0.5
			view._refresh_nearby_interactions()
			_check(not contacts.is_empty() and contacts.back().id == interaction.id, "walking into heal zone activates it")
			var result := session.interact(interaction.id, view.player_position(), room.spawn_ids[0])
			_check(result.ok and session.state.safe_location.get("room_id", "") == String(room.id), "heal contact records death checkpoint")
			_check(session.state.party[0].persistent_health > 1 and session.state.party[0].persistent_energy > 0, "heal contact restores health and energy")
		view.queue_free()
		await process_frame
	var hard := _session(catalog, campaign, &"base:room/level_1_1_h2", 31)
	var boss_room := catalog.get_definition(hard.state.current_room_id) as RoomDefinition
	var boss: Dictionary = boss_room.interactions.filter(func(item: Dictionary) -> bool: return item.kind == &"unlock_boss_door")[0]
	hard.state.progression.floor_keys = 3
	_check(hard.interact(boss.id).kind == &"door_already_open" and hard.state.progression.floor_keys == 3, "hard boss door never consumes keys")
	var boss_route: Dictionary = boss_room.exits.filter(func(item: Dictionary) -> bool: return item.get("requires_progression_flag", "") == "boss_door_unlocked")[0]
	_check(hard.enter_room(boss_route.target_room_id, boss_route.transition_id).ok, "hard boss portal works with legacy false flag")
	hard.state.current_room_id = &"base:room/level_1_1_e"
	var egg_room := catalog.get_definition(hard.state.current_room_id) as RoomDefinition
	var egg: Dictionary = egg_room.interactions.filter(func(item: Dictionary) -> bool: return item.kind == &"unlock_eggery_door")[0]
	for ring in [[0, 3], [2, 3], [3, 0], [3, 1], [3, 2]]:
		hard.state.progression.floor_keys = ring[0]
		hard.state.progression.eggery_keys = ring[1]
		_check(hard.interact(egg.id).kind == &"door_locked" and hard.state.progression.floor_keys == ring[0] and hard.state.progression.eggery_keys == ring[1], "hatchery rejects incomplete hard key rings")
	hard.state.progression.floor_keys = 3
	hard.state.progression.eggery_keys = 3
	_check(hard.interact(egg.id).kind == &"door_unlocked" and hard.state.progression.floor_keys == 0 and hard.state.progression.eggery_keys == 0, "six keys open hard hatchery")
	hard.state.progression.eggery_door_unlocked = false
	hard.state.progression.boss_door_unlocked = true
	hard.state.progression.erase("hard_door_keys_version")
	var earned := 0
	for encounter in CampaignTowerModeService.hard_encounters_for_floor(catalog, 31):
		if int(encounter.rewards.get("first_clear", {}).get("floor_keys", 0)) > 0:
			hard.state.progression.completed_encounters[String(encounter.id)] = true
			earned += int(encounter.rewards.first_clear.floor_keys)
	_check(hard._repair_hard_door_keys(hard.state) and hard.state.progression.floor_keys == earned, "old hard save recovers ring consumed at first door")
	_check(not hard._repair_hard_door_keys(hard.state) and hard.state.progression.floor_keys == earned, "key recovery happens only once")
	for index in [4, 5]:
		var encounter := catalog.get_definition(StringName("base:encounter/floor32_trainer_%d_%s" % [index, "hard" if index == 4 else "expert"])) as EncounterDefinition
		_check(encounter != null and preload("res://src/application/source_trainer_dialogue.gd").for_encounter(encounter).get("first_visit_text", "") == "In Hard Mode, we must fight!", "extra hard fights have dialogue")
	var result := BattleResult.new()
	var state := CampaignState.new()
	for index in 5:
		var owned := OwnedMinionState.new()
		owned.instance_id = StringName("owned-%d" % index)
		state.party.append(owned)
		result.participants.append({"team": 0, "slot_index": index, "instance_id": String(owned.instance_id), "retired": index < 2, "remaining_health": 0 if index < 2 else 10})
	result.participants.append({"team": 0, "slot_index": 0, "instance_id": "replacement-0", "remaining_health": 10})
	result.participants.append({"team": 0, "slot_index": 1, "instance_id": "replacement-1", "remaining_health": 0})
	_check(CampaignProgressionService._battle_star_rating(state, result) == 3, "four surviving slots including replacement earn three stars")
	result.participants.back().remaining_health = 10
	result.participants[5].remaining_health = 0
	result.participants[2].remaining_health = 0
	_check(CampaignProgressionService._battle_star_rating(state, result) == 2, "two dead active slots earn two stars")
	await _check_battle_ui(catalog)
	for failure in failures: push_error(failure)
	print("%s: October 14 player report (%d checks; %d rooms, %d portals, %d heal zones)" % ["PASS" if failures.is_empty() else "FAIL", checks, room_count, portal_count, heal_count])
	quit(0 if failures.is_empty() else 1)

func _session(catalog: ContentCatalog, campaign: CampaignDefinition, room_id: StringName, floor_index: int) -> MemorySession:
	var session := MemorySession.new()
	session.catalog = catalog
	session.campaign = campaign
	session.state = CampaignState.new()
	session.state.campaign_id = campaign.id
	session.state.current_room_id = room_id
	session.state.progression.floor_index = floor_index
	return session

func _check_battle_ui(catalog: ContentCatalog) -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	if not main.has_method("_start_battle"):
		_check(false, "battle presentation script loads")
		main.free()
		return
	root.add_child(main)
	await main._start_battle()
	var actor_id := StringName(main.controller.engine.get_decision().actor_id)
	var actor: CombatantState = main.controller.engine._state.combatants[actor_id]
	actor.move_ids.clear()
	for definition in catalog._by_id.values():
		if definition is MoveDefinition and definition.available and not definition.is_passive and not definition.is_global_passive and definition.target_side == MoveDefinition.TargetSide.ENEMY:
			actor.move_ids.append(definition.id)
			if actor.move_ids.size() == 25: break
	actor.energy = 10000
	main.catalog = catalog
	for view in main.combatant_views.values():
		if view.instance_id == actor_id: view.state_cache = actor.to_dict()
	main._build_move_buttons(main.controller.engine.get_decision())
	var first_ids: Array[StringName] = []
	var positions: Array[Vector2] = []
	for button in main.move_buttons.get_children():
		if not button is Button or not button.has_meta("move_id"): continue
		first_ids.append(button.get_meta("move_id"))
		var position: Vector2 = button.get_meta("selector_final_position")
		_check(position not in positions, "extra moves have distinct positions")
		positions.append(position)
	_check(first_ids.size() == 16, "first skill page contains 16 moves")
	if DisplayServer.get_name() != "headless":
		await create_timer(2.8).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/player-report-20261014/expanded_moves.png")
	main._change_move_page(1)
	var second_ids: Array[StringName] = []
	for button in main.move_buttons.get_children():
		if button is Button and button.has_meta("move_id"): second_ids.append(button.get_meta("move_id"))
	_check(second_ids.size() == 9 and first_ids + second_ids == actor.move_ids, "all 25 moves remain selectable across pages")
	var selected := main.combatant_views[String(actor_id)] as BattleCombatantView
	_check(not selected.selected_indicator.z_as_relative and selected.selected_indicator.z_index > 700, "target marker draws above focused minions")
	main._show_resurrection_tombstone(actor_id, 3)
	var tomb: Node2D = main.resurrection_tombstones[String(actor_id)].root
	_check(not tomb.z_as_relative and tomb.z_index > 700, "gravestone draws above minions and arena")
	main._create_move_timer_visuals({"move_id": &"base:move/burn/tier1", "buff_move_id": &"base:move/agile_inspiration/tier1"})
	var icon := main.battle_modifier_layer.get_node("MoveTimerModVisuals/TimerMoveIcon") as Sprite2D
	_check((icon.position - icon.texture.get_size() * 0.4).is_equal_approx(Vector2(308, -12)), "timer icon retains source top-left placement")
	main.queue_free()
	await process_frame

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
