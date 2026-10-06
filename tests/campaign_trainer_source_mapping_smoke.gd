extends SceneTree

const SOURCE := "res://development/extracted/full-20260908/script/scripts/"

func _initialize() -> void:
	_run.call_deferred()

func _regex(pattern: String) -> RegEx:
	var expression := RegEx.new()
	assert(expression.compile(pattern) == OK)
	return expression

func _dialogue(body: String, field: String) -> String:
	var found := _regex(field + '\\s*=\\s*"((?:\\\\.|[^"\\\\])*)"').search(body)
	return found.get_string(1).replace("\\'", "'").replace("\\n", "\n") if found != null else ""

func _run() -> void:
	await process_frame
	var catalog: ContentCatalog = root.get_node("CampaignRuntime").catalog
	var trainer_source := FileAccess.get_file_as_string(SOURCE + "TopDown/Trainers/TrainerSystem.as")
	var dex_source := FileAccess.get_file_as_string(SOURCE + "States/MinionDexID.as")
	var source_blocks: Dictionary = {}
	var markers := _regex('AddTrainerToFloor\\(TrainerType\\.(\\w+),(\\d+),(\\d+)\\);').search_all(trainer_source)
	for index in markers.size():
		var marker := markers[index]
		var key := "%s/%s" % [marker.get_string(2), marker.get_string(3)]
		if source_blocks.has(key): continue
		var end := markers[index + 1].get_start() if index + 1 < markers.size() else trainer_source.length()
		source_blocks[key] = trainer_source.substr(marker.get_end(), end - marker.get_end())
	var bases := {5: 18, 6: 21, 7: 24, 8: 33, 9: 26}
	var active_encounter_ids: Dictionary = {}
	var campaign := catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
	for floor_data in campaign.floors:
		if not bases.has(int(floor_data.floor_index)): continue
		for room_id in floor_data.room_ids:
			var room := catalog.get_definition(StringName(room_id)) as RoomDefinition
			assert(room != null)
			for encounter_id in room.encounter_ids: active_encounter_ids[encounter_id] = true
	var checked := 0
	var checked_minions := 0
	for definition in catalog._by_id.values():
		if not definition is EncounterDefinition: continue
		var encounter := definition as EncounterDefinition
		if not active_encounter_ids.has(encounter.id): continue
		if not bases.has(encounter.source_floor_index): continue
		var floor_index: int = encounter.source_floor_index
		var trainer_slot := int(String(encounter.source_trainer_id).get_slice("/", 3))
		var source_key := "%d/%d" % [floor_index, trainer_slot]
		assert(String(encounter.source_trainer_id) == "base:trainer/standard/" + source_key, "Trainer family must use its actual zero-based tower floor")
		assert(source_blocks.has(source_key), "Source trainer block missing: " + source_key)
		var body: String = source_blocks[source_key]
		var offset_match := _regex('m_extraMinionLevels\\s*=\\s*(-?\\d+)').search(body)
		var offset := int(offset_match.get_string(1)) if offset_match != null else 0
		assert(encounter.source_level_offset == offset)
		var minions := _regex('AddMinion\\(MinionDexID\\.DEX_ID_(\\w+),\\[([^\\]]+)\\]\\)').search_all(body)
		# Last block ends at the next function's first trainer; no AddMinion
		# occurs in the intervening function header.
		assert(minions.size() == encounter.team_entries.size())
		for slot in minions.size():
			var entry: Dictionary = encounter.team_entries[slot]
			var imported := catalog.get_definition(entry.definition_id) as MinionDefinition
			var dex_match := _regex('DEX_ID_' + minions[slot].get_string(1) + ':int\\s*=\\s*(\\d+)').search(dex_source)
			assert(dex_match != null and imported.legacy_numeric_id == int(dex_match.get_string(1)), "Wrong source minion for " + source_key)
			var numeric_moves := minions[slot].get_string(2).split(",")
			assert(entry.move_ids.size() == numeric_moves.size())
			for move_index in numeric_moves.size():
				var move := catalog.get_definition(entry.move_ids[move_index]) as MoveDefinition
				assert(move != null and move.legacy_numeric_id == int(numeric_moves[move_index]), "Wrong source talent/move sequence for " + source_key)
			assert(int(entry.level) == int(bases[floor_index]) and int(entry.source_level_offset) == offset, "Base level/offset mismatch for %s: %s, expected %s/%s" % [encounter.id, entry, bases[floor_index], offset])
			checked_minions += 1
		var state := CampaignState.new()
		state.pending_battle = {"encounter_id": String(encounter.id), "battle_id": "source-mapping-fixture"}
		var owned := OwnedMinionState.new()
		owned.instance_id = &"source-mapping-player"
		owned.definition_id = &"base:minion/fire_pig_1"
		owned.level = 26
		owned.learned_move_ids.assign((catalog.get_definition(owned.definition_id) as MinionDefinition).initial_move_ids)
		state.party.append(owned)
		var setup := CampaignProgressionService.build_battle_setup(state, catalog, encounter)
		assert(setup.ok)
		for combatant in setup.combatants:
			if int(combatant.team) == 1: assert(int(combatant.level) == int(bases[floor_index]) + offset)
		if floor_index == 5:
			assert(encounter.battle_modifier_configuration.is_empty(), "Original Floor 6 has no timer stones")
			var bound := false
			for room in catalog._by_id.values():
				if not room is RoomDefinition or encounter.id not in room.encounter_ids: continue
				for interaction in room.interactions:
					if StringName(interaction.get("encounter_id", "")) != encounter.id: continue
					assert(interaction.get("first_visit_text", "") == _dialogue(body, "m_whatTrainerSaysAtStart_notBeaten"))
					assert(interaction.get("lose_text", "") == _dialogue(body, "m_whatTrainerSaysAtLose"))
					bound = true
			assert(bound, "Preserved encounter ID must still resolve from its live room")
		checked += 1
	assert(checked == 25 and checked_minions == 125)
	print("PASS: 25 floor-6–10 source trainer mappings, 125 minions/move sequences, original levels applied once, native setup and Floor 6 live dialogue bindings")
	quit(0)
