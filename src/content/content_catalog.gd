class_name ContentCatalog
extends Resource

const ROOM_GRAPH_BUILDER = preload("res://src/content/source_room_graph_builder.gd")
const ROOM_DEPTH_REFERENCE = preload("res://content/base/room_payloads/floor_1_room_a_payload.tres")
const LEGACY_MOD_FLAG_ALIASES := {
	&"holyBirb1": &"holyBird1",
	&"HolyBirb1": &"holyBird1",
	&"holyBirb2": &"holyBird2",
}

@export var content_version: String = "0.1.0-foundation"
@export var packs: Array[ContentPackDefinition] = []

var _by_id: Dictionary = {}
var _indexed_signature: Array = []
var _index_errors := PackedStringArray()

func ensure_index() -> PackedStringArray:
	# Runtime packs are stable between battles. Explicit rebuild_index remains
	# available for tools that edit definition fields in place.
	if _indexed_signature != _pack_signature():
		return rebuild_index()
	return _index_errors.duplicate()

func _pack_signature() -> Array:
	var signature: Array = [content_version]
	for pack in packs:
		signature.append(pack)
		if pack != null:
			signature.append(pack.source_room_graph_path)
			signature.append(pack.definitions.duplicate())
	return signature

func rebuild_index() -> PackedStringArray:
	_by_id.clear()
	var errors := PackedStringArray()
	for pack in packs:
		if pack == null:
			errors.append("catalog contains a null pack")
			continue
		for error in pack.validation_errors(): errors.append(error)
		_register(pack, errors)
		for definition in pack.definitions:
			if definition == null:
				errors.append("pack %s contains a null definition" % pack.id)
				continue
			for error in definition.validation_errors(): errors.append(error)
			_register(definition, errors)
		for room in ROOM_GRAPH_BUILDER.load_rooms(pack.source_room_graph_path, ROOM_DEPTH_REFERENCE.source_height_thresholds):
			for error in room.validation_errors(): errors.append(error)
			_register(room, errors)
	_bind_standard_map_trainers()
	_validate_references(errors)
	_indexed_signature = _pack_signature()
	_index_errors = errors.duplicate()
	return errors

func _bind_standard_map_trainers() -> void:
	# BaseTopDownLevel.PerformButtonAction makes HARD_TRAINER a Qui-tel
	# map giver throughout the standard tower, not just Floors 1 and 2.
	for definition in _by_id.values():
		if definition is not RoomDefinition:
			continue
		var room: RoomDefinition = definition
		var maps: Array[Dictionary] = []
		for interaction in room.interactions:
			if StringName(interaction.get("kind", "")) != &"trainer":
				continue
			var encounter := get_definition(StringName(interaction.get("encounter_id", ""))) as EncounterDefinition
			if encounter == null or encounter.source_trainer_type != "TrainerType.HARD_TRAINER" or encounter.source_floor_index >= 31:
				continue
			interaction["requires_tower_mode"] = "hard"
			var has_map := false
			for existing in room.interactions:
				if StringName(existing.get("kind", "")) == &"map_station" and int(existing.get("source_zone_id", -1)) == int(interaction.get("source_zone_id", -1)):
					has_map = true
					break
			if has_map:
				continue
			var map_interaction: Dictionary = interaction.duplicate(true)
			map_interaction["id"] = StringName("%s-map" % interaction.get("id", "trainer"))
			map_interaction["kind"] = &"map_station"
			map_interaction["requires_tower_mode"] = "standard"
			map_interaction["trainer_name"] = "Qui-tel Trainer"
			map_interaction["first_visit_text"] = "Here is a map to help you with this floor."
			map_interaction["return_text"] = "Use the map well."
			map_interaction.erase("encounter_id")
			maps.append(map_interaction)
		room.interactions.append_array(maps)

func get_definition(id: StringName) -> ContentDefinition:
	return _by_id.get(id) as ContentDefinition

func get_menu_definitions() -> Array[MenuDefinition]:
	var menus: Array[MenuDefinition] = []
	for definition in _by_id.values():
		if definition is MenuDefinition:
			menus.append(definition as MenuDefinition)
	menus.sort_custom(func(left: MenuDefinition, right: MenuDefinition) -> bool:
		if left.order != right.order:
			return left.order < right.order
		return String(left.id) < String(right.id)
	)
	return menus

func has_definition(id: StringName) -> bool:
	return _by_id.has(id)

static func canonical_mod_flag_id(flag_id: StringName) -> StringName:
	return StringName(LEGACY_MOD_FLAG_ALIASES.get(flag_id, flag_id))

func get_pack_for_mod_flag(flag_id: StringName) -> ContentPackDefinition:
	var canonical_flag := canonical_mod_flag_id(flag_id)
	for pack in packs:
		if pack != null and canonical_flag in pack.mod_flag_ids:
			return pack
	return null

func get_type_chart() -> TypeChartDefinition:
	for definition in _by_id.values():
		if definition is TypeChartDefinition: return definition as TypeChartDefinition
	return null

func _register(definition: ContentDefinition, errors: PackedStringArray) -> void:
	if definition.id.is_empty(): return
	if _by_id.has(definition.id):
		errors.append("duplicate content id: %s" % definition.id)
	else:
		_by_id[definition.id] = definition

func _validate_references(errors: PackedStringArray) -> void:
	var mod_flag_owners: Dictionary = {}
	for pack in packs:
		if pack == null: continue
		for flag_id in pack.mod_flag_ids:
			var canonical_flag := canonical_mod_flag_id(flag_id)
			if mod_flag_owners.has(canonical_flag):
				errors.append("mod flag %s is assigned to both %s and %s" % [canonical_flag, mod_flag_owners[canonical_flag], pack.id])
			else:
				mod_flag_owners[canonical_flag] = pack.id
	for definition in _by_id.values():
		if definition is MinionDefinition:
			var minion := definition as MinionDefinition
			for type_id in minion.type_ids: _require(type_id, minion.id, errors)
			for move_id in minion.initial_move_ids: _require(move_id, minion.id, errors)
			for move_id in minion.specialization_move_ids: _require(move_id, minion.id, errors)
			for tree_id in minion.talent_tree_ids: _require(tree_id, minion.id, errors)
			if not minion.evolution_id.is_empty(): _require(minion.evolution_id, minion.id, errors)
		elif definition is MoveDefinition:
			var move := definition as MoveDefinition
			_require(move.type_id, move.id, errors)
		elif definition is TalentTreeDefinition:
			var tree := definition as TalentTreeDefinition
			for node in tree.nodes:
				for move_id in node.get("move_ids", []): _require(StringName(move_id), tree.id, errors)
		elif definition is EncounterDefinition:
			var encounter := definition as EncounterDefinition
			for entry in encounter.team_entries:
				var minion_id := StringName(entry.get("definition_id", ""))
				if not _by_id.get(minion_id) is MinionDefinition:
					errors.append("%s references missing minion %s" % [encounter.id, minion_id])
				for move_id in entry.get("move_ids", []):
					if not _by_id.get(StringName(move_id)) is MoveDefinition:
						errors.append("%s references missing move %s" % [encounter.id, move_id])
		elif definition is RoomDefinition:
			var room := definition as RoomDefinition
			for encounter_id in room.encounter_ids:
				if not _by_id.get(encounter_id) is EncounterDefinition:
					errors.append("%s references missing encounter %s" % [room.id, encounter_id])
			for exit_data in room.exits:
				var target_id := StringName(exit_data.get("target_room_id", ""))
				var target_room := _by_id.get(target_id) as RoomDefinition
				if target_room == null:
					errors.append("%s references missing room %s" % [room.id, target_id])
				elif not StringName(exit_data.get("target_spawn_id", "")).is_empty() and StringName(exit_data.target_spawn_id) not in target_room.spawn_ids:
					errors.append("%s exit to %s references missing spawn %s" % [room.id, target_id, exit_data.target_spawn_id])
			var interaction_ids: Dictionary = {}
			for interaction in room.interactions:
				var interaction_id := StringName(interaction.get("id", ""))
				if interaction_id.is_empty() or interaction_ids.has(interaction_id):
					errors.append("%s has an empty or duplicate interaction ID" % room.id)
				interaction_ids[interaction_id] = true
				var interaction_encounter_id := StringName(interaction.get("encounter_id", ""))
				if not interaction_encounter_id.is_empty() and not _by_id.get(interaction_encounter_id) is EncounterDefinition:
					errors.append("%s interaction %s references missing encounter %s" % [room.id, interaction_id, interaction_encounter_id])
				elif not interaction_encounter_id.is_empty() and not room.encounter_ids.has(interaction_encounter_id):
					errors.append("%s interaction %s uses an encounter not attached to the room" % [room.id, interaction_id])
		elif definition is CampaignDefinition:
			var campaign := definition as CampaignDefinition
			if not _by_id.get(campaign.starting_room_id) is RoomDefinition:
				errors.append("%s references missing starting room %s" % [campaign.id, campaign.starting_room_id])
			for floor_data in campaign.floors:
				for room_id in floor_data.get("room_ids", []):
					if not _by_id.get(StringName(room_id)) is RoomDefinition:
						errors.append("%s references missing room %s" % [campaign.id, room_id])
		elif definition is ContentPackDefinition:
			for dependency in (definition as ContentPackDefinition).dependencies: _require(dependency, definition.id, errors)

func _require(reference_id: StringName, owner_id: StringName, errors: PackedStringArray) -> void:
	if reference_id.is_empty() or not _by_id.has(reference_id):
		errors.append("%s references missing id %s" % [owner_id, reference_id])
