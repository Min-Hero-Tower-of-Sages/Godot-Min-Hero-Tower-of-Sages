extends SceneTree

# Real room and shell integration, with no writes to player saves.
class MemorySession extends CampaignSession:
	var saved_states: Array[Dictionary] = []
	func _save_candidate(candidate) -> Dictionary:
		saved_states.append(candidate.to_dictionary(catalog.content_version))
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
	session.state.current_room_id = &"base:room/level_1_1_eggery"
	session.state.character = {"name": "Hatchery fixture", "gender": "male"}
	session.state.progression = {"floor_index": 0, "eggery_picks_remaining": 3, "eggery_taken_slots": []}
	var definition := runtime.catalog.get_definition(&"base:minion/fire_pig_1") as MinionDefinition
	for index in 5:
		var owned := OwnedMinionState.new()
		owned.instance_id = StringName("hatchery-fixture-%d" % index)
		owned.definition_id = definition.id
		owned.level = 5
		owned.experience = 5000
		owned.learned_move_ids.assign(definition.initial_move_ids)
		session.state.party.append(owned)
	runtime.session = session
	var shell := (load("res://scenes/application_shell.tscn") as PackedScene).instantiate()
	root.add_child(shell)
	shell.call("_show_room_from_state")
	await process_frame
	var room: CampaignRoomView = shell.current_room
	var exit_blockade: CollisionShape2D
	var lobby_exit: Dictionary
	for shape in room._collision.get_children():
		if bool(shape.get_meta("eggery_exit_blockade", false)):
			exit_blockade = shape
	for transition in room._room_transitions:
		if String(transition.exit.get("target_route", "")) == "lobby":
			lobby_exit = transition
	assert(exit_blockade != null and not exit_blockade.disabled, "Hatchery must require an egg choice before leaving")
	assert(not lobby_exit.is_empty(), "Source hatchery-to-lobby portal must be registered")
	shell.call("_on_room_interaction_requested", {"kind": &"eggery_exit_blocked"})
	await process_frame
	assert(shell._source_dialogue_label.text == "You still need to choose an egg!")
	shell.call("_clear_dialog")
	assert(room._egg_sprites_by_slot.size() == 9, "All nine eggs must render using the recovered shared egg bitmap")
	assert(room.call("_art_texture_name", "eggery_eggPit_front") == "eggery_eggPit_front")
	assert(room.call("_art_texture_name", "eggery_eggPit_back") == "eggery_eggPit_back")
	var nest_count := 0
	for sprite in room._art.get_children():
		if sprite is Sprite2D and sprite.texture != null and (sprite.texture.resource_path.ends_with("eggery_eggPit_front.png") or sprite.texture.resource_path.ends_with("eggery_eggPit_back.png")):
			nest_count += 1
	assert(nest_count == 18, "Nine authored nests must retain their front/back bitmap pieces")
	var source_objects: Array = room.room.ensure_payload().objects
	var fireplace_count := 0
	for source_index in source_objects.size():
		var attributes: Dictionary = source_objects[source_index]
		var symbol := String(attributes.get("spriteName", ""))
		if symbol.begins_with("eggery_egg"):
			var rendered := room._art.get_node("SourceObject_%03d" % source_index) as Sprite2D
			assert(rendered.position.is_equal_approx(Vector2(float(attributes.xPos), float(attributes.yPos))), "Nest/egg positions must come from the authored room, not a generated grid")
		if symbol == "eggery_fireplace":
			fireplace_count += 1
			var fire := room._art.get_node("SourceAnimation_%03d" % source_index) as AnimatedSprite2D
			assert(fire.is_playing() and fire.sprite_frames.get_frame_count(&"default") == 7)
			assert(fire.sprite_frames.get_animation_speed(&"default") == 15.0)
	assert(fireplace_count > 0, "Fixture must cover the formerly missing fireplace loop")
	var pick := session._pick_egg(room.room.interactions[0])
	assert(pick.ok and session.state.storage.is_empty(), "Egg must remain an unowned preview before acceptance")
	shell.call("_show_egg_reveal", pick, 0)
	await process_frame
	await process_frame
	assert(shell.interaction_dialog.get_node_or_null("HatcheryMinionDetails") != null, "Details must appear during the initial dialogue, not after closing it")
	assert(shell._source_dialogue_label.text == "This egg contains a %s. Would you like to keep it?" % pick.definition.display_name)
	while shell.call("_source_dialogue_can_scroll"):
		shell.call("_advance_source_dialogue")
		await create_timer(0.4).timeout
	assert(shell._source_dialogue_choices.size() == 2, "Full-party previews must offer keep/decline before party replacement")
	shell.call("_accept_egg_preview", pick, 0)
	await create_timer(0.3).timeout
	assert(shell._source_dialogue_label.text == "Would you like to add %s to your party?" % pick.definition.display_name)
	var outgoing_id: StringName = session.state.party[2].instance_id
	# Calling the integrated handler checks the formerly broken storage lookup.
	shell.call("_swap_egg_into_party", 2, pick.minion.instance_id, pick.definition.display_name, "outgoing", 0)
	await process_frame
	assert(session.state.party[2].instance_id == pick.minion.instance_id)
	assert(session.state.storage.size() == 1 and session.state.storage[0].instance_id == outgoing_id)
	assert(session.state.progression.eggery_picks_remaining == 0)
	await create_timer(0.55).timeout
	assert(shell._source_dialogue_label.text == "outgoing has been sent to storage", "Replacement must show the original storage confirmation")
	while shell.call("_source_dialogue_can_scroll"):
		shell.call("_advance_source_dialogue")
		await create_timer(0.4).timeout
	shell.call("_advance_source_dialogue")
	await create_timer(0.3).timeout
	assert(room._controls_enabled, "Movement resumes while eggs sink after the storage confirmation")
	assert(exit_blockade.disabled, "Finishing the egg choice must unlock the live hatchery exit without rebuilding")
	assert(room._sinking_egg_slots.size() == 9)
	assert(room.sink_egg(0) == null, "An already sinking egg must not start a second tween")
	for interaction in room._room_interactions:
		assert(StringName(interaction.get("kind", "")) != &"egg_pick", "Sinking eggs cannot remain interactive")
	assert(session.saved_states.size() == 2, "Preview and acceptance each persist once; acceptance includes pedia atomically")
	var tooltip := BattleMoveTooltip.new()
	root.add_child(tooltip)
	tooltip.show_move(runtime.catalog.get_definition(&"base:move/agility/tier1") as MoveDefinition)
	assert(tooltip.details.get_parsed_text().contains("speed by 15%"), "Passive talent descriptions must name the stat and percentage")
	for tween in get_processed_tweens():
		tween.custom_step(6.0)
	await process_frame
	assert(shell.current_room == room, "Egg animation completion must not rebuild the room")
	# Complete the actual authored exit, using the normal application routing.
	shell.call("_complete_room_transition", lobby_exit.exit)
	assert(session.state.current_room_id == &"base:room/main_tower_lobby")
	assert(shell.current_room.room.id == &"base:room/main_tower_lobby")
	assert(String(session.state.safe_location.spawn_id) == "lobby_from_eggery")
	var hatchery_count := 0
	for candidate in runtime.catalog._by_id.values():
		if not candidate is RoomDefinition or not String(candidate.id).contains("eggery"):
			continue
		hatchery_count += 1
		var restored := CampaignRoomView.new()
		root.add_child(restored)
		assert(restored.configure(candidate, candidate.spawn_ids[0], Vector2.INF, {}, {"progression": {"eggery_picks_remaining": 0, "floor_index": candidate.minimap_metadata.floor_index}}))
		restored.set_physics_process(false)
		for shape in restored._collision.get_children():
			assert(not bool(shape.get_meta("eggery_exit_blockade", false)), "Reloaded completed hatcheries must not recreate the exit wall")
		var has_lobby_route := false
		for transition in restored._room_transitions:
			has_lobby_route = has_lobby_route or String(transition.exit.get("target_route", "")) == "lobby"
		assert(has_lobby_route, "Every floor-10-slice hatchery needs its actual lobby portal")
		restored.queue_free()
		await process_frame
	assert(hatchery_count == 8)
	print("PASS: authored hatchery eggs/nests, simultaneous dialogue/card, keep/party flow, atomic replacement, movement and stat tooltip")
	tooltip.queue_free()
	shell.queue_free()
	await process_frame
	runtime.session = null
	quit(0)
