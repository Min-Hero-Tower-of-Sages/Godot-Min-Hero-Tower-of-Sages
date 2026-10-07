class_name CampaignSession
extends RefCounted

const ProgressionService = preload("res://src/application/campaign_progression_service.gd")
const GemEquipmentService = preload("res://src/application/campaign_gem_equipment_service.gd")
const GemEconomyService = preload("res://src/application/campaign_gem_economy_service.gd")
const StateScript = preload("res://src/domain/campaign_state.gd")
const TrainerDialogue = preload("res://src/application/source_trainer_dialogue.gd")
const LEGACY_BROKEN_START_POSITIONS := [Vector2(412.0, 736.0), Vector2.ONE]

var catalog: ContentCatalog
var campaign: CampaignDefinition
var state
var save_repository := SaveRepository.new()
var save_slot: int = 1
## Optional Callable(Dictionary) -> Dictionary that receives every validated
## save payload instead of the save repository, and returns the save result.
## A multiplayer guest sends its progress to the host this way; its own save
## slots are never touched while it plays in someone else's world.
var save_redirect: Callable
var _pending_egg_preview: OwnedMinionState
var _pending_egg_preview_slot: int = -1

func start_new(campaign_id: StringName, new_party: Array[OwnedMinionState], character_data: Dictionary = {}, slot: int = 1, overwrite_existing: bool = false) -> Dictionary:
	if catalog == null:
		return _error("missing_catalog", "set a content catalog before starting a campaign")
	campaign = catalog.get_definition(campaign_id) as CampaignDefinition
	if campaign == null:
		return _error("missing_campaign", "campaign %s does not exist" % campaign_id)
	if slot < 1 or slot > SaveRepository.SLOT_COUNT:
		return _error("invalid_slot", "save slot must be between 1 and 3")
	var existing_save := save_repository.load_slot(slot)
	if existing_save.ok and not overwrite_existing:
		return _error("slot_in_use", "save slot %d already contains a campaign" % slot)
	if not existing_save.ok and String(existing_save.get("code", "")) != "not_found":
		return existing_save
	var starting_room := catalog.get_definition(campaign.starting_room_id) as RoomDefinition
	if starting_room == null:
		return _error("missing_start_room", "campaign starting room %s does not exist" % campaign.starting_room_id)
	var created = StateScript.new()
	created.campaign_id = campaign_id
	created.current_room_id = starting_room.id
	created.character = character_data.duplicate(true)
	created.party.assign(new_party)
	ProgressionService.refresh_minion_pedia(created)
	created.progression["eggery_picks_remaining"] = 1
	created.progression["chest_seed"] = randi()
	created.room_state = {"current_room_id": String(starting_room.id), "flags": {}}
	created.safe_location = {
		"room_id": String(starting_room.id),
		"spawn_id": String(starting_room.spawn_ids[0]) if not starting_room.spawn_ids.is_empty() else "",
		"position": starting_room.spawn_positions.get(String(starting_room.spawn_ids[0]), Vector2.ZERO) if not starting_room.spawn_ids.is_empty() else Vector2.ZERO,
	}
	_set_exploration_location(created, starting_room, StringName(created.safe_location.spawn_id), created.safe_location.position)
	var errors := created.validation_errors(catalog)
	if not errors.is_empty():
		return _error("invalid_campaign_state", "\n".join(errors))
	var save_result := save_repository.save_slot(slot, created.to_dictionary(catalog.content_version))
	if not save_result.ok:
		return save_result
	state = created
	save_slot = slot
	save_redirect = Callable()
	_clear_pending_egg_preview()
	return {"ok": true, "state": state}

func load(slot: int) -> Dictionary:
	if catalog == null:
		return _error("missing_catalog", "set a content catalog before loading a campaign")
	var loaded := save_repository.load_slot(slot)
	if not loaded.ok:
		return loaded
	var candidate = StateScript.new()
	candidate.load_dictionary(loaded.state)
	var errors := candidate.validation_errors(catalog)
	if not errors.is_empty():
		return _error("invalid_campaign_state", "\n".join(errors))
	var loaded_campaign := catalog.get_definition(candidate.campaign_id) as CampaignDefinition
	if loaded_campaign == null:
		return _error("missing_campaign", "save references missing campaign %s" % candidate.campaign_id)
	if catalog.get_definition(candidate.current_room_id) is not RoomDefinition:
		return _error("missing_room", "save references missing current room %s" % candidate.current_room_id)
	state = candidate
	campaign = loaded_campaign
	save_slot = slot
	save_redirect = Callable()
	_clear_pending_egg_preview()
	loaded.state = candidate
	return loaded

## Play a state that lives outside the save slots (a multiplayer guest).
## `id_slot` only numbers new minion/gem IDs; every save goes to `redirect`.
func load_detached(data: Dictionary, id_slot: int, redirect: Callable) -> Dictionary:
	if catalog == null:
		return _error("missing_catalog", "set a content catalog before loading a campaign")
	var candidate = StateScript.new()
	candidate.load_dictionary(data)
	var errors := candidate.validation_errors(catalog)
	if not errors.is_empty():
		return _error("invalid_campaign_state", "
".join(errors))
	var loaded_campaign := catalog.get_definition(candidate.campaign_id) as CampaignDefinition
	if loaded_campaign == null:
		return _error("missing_campaign", "state references missing campaign %s" % candidate.campaign_id)
	if catalog.get_definition(candidate.current_room_id) is not RoomDefinition:
		return _error("missing_room", "state references missing current room %s" % candidate.current_room_id)
	state = candidate
	campaign = loaded_campaign
	save_slot = id_slot
	save_redirect = redirect
	_clear_pending_egg_preview()
	return {"ok": true, "state": state}

func repair_legacy_start_spawns() -> Dictionary:
	if catalog == null:
		return _error("missing_catalog", "set a content catalog before migrating save positions")
	var repaired_slots: Array[int] = []
	var failures: Array[String] = []
	for slot in range(1, SaveRepository.SLOT_COUNT + 1):
		var loaded := save_repository.load_slot(slot)
		if not loaded.ok:
			continue
		var candidate = StateScript.new()
		candidate.load_dictionary(loaded.state)
		var loaded_campaign := catalog.get_definition(candidate.campaign_id) as CampaignDefinition
		if loaded_campaign == null or not _repair_legacy_start_spawn(candidate, loaded_campaign):
			continue
		var validation_errors: PackedStringArray = candidate.validation_errors(catalog)
		if not validation_errors.is_empty():
			failures.append("slot %d: %s" % [slot, "; ".join(validation_errors)])
			continue
		var saved := save_repository.save_slot(slot, candidate.to_dictionary(catalog.content_version))
		if not saved.ok:
			failures.append("slot %d: %s" % [slot, saved.get("message", "save migration failed")])
			continue
		repaired_slots.append(slot)
	return {"ok": failures.is_empty(), "repaired_slots": repaired_slots, "failures": failures}

func _repair_legacy_start_spawn(candidate, loaded_campaign: CampaignDefinition) -> bool:
	var starting_room_id := loaded_campaign.starting_room_id
	if candidate.current_room_id != starting_room_id:
		return false
	var safe_location: Dictionary = candidate.safe_location.duplicate(true)
	if StringName(safe_location.get("room_id", "")) != starting_room_id:
		return false
	if StringName(safe_location.get("spawn_id", "")) != &"start":
		return false
	var old_position := _as_vector2(safe_location.get("position", Vector2.ZERO), Vector2.ZERO)
	var is_known_bad_position := false
	for known_bad_value in LEGACY_BROKEN_START_POSITIONS:
		var known_bad_position: Vector2 = known_bad_value
		if old_position.is_equal_approx(known_bad_position):
			is_known_bad_position = true
			break
	if not is_known_bad_position:
		return false
	var starting_room := catalog.get_definition(starting_room_id) as RoomDefinition
	if starting_room == null or not starting_room.spawn_positions.has("start"):
		return false
	var corrected_position: Variant = starting_room.spawn_positions["start"]
	if not corrected_position is Vector2:
		return false
	safe_location["position"] = corrected_position
	candidate.safe_location = safe_location
	return true

func _as_vector2(value: Variant, fallback: Vector2) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	if value is Dictionary:
		return Vector2(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)))
	if value is String:
		var serialized: String = String(value).trim_prefix("Vector2(").trim_suffix(")").trim_prefix("(").trim_suffix(")")
		var components: PackedStringArray = serialized.split(",")
		if components.size() >= 2 and components[0].strip_edges().is_valid_float() and components[1].strip_edges().is_valid_float():
			return Vector2(float(components[0]), float(components[1]))
	return fallback

func save() -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign to save")
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	ProgressionService.refresh_minion_pedia(candidate)
	var saved: Dictionary = _save_candidate(candidate)
	if saved.ok:
		# Preserve live owned-minion references held by the progression presenter.
		# Only commit these derived history fields after the save succeeds.
		state.progression["owned_minion_ids"] = candidate.progression["owned_minion_ids"]
		state.progression["seen_minion_ids"] = candidate.progression["seen_minion_ids"]
	return saved

func update_exploration_position(position: Vector2, spawn_id: StringName, facing: StringName) -> void:
	# DynamicData kept live player coordinates separate from its death return.
	# Update memory only; normal campaign saves persist this with their own state.
	if state == null or catalog == null or not state.pending_battle.is_empty() or not position.is_finite():
		return
	var room := catalog.get_definition(state.current_room_id) as RoomDefinition
	if room != null:
		_set_exploration_location(state, room, spawn_id, position, facing)

func _set_exploration_location(candidate, room: RoomDefinition, spawn_id: StringName, position: Vector2, facing: StringName = &"") -> void:
	candidate.room_state["current_location"] = {"room_id": String(room.id), "spawn_id": String(spawn_id), "position": [position.x, position.y], "facing": String(facing) if not facing.is_empty() else String(room.spawn_directions.get(String(spawn_id), ""))}

func enter_tower_lobby(from_eggery: bool = false) -> Dictionary:
	if state == null or catalog == null or campaign == null:
		return _error("no_campaign", "there is no active campaign")
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	candidate.progression["in_tower_lobby"] = true
	var lobby := catalog.get_definition(&"base:room/main_tower_lobby") as RoomDefinition
	if lobby == null:
		return _error("missing_lobby", "the source tower lobby is not registered")
	var spawn_id := "lobby_from_eggery" if from_eggery else "lobby_from_floor"
	candidate.current_room_id = lobby.id
	candidate.safe_location = {"room_id": String(lobby.id), "spawn_id": spawn_id, "position": lobby.spawn_positions.get(spawn_id, Vector2.ZERO)}
	_set_exploration_location(candidate, lobby, StringName(spawn_id), candidate.safe_location.position)
	var saved := _save_candidate(candidate)
	if not saved.ok:
		return saved
	state = candidate
	return {"ok": true, "in_tower_lobby": true}

func lobby_titan_status() -> Dictionary:
	return ProgressionService.lobby_titan_status(state)

func claim_lobby_titan() -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	var status: Dictionary = ProgressionService.lobby_titan_status(state)
	if not bool(status.get("can_claim_titans", false)):
		return _error("titan_reward_locked", String(status.get("message", "the Titan reward is unavailable")))
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	var sequence := int(candidate.progression.get("lobby_titan_sequence", 0))
	var rewards: Array[Dictionary] = []
	for reward_id in [ProgressionService.TITAN_1_ID, ProgressionService.TITAN_2_ID]:
		if _has_owned_definition(candidate, reward_id):
			continue
		sequence += 1
		var instance_id := StringName("slot-%d-lobby-titan-%d" % [save_slot, sequence])
		var built: Dictionary = ProgressionService.create_lobby_titan(candidate, catalog, reward_id, instance_id)
		if not built.ok:
			return built
		var owned: OwnedMinionState = built.minion
		var destination: StringName = &"party" if candidate.party.size() < 5 else &"storage"
		if destination == &"party":
			candidate.party.append(owned)
		else:
			candidate.storage.append(owned)
		rewards.append({
			"minion": owned,
			"definition": built.definition,
			"level": 60,
			"destination": destination,
		})
	candidate.progression["lobby_titan_sequence"] = sequence
	ProgressionService.refresh_minion_pedia(candidate)
	var saved: Dictionary = _save_candidate(candidate)
	if not saved.ok:
		return saved
	state = candidate
	return {"ok": true, "kind": &"lobby_titans_claimed", "rewards": rewards, "granted_count": rewards.size()}

func _has_owned_definition(candidate, definition_id: StringName) -> bool:
	for owned in candidate.party + candidate.storage:
		if owned.definition_id == definition_id:
			return true
	return false

func select_tower_floor(floor_index: int) -> Dictionary:
	if state == null or catalog == null or campaign == null:
		return _error("no_campaign", "there is no active campaign")
	if not bool(state.progression.get("in_tower_lobby", false)):
		return _error("not_in_tower_lobby", "return to the tower lobby before selecting a floor")
	var unlocked: Array = state.progression.get("unlocked_floor_indices", [0])
	if floor_index not in unlocked:
		return _error("floor_locked", "floor %d has not been unlocked" % (floor_index + 1))
	var mode := CampaignTowerModeService.mode_for_global_floor(floor_index)
	if floor_index < 0 or floor_index >= CampaignTowerModeService.TOTAL_TOWER_FLOORS:
		return _error("invalid_floor", "tower floor index is out of range")
	var source_index := CampaignTowerModeService.source_floor_index(floor_index)
	var floor_data := CampaignTowerModeService.mode_floor_data(campaign, source_index, mode)
	if mode == &"hard" and not CampaignTowerModeService.floor_has_mode_content(catalog, campaign, source_index, mode):
		return _error("hard_floor_not_migrated", "this hard-mode floor does not have its source rosters converted yet")
	if floor_data.is_empty():
		return _error("floor_not_migrated", "floor %d does not have converted campaign content yet" % (floor_index + 1))
	var room_id := StringName(floor_data.get("start_room_id", ""))
	if room_id.is_empty():
		var room_ids: Array = floor_data.get("room_ids", [])
		if not room_ids.is_empty():
			room_id = StringName(room_ids[0])
	var starting_room := catalog.get_definition(room_id) as RoomDefinition
	if starting_room == null:
		return _error("missing_floor_start", "floor %d start room %s is missing" % [floor_index + 1, room_id])
	var spawn_id := StringName(floor_data.get("start_spawn_id", "start"))
	if spawn_id.is_empty() or spawn_id not in starting_room.spawn_ids:
		return _error("missing_floor_spawn", "floor %d start room %s has no spawn %s" % [floor_index + 1, room_id, spawn_id])
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	# Entering a floor from the Lobby runs the source's SetupDataForBringingInANewFloor
	# path even when the player chooses the same floor again.
	candidate.progression["floor_keys"] = 0
	candidate.progression["eggery_keys"] = 0
	candidate.progression["boss_door_unlocked"] = false
	candidate.progression["eggery_door_unlocked"] = false
	candidate.progression["map_unlocked"] = false
	candidate.progression["eggery_picks_remaining"] = _eggery_pick_count(int(candidate.progression.get("sage_seals", 0)))
	candidate.progression["eggery_taken_slots"] = []
	for floor_room_id in floor_data.get("room_ids", []):
		if not String(floor_room_id).ends_with("_eggery"):
			continue
		var eggery_room_state: Dictionary = candidate.room_state.get(String(floor_room_id), {}).duplicate(true)
		eggery_room_state.erase("eggery_taken_slots")
		candidate.room_state[String(floor_room_id)] = eggery_room_state
		break
	var rested := ProgressionService.rest_party(candidate, catalog)
	if not rested.ok:
		return rested
	candidate.progression["floor_index"] = floor_index
	candidate.progression["tower_mode"] = String(mode)
	candidate.progression["in_tower_lobby"] = false
	candidate.current_room_id = starting_room.id
	candidate.room_state["current_room_id"] = String(starting_room.id)
	var room_data: Dictionary = candidate.room_state.get(String(starting_room.id), {}).duplicate(true)
	room_data["visited"] = true
	candidate.room_state[String(starting_room.id)] = room_data
	var position: Vector2 = starting_room.spawn_positions.get(String(spawn_id), Vector2.ZERO)
	candidate.safe_location = {"room_id": String(starting_room.id), "spawn_id": String(spawn_id), "position": position}
	_set_exploration_location(candidate, starting_room, spawn_id, position)
	var saved := _save_candidate(candidate)
	if not saved.ok:
		return saved
	state = candidate
	return {"ok": true, "room": starting_room, "spawn_id": spawn_id, "position": position, "floor_index": floor_index}

func select_tower_mode(mode: StringName) -> Dictionary:
	if state == null or catalog == null or campaign == null:
		return _error("no_campaign", "there is no active campaign")
	if not bool(state.progression.get("in_tower_lobby", false)):
		return _error("not_in_tower_lobby", "change tower mode at the lobby elevator")
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	var selected := CampaignTowerModeService.select_mode(candidate, catalog, campaign, mode)
	if not selected.ok:
		return selected
	var saved := _save_candidate(candidate)
	if not saved.ok:
		return saved
	state = candidate
	return selected

func complete_optional_floor_reveal(floor_index: int, tutorial_seen: bool = false) -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	if floor_index not in [3, 8, 13, 18]:
		return _error("invalid_bonus_floor", "that floor is not a source bonus floor")
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	var remaining: Array[int] = []
	for value in candidate.progression.get("pending_optional_floor_reveals", []):
		if int(value) != floor_index and int(value) not in remaining:
			remaining.append(int(value))
	candidate.progression["pending_optional_floor_reveals"] = remaining
	if tutorial_seen:
		candidate.progression["bonus_floor_tutorial_seen"] = true
	var saved := _save_candidate(candidate)
	if not saved.ok:
		return saved
	state = candidate
	return {"ok": true, "floor_index": floor_index}

func acknowledge_source_tutorial(tutorial_id: String) -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	if tutorial_id not in ["battle_basics", "focus_targets", "boss_room", "energy", "type_effectiveness", "shield_modifier", "move_timer_modifier", "extra_minions_modifier", "resurrection_modifier", "move_select", "key_keepers", "tank", "reset_talents_first", "reset_talents_second"]:
		return _error("unknown_tutorial", "that source tutorial is not supported")
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	candidate.progression[tutorial_id + "_tutorial_seen"] = true
	if tutorial_id == "reset_talents_first":
		candidate.progression["deaths_since_victory"] = 0
	var saved := _save_candidate(candidate)
	if not saved.ok:
		return saved
	state = candidate
	return {"ok": true, "tutorial_id": tutorial_id}

func enter_room(target_room_id: StringName, transition_id: int = -1) -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	var current_room := catalog.get_definition(state.current_room_id) as RoomDefinition
	var next_room := catalog.get_definition(target_room_id) as RoomDefinition
	if current_room == null or next_room == null:
		return _error("missing_room", "room transition references an unknown room")
	var matching_exit: Dictionary = {}
	for exit_data in current_room.exits:
		if StringName(exit_data.get("target_room_id", "")) != target_room_id:
			continue
		if transition_id >= 0 and int(exit_data.get("transition_id", -1)) != transition_id:
			continue
		matching_exit = exit_data
		break
	if matching_exit.is_empty():
		return _error("invalid_transition", "%s has no matching exit to %s" % [current_room.id, target_room_id])
	if not _route_is_available(matching_exit):
		return {"ok": false, "code": "locked_exit", "message": "that route is not available in the current tower mode"}
	var required_flag := StringName(matching_exit.get("requires_progression_flag", ""))
	if not required_flag.is_empty() and not bool(state.progression.get(String(required_flag), false)):
		return {"ok": false, "code": "locked_exit", "message": "that route is still locked", "required_flag": required_flag}
	var entry_spawn_id := StringName(matching_exit.get("target_spawn_id", ""))
	if not entry_spawn_id.is_empty() and entry_spawn_id not in next_room.spawn_ids:
		return _error("invalid_spawn", "%s does not define entry spawn %s" % [next_room.id, entry_spawn_id])
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	candidate.current_room_id = target_room_id
	var room_data: Dictionary = candidate.room_state.get(String(target_room_id), {}).duplicate(true)
	room_data["visited"] = true
	candidate.room_state[String(target_room_id)] = room_data
	candidate.room_state["current_room_id"] = String(target_room_id)
	var spawn_position: Variant = next_room.spawn_positions.get(String(entry_spawn_id), Vector2.ZERO)
	_set_exploration_location(candidate, next_room, entry_spawn_id, spawn_position)
	var save_result := _save_candidate(candidate)
	if not save_result.ok:
		return save_result
	state = candidate
	return {"ok": true, "room": next_room, "spawn_id": entry_spawn_id, "position": spawn_position}

func interact(interaction_id: StringName, checkpoint_position: Variant = null, checkpoint_spawn_id: StringName = &"") -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	var room := catalog.get_definition(state.current_room_id) as RoomDefinition
	if room == null:
		return _error("missing_room", "current room %s does not exist" % state.current_room_id)
	for interaction in room.interactions:
		if StringName(interaction.get("id", "")) != interaction_id:
			continue
		if not _route_is_available(interaction):
			return {"ok": false, "code": "interaction_unavailable", "message": "that interaction is not available in the current tower mode"}
		var kind := StringName(interaction.get("kind", ""))
		match kind:
			&"heal_party":
				var candidate = StateScript.new()
				candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
				var rested := ProgressionService.rest_party(candidate, catalog)
				if not rested.ok:
					return rested
				if checkpoint_position is Vector2:
					_set_death_checkpoint(candidate, checkpoint_position, checkpoint_spawn_id)
				var save_result := _save_candidate(candidate)
				if not save_result.ok:
					return save_result
				state = candidate
				return {"ok": true, "kind": kind, "rested": rested.rested}
			&"trainer":
				var encounter_id := StringName(interaction.get("encounter_id", ""))
				if not room.encounter_ids.has(encounter_id):
					return _error("invalid_interaction", "trainer encounter is not attached to this room")
				var resolved_dialogue := CampaignTowerModeService.resolve_encounter(catalog, catalog.get_definition(encounter_id) as EncounterDefinition, int(state.progression.get("floor_index", 0)))
				if not resolved_dialogue.ok:
					return resolved_dialogue
				var dialogue_encounter: EncounterDefinition = resolved_dialogue.encounter
				var completed: Dictionary = state.progression.get("completed_encounters", {})
				var already_beaten := bool(completed.get(String(dialogue_encounter.id), false))
				var dialogue: Dictionary = TrainerDialogue.for_encounter(dialogue_encounter)
				var text := String(dialogue.get("first_visit_text", interaction.get("first_visit_text", "A trainer challenges you.")))
				if already_beaten:
					var ratings: Dictionary = state.progression.get("encounter_star_ratings", {})
					text = "You already beat me!   Replay me for exp?" if int(ratings.get(String(dialogue_encounter.id), 0)) >= 3 else String(dialogue.get("repeat_text", "You already beat me!   Retry for three stars?"))
				return {"ok": true, "kind": kind, "encounter_id": encounter_id, "already_beaten": already_beaten, "dialog_text": text, "trainer_name": String(interaction.get("trainer_name", dialogue.get("trainer_name", "Trainer")))}
			&"map_station":
				if not bool(state.progression.get("map_unlocked", false)):
					var map_state = StateScript.new()
					map_state.load_dictionary(state.to_dictionary(catalog.content_version, true))
					map_state.progression["map_unlocked"] = true
					var map_saved := _save_candidate(map_state)
					if not map_saved.ok:
						return map_saved
					state = map_state
					return {"ok": true, "kind": &"map_granted", "message": String(interaction.get("first_visit_text", "Here is a map to help you with this floor."))}
				return {"ok": true, "kind": &"map_hint", "message": String(interaction.get("return_text", "Use the map well."))}
			&"unlock_boss_door":
				if bool(state.progression.get("boss_door_unlocked", false)):
					return {"ok": true, "kind": &"door_already_open"}
				var required_keys := int(interaction.get("required_floor_keys", 3))
				var available_keys := int(state.progression.get("floor_keys", 0))
				if available_keys < required_keys:
					return {"ok": true, "kind": &"door_locked", "message": String(interaction.get("locked_text", "The door is locked.")), "keys_needed": required_keys - available_keys}
				var boss_door_state = StateScript.new()
				boss_door_state.load_dictionary(state.to_dictionary(catalog.content_version, true))
				# RegularKeyDoor consumes the floor's key ring, not just three keys.
				boss_door_state.progression["floor_keys"] = 0
				boss_door_state.progression["boss_door_unlocked"] = true
				var boss_door_saved := _save_candidate(boss_door_state)
				if not boss_door_saved.ok:
					return boss_door_saved
				state = boss_door_state
				return {"ok": true, "kind": &"door_unlocked", "door": &"boss"}
			&"unlock_eggery_door":
				if bool(state.progression.get("eggery_door_unlocked", false)):
					return {"ok": true, "kind": &"door_already_open"}
				var eggery_keys := int(state.progression.get("eggery_keys", 0))
				if eggery_keys < 1:
					return {"ok": true, "kind": &"door_locked", "message": String(interaction.get("locked_text", "I need a key to open the hatchery.")), "keys_needed": 1 - eggery_keys}
				var eggery_door_state = StateScript.new()
				eggery_door_state.load_dictionary(state.to_dictionary(catalog.content_version, true))
				# BossToEggeryDoorWall consumes the player's accumulated tower keys
				# when it opens in standard mode, not just the single Eggery key.
				eggery_door_state.progression["eggery_keys"] = 0
				eggery_door_state.progression["floor_keys"] = 0
				eggery_door_state.progression["eggery_door_unlocked"] = true
				var eggery_door_saved := _save_candidate(eggery_door_state)
				if not eggery_door_saved.ok:
					return eggery_door_saved
				state = eggery_door_state
				return {"ok": true, "kind": &"door_unlocked", "door": &"eggery"}
			&"grand_sage":
				var first_visit := not bool(state.progression.get("grand_sage_met", false))
				var sage_text := String(interaction.get("return_text", "Welcome to the Tower.")) if not first_visit else String(interaction.get("first_visit_text", "Welcome to the Tower."))
				return {"ok": true, "kind": kind, "first_visit": first_visit, "message": sage_text}
			&"egg_pick":
				return _pick_egg(interaction)
			_:
				return _error("unsupported_interaction", "interaction kind %s is not implemented" % kind)
	return _error("missing_interaction", "interaction %s does not exist in %s" % [interaction_id, room.id])

func claim_room_chest(interaction: Dictionary) -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	var room := catalog.get_definition(state.current_room_id) as RoomDefinition
	if room == null:
		return _error("missing_room", "current room %s does not exist" % state.current_room_id)
	var payload := room.ensure_payload()
	if payload == null:
		return _error("missing_room_payload", "current room %s has no source payload" % room.id)
	var source_index := int(interaction.get("source_object_index", -1))
	if source_index < 0 or source_index >= payload.objects.size():
		return _error("invalid_chest", "chest does not belong to the current room")
	var attributes: Dictionary = payload.objects[source_index]
	if String(attributes.get("spriteName", "")).strip_edges() != "room_goldChest":
		return _error("invalid_chest", "only source money chests can be claimed")
	var chest_id := "chest-gold-%d" % source_index
	if String(interaction.get("id", "")) != chest_id:
		return _error("invalid_chest", "chest identifier does not match its source object")
	if int(state.progression.get("sage_seals", 0)) <= 0:
		return _error("chest_locked", "money chests require a Sage Seal")
	if not CampaignChestPolicy.spawned(room.id, "gold", source_index, state.progression):
		return _error("chest_not_spawned", "this source chest was not generated on this visit")
	var room_data: Dictionary = state.room_state.get(String(room.id), {}).duplicate(true)
	var claimed_slots: Array = room_data.get("claimed_chest_slots", []).duplicate()
	if chest_id in claimed_slots:
		return {"ok": true, "kind": &"chest_already_claimed"}
	var floor_index := maxi(0, int(state.progression.get("floor_index", 0)))
	var floor_money := minf(2000.0, 7.0 * pow(1.25, floor_index))
	var reward := int(roundi(floor_money) / 3.0)
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	candidate.progression["currency"] = int(candidate.progression.get("currency", 0)) + reward
	claimed_slots.append(chest_id)
	room_data["claimed_chest_slots"] = claimed_slots
	candidate.room_state[String(room.id)] = room_data
	var saved := _save_candidate(candidate)
	if not saved.ok:
		return saved
	state = candidate
	return {"ok": true, "kind": &"chest_claimed", "chest_kind": "gold", "currency": reward}

func claim_room_gem_chest(interaction: Dictionary) -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	var room := catalog.get_definition(state.current_room_id) as RoomDefinition
	if room == null:
		return _error("missing_room", "current room %s does not exist" % state.current_room_id)
	var payload := room.ensure_payload()
	if payload == null:
		return _error("missing_room_payload", "current room %s has no source payload" % room.id)
	var source_index := int(interaction.get("source_object_index", -1))
	if source_index < 0 or source_index >= payload.objects.size():
		return _error("invalid_chest", "chest does not belong to the current room")
	var attributes: Dictionary = payload.objects[source_index]
	if String(attributes.get("spriteName", "")).strip_edges() != "room_gemChest":
		return _error("invalid_chest", "only source gem chests can be claimed")
	var chest_id := "chest-gem-%d" % source_index
	if String(interaction.get("id", "")) != chest_id:
		return _error("invalid_chest", "chest identifier does not match its source object")
	if int(state.progression.get("sage_seals", 0)) <= 3:
		return _error("chest_locked", "gem chests require more than three Sage Seals")
	if not CampaignChestPolicy.spawned(room.id, "gem", source_index, state.progression):
		return _error("chest_not_spawned", "this source chest was not generated on this visit")
	var room_data: Dictionary = state.room_state.get(String(room.id), {}).duplicate(true)
	var claimed_slots: Array = room_data.get("claimed_chest_slots", []).duplicate()
	if chest_id in claimed_slots:
		return {"ok": true, "kind": &"chest_already_claimed", "chest_kind": "gem"}
	var gem := _create_source_random_gem(_source_gem_tier_for_floor(int(state.progression.get("floor_index", 0))))
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	var gem_sequence: int = candidate.owned_gems.size() + 1
	gem["instance_id"] = "slot-%d-gem-%d" % [save_slot, gem_sequence]
	candidate.owned_gems.append(gem)
	claimed_slots.append(chest_id)
	room_data["claimed_chest_slots"] = claimed_slots
	candidate.room_state[String(room.id)] = room_data
	var saved := _save_candidate(candidate)
	if not saved.ok:
		return saved
	state = candidate
	return {
		"ok": true,
		"kind": &"chest_claimed",
		"chest_kind": "gem",
		"gem": gem.duplicate(true),
		"message": "Found Gem (tier %d): +%d %s" % [int(gem.tier), int(gem.stat_value), String(gem.stat_label)],
	}

func equip_gem(gem_instance_id: StringName, minion_instance_id: StringName, slot: int) -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	var equipped := GemEquipmentService.equip_gem(candidate, catalog, gem_instance_id, minion_instance_id, slot)
	if not equipped.ok:
		return equipped
	candidate.progression["gem_tutorial_seen"] = true
	var saved := _save_candidate(candidate)
	if not saved.ok:
		return saved
	state = candidate
	return equipped

func unequip_gem(minion_instance_id: StringName, slot: int) -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	var unequipped := GemEquipmentService.unequip_gem(candidate, catalog, minion_instance_id, slot)
	if not unequipped.ok:
		return unequipped
	var saved := _save_candidate(candidate)
	if not saved.ok:
		return saved
	state = candidate
	return unequipped

func sort_gems() -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	GemEquipmentService.sort_gems(candidate)
	var saved := _save_candidate(candidate)
	if not saved.ok:
		return saved
	state = candidate
	return {"ok": true, "kind": &"gems_sorted"}

func swap_gems(first_id: StringName, second_id: StringName) -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	var swapped := GemEquipmentService.swap_gems(candidate, first_id, second_id)
	if not swapped.ok:
		return swapped
	var saved := _save_candidate(candidate)
	if not saved.ok:
		return saved
	state = candidate
	return swapped

func move_gem_to_slot(gem_id: StringName, target_slot: int) -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	var moved := GemEquipmentService.move_gem_to_slot(candidate, gem_id, target_slot)
	if not moved.ok:
		return moved
	var saved := _save_candidate(candidate)
	if not saved.ok:
		return saved
	state = candidate
	return moved

func combine_gems(ids: Array[StringName], inventory_page: int = 0) -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	candidate.progression["gem_inventory_slots"] = GemEquipmentService.inventory_slots(candidate)
	var combined := GemEconomyService.combine_gems(candidate, ids)
	if not combined.ok:
		return combined
	var placed := GemEquipmentService.place_gem_from_page(candidate, StringName(combined.gem.instance_id), inventory_page)
	if not placed.ok:
		return placed
	combined["inventory_slot"] = placed.slot
	var saved := _save_candidate(candidate)
	if not saved.ok:
		return saved
	state = candidate
	return combined

func sell_gem(gem_instance_id: StringName) -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	var sold := GemEconomyService.sell_gem(candidate, gem_instance_id)
	if not sold.ok:
		return sold
	var saved := _save_candidate(candidate)
	if not saved.ok:
		return saved
	state = candidate
	return sold

func gem_shop_stock() -> Array[Dictionary]:
	if state == null or catalog == null:
		return []
	var stock := GemEconomyService.current_shop_stock(state)
	if stock.is_empty():
		var refreshed := refresh_gem_shop()
		if not refreshed.ok:
			return []
		stock = GemEconomyService.current_shop_stock(state)
	return stock

func refresh_gem_shop() -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	var unlocked: Array = candidate.progression.get("unlocked_floor_indices", [0])
	var highest_floor := int(candidate.progression.get("floor_index", 0))
	for floor_index in unlocked:
		highest_floor = maxi(highest_floor, int(floor_index))
	var stock := GemEconomyService.refresh_shop(candidate, mini(61, highest_floor + 1))
	var saved := _save_candidate(candidate)
	if not saved.ok:
		return saved
	state = candidate
	return {"ok": true, "kind": &"gem_shop_refreshed", "stock": stock}

func buy_shop_gem(index: int, inventory_page: int = 0) -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	candidate.progression["gem_inventory_slots"] = GemEquipmentService.inventory_slots(candidate)
	var bought := GemEconomyService.buy_shop_gem(candidate, index)
	if not bought.ok:
		return bought
	var placed := GemEquipmentService.place_gem_from_page(candidate, StringName(bought.gem.instance_id), inventory_page)
	if not placed.ok:
		return placed
	bought["inventory_slot"] = placed.slot
	var saved := _save_candidate(candidate)
	if not saved.ok:
		return saved
	state = candidate
	return bought

func restore_combiner_materials(ids: Array[StringName]) -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	var inventory := GemEquipmentService.inventory_slots(candidate)
	var initial := inventory.duplicate()
	for id in ids:
		var origin := inventory.find(String(id))
		if origin < 0:
			return _error("gem_unavailable", "a combiner material is no longer available")
		inventory[origin] = ""
	for id in ids:
		var target := inventory.find("")
		if target < 0:
			return _error("gem_inventory_full", "no slot remains for a combiner material")
		inventory[target] = String(id)
	if inventory == initial:
		return {"ok": true}
	candidate.progression["gem_inventory_slots"] = inventory
	var saved := _save_candidate(candidate)
	if saved.ok:
		state = candidate
	return saved

func select_storage_minion(instance_id: StringName, party_slot: int = -1) -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	var storage_index := -1
	for index in candidate.storage.size():
		if candidate.storage[index].instance_id == instance_id:
			storage_index = index
			break
	if storage_index < 0:
		return _error("missing_storage_minion", "minion %s is not in storage" % String(instance_id))
	var selected: OwnedMinionState = candidate.storage[storage_index]
	if party_slot == -1:
		if candidate.party.size() >= 5:
			return _error("party_full", "choose a party slot to replace because the party is full")
		candidate.storage.remove_at(storage_index)
		candidate.party.append(selected)
	else:
		if party_slot < 0 or party_slot >= candidate.party.size():
			return _error("invalid_party_slot", "choose a valid active party slot")
		var replaced: OwnedMinionState = candidate.party[party_slot]
		candidate.party[party_slot] = selected
		candidate.storage[storage_index] = replaced
	var saved := _save_candidate(candidate)
	if not saved.ok:
		return saved
	state = candidate
	return {"ok": true, "kind": &"storage_minion_selected", "minion": selected, "party_slot": candidate.party.find(selected), "swapped": party_slot >= 0}

func swap_storage_minions(first_id: StringName, second_id: StringName) -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	var first_index := _storage_minion_index(candidate, first_id)
	var second_index := _storage_minion_index(candidate, second_id)
	if first_index < 0 or second_index < 0:
		return _error("missing_storage_minion", "both minions must be in storage")
	if first_index != second_index:
		var first: OwnedMinionState = candidate.storage[first_index]
		candidate.storage[first_index] = candidate.storage[second_index]
		candidate.storage[second_index] = first
	var saved := _save_candidate(candidate)
	if not saved.ok:
		return saved
	state = candidate
	return {"ok": true, "kind": &"storage_minions_swapped", "first_id": String(first_id), "second_id": String(second_id)}

func swap_party_minions(first_id: StringName, second_id: StringName) -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	var first_index := _party_minion_index(candidate, first_id)
	var second_index := _party_minion_index(candidate, second_id)
	if first_index < 0 or second_index < 0:
		return _error("missing_party_minion", "both minions must be in the active party")
	var first: OwnedMinionState = candidate.party[first_index]
	candidate.party[first_index] = candidate.party[second_index]
	candidate.party[second_index] = first
	var saved := _save_candidate(candidate)
	if not saved.ok:
		return saved
	state = candidate
	return {"ok": true, "kind": &"party_minions_swapped", "first_id": String(first_id), "second_id": String(second_id)}

func release_storage_minion(instance_id: StringName) -> Dictionary:
	return release_minion(instance_id)

func release_minion(instance_id: StringName) -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	var party_index := _party_minion_index(candidate, instance_id)
	var storage_index := _storage_minion_index(candidate, instance_id)
	var owned: OwnedMinionState = null
	if party_index >= 0:
		if candidate.party.size() <= 1:
			return _error("last_party_minion", "release another minion into the active party first")
		owned = candidate.party[party_index]
		candidate.party.remove_at(party_index)
	elif storage_index >= 0:
		owned = candidate.storage[storage_index]
		candidate.storage.remove_at(storage_index)
	else:
		return _error("missing_minion", "minion %s is not owned" % String(instance_id))
	var released_gems := owned.equipment_ids.duplicate()
	owned.equipment_ids.clear()
	var saved := _save_candidate(candidate)
	if not saved.ok:
		return saved
	state = candidate
	return {"ok": true, "kind": &"minion_released", "minion": owned, "unequipped_gem_ids": released_gems}

func purchase_star_upgrade(upgrade_index: int) -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	var purchase := ProgressionService.purchase_star_upgrade(candidate, upgrade_index)
	if not purchase.ok:
		return purchase
	var saved := _save_candidate(candidate)
	if not saved.ok:
		return saved
	state = candidate
	return purchase

func reset_star_upgrades() -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	var reset := ProgressionService.reset_star_upgrades(candidate)
	if not reset.ok:
		return reset
	var saved := _save_candidate(candidate)
	if not saved.ok:
		return saved
	state = candidate
	return reset

func star_summary() -> Dictionary:
	if state == null:
		return {"earned": 0, "spent": 0, "available": 0, "upgrades": {}}
	var upgrades: Dictionary = state.progression.get("star_upgrades", {}).duplicate(true)
	var rows: Array[Dictionary] = []
	for index in ProgressionService.star_upgrade_keys().size():
		var key: StringName = ProgressionService.star_upgrade_keys()[index]
		var rank := maxi(0, int(upgrades.get(String(key), 0)))
		rows.append({"index": index, "id": key, "rank": rank, "cost": ProgressionService.star_upgrade_cost(rank)})
	return {"earned": ProgressionService.total_earned_stars(state), "spent": ProgressionService.spent_stars(state), "available": ProgressionService.available_stars(state), "upgrades": upgrades, "rows": rows}

func _source_gem_tier_for_floor(floor_index: int) -> int:
	return CampaignGemFactory.tier_for_floor(floor_index)

func _create_source_random_gem(tier: int) -> Dictionary:
	return CampaignGemFactory.create_random(tier)

func _pick_egg(interaction: Dictionary) -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	if _pending_egg_preview != null:
		return _error("egg_preview_pending", "accept or decline the egg preview before selecting another egg")
	var remaining := int(state.progression.get("eggery_picks_remaining", 0))
	if remaining <= 0:
		return {"ok": false, "code": "no_egg_picks", "message": "There are no unclaimed eggs remaining."}
	var slot := int(interaction.get("source_zone_id", -1))
	var current_room := catalog.get_definition(state.current_room_id) as RoomDefinition
	if current_room == null or not String(current_room.id).ends_with("_eggery"):
		return _error("wrong_room", "egg selection is only available in the hatchery")
	var current_room_state: Dictionary = state.room_state.get(String(current_room.id), {}).duplicate(true)
	var taken: Array = current_room_state.get("eggery_taken_slots", state.progression.get("eggery_taken_slots", [])).duplicate()
	if slot < 0 or slot >= 9 or slot in taken:
		return _error("egg_already_claimed", "that egg has already been chosen")
	var candidates: Array = interaction.get("candidates", [])
	var weights: Array = interaction.get("weights", [])
	if candidates.is_empty() or candidates.size() != weights.size():
		return _error("invalid_egg_table", "hatchery egg table is missing candidates or weights")
	var roll := randi_range(1, 100)
	var running_weight := 0
	var definition_id := StringName(candidates.back())
	for index in candidates.size():
		running_weight += int(weights[index])
		if roll <= running_weight:
			definition_id = StringName(candidates[index])
			break
	var definition := catalog.get_definition(definition_id) as MinionDefinition
	if definition == null:
		return _error("missing_egg_minion", "hatchery references missing minion %s" % definition_id)
	var candidate_state = StateScript.new()
	candidate_state.load_dictionary(state.to_dictionary(catalog.content_version, true))
	var sequence := int(candidate_state.progression.get("eggery_pick_sequence", 0)) + 1
	var level := 0
	var owned := OwnedMinionState.new()
	owned.instance_id = StringName("slot-%d-eggery-%d" % [save_slot, sequence])
	owned.definition_id = definition.id
	var minion_base_level := 7
	var campaign := catalog.get_definition(candidate_state.campaign_id) as CampaignDefinition
	var selected_floor_index := int(candidate_state.progression.get("floor_index", 0))
	if campaign != null:
		for floor_data in campaign.floors:
			if int(floor_data.get("floor_index", -1)) == CampaignTowerModeService.source_floor_index(selected_floor_index):
				minion_base_level = int(floor_data.get("eggery_minion_base_level", minion_base_level))
				break
	level = CampaignTowerModeService.hard_eggery_level(selected_floor_index) if selected_floor_index >= CampaignTowerModeService.STANDARD_FLOOR_COUNT else mini(60, minion_base_level + randi_range(0, 2))
	owned.level = level
	owned.experience = level * 1000
	var stat_bonuses: Array[StringName] = [&"health", &"energy", &"attack", &"healing", &"speed"]
	owned.stat_bonus = stat_bonuses[randi_range(0, stat_bonuses.size() - 1)]
	owned.learned_move_ids.assign(definition.initial_move_ids)
	var storage_destination: bool = candidate_state.party.size() >= 5
	taken.append(slot)
	current_room_state["eggery_taken_slots"] = taken
	candidate_state.room_state[String(current_room.id)] = current_room_state
	# Keep the pre-room-state field current for older save readers.
	candidate_state.progression["eggery_taken_slots"] = taken.duplicate()
	candidate_state.progression["eggery_picks_remaining"] = remaining - 1
	candidate_state.progression["eggery_pick_sequence"] = sequence
	var saved := _save_candidate(candidate_state)
	if not saved.ok:
		return saved
	state = candidate_state
	_pending_egg_preview = owned
	_pending_egg_preview_slot = slot
	return {"ok": true, "kind": &"egg_pick", "minion": owned, "definition": definition, "level": level, "destination": &"storage" if storage_destination else &"party", "remaining": remaining - 1, "slot": slot}

func finish_egg_selection(accepted_instance_id: StringName, party_slot: int = -1) -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	var current_room := catalog.get_definition(state.current_room_id) as RoomDefinition
	if current_room == null or not String(current_room.id).ends_with("_eggery"):
		return _error("wrong_room", "egg selection is only available in the hatchery")
	var sequence := int(state.progression.get("eggery_pick_sequence", 0))
	if sequence <= 0 or accepted_instance_id != StringName("slot-%d-eggery-%d" % [save_slot, sequence]):
		return _error("not_latest_egg", "only the most recently hatched minion can be accepted")
	if _pending_egg_preview != null and (accepted_instance_id != _pending_egg_preview.instance_id or _pending_egg_preview_slot < 0):
		return _error("egg_preview_mismatch", "the pending preview does not match the selected hatchery egg")
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	var accepted := _pending_egg_preview.duplicate_state() if _pending_egg_preview != null else null
	var party_index := _party_minion_index(candidate, accepted_instance_id)
	var storage_index := _storage_minion_index(candidate, accepted_instance_id)
	if accepted == null and party_index >= 0:
		accepted = candidate.party[party_index]
	if accepted == null and storage_index >= 0:
		accepted = candidate.storage[storage_index]
	if accepted == null:
		return _error("egg_minion_not_found", "the hatched minion is no longer in the party or storage")
	if party_slot < -1 or (party_slot >= 0 and party_slot >= candidate.party.size()):
		return _error("invalid_party_slot", "choose a valid active party slot")
	if party_slot >= 0:
		if party_index == party_slot:
			pass
		else:
			if party_index >= 0:
				candidate.party.remove_at(party_index)
				if party_index < party_slot:
					party_slot -= 1
			if storage_index >= 0:
				candidate.storage.remove_at(storage_index)
			var outgoing: OwnedMinionState = candidate.party[party_slot]
			candidate.party[party_slot] = accepted
			candidate.storage.append(outgoing)
	elif party_index >= 0:
		# Legacy pre-added candidates stay in their current party position.
		pass
	elif storage_index >= 0:
		# Legacy pre-added candidates can be kept in storage or moved to the
		# first free party slot without duplicating the stored instance.
		if candidate.party.size() < 5:
			candidate.storage.remove_at(storage_index)
			candidate.party.append(accepted)
	else:
		if candidate.party.size() < 5:
			candidate.party.append(accepted)
		else:
			candidate.storage.append(accepted)
	# Source choices are additional chances to inspect an egg, not additional
	# rewards. Keeping any egg ends this floor's selection and sinks every egg.
	var taken: Array = range(9)
	var room_state: Dictionary = candidate.room_state.get(String(current_room.id), {}).duplicate(true)
	room_state["eggery_taken_slots"] = taken.duplicate()
	candidate.room_state[String(current_room.id)] = room_state
	candidate.progression["eggery_taken_slots"] = taken.duplicate()
	candidate.progression["eggery_picks_remaining"] = 0
	ProgressionService.refresh_minion_pedia(candidate)
	var saved: Dictionary = _save_candidate(candidate)
	if not saved.ok:
		return saved
	state = candidate
	_clear_pending_egg_preview()
	return {"ok": true, "minion": accepted, "remaining": 0, "slots": taken, "destination": &"party" if _party_minion_index(candidate, accepted_instance_id) >= 0 else &"storage"}

func discard_latest_egg_minion(instance_id: StringName) -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	var latest_sequence := int(state.progression.get("eggery_pick_sequence", 0))
	var expected_instance_id := StringName("slot-%d-eggery-%d" % [save_slot, latest_sequence])
	if latest_sequence <= 0 or instance_id != expected_instance_id:
		return _error("not_latest_egg", "only the most recently hatched minion can be declined")
	if _pending_egg_preview != null:
		if _pending_egg_preview.instance_id != instance_id:
			return _error("egg_preview_mismatch", "the pending preview does not match the selected hatchery egg")
		_clear_pending_egg_preview()
		return {"ok": true, "instance_id": instance_id, "preview_discarded": true}
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	var removed := false
	for index in range(candidate.party.size() - 1, -1, -1):
		var owned := candidate.party[index] as OwnedMinionState
		if owned != null and owned.instance_id == instance_id:
			candidate.party.remove_at(index)
			removed = true
			break
	if not removed:
		for index in range(candidate.storage.size() - 1, -1, -1):
			var owned := candidate.storage[index] as OwnedMinionState
			if owned != null and owned.instance_id == instance_id:
				candidate.storage.remove_at(index)
				removed = true
				break
	if not removed:
		return _error("egg_minion_not_found", "the latest hatched minion is no longer in the party or storage")
	var saved := _save_candidate(candidate)
	if not saved.ok:
		return saved
	state = candidate
	_clear_pending_egg_preview()
	return {"ok": true, "instance_id": instance_id}

func _clear_pending_egg_preview() -> void:
	_pending_egg_preview = null
	_pending_egg_preview_slot = -1

func rename_minion(instance_id: StringName, new_name: String) -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	if new_name.length() > 16 or "\n" in new_name or "\r" in new_name:
		return _error("invalid_name", "minion names may contain up to 16 characters on one line")
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	var renamed: OwnedMinionState
	for owned in candidate.party + candidate.storage:
		if owned.instance_id == instance_id:
			renamed = owned
			break
	if renamed == null:
		return _error("missing_minion", "choose an owned minion to rename")
	renamed.nickname = new_name
	var saved: Dictionary = _save_candidate(candidate)
	if not saved.ok:
		return saved
	state = candidate
	return {"ok": true, "minion": renamed}

func choose_grand_sage_bonus(stat_bonus: StringName, checkpoint_position: Variant = null, checkpoint_spawn_id: StringName = &"") -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	if bool(state.progression.get("grand_sage_met", false)):
		return _error("bonus_already_chosen", "the Grand Sage's starting bonus has already been chosen")
	if stat_bonus not in [&"attack", &"health", &"speed"]:
		return _error("invalid_bonus", "choose attack, health, or speed")
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	for index in mini(2, candidate.party.size()):
		candidate.party[index].stat_bonus = stat_bonus
	candidate.progression["grand_sage_met"] = true
	if checkpoint_position is Vector2:
		_set_death_checkpoint(candidate, checkpoint_position, checkpoint_spawn_id)
	var saved := _save_candidate(candidate)
	if not saved.ok:
		return saved
	state = candidate
	return {"ok": true, "stat_bonus": stat_bonus, "affected_minions": mini(2, candidate.party.size())}

func _set_death_checkpoint(candidate, position: Vector2, preferred_spawn_id: StringName) -> void:
	if candidate == null or catalog == null:
		return
	var room := catalog.get_definition(candidate.current_room_id) as RoomDefinition
	if room == null:
		return
	var spawn_id := preferred_spawn_id
	if spawn_id not in room.spawn_ids:
		var existing_spawn_id := StringName(candidate.safe_location.get("spawn_id", ""))
		var fallback_spawn_id: StringName = &""
		if not room.spawn_ids.is_empty():
			fallback_spawn_id = room.spawn_ids[0]
		spawn_id = existing_spawn_id if existing_spawn_id in room.spawn_ids else fallback_spawn_id
	candidate.safe_location = {
		"room_id": String(room.id),
		"spawn_id": String(spawn_id),
		"position": position,
	}

func swap_party_with_storage(party_index: int, storage_index: int) -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	if party_index < 0 or party_index >= state.party.size():
		return _error("invalid_party_index", "choose an existing party member")
	if storage_index < 0 or storage_index >= state.storage.size():
		return _error("invalid_storage_index", "choose an existing stored minion")
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	var outgoing: OwnedMinionState = candidate.party[party_index]
	candidate.party[party_index] = candidate.storage[storage_index]
	candidate.storage[storage_index] = outgoing
	var saved := _save_candidate(candidate)
	if not saved.ok:
		return saved
	state = candidate
	return {"ok": true, "party_index": party_index, "storage_index": storage_index, "party_member": candidate.party[party_index], "stored_minion": candidate.storage[storage_index]}

func _save_candidate(candidate) -> Dictionary:
	var errors: PackedStringArray = candidate.validation_errors(catalog)
	if not errors.is_empty():
		return _error("invalid_campaign_state", "\n".join(errors))
	var payload: Dictionary = candidate.to_dictionary(catalog.content_version)
	if save_redirect.is_valid():
		return save_redirect.call(payload)
	return save_repository.save_slot(save_slot, payload)

func _eggery_pick_count(sage_seals: int) -> int:
	if sage_seals > 5:
		return 3
	if sage_seals > 2:
		return 2
	return 1

func _route_is_available(route: Dictionary) -> bool:
	var required_flag := StringName(route.get("requires_progression_flag", ""))
	if not required_flag.is_empty() and not bool(state.progression.get(String(required_flag), false)):
		return false
	var required_mode := String(route.get("requires_tower_mode", ""))
	var tower_mode := String(CampaignTowerModeService.mode_for_global_floor(int(state.progression.get("floor_index", 0)))) if state != null else "standard"
	return required_mode.is_empty() or required_mode == tower_mode

func _party_minion_index(candidate, instance_id: StringName) -> int:
	for index in candidate.party.size():
		if candidate.party[index].instance_id == instance_id:
			return index
	return -1

func _storage_minion_index(candidate, instance_id: StringName) -> int:
	for index in candidate.storage.size():
		if candidate.storage[index].instance_id == instance_id:
			return index
	return -1

func prepare_battle(encounter_id: StringName) -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	var room := catalog.get_definition(state.current_room_id) as RoomDefinition
	var encounter := catalog.get_definition(encounter_id) as EncounterDefinition
	if room == null or encounter == null:
		return _error("missing_encounter", "current room or requested encounter is missing")
	if not room.encounter_ids.has(encounter_id):
		return _error("encounter_not_in_room", "%s does not host encounter %s" % [room.id, encounter_id])
	for interaction in room.interactions:
		if StringName(interaction.get("encounter_id", "")) == encounter_id and not _route_is_available(interaction):
			return _error("interaction_unavailable", "that encounter is not available in the current tower mode")
	var resolved := CampaignTowerModeService.resolve_encounter(catalog, encounter, int(state.progression.get("floor_index", 0)))
	if not resolved.ok:
		return resolved
	encounter = resolved.encounter as EncounterDefinition
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	var rested := ProgressionService.rest_party(candidate, catalog)
	if not rested.ok:
		return rested
	var prepared := ProgressionService.prepare_battle(candidate, encounter)
	if not prepared.ok:
		return prepared
	prepared["setup"] = ProgressionService.build_battle_setup(candidate, catalog, encounter)
	if not prepared.setup.ok:
		return prepared.setup
	var save_result := _save_candidate(candidate)
	if not save_result.ok:
		return save_result
	state = candidate
	return prepared

func cancel_pending_battle() -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	if state.pending_battle.is_empty():
		return {"ok": true, "already_cleared": true}
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	candidate.pending_battle.clear()
	var saved := _save_candidate(candidate)
	if not saved.ok:
		return saved
	state = candidate
	return {"ok": true, "pending_battle_cleared": true}

func complete_defeat_return() -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	if state.pending_defeat_return.is_empty():
		return {"ok": true, "already_returned": true}
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	var returned := ProgressionService.complete_defeat_return(candidate, catalog)
	if not returned.ok: return returned
	var saved := _save_candidate(candidate)
	if not saved.ok: return saved
	state = candidate
	return returned

func apply_battle_result(result: BattleResult) -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	if result == null or result.is_empty():
		return _error("invalid_result", "a completed battle result is required")
	# Settlement clears pending_battle. Check the committed ID before looking up
	# that context, including when a delayed callback arrives during a new battle.
	if String(result.battle_id) in state.applied_battle_ids:
		return {"ok": true, "already_applied": true, "battle_id": String(result.battle_id)}
	var context: Dictionary = state.pending_battle.duplicate(true)
	var encounter := catalog.get_definition(StringName(context.get("encounter_id", ""))) as EncounterDefinition
	if encounter == null:
		return _error("missing_encounter", "pending battle encounter is missing")
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	var applied := ProgressionService.apply_battle_result(candidate, result, encounter, catalog)
	if not applied.ok or applied.already_applied:
		return applied
	var saved := _save_candidate(candidate)
	if not saved.ok:
		return saved
	state = candidate
	return applied

## Partner side of a multiplayer double battle (see ProgressionService).
func apply_ally_battle_result(result: BattleResult, encounter_id: StringName, ally_prefix: String) -> Dictionary:
	if state == null or catalog == null:
		return _error("no_campaign", "there is no active campaign")
	var encounter := catalog.get_definition(encounter_id) as EncounterDefinition
	if encounter == null:
		return _error("missing_encounter", "double battle encounter %s is missing" % encounter_id)
	var candidate = StateScript.new()
	candidate.load_dictionary(state.to_dictionary(catalog.content_version, true))
	var applied := ProgressionService.apply_ally_battle_result(candidate, result, encounter, catalog, ally_prefix)
	if not applied.ok or applied.already_applied:
		return applied
	var saved := _save_candidate(candidate)
	if not saved.ok:
		return saved
	state = candidate
	return applied

func _error(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
