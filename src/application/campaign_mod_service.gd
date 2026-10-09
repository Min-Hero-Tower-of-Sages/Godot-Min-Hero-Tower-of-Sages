class_name CampaignModService
extends RefCounted

const OPTIONS := [
	{"name": "Zanyu", "flags": ["dirtFish"], "description": "A legendary beast with a custom skill tree. Found in Floor 5-2."},
	{"name": "Stingaray", "flags": ["waterRay1", "waterRay2"], "description": "Water-infused minions. Found in Floors 1-3 and 3-1."},
	{"name": "Arkvian", "flags": ["holyBird1", "holyBird2"], "description": "Holy birds Arkvian and Arkclaw. Found in Floors 1-4 and 4-2."},
	{"name": "Ophan", "flags": ["HolyEye1", "HolyEye2", "HolyEye3"], "description": "A fast one-eyed minion and its evolutions. Found in Floors 4-2 and 5-3."},
	{"name": "Ice Floor", "flags": ["iceFloor", "iMammoth1", "iMammoth2", "iMammoth3", "iUnicorn1", "iUnicorn2", "iUnicorn3", "iSloth1", "iSloth2", "iSloth3", "iSeal1", "iSeal2", "iSeal3"], "description": "Recovered Ice minions and moves. The reference Ice Floor route is unfinished; its minions can be imported from Flash saves."},
	{"name": "Nuzlocke", "flags": ["nuzlocke"], "description": "Fainted minions are permanently lost after battle. Losing your entire roster ends the run."},
	{"name": "No Regen", "flags": ["no_natural_regen"], "description": "No natural health refill within a floor. Explicit healing and entering another floor still restore health."},
]
const MINION_FLAGS := {
	"dirtFish": "zanyu:minion/dirtfish",
	"waterRay1": "stingaray:minion/waterray1", "waterRay2": "stingaray:minion/waterray2",
	"holyBird1": "arkvian:minion/holybird1", "holyBird2": "arkvian:minion/holybird2",
	"HolyEye1": "ophan:minion/holyeye1", "HolyEye2": "ophan:minion/holyeye2", "HolyEye3": "ophan:minion/holyeye3",
	"iMammoth1": "ice_floor:minion/imammoth1", "iMammoth2": "ice_floor:minion/imammoth2", "iMammoth3": "ice_floor:minion/imammoth3",
	"iUnicorn1": "ice_floor:minion/iunicorn1", "iUnicorn2": "ice_floor:minion/iunicorn2", "iUnicorn3": "ice_floor:minion/iunicorn3",
	"iSloth1": "ice_floor:minion/isloth1", "iSloth2": "ice_floor:minion/isloth2", "iSloth3": "ice_floor:minion/isloth3",
	"iSeal1": "ice_floor:minion/iseal1", "iSeal2": "ice_floor:minion/iseal2", "iSeal3": "ice_floor:minion/iseal3",
}
const EGG_TABLE_PATH := "res://content/mods/source_egg_tables.json"
static var _egg_tables: Dictionary = {}

static func normalize(flags: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in flags:
		var canonical := String(ContentCatalog.canonical_mod_flag_id(StringName(key)))
		if canonical in MINION_FLAGS or canonical in ["iceFloor", "nuzlocke", "no_natural_regen"]:
			result[canonical] = bool(flags[key])
	return result

static func enabled(state, flag: String) -> bool:
	return state != null and bool(state.active_mods.get(flag, false))

static func minion_is_available(state, definition: MinionDefinition) -> bool:
	if definition.source_mod == &"base": return true
	if state != null:
		for owned in state.party + state.storage:
			if owned.definition_id == definition.id: return true
	for flag in MINION_FLAGS:
		if String(definition.id) == String(MINION_FLAGS[flag]): return enabled(state, flag)
	return false # Internal trainer-only records and the excluded Eevee fixture.

static func egg_pool(state, source_floor: int, fallback: Dictionary) -> Dictionary:
	if _egg_tables.is_empty() and FileAccess.file_exists(EGG_TABLE_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EGG_TABLE_PATH))
		if parsed is Dictionary: _egg_tables = parsed
	var mask := 0
	for index in 4:
		if enabled(state, String(OPTIONS[index].flags[0])): mask |= 1 << index
	if mask == 0: return fallback
	var table: Dictionary = _egg_tables.get(str(mask), {})
	return table.get(str(source_floor), fallback).duplicate(true)

static func retire_fainted(state, fainted_ids: Array[StringName]) -> void:
	if fainted_ids.is_empty(): return
	var memorial: Array = state.progression.get("nuzlocke_memorial", []).duplicate(true)
	var lost_gems: Array[StringName] = []
	for index in range(state.party.size() - 1, -1, -1):
		var owned: OwnedMinionState = state.party[index]
		if owned.instance_id not in fainted_ids: continue
		memorial.append(owned.to_dictionary())
		lost_gems.append_array(owned.equipment_ids)
		state.party.remove_at(index)
	for index in range(state.owned_gems.size() - 1, -1, -1):
		if StringName(state.owned_gems[index].get("instance_id", "")) in lost_gems: state.owned_gems.remove_at(index)
	state.progression["nuzlocke_memorial"] = memorial
	# Keep a surviving stored roster usable if every active minion fainted.
	if state.party.is_empty():
		while not state.storage.is_empty() and state.party.size() < 5:
			state.party.append(state.storage.pop_front())
	state.progression["nuzlocke_run_ended"] = state.party.is_empty()
