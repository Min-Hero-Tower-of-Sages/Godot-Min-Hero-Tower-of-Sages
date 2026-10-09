class_name CampaignState
extends RefCounted

const OWNED_MINION_SCRIPT = preload("res://src/domain/battle/owned_minion_state.gd")
const DEFAULT_PROGRESSION := {
	"currency": 0,
	"floor_index": 0,
	"unlocked_floor_indices": [0],
	"in_tower_lobby": false,
	"sage_seals": 0,
	"floor_keys": 0,
	"eggery_keys": 0,
	"boss_door_unlocked": false,
	"eggery_door_unlocked": false,
	"eggery_picks_remaining": 1,
	"eggery_taken_slots": [],
	"eggery_pick_sequence": 0,
	"map_unlocked": false,
	"grand_sage_met": false,
	"death_exp_tutorial_seen": false,
	"completed_encounters": {},
	"encounter_star_ratings": {},
	"star_upgrades": {},
}

var campaign_id: StringName = &""
var current_room_id: StringName = &""
var character: Dictionary = {}
var party: Array[OwnedMinionState] = []
var storage: Array[OwnedMinionState] = []
var owned_gems: Array[Dictionary] = []
var progression: Dictionary = DEFAULT_PROGRESSION.duplicate(true)
var room_state: Dictionary = {"current_room_id": "", "flags": {}}
var safe_location: Dictionary = {}
var active_mods: Dictionary = {}
var pending_mods: Dictionary = {}
var battle_sequence: int = 0
var pending_battle: Dictionary = {}
## Loss XP is committed before the blackout/checkpoint return. Persist the
## unfinished return so restarting cannot strand a defeated party in that room.
var pending_defeat_return: Dictionary = {}
var applied_battle_ids: Array[String] = []
var last_battle_result: Dictionary = {}
## Source m_currTrainerData survives room/menu changes, but is not saved.
## Its timer aura persists until another trainer loads; stages do not.
var runtime_trainer_bonus_move_ids: Array[StringName] = []

func to_dictionary(content_version: String = "", include_runtime_context: bool = false) -> Dictionary:
	var serialized_party: Array[Dictionary] = []
	var serialized_storage: Array[Dictionary] = []
	var serialized_gems: Array[Dictionary] = []
	for owned in party:
		serialized_party.append(owned.to_dictionary())
	for owned in storage:
		serialized_storage.append(owned.to_dictionary())
	for gem in owned_gems:
		serialized_gems.append(gem.duplicate(true))
	var serialized_room_state := room_state.duplicate(true)
	serialized_room_state["current_room_id"] = String(current_room_id)
	var data := {
		"schema_version": SaveRepository.SAVE_SCHEMA_VERSION,
		"content_version": content_version,
		"campaign_id": String(campaign_id),
		"current_room_id": String(current_room_id),
		"character": character.duplicate(true),
		"party": serialized_party,
		"storage": serialized_storage,
		"owned_gems": serialized_gems,
		"progression": progression.duplicate(true),
		"room_state": serialized_room_state,
		"safe_location": safe_location.duplicate(true),
		"active_mods": active_mods.duplicate(true),
		"pending_mods": pending_mods.duplicate(true),
		"battle_sequence": battle_sequence,
		"pending_battle": pending_battle.duplicate(true),
		"pending_defeat_return": pending_defeat_return.duplicate(true),
		"applied_battle_ids": applied_battle_ids.duplicate(),
		"last_battle_result": last_battle_result.duplicate(true),
	}
	if include_runtime_context:
		data["runtime_trainer_bonus_move_ids"] = runtime_trainer_bonus_move_ids.duplicate()
	return data

func load_dictionary(data: Dictionary) -> void:
	runtime_trainer_bonus_move_ids.assign(data.get("runtime_trainer_bonus_move_ids", []))
	party.clear()
	storage.clear()
	owned_gems.clear()
	campaign_id = StringName(data.get("campaign_id", ""))
	current_room_id = StringName(data.get("current_room_id", data.get("room_state", {}).get("current_room_id", "")))
	character = (data.get("character", {}) as Dictionary).duplicate(true)
	for raw_owned in data.get("party", []):
		if raw_owned is Dictionary:
			party.append(OWNED_MINION_SCRIPT.from_dictionary(raw_owned))
	for raw_owned in data.get("storage", []):
		if raw_owned is Dictionary:
			storage.append(OWNED_MINION_SCRIPT.from_dictionary(raw_owned))
	for raw_gem in data.get("owned_gems", []):
		if raw_gem is Dictionary:
			owned_gems.append(raw_gem.duplicate(true))
	progression = (data.get("progression", {}) as Dictionary).duplicate(true)
	# DynamicData.m_currMoney is an int. Recover older port saves that retained
	# fractional rewards using the same truncation, without rounding upward.
	progression["currency"] = int(progression.get("currency", 0))
	for key in DEFAULT_PROGRESSION:
		if not progression.has(key):
			progression[key] = DEFAULT_PROGRESSION[key].duplicate(true) if DEFAULT_PROGRESSION[key] is Array or DEFAULT_PROGRESSION[key] is Dictionary else DEFAULT_PROGRESSION[key]
	# JSON numbers decode as floats. Array.has/in compare their Variant types,
	# unlike scalar ==: integer floor 0 does not match saved float 0.0.
	var unlocked := _saved_integer_list(progression.get("unlocked_floor_indices", []), 0, 61)
	if 0 not in unlocked:
		unlocked.push_front(0) # Standard Floor 1 is always available.
	progression["unlocked_floor_indices"] = unlocked
	progression["eggery_taken_slots"] = _saved_integer_list(progression.get("eggery_taken_slots", []), 0, 8)
	room_state = (data.get("room_state", {}) as Dictionary).duplicate(true)
	for room_key in room_state:
		if room_state[room_key] is Dictionary and room_state[room_key].has("eggery_taken_slots"):
			room_state[room_key]["eggery_taken_slots"] = _saved_integer_list(room_state[room_key]["eggery_taken_slots"], 0, 8)
	safe_location = (data.get("safe_location", {}) as Dictionary).duplicate(true)
	active_mods = (data.get("active_mods", {}) as Dictionary).duplicate(true)
	pending_mods = (data.get("pending_mods", {}) as Dictionary).duplicate(true)
	battle_sequence = int(data.get("battle_sequence", 0))
	pending_battle = (data.get("pending_battle", {}) as Dictionary).duplicate(true)
	pending_defeat_return = (data.get("pending_defeat_return", {}) as Dictionary).duplicate(true)
	applied_battle_ids.assign(data.get("applied_battle_ids", []))
	last_battle_result = (data.get("last_battle_result", {}) as Dictionary).duplicate(true)

static func _saved_integer_list(raw_values: Variant, minimum: int, maximum: int) -> Array[int]:
	var result: Array[int] = []
	if not raw_values is Array:
		return result
	for raw_value in raw_values:
		if not raw_value is int and not raw_value is float:
			continue
		var value := int(raw_value)
		if value >= minimum and value <= maximum and float(value) == float(raw_value) and value not in result:
			result.append(value)
	return result

func validation_errors(catalog: ContentCatalog = null) -> PackedStringArray:
	var errors := PackedStringArray()
	if campaign_id.is_empty():
		errors.append("campaign state has no campaign ID")
	if current_room_id.is_empty():
		errors.append("campaign state has no current room ID")
	if (party.is_empty() and not bool(progression.get("nuzlocke_run_ended", false))) or party.size() > 5:
		errors.append("active party must contain between one and five minions")
	if battle_sequence < 0:
		errors.append("battle sequence must not be negative")
	var instance_ids: Dictionary = {}
	for owned in party + storage:
		if owned.instance_id.is_empty() or instance_ids.has(owned.instance_id):
			errors.append("owned minion instance IDs must be non-empty and unique")
			continue
		instance_ids[owned.instance_id] = true
		if owned.definition_id.is_empty():
			errors.append("owned minion %s has no definition ID" % owned.instance_id)
		if owned.level < 1 or owned.level > 60 or owned.experience < 0:
			errors.append("owned minion %s has invalid level or experience" % owned.instance_id)
		if catalog != null:
			var definition := catalog.get_definition(owned.definition_id) as MinionDefinition
			if definition == null:
				errors.append("owned minion %s references missing minion %s" % [owned.instance_id, owned.definition_id])
			else:
				for move_id in owned.learned_move_ids:
					if not catalog.get_definition(move_id) is MoveDefinition:
						errors.append("owned minion %s references missing move %s" % [owned.instance_id, move_id])
	var seen_battle_ids: Dictionary = {}
	for battle_id in applied_battle_ids:
		if battle_id.is_empty() or seen_battle_ids.has(battle_id):
			errors.append("applied battle IDs must be non-empty and unique")
		seen_battle_ids[battle_id] = true
	return errors
