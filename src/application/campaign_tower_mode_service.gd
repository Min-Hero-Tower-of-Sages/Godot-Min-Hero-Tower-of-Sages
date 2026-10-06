class_name CampaignTowerModeService
extends RefCounted

## The source tower has 31 regular floors followed by 31 hard-mode floors.
## Hard-mode global indices share the regular floor layout but use a separate
## progression/star range and hard-mode trainer records.
const STANDARD_FLOOR_COUNT := 31
const TOTAL_TOWER_FLOORS := 62
const HARD_MODE_LEVELS: Array[int] = [58, 59, 60]

static func select_mode(state: CampaignState, catalog: ContentCatalog, campaign: CampaignDefinition, mode: StringName) -> Dictionary:
	if state == null or catalog == null or campaign == null:
		return _error("invalid_context", "campaign state, catalog, and campaign are required")
	if mode != &"standard" and mode != &"hard":
		return _error("invalid_mode", "tower mode must be standard or hard")
	if mode == &"hard" and not hard_mode_unlocked(state):
		return _error("hard_mode_locked", "hard mode unlocks after clearing Standard Floor 31")
	var current_floor := int(state.progression.get("floor_index", 0))
	var source_floor := source_floor_index(current_floor)
	state.progression["tower_mode"] = String(mode)
	return {
		"ok": true,
		"mode": mode,
		"current_floor_index": tower_floor_index(source_floor, mode),
		"source_floor_index": source_floor,
		"floor_offset": STANDARD_FLOOR_COUNT if mode == &"hard" else 0,
		"unlocked_floor_indices": unlocked_display_indices(state, mode),
	}

## Resolves a clicked display slot into the source's global tower floor number
## and migrated base layout. Call this on a candidate before the session applies
## its normal floor-entry resets/rest/save logic.
static func floor_selection_context(state: CampaignState, catalog: ContentCatalog, campaign: CampaignDefinition, source_floor: int, mode: StringName) -> Dictionary:
	if state == null or catalog == null or campaign == null:
		return _error("invalid_context", "campaign state, catalog, and campaign are required")
	if mode != &"standard" and mode != &"hard":
		return _error("invalid_mode", "tower mode must be standard or hard")
	if source_floor < 0 or source_floor >= STANDARD_FLOOR_COUNT:
		return _error("floor_out_of_range", "source floor slot must be between 0 and 30")
	if mode == &"hard" and not hard_mode_unlocked(state):
		return _error("hard_mode_locked", "hard mode unlocks after clearing Standard Floor 31")
	var global_index := tower_floor_index(source_floor, mode)
	if not floor_is_unlocked(state, source_floor, mode):
		return _error("floor_locked", "floor %d has not been unlocked" % (global_index + 1))
	if not floor_has_mode_content(catalog, campaign, source_floor, mode):
		return _error("floor_content_unavailable", "floor %d has no recovered %s-mode content" % [global_index + 1, mode])
	var floor_data := mode_floor_data(campaign, source_floor, mode)
	var start_room_id := StringName(floor_data.get("start_room_id", ""))
	if start_room_id.is_empty():
		var room_ids: Array = floor_data.get("room_ids", [])
		if not room_ids.is_empty():
			start_room_id = StringName(room_ids[0])
	var room := catalog.get_definition(start_room_id) as RoomDefinition
	if room == null:
		return _error("missing_floor_start", "floor %d starting room %s is missing" % [global_index + 1, start_room_id])
	var spawn_id := StringName(floor_data.get("start_spawn_id", "start"))
	if spawn_id.is_empty() or spawn_id not in room.spawn_ids:
		return _error("missing_floor_spawn", "floor %d start room %s has no spawn %s" % [global_index + 1, room.id, spawn_id])
	state.progression["tower_mode"] = String(mode)
	state.progression["floor_index"] = global_index
	return {
		"ok": true,
		"mode": mode,
		"floor_index": global_index,
		"source_floor_index": source_floor,
		"floor_data": floor_data,
		"room": room,
		"spawn_id": spawn_id,
		"position": room.spawn_positions.get(String(spawn_id), Vector2.ZERO),
	}

static func hard_mode_unlocked(state: CampaignState) -> bool:
	if state == null:
		return false
	var unlocked: Array = state.progression.get("unlocked_floor_indices", [0])
	return STANDARD_FLOOR_COUNT in unlocked

static func selected_mode(state: CampaignState) -> StringName:
	if state == null:
		return &"standard"
	var mode := StringName(state.progression.get("tower_mode", "standard"))
	return &"hard" if mode == &"hard" and hard_mode_unlocked(state) else &"standard"

static func tower_floor_index(source_floor: int, mode: StringName) -> int:
	var base := clampi(source_floor, 0, STANDARD_FLOOR_COUNT - 1)
	return base + STANDARD_FLOOR_COUNT if mode == &"hard" else base

static func source_floor_index(tower_floor: int) -> int:
	return posmod(tower_floor, STANDARD_FLOOR_COUNT)

static func mode_for_global_floor(tower_floor: int) -> StringName:
	return &"hard" if tower_floor >= STANDARD_FLOOR_COUNT else &"standard"

static func floor_is_unlocked(state: CampaignState, source_floor: int, mode: StringName) -> bool:
	if state == null:
		return false
	var global_index := tower_floor_index(source_floor, mode)
	var unlocked: Array = state.progression.get("unlocked_floor_indices", [0])
	return global_index in unlocked

static func unlocked_display_indices(state: CampaignState, mode: StringName) -> Array[int]:
	var result: Array[int] = []
	if state == null:
		return result
	var global_start := STANDARD_FLOOR_COUNT if mode == &"hard" else 0
	var global_end := global_start + STANDARD_FLOOR_COUNT
	for value in state.progression.get("unlocked_floor_indices", [0]):
		var global_index := int(value)
		if global_index >= global_start and global_index < global_end:
			result.append(global_index - global_start)
	result.sort()
	return result

static func mode_floor_data(campaign: CampaignDefinition, source_floor: int, mode: StringName) -> Dictionary:
	if campaign == null or source_floor < 0 or source_floor >= STANDARD_FLOOR_COUNT:
		return {}
	for floor_data in campaign.floors:
		if int(floor_data.get("floor_index", -1)) == source_floor:
			var mapped: Dictionary = floor_data.duplicate(true)
			mapped["source_floor_index"] = source_floor
			mapped["floor_index"] = tower_floor_index(source_floor, mode)
			mapped["tower_mode"] = String(mode)
			if mode == &"hard":
				mapped["eggery_minion_base_level"] = hard_eggery_level(tower_floor_index(source_floor, mode))
			return mapped
	return {}

static func floor_has_mode_content(catalog: ContentCatalog, campaign: CampaignDefinition, source_floor: int, mode: StringName) -> bool:
	var floor_data := mode_floor_data(campaign, source_floor, mode)
	if floor_data.is_empty():
		return false
	if mode != &"hard":
		return true
	var tower_floor := tower_floor_index(source_floor, mode)
	var encounters_checked := 0
	for room_id in floor_data.get("room_ids", []):
		var room := catalog.get_definition(StringName(room_id)) as RoomDefinition
		if room == null:
			return false
		for normal_id in room.encounter_ids:
			var normal := catalog.get_definition(normal_id) as EncounterDefinition
			if normal == null or _hard_encounter_for(catalog, normal, tower_floor) == null:
				return false
			encounters_checked += 1
	return encounters_checked > 0

static func floor_star_count(state: CampaignState, catalog: ContentCatalog, campaign: CampaignDefinition, source_floor: int, mode: StringName) -> int:
	if state == null or catalog == null or campaign == null:
		return 0
	var floor_data := mode_floor_data(campaign, source_floor, mode)
	if floor_data.is_empty():
		return 0
	var encounter_ids: Dictionary = {}
	if mode == &"hard":
		for encounter in hard_encounters_for_floor(catalog, tower_floor_index(source_floor, mode)):
			encounter_ids[String(encounter.id)] = true
	else:
		for room_id in floor_data.get("room_ids", []):
			var room := catalog.get_definition(StringName(room_id)) as RoomDefinition
			if room == null:
				continue
			for encounter_id in room.encounter_ids:
				encounter_ids[String(encounter_id)] = true
	var ratings: Dictionary = state.progression.get("encounter_star_ratings", {})
	var total := 0
	for encounter_id in encounter_ids:
		total += clampi(int(ratings.get(encounter_id, 0)), 0, 3)
	var hard_cap := 18 if mode == &"hard" else 12
	if source_floor % 5 == 4 or source_floor == STANDARD_FLOOR_COUNT - 1:
		hard_cap = 3
	return mini(hard_cap, total)

static func resolve_encounter(catalog: ContentCatalog, normal_encounter: EncounterDefinition, tower_floor: int) -> Dictionary:
	if catalog == null or normal_encounter == null:
		return _error("invalid_encounter", "catalog and source encounter are required")
	if tower_floor < STANDARD_FLOOR_COUNT:
		return {"ok": true, "encounter": normal_encounter, "mode": &"standard", "tower_floor_index": tower_floor}
	if tower_floor >= TOTAL_TOWER_FLOORS:
		return _error("floor_out_of_range", "tower floor index is outside the 31-floor hard tower")
	var hard_id := hard_trainer_id(normal_encounter.source_trainer_id, tower_floor)
	var hard_encounter := _hard_encounter_for(catalog, normal_encounter, tower_floor)
	if hard_encounter == null:
		return _error("hard_encounter_unavailable", "no recovered hard-mode roster exists for %s on floor %d" % [hard_id, tower_floor + 1])
	var scaled := hard_encounter.duplicate(true) as EncounterDefinition
	var hard_level := hard_mode_level(tower_floor)
	scaled.source_floor_index = tower_floor
	scaled.source_level_offset = 0
	var normalized_entries: Array[Dictionary] = []
	for raw_entry in scaled.team_entries:
		var entry: Dictionary = raw_entry.duplicate(true)
		entry["level"] = hard_level
		# LoadTrianer's floor >= 31 branch deliberately omits extraMinionLevels.
		# The catalog resource retains authored metadata; only this resolved copy
		# changes. Modifier-spawn level offsets are a separate source mechanism.
		entry["source_level_offset"] = 0
		normalized_entries.append(entry)
	scaled.team_entries = normalized_entries
	return {"ok": true, "encounter": scaled, "mode": &"hard", "tower_floor_index": tower_floor, "enemy_level": hard_level, "source_trainer_id": hard_id}

static func hard_encounters_for_floor(catalog: ContentCatalog, tower_floor: int) -> Array[EncounterDefinition]:
	var result: Array[EncounterDefinition] = []
	if catalog == null or tower_floor < STANDARD_FLOOR_COUNT or tower_floor >= TOTAL_TOWER_FLOORS:
		return result
	for encounter in _all_encounters(catalog):
		if encounter.source_floor_index == tower_floor and String(encounter.source_trainer_id).begins_with("base:trainer/hard/"):
			result.append(encounter)
	result.sort_custom(func(left: EncounterDefinition, right: EncounterDefinition) -> bool: return String(left.source_trainer_id) < String(right.source_trainer_id))
	return result

static func hard_mode_level(tower_floor: int) -> int:
	if tower_floor < STANDARD_FLOOR_COUNT or tower_floor >= TOTAL_TOWER_FLOORS:
		return 0
	var hard_relative_floor := tower_floor - STANDARD_FLOOR_COUNT
	if hard_relative_floor < HARD_MODE_LEVELS.size():
		return HARD_MODE_LEVELS[hard_relative_floor]
	return 60

static func hard_eggery_level(tower_floor: int) -> int:
	## Source StaticData.GetRandomMinion forces every hard-mode hatchling to 55,
	## independent of the indexed hard floor's normal level table.
	return 55 if mode_for_global_floor(tower_floor) == &"hard" else 0

static func hard_trainer_id(standard_trainer_id: StringName, tower_floor: int) -> StringName:
	if tower_floor < STANDARD_FLOOR_COUNT or tower_floor >= TOTAL_TOWER_FLOORS:
		return &""
	var trainer_slot := String(standard_trainer_id).get_file()
	if trainer_slot.is_empty():
		return &""
	var hard_floor_number := tower_floor - STANDARD_FLOOR_COUNT + 1
	return StringName("base:trainer/hard/%d/room/%s" % [hard_floor_number, trainer_slot])

static func _hard_encounter_for(catalog: ContentCatalog, normal_encounter: EncounterDefinition, tower_floor: int) -> EncounterDefinition:
	if catalog == null or normal_encounter == null:
		return null
	var hard_id := hard_trainer_id(normal_encounter.source_trainer_id, tower_floor)
	for candidate in _all_encounters(catalog):
		if candidate.source_floor_index == tower_floor and candidate.source_trainer_id == hard_id:
			return candidate
	return null

static func _all_encounters(catalog: ContentCatalog) -> Array[EncounterDefinition]:
	var result: Array[EncounterDefinition] = []
	for pack in catalog.packs:
		if pack == null:
			continue
		for definition in pack.definitions:
			if definition is EncounterDefinition:
				result.append(definition as EncounterDefinition)
	return result

static func _error(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
