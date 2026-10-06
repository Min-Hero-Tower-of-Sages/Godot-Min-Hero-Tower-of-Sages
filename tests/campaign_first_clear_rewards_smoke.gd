extends SceneTree

class MemorySession extends CampaignSession:
	var reject_save := false
	func _save_candidate(_candidate) -> Dictionary:
		return {"ok": not reject_save, "code": "fixture_rejection" if reject_save else ""}

func _initialize() -> void:
	_run.call_deferred()

func _result(prepared: Dictionary) -> BattleResult:
	var result := BattleResult.new()
	result.battle_id = StringName(prepared.battle_id)
	result.winning_team = 0
	result.reason = &"victory"
	result.rounds = 1
	for combatant in prepared.setup.combatants:
		result.participants.append({"instance_id": combatant.instance_id, "team": combatant.team, "survived": true, "persistent_changes": {"health": combatant.health, "energy": combatant.energy}})
	return result

func _prepare(session: MemorySession, encounter: EncounterDefinition) -> Dictionary:
	var prepared := session.prepare_battle(encounter.id)
	if prepared.ok or prepared.get("code", "") != "interaction_unavailable": return prepared
	# Some authored early-floor trials are hidden by the source tower-mode
	# gate. Exercise their reward contract without changing that gate. This
	# fixture proves settlement, not availability of those trials in standard.
	prepared = CampaignProgressionService.prepare_battle(session.state, encounter)
	if prepared.ok:
		prepared["setup"] = CampaignProgressionService.build_battle_setup(session.state, session.catalog, encounter)
	return prepared

func _session(catalog: ContentCatalog, campaign: CampaignDefinition, room: RoomDefinition, floor_index: int, money_rank: int) -> MemorySession:
	var session := MemorySession.new()
	session.catalog = catalog
	session.campaign = campaign
	session.state = CampaignState.new()
	session.state.campaign_id = campaign.id
	session.state.current_room_id = room.id
	session.state.progression = {"floor_index": floor_index, "unlocked_floor_indices": [0, floor_index], "floor_keys": 0, "eggery_keys": 0, "currency": 0.0, "star_upgrades": {"money": money_rank}}
	var owned := OwnedMinionState.new()
	owned.instance_id = &"rewards-fixture-player"
	owned.definition_id = &"base:minion/fire_pig_1"
	owned.level = 60
	owned.experience = 60000
	owned.learned_move_ids.assign((catalog.get_definition(owned.definition_id) as MinionDefinition).initial_move_ids)
	session.state.party.append(owned)
	return session

func _run() -> void:
	await process_frame
	var catalog: ContentCatalog = root.get_node("CampaignRuntime").catalog
	var campaign := catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
	var unique: Dictionary = {}
	var checked := 0
	var gem_clears := 0
	for floor_data in campaign.floors:
		var floor_index := int(floor_data.floor_index)
		if floor_index > 9: continue
		var expected_basis := floori(minf(7.0 * pow(1.25, floor_index), 2000.0) + 0.5)
		for room_id in floor_data.room_ids:
			var room := catalog.get_definition(StringName(room_id)) as RoomDefinition
			for encounter_id in room.encounter_ids:
				if unique.has(encounter_id): continue
				unique[encounter_id] = true
				var encounter := catalog.get_definition(encounter_id) as EncounterDefinition
				var normal := encounter.source_trainer_type == &"TrainerType.NORMAL_TRAINER"
				var gem_reward := encounter.source_trainer_type in [&"TrainerType.HARD_TRAINER", &"TrainerType.EXPERT_TRAINER"]
				var eggery_reward := gem_reward or encounter.source_trainer_type == &"TrainerType.BOSS_TRAINER"
				var first: Dictionary = encounter.rewards.first_clear
				assert(int(first.floor_money_basis) == expected_basis, "Money must use StaticData's rounded current-floor reward")
				assert(int(first.get("floor_keys", 0)) == int(normal) and int(first.get("eggery_keys", 0)) == int(eggery_reward), "Wrong source key type: %s" % encounter.id)
				if gem_reward:
					assert(int(first.random_gems.count) == 1 and int(first.random_gems.tier) == (1 if floor_index < 5 else 2))
				for rank in [0, 2]:
					var session := _session(catalog, campaign, room, floor_index, rank)
					var prepared := _prepare(session, encounter)
					assert(prepared.ok, "Reward fixture could not prepare %s: %s" % [encounter.id, prepared])
					var result := _result(prepared)
					var expected_money: int = int(float(expected_basis) / 6.0 * int(rank) * int(rank)) + (int(float(expected_basis) / 3.0) if normal else 0)
					if checked == 0 and rank == 0:
						var before: Dictionary = session.state.to_dictionary()
						session.reject_save = true
						assert(not session.apply_battle_result(result).ok)
						assert(session.state.to_dictionary() == before, "Rejected settlement must not consume first-clear rewards")
						session.reject_save = false
					var settlement := session.apply_battle_result(result)
					assert(settlement.ok)
					var awards: Dictionary = settlement.first_clear_rewards
					assert(is_equal_approx(float(awards.money), expected_money) and is_equal_approx(float(session.state.progression.currency), expected_money))
					assert(int(session.state.progression.floor_keys) == int(normal) and int(session.state.progression.eggery_keys) == int(eggery_reward))
					assert(awards.gems.size() == int(gem_reward) and session.state.owned_gems.size() == int(gem_reward))
					if gem_reward: assert(int(session.state.owned_gems[0].tier) == (1 if floor_index < 5 else 2))
					var committed: Dictionary = session.state.to_dictionary()
					assert(session.apply_battle_result(result).ok and session.state.to_dictionary() == committed, "Duplicate result must not repeat rewards")
					var rematch := _prepare(session, encounter)
					assert(rematch.ok)
					var replayed := session.apply_battle_result(_result(rematch))
					assert(replayed.ok and is_equal_approx(float(replayed.first_clear_rewards.money), 0.0))
					assert(is_equal_approx(float(session.state.progression.currency), expected_money) and session.state.owned_gems.size() == int(gem_reward))
					assert(int(session.state.progression.floor_keys) == int(normal) and int(session.state.progression.eggery_keys) == int(eggery_reward))
				checked += 1
				gem_clears += int(gem_reward)
	assert(checked > 40 and gem_clears > 10)
	print("PASS: %d live floor-1–10 first clears at money ranks 0/2, native key/money/gem settlement, rejected-save retry, duplicate result and reward-free rematches (%d gem encounters)" % [checked, gem_clears])
	quit(0)
