extends SceneTree

const BUILDER = preload("res://src/domain/battle/legacy_minion_autobuilder.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var catalog: ContentCatalog = root.get_node("CampaignRuntime").catalog
	var state := CampaignState.new()
	var starter := OwnedMinionState.new()
	starter.instance_id = &"trainer-preparation-fixture"
	starter.definition_id = &"base:minion/fire_pig_1"
	starter.level = 10
	state.party.append(starter)
	var encounters := 0
	var opponents := 0
	for definition in catalog._by_id.values():
		if definition is not EncounterDefinition: continue
		var encounter: EncounterDefinition = definition
		if not String(encounter.source_trainer_id).begins_with("base:trainer/"): continue
		state.pending_battle = {"battle_id": "source-trainer/%s" % encounter.id, "encounter_id": String(encounter.id)}
		var setup := CampaignProgressionService.build_battle_setup(state, catalog, encounter)
		assert(setup.ok, str(setup))
		assert(setup == CampaignProgressionService.build_battle_setup(state, catalog, encounter), "Pending trainer rerolled on rebuild")
		var rng := BattleRng.new(hash("trainer/%s/%s" % [state.pending_battle.battle_id, encounter.id]))
		for index in encounter.team_entries.size():
			var entry: Dictionary = encounter.team_entries[index]
			var enemy: Dictionary = setup.combatants[state.party.size() + index]
			var species := catalog.get_definition(StringName(entry.definition_id)) as MinionDefinition
			var bonus: String = ["health", "energy", "attack", "healing", "speed"][int(rng.next_unit() * 5.0)]
			var level := int(entry.level) + (int(entry.get("source_level_offset", encounter.source_level_offset)) if encounter.source_floor_index < 31 else 0)
			assert(enemy.level == level, "Trainer level offset differs from LoadTrianer")
			var builder := BUILDER.new()
			var preferred: Array = entry.get("move_ids", [])
			var moves: Array[StringName] = builder.build(species, level, preferred, catalog, rng)
			assert(enemy.move_ids == moves, "Trainer did not use source talent preferences")
			assert(builder._known.size() - species.initial_move_ids.size() <= builder._budget)
			var stats := LegacyMinionStats.enemy_stats(species, level, encounter.source_floor_index, bonus)
			for stat in ["attack", "healing", "speed", "max_attack_stat", "max_healing_stat"]:
				assert(enemy[stat] == stats[stat], "Enemy stat/power multiplier missing")
			assert(enemy.health == stats.health and enemy.energy == stats.energy)
			opponents += 1
		encounters += 1
	# Independent source table: parse only the authoritative assignment calls,
	# then compare every floor/stat rather than restating the implementation.
	var source := FileAccess.get_file_as_string("res://development/extracted/full-20260908/script/scripts/PresistentData/StaticData.as")
	var rates: Array = []
	for floor_id in 62: rates.append([0.05, 0.055, 0.05, 0.05, 0.05])
	var overrides := RegEx.new()
	overrides.compile("this\\.AddEnemyStatIncreaseToFloor_NewValues\\((\\d+),([0-9.]+)\\)")
	for found in overrides.search_all(source):
		var value := float(found.get_string(2))
		rates[int(found.get_string(1))] = [value, value * 1.3, value, value, value]
	var tuned := RegEx.new()
	tuned.compile("this\\.AddEnemyStatIncreaseToFloor_FineTuning\\((\\d+),([0-9.]+),([0-9.]+),([0-9.]+),([0-9.]+),([0-9.]+)\\)")
	for found in tuned.search_all(source):
		for stat_index in 5: rates[int(found.get_string(1))][stat_index] = float(found.get_string(stat_index + 2))
	var probe := MinionDefinition.new()
	probe.gem_slots = 3
	probe.locked_gem_slots = 2
	for floor_id in 62:
		for stat_index in 5:
			var stat: String = ["health", "energy", "attack", "healing", "speed"][stat_index]
			assert(is_equal_approx(LegacyMinionStats.enemy_stat_multiplier(probe, floor_id, stat), 1.0 + rates[floor_id][stat_index] * 3), "Source floor coefficient mismatch")
	# Source-only preparation must not reinterpret extension-authored moves.
	var extension := EncounterDefinition.new()
	extension.id = &"fixture:encounter/explicit"
	extension.team_entries = [{"definition_id": starter.definition_id, "level": 3, "move_ids": [&"base:move/fire_bolt/tier5"], "slot_index": 0}]
	state.pending_battle = {"battle_id": "extension", "encounter_id": String(extension.id)}
	var explicit := CampaignProgressionService.build_battle_setup(state, catalog, extension)
	assert(explicit.ok and explicit.combatants[1].move_ids == [&"base:move/fire_bolt/tier5"])
	print("PASS: %d source trainer encounters / %d opponents, deterministic talent-budget preparation, hard levels, constructor/stat-power bonuses; all 62 source floor coefficient rows; explicit extensions preserved" % [encounters, opponents])
	quit()
