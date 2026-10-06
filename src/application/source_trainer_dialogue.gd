extends RefCounted

## Normalized from TrainerSystem and TrainerDataObject for standard and hard mode.
## Runtime does not need to parse the extracted ActionScript to show dialogue.
const DATA_PATH := "res://content/base/campaigns/source_trainer_dialogue.json"
static var _entries: Dictionary = {}

static func for_encounter(encounter: EncounterDefinition) -> Dictionary:
	if encounter == null:
		return {}
	if _entries.is_empty():
		var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if decoded is Dictionary:
			_entries = decoded
	return _entries.get(String(encounter.source_trainer_id), {}).duplicate(true)
