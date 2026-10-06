class_name SaveRepository
extends RefCounted

const SAVE_SCHEMA_VERSION := 2
const SLOT_COUNT := 3
const REQUIRED_KEYS := ["schema_version", "content_version", "character", "party", "storage", "progression", "room_state", "safe_location", "active_mods", "pending_mods"]
const SCHEMA_2_KEYS := ["campaign_id", "current_room_id", "battle_sequence", "pending_battle", "applied_battle_ids", "last_battle_result"]

func save_slot(slot: int, state: Dictionary) -> Dictionary:
	if slot < 1 or slot > SLOT_COUNT: return _error("invalid_slot", "slot must be between 1 and 3")
	var payload := migrate_payload(state)
	if not payload.ok: return payload
	var normalized: Dictionary = payload.state
	var validation := validate(normalized)
	if not validation.ok: return validation
	var directory := DirAccess.open("user://")
	if directory == null: return _error("storage_unavailable", "cannot open user data directory")
	var live := _slot_path(slot)
	var temporary := live + ".tmp"
	var backup := live + ".bak"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return _error("write_failed", error_string(FileAccess.get_open_error()))
	file.store_string(JSON.stringify(normalized, "\t"))
	file.flush()
	file.close()
	var verify := _load_path(temporary)
	if not verify.ok:
		directory.remove(temporary.get_file())
		return verify
	if FileAccess.file_exists(live):
		if FileAccess.file_exists(backup): directory.remove(backup.get_file())
		var backup_error := directory.rename(live.get_file(), backup.get_file())
		if backup_error != OK: return _error("backup_failed", error_string(backup_error))
	var replace_error := directory.rename(temporary.get_file(), live.get_file())
	if replace_error != OK:
		if FileAccess.file_exists(backup): directory.rename(backup.get_file(), live.get_file())
		return _error("replace_failed", error_string(replace_error))
	return {"ok": true}

func load_slot(slot: int) -> Dictionary:
	if slot < 1 or slot > SLOT_COUNT: return _error("invalid_slot", "slot must be between 1 and 3")
	var result := _load_path(_slot_path(slot))
	if result.ok: return result
	var backup := _load_path(_slot_path(slot) + ".bak")
	if backup.ok:
		backup.recovered_from_backup = true
		return backup
	return result

func delete_slot(slot: int) -> Dictionary:
	if slot < 1 or slot > SLOT_COUNT:
		return _error("invalid_slot", "slot must be between 1 and 3")
	var directory := DirAccess.open("user://")
	if directory == null:
		return _error("storage_unavailable", "cannot open user data directory")
	var base_path := _slot_path(slot)
	var deleted := false
	# Remove recovery/temporary siblings too, otherwise a deleted save could be
	# silently restored from its atomic-write backup on the next load.
	for path in [base_path + ".tmp", base_path + ".bak", base_path]:
		if not FileAccess.file_exists(path):
			continue
		var remove_error := directory.remove(path.get_file())
		if remove_error != OK:
			return _error("delete_failed", error_string(remove_error))
		deleted = true
	return {"ok": true, "deleted": deleted}

func validate(payload: Dictionary) -> Dictionary:
	for key in REQUIRED_KEYS:
		if not payload.has(key): return _error("invalid_save", "missing required field: %s" % key)
	var schema := int(payload.schema_version)
	if schema > SAVE_SCHEMA_VERSION: return _error("unsupported_schema", "save schema %d is newer than %d" % [schema, SAVE_SCHEMA_VERSION])
	if schema < 1: return _error("invalid_save", "invalid schema version")
	if schema >= 2:
		for key in SCHEMA_2_KEYS:
			if not payload.has(key): return _error("invalid_save", "missing schema 2 field: %s" % key)
		if not payload.content_version is String:
			return _error("invalid_save", "content_version must be a string")
		if not payload.party is Array or not payload.storage is Array:
			return _error("invalid_save", "party and storage must be arrays")
		if payload.has("owned_gems") and not payload.owned_gems is Array:
			return _error("invalid_save", "owned_gems must be an array")
		for gem in payload.get("owned_gems", []):
			if not gem is Dictionary:
				return _error("invalid_save", "owned gem entries must be objects")
			for key in ["tier", "stat_id", "raw_stats", "facet_positions"]:
				if not gem.has(key):
					return _error("invalid_save", "owned gem is missing %s" % key)
			if int(gem.tier) < 1 or String(gem.stat_id) not in ["health", "energy", "attack", "healing", "speed"]:
				return _error("invalid_save", "owned gem tier or stat is invalid")
			if not gem.raw_stats is Array or gem.raw_stats.size() != 5 or not gem.facet_positions is Array or gem.facet_positions.size() != 12:
				return _error("invalid_save", "owned gem stats or facets are invalid")
		if not payload.applied_battle_ids is Array:
			return _error("invalid_save", "applied battle IDs must be an array")
		if int(payload.battle_sequence) < 0:
			return _error("invalid_save", "battle sequence must not be negative")
		for key in ["character", "progression", "room_state", "safe_location", "active_mods", "pending_mods", "pending_battle", "last_battle_result"]:
			if not payload[key] is Dictionary:
				return _error("invalid_save", "%s must be an object" % key)
		var instance_ids: Dictionary = {}
		for owned_list in [payload.party, payload.storage]:
			for owned in owned_list:
				if not owned is Dictionary:
					return _error("invalid_save", "owned minion entries must be objects")
				for key in ["instance_id", "definition_id", "level", "experience", "learned_move_ids"]:
					if not owned.has(key):
						return _error("invalid_save", "owned minion is missing %s" % key)
				var instance_id := String(owned.instance_id)
				if instance_id.is_empty() or instance_ids.has(instance_id):
					return _error("invalid_save", "owned minion instance IDs must be non-empty and unique")
				instance_ids[instance_id] = true
				if String(owned.definition_id).is_empty() or int(owned.level) < 1 or int(owned.level) > 60 or int(owned.experience) < 0:
					return _error("invalid_save", "owned minion identity, level, or experience is invalid")
				if not owned.learned_move_ids is Array:
					return _error("invalid_save", "owned minion learned_move_ids must be an array")
		var seen_battle_ids: Dictionary = {}
		for raw_battle_id in payload.applied_battle_ids:
			var battle_id := String(raw_battle_id)
			if battle_id.is_empty() or seen_battle_ids.has(battle_id):
				return _error("invalid_save", "applied battle IDs must be non-empty and unique")
			seen_battle_ids[battle_id] = true
	return {"ok": true}

func migrate_payload(payload: Dictionary) -> Dictionary:
	var migrated := payload.duplicate(true)
	var schema := int(migrated.get("schema_version", 1))
	if schema > SAVE_SCHEMA_VERSION:
		return _error("unsupported_schema", "save schema %d is newer than %d" % [schema, SAVE_SCHEMA_VERSION])
	if schema < 1:
		return _error("invalid_save", "invalid schema version")
	if schema == 1:
		var room_data := migrated.get("room_state", {}) as Dictionary
		var progression_data := migrated.get("progression", {}) as Dictionary
		var applied_ids: Array[String] = []
		var old_applied_id := String(progression_data.get("last_applied_battle", migrated.get("last_applied_battle", "")))
		if not old_applied_id.is_empty():
			applied_ids.append(old_applied_id)
		migrated["campaign_id"] = String(progression_data.get("campaign_id", ""))
		migrated["current_room_id"] = String(room_data.get("current_room_id", ""))
		migrated["battle_sequence"] = int(progression_data.get("battle_sequence", 0))
		migrated["pending_battle"] = {}
		migrated["applied_battle_ids"] = applied_ids
		var old_result: Variant = progression_data.get("last_battle_result", {})
		migrated["last_battle_result"] = old_result.duplicate(true) if old_result is Dictionary else {}
		migrated["schema_version"] = 2
	if not migrated.has("owned_gems"):
		migrated["owned_gems"] = []
	var validation := validate(migrated)
	if not validation.ok: return validation
	return {"ok": true, "state": migrated, "migrated_from_schema": schema if schema < SAVE_SCHEMA_VERSION else 0}

func _load_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return _error("not_found", "save does not exist")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return _error("read_failed", error_string(FileAccess.get_open_error()))
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary: return _error("corrupt_save", "save is not valid JSON object data")
	var migrated := migrate_payload(parsed)
	if not migrated.ok: return migrated
	return migrated

func _slot_path(slot: int) -> String:
	return "user://save_slot_%d.json" % slot

func _error(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
