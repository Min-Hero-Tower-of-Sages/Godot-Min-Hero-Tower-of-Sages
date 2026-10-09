extends SceneTree

## Consolidated regression check for the older executable's player report.
## All campaign writes stay in this memory repository, never player slots.
class MemoryRepository extends SaveRepository:
	var payload: Dictionary = {}
	var reject := false
	func save_slot(_slot: int, data: Dictionary) -> Dictionary:
		if reject: return {"ok": false, "message": "Fixture rejected save"}
		payload = data.duplicate(true)
		return {"ok": true}
	func load_slot(_slot: int) -> Dictionary:
		return {"ok": false, "code": "not_found"} if payload.is_empty() else {"ok": true, "state": payload.duplicate(true)}

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
	var session := CampaignSession.new()
	session.catalog = runtime.catalog
	var repository := MemoryRepository.new()
	session.save_repository = repository
	var starter := OwnedMinionState.new()
	starter.instance_id = &"report-starter"
	starter.definition_id = &"base:minion/fire_pig_1"
	starter.level = 5
	starter.experience = 5000
	var definition := session.catalog.get_definition(starter.definition_id) as MinionDefinition
	starter.learned_move_ids.assign(definition.initial_move_ids)
	var party: Array[OwnedMinionState] = [starter]
	_check(session.start_new(&"base:campaign/standard_tower", party, {"name": "Report fixture", "gender": "male"}).ok, "Cannot create memory campaign")
	var trainer: EncounterDefinition
	var eggery: RoomDefinition
	var river_room: RoomDefinition
	for pack in session.catalog.packs:
		for item in pack.definitions:
			if item is EncounterDefinition and item.source_floor_index == 0 and item.source_trainer_type == &"TrainerType.NORMAL_TRAINER": trainer = item
			if item is RoomDefinition and String(item.id).ends_with("floor_1_eggery"): eggery = item
			if item is RoomDefinition and river_room == null:
				var layout: RoomPayloadDefinition = item.ensure_payload()
				if layout == null: continue
				for object in layout.objects:
					if String(object.get("spriteName", "")) == "sound3D_river": river_room = item
	_check(trainer != null and eggery != null, "Missing report fixture content")
	if trainer == null or eggery == null:
		quit(1)
		return
	session.state.progression.highest_beaten_floor = 1
	session.state.progression.unlocked_floor_indices = [0, 1]
	session.state.progression.completed_encounters[String(trainer.id)] = true
	session.state.progression.encounter_star_ratings[String(trainer.id)] = 3
	_check(session.enter_tower_lobby().ok and session.select_tower_floor(0).ok, "Cannot revisit Floor 1")
	_check(not session.state.progression.completed_encounters.has(String(trainer.id)), "Fresh visit retains trainer completion")
	_check(session.state.progression.encounter_star_ratings[String(trainer.id)] == 3, "Fresh visit loses permanent best stars")
	var reward := CampaignProgressionService._grant_first_clear_rewards(session.state, trainer)
	_check(int(reward.floor_keys) > 0, "Revisited trainer cannot grant a key")
	session.state.progression.completed_encounters[String(trainer.id)] = true
	_check(int(CampaignProgressionService._grant_first_clear_rewards(session.state, trainer).floor_keys) == 0, "Same-visit rematch duplicates keys")
	# Repair the old softlocked visit, once, without changing its star record.
	session.state.progression.erase("floor_visit_reward_version")
	session.state.progression.floor_keys = 0
	_check(session.save().ok and session.load(1).ok, "Cannot repair legacy visit")
	_check(not session.state.progression.completed_encounters.has(String(trainer.id)), "Legacy zero-key visit stays softlocked")
	_check(session.state.progression.encounter_star_ratings[String(trainer.id)] == 3, "Legacy repair loses stars")
	# Opening/accepting/declining all have distinct durable outcomes.
	session.state.current_room_id = eggery.id
	session.state.room_state.current_room_id = String(eggery.id)
	session.state.room_state.erase("current_location")
	session.state.progression.eggery_picks_remaining = 1
	session.state.progression.eggery_taken_slots = []
	var egg: Dictionary = {}
	for interaction in eggery.interactions:
		if StringName(interaction.get("kind", "")) == &"egg_pick":
			egg = interaction
			break
	var preview := session._pick_egg(egg)
	_check(preview.ok, "Cannot preview fixture egg")
	_check(session.state.progression.eggery_picks_remaining == 0, "Egg preview did not reserve a pick")
	_check(session.load(1).ok, "Cannot reload interrupted hatch")
	_check(session.state.progression.eggery_picks_remaining == 1, "Interrupted preview lost the egg allowance")
	_check(not session.state.progression.eggery_taken_slots.has(int(egg.source_zone_id)), "Interrupted preview leaves egg hidden")
	_check(not session.state.progression.has("pending_egg_preview"), "Recovered preview marker not cleared")
	preview = session._pick_egg(egg)
	_check(preview.ok and session.finish_egg_selection(preview.minion.instance_id).ok, "Cannot accept egg")
	_check(session.load(1).ok and session.state.party.size() == 2, "Accepted hatch missing after reload")
	_check(session.state.progression.eggery_picks_remaining == 0, "Reload restores an already accepted egg")
	session.state.progression.eggery_picks_remaining = 1
	session.state.progression.eggery_taken_slots = []
	session.state.room_state[String(eggery.id)]["eggery_taken_slots"] = []
	preview = session._pick_egg(egg)
	_check(preview.ok and session.discard_latest_egg_minion(preview.minion.instance_id).ok, "Cannot decline egg")
	_check(session.load(1).ok and session.state.progression.eggery_picks_remaining == 0, "Explicitly declined hatch is restored on reload")
	# Source buttons do not absorb Space after mouse interaction.
	var button := SourceMenuArt.button(root, "menu_muteMusicButton_on", Vector2.ZERO, func() -> void: pass)
	_check(button.focus_mode == Control.FOCUS_NONE, "Source button retains keyboard focus")
	button.queue_free()
	var save_menu := preload("res://src/presentation/campaign_save_menu_view.gd").new()
	root.add_child(save_menu)
	save_menu.configure(session)
	_check(save_menu._lobby_available and not save_menu._lobby_button.disabled, "Lobby return still locked after Floor 1")
	save_menu.queue_free()
	var tutorial := SourceCampaignTutorialView.new()
	root.add_child(tutorial)
	tutorial.configure(session, "focus_targets")
	for label in tutorial._content.get_children():
		if label is Label and label.text.begins_with("Focus targets:"):
			_check(label.size.x <= 353.0, "Focus-target tutorial text overflows its authored width")
			_check(label.position.x + label.size.x < 420.0, "Focus-target tutorial spills outside its frame")
	if DisplayServer.get_name() != "headless":
		await create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/player-report-tip.png")
	tutorial.queue_free()
	var battle := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(battle)
	_check(battle.get_node_or_null("BattleAudioControls") != null, "Battle has no audio controls")
	_check(battle._music_toggle.focus_mode == Control.FOCUS_NONE and battle._sound_toggle.focus_mode == Control.FOCUS_NONE, "Battle audio controls take keyboard focus")
	battle.queue_free()
	_check(river_room != null, "No recovered river audio marker")
	if river_room != null:
		var view := CampaignRoomView.new()
		root.add_child(view)
		_check(view.configure(river_room, &"", Vector2.ZERO, {"name": "Fixture", "gender": "male"}, {"progression": session.state.progression}), "Cannot build river room")
		_check(not view._ambient_emitters.is_empty(), "River has no distance-based ambient track")
		var animated := 0
		for sprite in view._art.get_children():
			if sprite.has_meta("source_river_animation"): animated += 1
		_check(animated > 0, "River splashes are still static")
		view.queue_free()
	await process_frame
	print("%s: compiled-player report — key focus, Floor 1 lobby unlock, replayed-floor keys, legacy repair, interrupted/accepted/declined eggs, tutorial width, battle audio, river animation/audio" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
