class_name CampaignModService
extends RefCounted

const OPTIONS := [
	{"name": "Zanyu", "flags": ["dirtFish"], "description": "A legendary beast with a custom skill tree. Found in Floor 5-2."},
	{"name": "Stingaray", "flags": ["waterRay1", "waterRay2"], "description": "Water-infused minions. Found in Floors 1-3 and 3-1."},
	{"name": "Arkvian", "flags": ["holyBird1", "holyBird2"], "description": "Holy birds Arkvian and Arkclaw. Found in Floors 1-4 and 4-2."},
	{"name": "Ophan", "flags": ["HolyEye1", "HolyEye2", "HolyEye3"], "description": "A fast one-eyed minion and its evolutions. Found in Floors 4-2 and 5-3."},
	{"name": "Ice Content", "flags": ["iceFloor", "iMammoth1", "iMammoth2", "iMammoth3", "iUnicorn1", "iUnicorn2", "iUnicorn3", "iSloth1", "iSloth2", "iSloth3", "iSeal1", "iSeal2", "iSeal3"], "description": "Ice minions and moves for imported saves. The Ice Floor itself is unfinished: this does not add a playable floor."},
	{"name": "Nuzlocke", "flags": ["nuzlocke"], "description": "Fainted minions are permanently lost after battle. Losing your entire roster ends the run."},
	{"name": "No Regen", "flags": ["no_natural_regen"], "description": "No natural health refill within a floor. Explicit healing and entering another floor still restore health."},
	{"name": "Move Trees", "flags": ["restored_moves", "restored_martyr", "restored_righteous_fate"], "description": "Martyr for Holymantis/Foramare; Righteous Fate for Arkvian/Arkclaw. Adds talents using normal skill points."},
	{"name": "Shinies", "flags": ["shinies"], "description": "New minions have a 1 in 512 shiny chance. Cosmetic only. Their palette is saved and retained on evolution."},
	{"name": "Debug Mode", "flags": ["debug_mode"], "description": "Unlocks a debug mod menu in Settings: unlimited money, level-60 party minions and guaranteed shiny rolls."},
]
const CATEGORIES := [
	{"id": "minions", "name": "Extra Minions", "groups": ["dirtFish", "waterRay1", "holyBird1", "HolyEye1"], "description": "Add minion families to tower hatcheries. Select a mod to see where it can be found."},
	{"id": "challenges", "name": "Challenge Rules", "groups": ["nuzlocke", "no_natural_regen"], "description": "Optional rules for a tougher run. Read each rule before enabling it."},
	{"id": "experimental", "name": "Experimental Content", "groups": ["iceFloor"], "description": "Recovered, unfinished content. Read its limitations before enabling it."},
	{"id": "gameplay", "name": "Gameplay Tweaks", "groups": ["restored_moves", "shinies", "debug_mode"], "description": "Move-tree additions, shiny variants and optional access to debug settings."},
]
# Bits belong to the recovered egg-table format, not presentation ordering.
const EGG_POOL_BITS := {"dirtFish": 1, "waterRay1": 2, "holyBird1": 4, "HolyEye1": 8}

static func option_index(group: String) -> int:
	for index in OPTIONS.size():
		if OPTIONS[index].flags[0] == group: return index
	return -1

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
		if canonical in MINION_FLAGS or canonical in ["iceFloor", "nuzlocke", "no_natural_regen", "restored_moves", "restored_martyr", "restored_righteous_fate", "shinies", "debug_mode"]:
			result[canonical] = bool(flags[key])
	return result

static func enabled(state, flag: String) -> bool:
	return state != null and bool(state.active_mods.get(flag, false))

# Per-minion overlays: Arkvian shares Holymantis's base Holy tree, so never
# mutate the catalog tree or an addition would leak to other species/saves.
static func talent_tree(state, definition: MinionDefinition, tree_index: int, catalog: ContentCatalog) -> TalentTreeDefinition:
	var original := catalog.get_definition(definition.talent_tree_ids[tree_index]) as TalentTreeDefinition
	if original == null: return null
	var family := ""
	var column := 0
	var row := 2
	if enabled(state, "restored_moves") or enabled(state, "restored_martyr"):
		if definition.id == &"base:minion/holymantris_1" and tree_index == 1:
			family = "martyr"
		elif definition.id == &"base:minion/healinghorse_1" and tree_index == 1:
			family = "martyr"
			row = 3
	if (enabled(state, "restored_moves") or enabled(state, "restored_righteous_fate")) and definition.id in [&"arkvian:minion/holybird1", &"arkvian:minion/holybird2"] and tree_index == 0:
		family = "righteous_fate"
	if family.is_empty(): return original
	var tree := original.duplicate(true) as TalentTreeDefinition
	var moves: Array[String] = []
	for tier in range(1, 6): moves.append("base:move/%s/tier%d" % [family, tier])
	tree.nodes.append({"id": "extended:talent/%s/%s" % [String(definition.id), family], "column": column, "row": row, "move_ids": moves, "prerequisite_node_ids": []})
	return tree

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
	for flag in EGG_POOL_BITS:
		if enabled(state, flag): mask |= int(EGG_POOL_BITS[flag])
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
