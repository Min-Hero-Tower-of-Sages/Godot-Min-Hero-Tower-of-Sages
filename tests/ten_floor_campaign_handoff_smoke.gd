extends SceneTree

## Uses the production catalog/session with synthetic results, not simulated
## battle animations. All saves are captured in memory; player saves are untouched.
class MemorySession extends CampaignSession:
	var reject_save := false
	var saved: Dictionary = {}
	func _save_candidate(candidate) -> Dictionary:
		var errors: PackedStringArray = candidate.validation_errors(catalog)
		if not errors.is_empty():
			return {"ok": false, "code": "invalid_campaign_state", "message": "\n".join(errors)}
		if reject_save:
			return {"ok": false, "code": "fixture_save_rejected"}
		saved = candidate.to_dictionary(catalog.content_version).duplicate(true)
		return {"ok": true}

var failures: Array[String] = []
var encounter_count := 0
var exit_count := 0
var floor_count := 10

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> bool:
	if not condition:
		failures.append(message)
		push_error(message)
	return condition

func _run() -> void:
	await process_frame
	var runtime := root.get_node("CampaignRuntime")
	var session := MemorySession.new()
	session.catalog = runtime.catalog
	session.campaign = session.catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
	session.state = CampaignState.new()
	session.state.campaign_id = session.campaign.id
	session.state.current_room_id = session.campaign.starting_room_id
	session.state.character = {"name": "Ten-floor handoff fixture", "gender": "male"}
	var starter := OwnedMinionState.new()
	starter.instance_id = &"ten-floor-starter"
	starter.definition_id = &"base:minion/fire_pig_1"
	starter.level = 4
	starter.experience = 4350
	var definition := session.catalog.get_definition(starter.definition_id) as MinionDefinition
	starter.learned_move_ids.assign(definition.initial_move_ids)
	session.state.party.append(starter)
	# Visit every converted floor, including source optional floors. This is a
	# coverage fixture, not evidence those optional floors unlock sequentially.
	session.state.progression["unlocked_floor_indices"] = range(floor_count)
	for floor_index in floor_count:
		session.state.progression["in_tower_lobby"] = true
		var selected: Dictionary = session.select_tower_floor(floor_index)
		if not _check(selected.ok, "Floor %d cannot be selected: %s" % [floor_index + 1, selected]):
			continue
		var floor_data: Dictionary = CampaignTowerModeService.mode_floor_data(session.campaign, floor_index, &"standard")
		for room_id in floor_data.get("room_ids", []):
			var room := session.catalog.get_definition(StringName(room_id)) as RoomDefinition
			if not _check(room != null, "Floor %d missing room %s" % [floor_index + 1, room_id]):
				continue
			for exit_data in room.exits:
				if String(exit_data.get("requires_tower_mode", "")) == "hard":
					continue
				session.state.current_room_id = room.id
				var flag := String(exit_data.get("requires_progression_flag", ""))
				if not flag.is_empty():
					session.state.progression[flag] = false
					_check(not session.enter_room(StringName(exit_data.target_room_id), int(exit_data.transition_id)).ok, "Locked exit accepted: %s" % room.id)
					session.state.progression[flag] = true
				var entered: Dictionary = session.enter_room(StringName(exit_data.target_room_id), int(exit_data.transition_id))
				_check(entered.ok, "Broken exit from %s: %s" % [room.id, entered])
				exit_count += 1
			for interaction in room.interactions:
				var encounter_id := StringName(interaction.get("encounter_id", ""))
				if encounter_id.is_empty() or String(interaction.get("requires_tower_mode", "")) == "hard":
					continue
				session.state.current_room_id = room.id
				if encounter_count == 0:
					var before: Dictionary = session.state.to_dictionary()
					session.reject_save = true
					_check(not session.prepare_battle(encounter_id).ok, "Preparation accepted rejected save")
					_check(session.state.to_dictionary() == before, "Rejected preparation changed live state")
					session.reject_save = false
				var prepared: Dictionary = session.prepare_battle(encounter_id)
				if not _check(prepared.ok, "Trainer cannot prepare %s: %s" % [encounter_id, prepared]):
					continue
				_check(prepared.setup.combatants.size() > session.state.party.size(), "Empty enemy team: %s" % encounter_id)
				var result := BattleResult.new()
				result.battle_id = StringName(prepared.battle_id)
				result.winning_team = 0
				result.reason = &"elimination"
				result.rounds = 2
				for combatant in prepared.setup.combatants:
					result.participants.append({"instance_id": combatant.instance_id, "team": combatant.team, "persistent_changes": {"health": combatant.health, "energy": combatant.energy}})
				if encounter_count == 0:
					var before: Dictionary = session.state.to_dictionary()
					session.reject_save = true
					_check(not session.apply_battle_result(result).ok, "Settlement accepted rejected save")
					_check(session.state.to_dictionary() == before, "Rejected settlement changed live state")
					session.reject_save = false
				var settled: Dictionary = session.apply_battle_result(result)
				_check(settled.ok, "Cannot settle %s: %s" % [encounter_id, settled])
				_check(session.state.pending_battle.is_empty(), "Pending battle remains after %s" % encounter_id)
				var committed: Dictionary = session.state.to_dictionary()
				var duplicate: Dictionary = session.apply_battle_result(result)
				_check(duplicate.ok and duplicate.get("already_applied", false), "Committed result not idempotent: %s" % encounter_id)
				_check(session.state.to_dictionary() == committed, "Duplicate changed rewards: %s" % encounter_id)
				var replay: Dictionary = session.prepare_battle(encounter_id)
				_check(replay.ok, "Trainer replay blocked: %s" % encounter_id)
				var pending: Dictionary = session.state.pending_battle.duplicate(true)
				_check(session.apply_battle_result(result).get("already_applied", false), "Delayed result rejected during replay")
				_check(session.state.pending_battle == pending, "Delayed result destroyed new battle context")
				_check(session.cancel_pending_battle().ok, "Replay cancel failed")
				encounter_count += 1
	await _natural_frontier(session.catalog, starter)
	print("%s: %d-floor campaign handoffs, %d trainer encounters, %d room exits; natural boss/Sage/lobby progression, selector motion, save rejection and duplicate/delayed settlement" % ["PASS" if failures.is_empty() else "FAIL", floor_count, encounter_count, exit_count])
	quit(0 if failures.is_empty() else 1)

func _natural_frontier(catalog: ContentCatalog, starter: OwnedMinionState) -> void:
	var session := MemorySession.new()
	session.catalog = catalog
	session.campaign = catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
	session.state = CampaignState.new()
	session.state.campaign_id = session.campaign.id
	session.state.current_room_id = session.campaign.starting_room_id
	session.state.party.append(OwnedMinionState.from_dictionary(starter.to_dictionary()))
	var route := [0, 1, 2, 4, 5, 6, 7, 9]
	var next_floors := [1, 2, 4, 5, 6, 7, 9, 10]
	for route_index in route.size():
		var floor_index: int = route[route_index]
		_check(session.enter_tower_lobby().ok, "Cannot return to source Lobby")
		_check(session.select_tower_floor(floor_index).ok, "Natural route cannot enter Floor %d" % (floor_index + 1))
		var floor_data: Dictionary = CampaignTowerModeService.mode_floor_data(session.campaign, floor_index, &"standard")
		var boss: EncounterDefinition
		for room_id in floor_data.get("room_ids", []):
			var room := catalog.get_definition(StringName(room_id)) as RoomDefinition
			for encounter_id in room.encounter_ids:
				var encounter := catalog.get_definition(encounter_id) as EncounterDefinition
				if CampaignProgressionService._trainer_unlocks_floor(encounter.source_trainer_type):
					boss = encounter
					session.state.current_room_id = room.id
		if not _check(boss != null, "Natural floor missing boss"):
			continue
		var prepared: Dictionary = session.prepare_battle(boss.id)
		if not _check(prepared.ok, "Natural boss preparation failed: %s" % prepared):
			continue
		var result := BattleResult.new()
		result.battle_id = StringName(prepared.battle_id)
		result.winning_team = 0
		result.reason = &"elimination"
		var before_refresh := int(session.state.progression.get("gem_shop_refresh_count", 0))
		_check(session.apply_battle_result(result).ok, "Natural boss settlement failed")
		_check(next_floors[route_index] in session.state.progression.unlocked_floor_indices, "Boss did not unlock source next floor")
		_check(int(session.state.progression.gem_shop_refresh_count) == before_refresh + 1, "Frontier boss did not refresh shop once")
		_check(CampaignGemEconomyService.current_shop_stock(session.state).size() == 6, "Frontier stock not six gems")
		if floor_index == 2:
			_check(3 not in session.state.progression.unlocked_floor_indices, "Optional Floor 4 unlocked too soon")
		if floor_index == 6:
			_check(3 in session.state.progression.unlocked_floor_indices, "Floor 7 did not backfill optional Floor 4")
			_check(3 in session.state.progression.get("pending_optional_floor_reveals", []), "Bonus unlock lost presentation marker")
			await _bonus_reveal(session)
		if floor_index == 4 or floor_index == 9:
			_check(int(session.state.progression.sage_seals) == (1 if floor_index == 4 else 2), "Sage seal frontier mismatch")
		if floor_index == 7:
			_check(8 not in session.state.progression.unlocked_floor_indices, "Optional Floor 9 unlocked too soon")
			var view := CampaignFloorSelectView.new()
			root.add_child(view)
			view.configure(session)
			_check(view._page == 2, "Selector opens at wrong progression page")
			_check(view._optional_floor_hidden(8), "Locked optional Floor 9 shown")
			_check(is_equal_approx(view._row_y(9, 329), 135.0), "Hidden optional floor leaves tower gap")
			var old_root: Control = view._root
			var tile: Control = view._floor_rows[0]
			var old_y := tile.position.y
			view._change_page(-1)
			_check(view._root == old_root and is_equal_approx(tile.position.y, old_y), "Paging rebuilds/snaps selector")
			await create_timer(0.5).timeout
			_check(tile.position.y < old_y and tile.position.y > old_y - view.SCREEN_SCROLL, "Selector has no intermediate scroll position")
			view.queue_free()
			await process_frame
	_check(session.enter_tower_lobby().ok, "Fire Sage cannot return to Lobby")
	_check(session.select_tower_floor(0).ok, "Floor 1 revisit locked after Fire Sage")

func _bonus_reveal(session: MemorySession) -> void:
	var view := CampaignFloorSelectView.new()
	root.add_child(view)
	view.configure(session)
	_check(view._insertion_active and view._page == 0, "Bonus floor insertion not active at source page")
	var tile: Control
	for row in view._floor_rows:
		if int(row.get_meta("source_floor")) == 4:
			tile = row
	var old_y := tile.position.y
	view._change_page(1)
	_check(view._page == 0, "Paging allowed during bonus insertion")
	await create_timer(2.0).timeout
	_check(tile.position.y < old_y and tile.position.y > old_y - view.ROW_SPACING, "Bonus floor did not move upper tower rows gradually")
	await create_timer(2.9).timeout
	_check(is_instance_valid(view._tutorial), "Original bonus tutorial did not follow insertion")
	_check(view._tutorial.get_node_or_null("BonusTutorialOK") != null, "Bonus tutorial missing source OK button")
	var before: Dictionary = session.state.to_dictionary()
	session.reject_save = true
	view._dismiss_bonus_floor_tutorial()
	_check(session.state.to_dictionary() == before and view._insertion_active, "Failed tutorial save consumed marker or unblocked selection")
	session.reject_save = false
	view._dismiss_bonus_floor_tutorial()
	await create_timer(0.6).timeout
	_check(not view._insertion_active and not is_instance_valid(view._tutorial), "Tutorial did not unblock and close")
	_check(session.state.progression.get("pending_optional_floor_reveals", []).is_empty(), "Completed bonus reveal remains pending")
	_check(bool(session.state.progression.get("bonus_floor_tutorial_seen", false)), "Bonus tutorial acknowledgement not saved")
	view.queue_free()
	await process_frame
	var reopened := CampaignFloorSelectView.new()
	root.add_child(reopened)
	reopened.configure(session)
	_check(not reopened._insertion_active, "Completed bonus insertion replayed")
	reopened.queue_free()
	await process_frame
