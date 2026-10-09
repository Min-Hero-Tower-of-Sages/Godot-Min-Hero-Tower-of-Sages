class_name FlashSaveImportService
extends RefCounted

const Reader = preload("res://src/infrastructure/flash_shared_object_reader.gd")
const Mods = preload("res://src/application/campaign_mod_service.gd")
const STAT_IDS := ["health", "energy", "attack", "healing", "speed"]
const STAR_IDS := ["health", "energy", "attack", "healing", "speed", "movement_speed", "experience", "money"]
# Numeric indices are from the recovered States.TutorialTypes constants.
const TUTORIAL_FLAGS := {
	1: "key_keepers_tutorial_seen", 2: "battle_basics_tutorial_seen",
	3: "move_select_tutorial_seen", 7: "energy_tutorial_seen",
	8: "type_effectiveness_tutorial_seen", 9: "focus_targets_tutorial_seen",
	10: "tank_tutorial_seen", 12: "gem_tutorial_seen",
	16: "death_exp_tutorial_seen", 18: "boss_room_tutorial_seen",
	21: "bonus_floor_tutorial_seen", 22: "shield_modifier_tutorial_seen",
	23: "move_timer_modifier_tutorial_seen", 24: "extra_minions_modifier_tutorial_seen",
	25: "resurrection_modifier_tutorial_seen",
}

## Build a candidate in memory only. Source files and Godot slots are untouched.
func preview_file(path: String, catalog: ContentCatalog, character_name: String = "", gender: String = "male") -> Dictionary:
	var decoded: Dictionary = Reader.new().read_file(path)
	if not decoded.ok: return decoded
	if not String(decoded.name).begins_with("TCrpgSaveSlot"):
		return _error("Select TCrpgSaveSlot0.sol, 1.sol or 2.sol, not the initial metadata file.")
	var slot_text := String(decoded.name).trim_prefix("TCrpgSaveSlot")
	if slot_text not in ["0", "1", "2"]: return _error("Unrecognized Min Hero Flash slot name.")
	var metadata_path := path.get_base_dir().path_join("TCrpgInitialData.sol")
	var metadata: Dictionary = {}
	if FileAccess.file_exists(metadata_path):
		var initial: Dictionary = Reader.new().read_file(metadata_path)
		if initial.ok and initial.name == "TCrpgInitialData": metadata = initial.data
	if character_name.strip_edges().is_empty():
		character_name = String(metadata.get("m_characterNames" + slot_text, "Flash Hero"))
	if metadata.has("m_isMaleMetaData" + slot_text):
		gender = "male" if bool(metadata["m_isMaleMetaData" + slot_text]) else "female"
	var result := convert_fields(decoded.data, catalog, character_name, gender)
	if result.ok and metadata.has("m_totalSageSeals" + slot_text):
		result.state.progression["sage_seals"] = clampi(int(metadata["m_totalSageSeals" + slot_text]), 0, 6)
	return result

func convert_fields(data: Dictionary, catalog: ContentCatalog, character_name: String = "Flash Hero", gender: String = "male") -> Dictionary:
	if catalog == null: return _error("Content catalog is unavailable.")
	if not data.has("m_currFloorOfTower") or not data.has("m_currMoney"):
		return _error("This file does not contain Min Hero campaign save data.")
	# SaveAllData writes scalar values only. Reject malformed fields before casts.
	for key in data:
		if not key is String or not (data[key] == null or data[key] is bool or data[key] is int or data[key] is float or data[key] is String):
			return _error("Invalid field type in Flash save: %s" % key)
	var field_error := _validate_field_types(data)
	if not field_error.is_empty(): return _error(field_error)
	var definitions: Dictionary = {}
	var moves: Dictionary = {}
	var encounters: Array[EncounterDefinition] = []
	for pack in catalog.packs:
		for definition in pack.definitions:
			if definition is MinionDefinition and definition.legacy_numeric_id >= 0 and definition.source_mod == &"base":
				definitions[definition.legacy_numeric_id] = definition
			elif definition is MoveDefinition and definition.legacy_numeric_id >= 0:
				moves[definition.legacy_numeric_id] = definition
			elif definition is EncounterDefinition: encounters.append(definition)
	var state := CampaignState.new()
	state.campaign_id = &"base:campaign/standard_tower"
	state.character = {"name": character_name.strip_edges().left(32), "gender": gender}
	var warnings: Array[String] = []
	var raw_flags: Dictionary = {}
	for key in data:
		if key.begins_with("m_isMod_"): raw_flags[key.trim_prefix("m_isMod_")] = data[key]
	state.active_mods = Mods.normalize(raw_flags)
	for index in 200:
		var prefix := "minion%d" % index
		if not bool(data.get(prefix, false)): continue
		var definition: MinionDefinition
		var mod_name := String(ContentCatalog.canonical_mod_flag_id(StringName(data.get(prefix + "ModName", ""))))
		if mod_name.is_empty() or mod_name == "Vanilla":
			definition = definitions.get(int(data.get(prefix + "dexID", -1))) as MinionDefinition
		else:
			definition = catalog.get_definition(StringName(Mods.MINION_FLAGS.get(mod_name, ""))) as MinionDefinition
			if definition != null: state.active_mods[mod_name] = true
		if definition == null: return _error("Cannot translate %s (dex %s, mod %s). No minion was discarded." % [prefix, data.get(prefix + "dexID", "?"), mod_name])
		var owned := OwnedMinionState.new()
		owned.instance_id = StringName("flash-" + prefix)
		owned.definition_id = definition.id
		owned.nickname = String(data.get(prefix + "name", definition.display_name))
		owned.experience = maxi(0, int(data.get(prefix + "exp", 1000)))
		owned.level = clampi(owned.experience / 1000, 1, 60)
		owned.stat_bonus = StringName(STAT_IDS[clampi(int(data.get(prefix + "statBonus", 0)), 0, 4)])
		owned.persistent_health = maxi(0, int(data.get(prefix + "currHealth", 0)))
		for move_index in 25:
			var numeric_id := int(data.get(prefix + "move%d" % move_index, -99))
			if numeric_id < 0: continue
			var move := moves.get(numeric_id) as MoveDefinition
			if move == null: return _error("Cannot translate move %d on %s. Import cancelled without changing any save." % [numeric_id, prefix])
			if move.id not in owned.learned_move_ids: owned.learned_move_ids.append(move.id)
		if owned.learned_move_ids.is_empty(): owned.learned_move_ids.assign(definition.initial_move_ids)
		for socket in 4:
			var gem_prefix := prefix + "gem%d" % socket
			owned.equipment_ids.append(&"")
			if bool(data.get(gem_prefix, false)):
				var gem := _gem(data, gem_prefix)
				if gem.is_empty(): return _error("Invalid equipped gem: " + gem_prefix)
				state.owned_gems.append(gem)
				owned.equipment_ids[socket] = StringName(gem.instance_id)
		if index < 5: state.party.append(owned)
		else: state.storage.append(owned)
	if state.party.is_empty(): return _error("The Flash save contains no active party. Import needs at least one minion in the first five Flash slots.")
	var inventory: Array[String] = []
	for index in 1485:
		var prefix := "gem%d" % index
		inventory.append("")
		if not bool(data.get(prefix, false)): continue
		var gem := _gem(data, prefix)
		if gem.is_empty(): return _error("Invalid inventory gem: " + prefix)
		state.owned_gems.append(gem)
		inventory[index] = String(gem.instance_id)
	state.progression["gem_inventory_slots"] = inventory
	var floor_index := int(data.m_currFloorOfTower)
	if floor_index < 0 or floor_index >= 62: return _error("Unsupported Flash floor index: %d" % floor_index)
	state.progression["floor_index"] = floor_index
	state.progression["tower_mode"] = "hard" if floor_index >= 31 else "standard"
	state.progression["currency"] = maxi(0, int(data.m_currMoney))
	state.progression["grand_sage_met"] = bool(data.get("m_hasTalkedToTheGrandSageForTheFirstTime", false))
	var unlocked: Array[int] = [0]
	var highest_beaten := 0
	var seals := 0
	for index in 62:
		if bool(data.get("m_hasBeatenFloor%d" % index, false)):
			highest_beaten = maxi(highest_beaten, index + 1)
			if index not in unlocked: unlocked.append(index)
			if index < 61 and index + 1 not in unlocked: unlocked.append(index + 1)
	if floor_index not in unlocked: unlocked.append(floor_index)
	state.progression["highest_beaten_floor"] = highest_beaten
	state.progression["unlocked_floor_indices"] = unlocked
	var completed: Dictionary = {}
	var ratings: Dictionary = {}
	for encounter in encounters:
		var parts := String(encounter.source_trainer_id).split("/")
		if parts.size() < 4: continue
		# DynamicData subtracts one from every nonzero trainer ID when saving
		# its arrays; sage ID zero uses array slot zero directly.
		var trainer_slot := maxi(0, int(parts[-1]) - 1)
		var index := encounter.source_floor_index
		var suffix := "%dslot%d" % [index, trainer_slot]
		if bool(data.get("m_hasBeatenTrainer" + suffix, false)):
			completed[String(encounter.id)] = true
			if String(encounter.source_trainer_type).begins_with("TrainerType.TRAINER_GYM_") and index < 31:
				seals = maxi(seals, int(String(encounter.source_trainer_type).trim_prefix("TrainerType.TRAINER_GYM_")))
		ratings[String(encounter.id)] = clampi(int(data.get("m_bestTrainerStarCounts" + suffix, 0)), 0, 3)
	state.progression["sage_seals"] = seals
	state.progression["completed_encounters"] = completed
	state.progression["encounter_star_ratings"] = ratings
	var upgrades: Dictionary = {}
	for index in STAR_IDS.size(): upgrades[STAR_IDS[index]] = clampi(int(data.get("m_starUpgradeAmounts%d" % index, 0)), 0, 100)
	state.progression["star_upgrades"] = upgrades
	var map_floors: Array[int] = []
	for index in 62:
		if bool(data.get("m_isMapUnlocked%d" % index, false)): map_floors.append(index)
	state.progression["map_unlocked_floor_indices"] = map_floors
	state.progression["map_unlocked"] = floor_index in map_floors
	# Raw values stay archived for future migrations; Flash never saved IVs,
	# current energy, chest history or the per-egg selection identities.
	state.progression["flash_import"] = {"version": 1, "source_fields": data.duplicate(true)}
	state.progression["flash_import_visit_flags_pending"] = range(62)
	state.progression["flash_resume_floor"] = {
		"floor_index": floor_index,
		"floor_keys": maxi(0, int(data.get("m_currKeysOnFloor", 0))),
		"eggery_keys": maxi(0, int(data.get("m_currEggeryKeys", 0))),
		"boss_door_unlocked": bool(data.get("m_hasUnlockedBossDoor", false)),
		"eggery_door_unlocked": bool(data.get("m_hasUnlockedEggeryDoor", false)),
		"eggery_picks_remaining": clampi(int(data.get("m_numOfMinionsLeftToChoose", 1)), 0, 3),
		"map_unlocked": bool(data.get("m_isMapUnlocked%d" % (floor_index % 31), false)),
	}
	CampaignProgressionService.refresh_minion_pedia(state)
	var room := catalog.get_definition(&"base:room/main_tower_lobby") as RoomDefinition
	if room == null: return _error("The tower lobby is missing from the catalog.")
	state.current_room_id = room.id
	state.progression["in_tower_lobby"] = true
	var position: Vector2 = room.spawn_positions.get("lobby_from_floor", Vector2.ZERO)
	var location := {"room_id": String(room.id), "spawn_id": "lobby_from_floor", "position": [position.x, position.y], "facing": String(room.spawn_directions.get("lobby_from_floor", "down"))}
	state.safe_location = location.duplicate(true)
	state.room_state = {"current_room_id": String(room.id), "flags": {}, "current_location": location}
	var repaired := repair_import_state(state, catalog)
	if not repaired.ok: return repaired
	warnings.append("Resume at the tower lobby. Selecting your saved floor once restores its keys, doors, remaining egg picks and trainer progress; other floor visits reset as in Flash.")
	warnings.append("Flash did not save IVs or current energy; these use the port defaults. Original fields are archived inside the imported save.")
	if bool(state.active_mods.get("iceFloor", false)): warnings.append("Ice minions/moves are retained; the reference Ice Floor route is unfinished.")
	var errors := state.validation_errors(catalog)
	if not errors.is_empty(): return _error("\n".join(errors))
	return {"ok": true, "state": state.to_dictionary(catalog.content_version), "warnings": warnings, "summary": "%s — %d party, %d stored, %d gems, %d coins; %d unlocked floors" % [state.character.name, state.party.size(), state.storage.size(), state.owned_gems.size(), int(state.progression.currency), unlocked.size()]}

## Versioned once-only repair also applies to slots imported before this fix.
## Never heal on subsequent loads: damage earned in the port must persist.
static func repair_import_state(state: CampaignState, catalog: ContentCatalog) -> Dictionary:
	var imported: Dictionary = state.progression.get("flash_import", {})
	if imported.is_empty() or int(imported.get("version", 1)) >= 2:
		return {"ok": true, "changed": false}
	var fields: Dictionary = imported.get("source_fields", {})
	for index in TUTORIAL_FLAGS:
		var flag: String = TUTORIAL_FLAGS[index]
		var source_key := "m_hasTutorialsBeenSeen%d" % index
		# Do not undo a tutorial acknowledged since the original import.
		state.progression[flag] = bool(state.progression.get(flag, false)) or bool(fields.get(source_key, false))
	var healed := CampaignProgressionService.rest_party(state, catalog, true)
	if not healed.ok: return healed
	imported["version"] = 2
	state.progression["flash_import"] = imported
	return {"ok": true, "changed": true}

func _gem(data: Dictionary, prefix: String) -> Dictionary:
	var tier := int(data.get(prefix + "tier", 0))
	if tier < 1 or tier > 20: return {}
	var stats: Array[float] = []
	var facets: Array[int] = []
	var main := 0
	for index in 5:
		var value := float(data.get(prefix + "stat%d" % index, 0.0))
		if not is_finite(value) or value < 0.0: return {}
		stats.append(value)
		if value > stats[main]: main = index
	for index in 12: facets.append(int(data.get(prefix + "facet%d" % index, index * 30)))
	var gem := {"instance_id": "flash-" + prefix, "tier": tier, "stat_id": STAT_IDS[main], "stat_label": CampaignGemFactory.STAT_LABELS[main], "raw_stats": stats, "facet_positions": facets}
	gem["stat_value"] = CampaignGemEquipmentService._extra_stat(gem, main)
	return gem

func _validate_field_types(data: Dictionary) -> String:
	var numeric := RegEx.new()
	numeric.compile("^(m_curr(FloorOfTower|Money|KeysOnFloor|EggeryKeys)|m_numOfMinionsLeftToChoose|m_(bestTrainerStarCounts|starUpgradeAmounts)|minion[0-9]+(dexID|exp|statBonus|currHealth|move[0-9]+)|(?:minion[0-9]+)?gem[0-9]+(tier|stat[0-9]+|facet[0-9]+))")
	var flags := RegEx.new()
	flags.compile("^(m_(isMod_|hasBeaten|hasTutorialsBeenSeen|isMapUnlocked|hasUnlocked|hasTalkedTo)|minion[0-9]+(?:gem[0-9]+)?$|gem[0-9]+$)")
	for key in data:
		var value: Variant = data[key]
		if numeric.search(key) != null:
			if not (value is int or value is float) or not is_finite(float(value)):
				return "Expected a finite number in Flash field: " + key
		elif flags.search(key) != null:
			if not value is bool and not ((value is int or value is float) and value in [0, 1, 0.0, 1.0]):
				return "Expected a boolean in Flash field: " + key
		elif key.begins_with("minion") and (key.ends_with("name") or key.ends_with("ModName")) and not value is String:
			return "Expected text in Flash field: " + key
	return ""

func _error(message: String) -> Dictionary:
	return {"ok": false, "code": "flash_import_failed", "message": message}
