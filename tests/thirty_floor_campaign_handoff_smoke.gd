extends "res://tests/ten_floor_campaign_handoff_smoke.gd"

func _initialize() -> void:
	floor_count = 30
	_run.call_deferred()

func _natural_frontier(catalog: ContentCatalog, starter: OwnedMinionState) -> void:
	await super._natural_frontier(catalog, starter)
	var session := MemorySession.new()
	session.catalog = catalog
	session.campaign = catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
	session.state = CampaignState.new()
	session.state.campaign_id = session.campaign.id
	session.state.current_room_id = session.campaign.starting_room_id
	session.state.party.append(OwnedMinionState.from_dictionary(starter.to_dictionary()))
	# Explicit source route: optional floors backfill later, not immediately.
	var route := [0, 1, 2, 4, 5, 6, 7, 9, 10, 11, 12, 14, 15, 16, 17, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29]
	for floor_index in route:
		_check(session.enter_tower_lobby().ok, "Expanded route cannot return to Lobby")
		if not _check(session.select_tower_floor(floor_index).ok, "Expanded route cannot enter Floor %d" % (floor_index + 1)): continue
		var floor_data: Dictionary = CampaignTowerModeService.mode_floor_data(session.campaign, floor_index, &"standard")
		var boss: EncounterDefinition
		for room_id in floor_data.room_ids:
			var room := catalog.get_definition(StringName(room_id)) as RoomDefinition
			for encounter_id in room.encounter_ids:
				var encounter := catalog.get_definition(encounter_id) as EncounterDefinition
				if CampaignProgressionService._trainer_unlocks_floor(encounter.source_trainer_type):
					boss = encounter
					session.state.current_room_id = room.id
		if not _check(boss != null, "Expanded route missing boss"): continue
		var prepared: Dictionary = session.prepare_battle(boss.id)
		if not _check(prepared.ok, "Expanded route boss preparation: %s" % prepared): continue
		var result := BattleResult.new()
		result.battle_id = StringName(prepared.battle_id)
		result.winning_team = 0
		result.reason = &"elimination"
		_check(session.apply_battle_result(result).ok, "Expanded route settlement failed")
		if floor_index in [2, 7, 12, 17]:
			_check(floor_index + 1 not in session.state.progression.unlocked_floor_indices, "Optional floor unlocked prematurely")
			_check(floor_index + 2 in session.state.progression.unlocked_floor_indices, "Optional floor skip missing")
		elif floor_index in [6, 11, 16, 21]:
			_check(floor_index - 3 in session.state.progression.unlocked_floor_indices, "Optional floor backfill missing")
		if floor_index % 5 == 4:
			_check(int(session.state.progression.sage_seals) == int((floor_index + 1) / 5), "Sage seal family mismatch")
	_check(int(session.state.progression.sage_seals) == 6, "Floor 30 must award the sixth Sage seal")
