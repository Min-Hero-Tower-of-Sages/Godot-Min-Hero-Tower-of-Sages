extends RefCounted

## Normalized from TrainerSystem and TrainerDataObject for standard and hard mode.
## Runtime does not need to parse the extracted ActionScript to show dialogue.
const DATA_PATH := "res://content/base/campaigns/source_trainer_dialogue.json"
static var _entries: Dictionary = {}

static func for_encounter(encounter: EncounterDefinition, state = null) -> Dictionary:
	if encounter == null:
		return {}
	if _entries.is_empty():
		var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if decoded is Dictionary:
			_entries = decoded
	var entry: Dictionary = _entries.get(String(encounter.source_trainer_id), {}).duplicate(true)
	if String(encounter.source_trainer_id).begins_with("base:trainer/hard/") and encounter.source_trainer_type in [&"TrainerType.HARD_TRAINER", &"TrainerType.EXPERT_TRAINER"] and String(entry.get("first_visit_text", "")).strip_edges().is_empty():
		entry["first_visit_text"] = "In Hard Mode, we must fight!"
	if encounter.source_trainer_type == &"TrainerType.TRAINER_GYM_5" and CampaignModService.enabled(state, "skill_gems"):
		entry["after_win_text"] = String(entry.get("after_win_text", "")).replace("With the talo Sage seal you have received a super strong gem.", "With the talo Sage seal you have unlocked Random Forge at the Gem Combiner. Combine three stat gems of the same tier to create a skill gem!")
	return entry
