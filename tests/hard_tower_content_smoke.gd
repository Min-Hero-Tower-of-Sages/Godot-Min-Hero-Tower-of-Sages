extends "res://tests/ten_floor_campaign_handoff_smoke.gd"

func _run() -> void:
	await process_frame
	var session := MemorySession.new()
	session.catalog = root.get_node("CampaignRuntime").catalog
	session.campaign = session.catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
	session.state = CampaignState.new()
	session.state.campaign_id = session.campaign.id
	session.state.current_room_id = session.campaign.starting_room_id
	session.state.progression["unlocked_floor_indices"] = range(62)
	var starter := OwnedMinionState.new()
	starter.instance_id = &"hard-tower-fixture"
	starter.definition_id = &"base:minion/fire_pig_1"
	starter.level = 60
	session.state.party.append(starter)
	var setups := 0
	var bound: Dictionary = {}
	for source_floor in 31:
		_check(session.enter_tower_lobby().ok, "Cannot return to Lobby")
		var selected: Dictionary = session.select_tower_floor(source_floor + 31)
		if not _check(selected.ok, "Hard floor %d selection failed: %s" % [source_floor + 1, selected]): continue
		var floor_data := CampaignTowerModeService.mode_floor_data(session.campaign, source_floor, &"hard")
		for room_id in floor_data.room_ids:
			var room := session.catalog.get_definition(StringName(room_id)) as RoomDefinition
			for encounter_id in room.encounter_ids:
				var original := session.catalog.get_definition(encounter_id) as EncounterDefinition
				var resolved := CampaignTowerModeService.resolve_encounter(session.catalog, original, source_floor + 31)
				if not _check(resolved.ok, "Hard room roster resolution missing"): continue
				var encounter: EncounterDefinition = resolved.encounter
				bound[encounter.source_trainer_id] = true
				_check(int(encounter.team_entries[0].source_level_offset) == 0 and encounter.source_level_offset == 0, "Hard trainer applies a standard-only level offset")
				session.state.current_room_id = room.id
				for interaction in room.interactions:
					if StringName(interaction.get("encounter_id", "")) != original.id: continue
					var spoken: Dictionary = session.interact(StringName(interaction.id))
					_check(spoken.ok and spoken.kind == &"trainer", "Cannot talk to hard-mode trainer")
				var prepared_native: Dictionary = session.prepare_battle(original.id)
				_check(prepared_native.ok and String(session.state.pending_battle.get("encounter_id", "")) == String(encounter.id), "Native hard-mode preparation uses the wrong roster")
				_check(session.cancel_pending_battle().ok, "Native hard preparation cancellation failed")
		for encounter in CampaignTowerModeService.hard_encounters_for_floor(session.catalog, source_floor + 31):
			session.state.pending_battle.clear()
			var prepared := CampaignProgressionService.prepare_battle(session.state, encounter)
			var setup := CampaignProgressionService.build_battle_setup(session.state, session.catalog, encounter)
			if not _check(prepared.ok and setup.ok, "Hard setup could not be built"): continue
			var rules := RuleSetDefinition.new()
			rules.configuration = {"ai_teams": [], "refill_on_activation": true, "battle_modifiers": encounter.battle_modifier_configuration.duplicate(true)}
			var engine := BattleEngine.new()
			var response := engine.start(setup, session.catalog, rules, BattleRng.new(123))
			_check(response.accepted, "Hard battle rejected %s: %s" % [encounter.id, response.message])
			var dialogue: Dictionary = preload("res://src/application/source_trainer_dialogue.gd").for_encounter(encounter)
			_check(not dialogue.is_empty(), "Hard dialogue missing")
			setups += 1
		session.state.pending_battle.clear()
	var unbound: Array[String] = []
	for source_floor in 31:
		for encounter in CampaignTowerModeService.hard_encounters_for_floor(session.catalog, source_floor + 31):
			if not bound.has(encounter.source_trainer_id): unbound.append(String(encounter.source_trainer_id))
	_check(setups == 151, "Hard source table does not contain 151 encounters")
	_check(unbound.is_empty(), "Hard source encounters lack room routes: %s" % [unbound])
	await _natural_hard_frontier(session.catalog, starter)
	print("%s: 31 hard floor selections, %d battle setups, %d room-bound rosters, source offsets/dialogue/modifiers" % ["PASS" if failures.is_empty() else "FAIL", setups, bound.size()])
	quit(0 if failures.is_empty() else 1)

func _natural_hard_frontier(catalog: ContentCatalog, starter: OwnedMinionState) -> void:
	var session := MemorySession.new()
	session.catalog = catalog
	session.campaign = catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
	session.state = CampaignState.new()
	session.state.campaign_id = session.campaign.id
	session.state.current_room_id = session.campaign.starting_room_id
	session.state.party.append(starter.duplicate_state())
	session.state.progression["unlocked_floor_indices"] = range(32)
	session.state.progression["sage_seals"] = 6
	for source_floor in 31:
		_check(session.enter_tower_lobby().ok, "Natural hard route cannot return to Lobby")
		_check(session.select_tower_floor(source_floor + 31).ok, "Natural hard frontier selection failed")
		var floor_data := CampaignTowerModeService.mode_floor_data(session.campaign, source_floor, &"hard")
		var boss: EncounterDefinition
		for room_id in floor_data.room_ids:
			var room := catalog.get_definition(StringName(room_id)) as RoomDefinition
			for encounter_id in room.encounter_ids:
				var encounter := catalog.get_definition(encounter_id) as EncounterDefinition
				if CampaignProgressionService._trainer_unlocks_floor(encounter.source_trainer_type):
					boss = encounter
					session.state.current_room_id = room.id
		if not _check(boss != null, "Natural hard floor has no boss"): continue
		var prepared: Dictionary = session.prepare_battle(boss.id)
		if not _check(prepared.ok, "Natural hard boss preparation failed"): continue
		var result := BattleResult.new()
		result.battle_id = StringName(prepared.battle_id)
		result.winning_team = 0
		result.reason = &"victory"
		_check(session.apply_battle_result(result).ok, "Natural hard boss settlement failed")
		if source_floor < 30:
			_check(source_floor + 32 in session.state.progression.unlocked_floor_indices, "Hard frontier did not unlock the next floor")
	_check(62 not in session.state.progression.unlocked_floor_indices, "Hard Grand Sage unlocked an invalid floor")
