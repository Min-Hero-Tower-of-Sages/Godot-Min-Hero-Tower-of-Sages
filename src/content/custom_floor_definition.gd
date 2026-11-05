class_name CustomFloorDefinition
extends ContentDefinition

@export var start_room_id: StringName
@export var room_ids: Array[StringName] = []
@export var required_mod_flag := ""

static func available(catalog: ContentCatalog, state: CampaignState) -> Array[CustomFloorDefinition]:
	var result: Array[CustomFloorDefinition] = []
	for pack in catalog.packs:
		for definition in pack.definitions:
			if definition is CustomFloorDefinition and definition.is_available(state):
				result.append(definition)
	result.sort_custom(func(a: CustomFloorDefinition, b: CustomFloorDefinition) -> bool:
		var order := a.display_name.naturalnocasecmp_to(b.display_name)
		return order < 0 if order != 0 else String(a.id) < String(b.id))
	return result

func is_available(state: CampaignState) -> bool:
	return required_mod_flag.is_empty() or CampaignModService.enabled(state, required_mod_flag)
