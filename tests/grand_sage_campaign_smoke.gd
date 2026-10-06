extends "res://tests/ten_floor_campaign_handoff_smoke.gd"

func _run() -> void:
	await process_frame
	var session := MemorySession.new()
	session.catalog = root.get_node("CampaignRuntime").catalog
	session.campaign = session.catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
	session.state = CampaignState.new()
	session.state.campaign_id = session.campaign.id
	session.state.current_room_id = session.campaign.starting_room_id
	session.state.progression["unlocked_floor_indices"] = range(31)
	session.state.progression["sage_seals"] = 6
	session.state.progression["highest_beaten_floor"] = 30
	var starter := OwnedMinionState.new()
	starter.instance_id = &"grand-sage-fixture"
	starter.definition_id = &"base:minion/fire_pig_1"
	starter.level = 60
	session.state.party.append(starter)
	_check(not session.lobby_titan_status().can_claim_titans, "Titans available before Grand Sage")
	_check(session.enter_tower_lobby().ok, "Cannot enter Lobby")
	var selected: Dictionary = session.select_tower_floor(30)
	_check(selected.ok, "Grand Sage Floor 31 unavailable")
	var room := session.catalog.get_definition(session.state.current_room_id) as RoomDefinition
	_check(room.id == &"base:room/level_7_gym" and room.external_transitions.size() == 1, "Grand Sage room/Lobby exit missing")
	var encounter := session.catalog.get_definition(&"base:encounter/floor31_trainer_0") as EncounterDefinition
	_check(encounter != null and encounter.team_entries.size() == 5 and encounter.source_trainer_type == &"TrainerType.TRAINER_GRAND_SAGE", "Grand Sage source roster missing")
	var prepared: Dictionary = session.prepare_battle(encounter.id)
	_check(prepared.ok, "Cannot start Grand Sage battle")
	var result := BattleResult.new()
	result.battle_id = StringName(prepared.battle_id)
	result.winning_team = 0
	result.reason = &"victory"
	var settled: Dictionary = session.apply_battle_result(result)
	_check(settled.ok, "Grand Sage settlement failed")
	_check(CampaignTowerModeService.hard_mode_unlocked(session.state), "Grand Sage did not unlock hard mode")
	_check(session.lobby_titan_status().can_claim_titans, "Grand Sage completion still locks Titans")
	var dialogue: Dictionary = preload("res://src/application/source_trainer_dialogue.gd").for_encounter(encounter)
	_check(dialogue.trainer_name == "Grand Sage" and not String(dialogue.after_win_text).is_empty(), "Grand Sage dialogue missing")
	session.reject_save = true
	_check(not session.claim_lobby_titan().ok and session.state.party.size() == 1, "Rejected Titan save changed party")
	session.reject_save = false
	var claimed: Dictionary = session.claim_lobby_titan()
	_check(claimed.ok and claimed.granted_count == 2, "Both Titans must be granted without a sponsor gate")
	_check(not session.lobby_titan_status().can_claim_titans, "Titans can be claimed twice")
	print("%s: Floor 31 source room/roster/dialogue, synthetic Grand Sage settlement, hard-mode unlock and both atomic Titan rewards" % ["PASS" if failures.is_empty() else "FAIL"])
	quit(0 if failures.is_empty() else 1)
