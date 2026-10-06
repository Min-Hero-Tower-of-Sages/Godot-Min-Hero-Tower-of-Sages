extends SceneTree

class MemoryRepository extends SaveRepository:
	var saved: Dictionary = {}
	func load_slot(_slot: int) -> Dictionary:
		return {"ok": true, "state": saved.duplicate(true)}
	func save_slot(_slot: int, data: Dictionary) -> Dictionary:
		saved = data.duplicate(true)
		return {"ok": true}

class MemorySession extends CampaignSession:
	var reject_save := false
	func _save_candidate(candidate) -> Dictionary:
		if reject_save: return {"ok": false, "message": "Fixture rejected save"}
		return save_repository.save_slot(save_slot, candidate.to_dictionary(catalog.content_version))

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var runtime := root.get_node("CampaignRuntime")
	var catalog: ContentCatalog = runtime.catalog
	var original_session: CampaignSession = runtime.session
	var encounter := catalog.get_definition(&"base:encounter/grass_floor1_room1_normal") as EncounterDefinition
	var species := catalog.get_definition(&"base:minion/fire_pig_1") as MinionDefinition
	var health_aura: StringName
	for move in catalog._by_id.values():
		if move is MoveDefinition and move.is_global_passive and move.tier == 1 and LegacyCombatModifiers._first_stat_percent(move, &"base:stat/health") > 0.0:
			health_aura = move.id
			break
	assert(not health_aura.is_empty())
	var session := MemorySession.new()
	session.catalog = catalog
	session.campaign = catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
	session.save_repository = MemoryRepository.new()
	session.state = CampaignState.new()
	session.state.campaign_id = session.campaign.id
	session.state.current_room_id = &"base:room/level_1_1_b"
	session.state.room_state.current_location = {"room_id": String(session.state.current_room_id), "position": Vector2(123, 234)}
	session.state.safe_location = {"room_id": "base:room/level_1_1_a", "spawn_id": "start", "position": Vector2(345, 456), "facing": "up"}
	for index in 2:
		var owned := OwnedMinionState.new()
		owned.instance_id = StringName("loss-party-%d" % index)
		owned.definition_id = species.id
		owned.level = 10
		owned.experience = 10000
		owned.learned_move_ids.assign(species.initial_move_ids)
		if index == 0: owned.learned_move_ids.append(health_aura)
		session.state.party.append(owned)
	var prepared := CampaignProgressionService.prepare_battle(session.state, encounter)
	var engine := BattleEngine.new()
	var rules := RuleSetDefinition.new()
	rules.configuration = {"ai_teams": []}
	assert(engine.start(CampaignProgressionService.build_battle_setup(session.state, catalog, encounter), catalog, rules, BattleRng.new(3)).accepted)
	for actor in engine._state.combatants.values():
		if actor.team == 0:
			actor.health = 0
			actor.energy = 0
			actor.defeated = true
	engine._finish(1, &"elimination")
	var result: BattleResult = engine.get_result()
	var battle_room: StringName = session.state.current_room_id
	var settled := session.apply_battle_result(result)
	assert(settled.ok and session.state.current_room_id == battle_room)
	assert(session.state.pending_battle.is_empty() and not session.state.pending_defeat_return.is_empty())
	for owned in session.state.party:
		assert(owned.persistent_health == 0 and owned.persistent_energy == 0 and owned.level == 10)
		assert(settled.experience_awards[String(owned.instance_id)].experience > 0)
	var display := CampaignProgressionService.owned_display_stats(session.state.party[1], species, catalog, session.state, -1, settled.finish_stat_context)
	var unboosted := CampaignProgressionService.owned_stats(session.state.party[1], species)
	assert(display.health == unboosted.health, "Loss finish stats revived a dead global provider before recovery")
	var pending_snapshot: Dictionary = session.state.to_dictionary()
	var experience_before: int = session.state.party[0].experience
	assert(session.apply_battle_result(result).already_applied and session.state.party[0].experience == experience_before)
	assert(not CampaignProgressionService.prepare_battle(session.state, encounter).ok, "Another battle bypassed pending loss recovery")
	session.reject_save = true
	assert(not session.complete_defeat_return().ok)
	assert(session.state.to_dictionary() == pending_snapshot, "Rejected checkpoint return mutated committed party/XP/location")
	session.reject_save = false
	var expected := CampaignState.new()
	expected.load_dictionary(pending_snapshot)
	assert(CampaignProgressionService.rest_party(expected, catalog).ok)
	assert(session.complete_defeat_return().ok)
	assert(session.state.current_room_id == &"base:room/level_1_1_a" and session.state.pending_defeat_return.is_empty())
	assert(session.state.room_state.current_location.position == Vector2(345, 456))
	for index in 2:
		assert(session.state.party[index].persistent_health == expected.party[index].persistent_health)
		assert(session.state.party[index].persistent_energy == expected.party[index].persistent_energy)
	assert(session.complete_defeat_return().already_returned and session.state.party[0].experience == experience_before)
	# Runtime loading uses the real session load path with an in-memory repository.
	# Interrupt during loss UI: only recovery runs, not XP or settlement again.
	var repository := session.save_repository as MemoryRepository
	repository.saved = pending_snapshot.duplicate(true)
	runtime.session = session
	assert(runtime.load_campaign(1).recovered_defeat_return)
	assert(session.state.pending_defeat_return.is_empty() and session.state.current_room_id == &"base:room/level_1_1_a")
	assert(session.state.party[0].experience == experience_before and session.state.applied_battle_ids == [String(prepared.battle_id)])
	# Forfeit intentionally keeps the source's immediate heal/checkpoint return.
	var next := CampaignProgressionService.prepare_battle(session.state, encounter)
	var forfeited := BattleResult.new()
	forfeited.battle_id = StringName(next.battle_id)
	forfeited.winning_team = 1
	forfeited.reason = &"forfeit"
	forfeited.participants = [{"instance_id": String(session.state.party[0].instance_id), "team": 0, "persistent_changes": {"health": 0, "energy": 0}}]
	var forfeit_settlement := session.apply_battle_result(forfeited)
	assert(forfeit_settlement.ok and forfeit_settlement.experience_awards.is_empty())
	assert(session.state.pending_defeat_return.is_empty() and session.state.party[0].persistent_health > 0)
	assert(session.state.party[0].experience == experience_before)
	runtime.session = original_session
	print("PASS: native defeat keeps loss HP/energy and dead-provider finish stats through XP; checkpoint recovery is atomic/idempotent/restart-safe; forfeits still recover immediately")
	quit(0)
