extends SceneTree

const SAMPLE = preload("res://content/sample/sample_content_factory.gd")

class MemoryRepository extends SaveRepository:
	var payload: Dictionary = {}
	func save_slot(_slot: int, data: Dictionary) -> Dictionary:
		payload = data.duplicate(true)
		return {"ok": true}
	func load_slot(_slot: int) -> Dictionary:
		return {"ok": false, "code": "not_found"} if payload.is_empty() else {"ok": true, "state": payload.duplicate(true)}

var catalog: ContentCatalog
var session: CampaignSession

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	catalog = root.get_node("CampaignRuntime").catalog
	assert(catalog.ensure_index().is_empty())
	session = CampaignSession.new()
	session.catalog = catalog
	session.save_repository = MemoryRepository.new()
	assert(session.start_new(&"base:campaign/standard_tower", CampaignProgressionService.starter_party(catalog, "hard-contact-")).ok)
	session.state.progression.unlocked_floor_indices = [0, 31]
	session.state.progression.map_unlocked_floor_indices = [0]
	assert(session.enter_tower_lobby().ok and session.select_tower_floor(0).ok)
	var map_room := catalog.get_definition(&"base:room/level_1_1_d") as RoomDefinition
	var normal_contact := _contact(map_room, &"standard")
	assert(normal_contact.kind == &"map_station" and normal_contact.id == &"floor-1-map-station")
	print("Standard-mode map contact verified")
	session.state.current_room_id = map_room.id
	assert(session.interact(normal_contact.id).kind == &"map_hint")
	assert(not session.interact(&"floor-1-trainer-4-hard").ok)
	assert(session.enter_tower_lobby().ok and session.select_tower_floor(31).ok)
	assert(not CampaignDebugService.enabled(session.state, "full_keys"))

	# The report's existing save has three students, the expert, and the boss
	# defeated. Settle those real fights to reproduce its five-key state.
	for entry in [
		["base:room/level_1_1_a", "floor-1-trainer-1"],
		["base:room/level_1_1_b", "floor-1-trainer-2"],
		["base:room/level_1_1_c", "floor-1-trainer-3"],
		["base:room/floor_1_expert_room_grass", "floor-1-expert-trainer"],
		["base:room/level_1_1_e", "floor-1-trainer-6"],
	]:
		print("Settling ", entry[1])
		_win(StringName(entry[0]), StringName(entry[1]))
	assert(session.state.progression.floor_keys == 3 and session.state.progression.eggery_keys == 2)
	print("Five-key state reproduced")
	assert(32 in session.state.progression.unlocked_floor_indices, "Flash unlocks 1-2 when the minor sage is beaten, before the hatchery")
	assert(session.interact(&"floor-1-eggery-door").kind == &"door_locked")
	assert(session.load(1).ok, "The existing five-key save remains loadable")
	assert(session.state.progression.floor_keys == 3 and session.state.progression.eggery_keys == 2)
	var hard_contact := _contact(map_room, &"hard")
	assert(hard_contact.kind == &"trainer" and hard_contact.id == &"floor-1-trainer-4-hard")
	session.state.current_room_id = map_room.id
	assert(not session.interact(&"floor-1-map-station").ok)
	var dialogue := session.interact(hard_contact.id)
	assert(dialogue.kind == &"trainer" and dialogue.dialog_text == "In Hard Mode, we must fight!")
	_win(map_room.id, hard_contact.id)
	assert(session.state.progression.floor_keys == 3 and session.state.progression.eggery_keys == 3)
	print("Missing hard trainer and sixth key verified")
	session.state.current_room_id = &"base:room/level_1_1_e"
	assert(session.interact(&"floor-1-eggery-door").kind == &"door_unlocked")
	assert(session.state.progression.floor_keys == 0 and session.state.progression.eggery_keys == 0)
	assert(CampaignTowerModeService.floor_star_count(session.state, catalog, session.campaign, 0, &"hard") == 18)

	# At every shared Qui-tel contact, exactly the intended interaction must
	# be available in each mode. The older direct session test missed priority.
	var map_count := 0
	for definition in catalog._by_id.values():
		if not definition is RoomDefinition: continue
		for trainer in definition.interactions:
			if trainer.kind != &"trainer": continue
			var encounter := catalog.get_definition(StringName(trainer.get("encounter_id", ""))) as EncounterDefinition
			if encounter == null or encounter.source_trainer_type != &"TrainerType.HARD_TRAINER" or encounter.source_floor_index >= 31: continue
			var maps: Array = definition.interactions.filter(func(i: Dictionary) -> bool: return i.kind == &"map_station" and i.source_zone_id == trainer.source_zone_id)
			assert(maps.size() == 1)
			assert(String(maps[0].get("requires_tower_mode", "")) == "standard")
			assert(String(trainer.get("requires_tower_mode", "")) == "hard")
			map_count += 1
	assert(map_count >= 24)
	print("Paired map contacts verified: ", map_count)
	assert(_check_conditions())
	assert(_check_replacements())
	print("PASS: standard/hard source contact, recovered five-key save and six-key hatchery, 18 stars, next-floor timing, %d paired map contacts, stun/freeze and replacement turn eligibility" % map_count)
	quit()

func _contact(room: RoomDefinition, mode: StringName) -> Dictionary:
	var view := CampaignRoomView.new()
	root.add_child(view)
	assert(view.configure(room, room.spawn_ids[0], room.spawn_positions[String(room.spawn_ids[0])], {}, {"progression": session.state.progression, "tower_mode": String(mode)}))
	view.set_physics_process(false)
	var choices: Array = view._room_interactions.filter(func(i: Dictionary) -> bool: return i.get("source_zone_id", -1) == 0 and i.kind in [&"trainer", &"map_station"])
	assert(choices.size() == 1, "Source contact must have exactly one active map/trainer interaction")
	var contact: Dictionary = choices[0]
	view._player.position = contact._zone_center - view.PLAYER_COLLISION_TOP_LEFT - view.PLAYER_COLLISION_SIZE * 0.5
	var requested: Array[Dictionary] = []
	view.interaction_requested.connect(func(item: Dictionary) -> void: requested.append(item))
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	view._unhandled_input(space)
	assert(requested.size() == 1 and requested[0].id == contact.id)
	view.free()
	return contact

func _win(room_id: StringName, interaction_id: StringName) -> void:
	session.state.current_room_id = room_id
	var interaction := session.interact(interaction_id)
	assert(interaction.ok and interaction.kind == &"trainer")
	var prepared := session.prepare_battle(interaction.encounter_id)
	assert(prepared.ok)
	var result := BattleResult.new()
	result.battle_id = StringName(prepared.battle_id)
	result.winning_team = 0
	result.reason = &"victory"
	assert(session.apply_battle_result(result).ok)

func _check_conditions() -> bool:
	var sample_catalog := SAMPLE.build_catalog()
	var wait_effect := EffectDefinition.new()
	wait_effect.id = &"foundation:effect/report_wait"
	wait_effect.display_name = "Wait"
	wait_effect.kind = EffectDefinition.Kind.ENERGY
	wait_effect.target_scope = EffectDefinition.TargetScope.ACTOR
	wait_effect.phase = EffectDefinition.Phase.BEFORE_ACCURACY
	wait_effect.executor = preload("res://src/domain/battle/energy_effect_executor.gd")
	var wait_move := MoveDefinition.new()
	wait_move.id = &"foundation:move/wait"
	wait_move.display_name = "Wait"
	wait_move.family_id = &"foundation:move_family/wait"
	wait_move.type_id = &"base:type/none"
	wait_move.target_side = MoveDefinition.TargetSide.SELF
	wait_move.effects = [wait_effect]
	sample_catalog.packs[0].definitions.append(wait_move)
	assert(sample_catalog.rebuild_index().is_empty())
	for condition in ["stunned", "frozen"]:
		var setup := SAMPLE.battle_setup()
		setup.combatants[0][condition] = true
		setup.combatants[1].move_ids = [wait_move.id]
		# Stun at exactly 50% skips; the next roll just below 50% acts.
		# Freeze always skips once; on a later activation a zero roll thaws.
		var initial_roll := 500000 if condition == "stunned" else 0
		var next_roll := 499999 if condition == "stunned" else 0
		var engine := BattleEngine.new()
		var start := engine.start(setup, sample_catalog, SAMPLE.build_rules(), BattleRng.new(9, [initial_roll, 0, 0, 0, 0, next_roll]))
		var skipped_kind := &"stunned_turn_skipped" if condition == "stunned" else &"frozen_turn_skipped"
		assert(start.accepted and start.events.any(func(e: BattleEvent) -> bool: return e.kind == skipped_kind))
		var decision := engine.get_decision()
		assert(decision.actor_id == "enemy-1")
		var response := engine.submit(BattleCommand.new(&"enemy-1", BattleCommand.Kind.USE_MOVE, wait_move.id, [&"enemy-1"], int(decision.revision)))
		var recovery_kind := &"stun_resisted" if condition == "stunned" else &"thawed"
		assert(response.accepted and response.events.any(func(e: BattleEvent) -> bool: return e.kind == recovery_kind))
		assert(engine.get_decision().actor_id == "player-1")
		var affected := engine._state.combatants[&"player-1"] as CombatantState
		assert(affected.stunned if condition == "stunned" else not affected.frozen)
	return true

func _check_replacements() -> bool:
	var sample_catalog := SAMPLE.build_catalog()
	var strike := sample_catalog.get_definition(&"foundation:move/strike/tier1") as MoveDefinition
	if strike == null:
		sample_catalog.rebuild_index()
		strike = sample_catalog.get_definition(&"foundation:move/strike/tier1") as MoveDefinition
	strike.effects[0].amount = 1000
	strike.effects[0].random_bonus = 0
	strike.accuracy_percent = 100
	for speed in [80, 1]:
		print("Checking replacement speed ", speed)
		var setup := SAMPLE.battle_setup()
		setup.combatants[0].speed = 100
		setup.combatants[1].speed = 1
		var ally: Dictionary = setup.combatants[0].duplicate(true)
		ally.instance_id = "player-2"
		ally.slot_index = 1
		ally.speed = 50
		setup.combatants.append(ally)
		var replacement: Dictionary = setup.combatants[1].duplicate(true)
		replacement.instance_id = "enemy-extra"
		replacement.speed = speed
		var rules := SAMPLE.build_rules()
		rules.configuration = {"battle_modifiers": {"extra_minions": {"enemy": {"count": 1, "templates": [replacement]}}}}
		var engine := BattleEngine.new()
		assert(engine.start(setup, sample_catalog, rules, BattleRng.new(7, [0, 0, 0, 0, 0, 0])).accepted)
		var decision := engine.get_decision()
		assert(decision.actor_id == "player-1")
		var response := engine.submit(BattleCommand.new(&"player-1", BattleCommand.Kind.USE_MOVE, strike.id, [&"enemy-1"], int(decision.revision)))
		assert(response.accepted and response.events.any(func(e: BattleEvent) -> bool: return e.kind == &"battle_mod_extra_spawned" and e.target_id == &"enemy-extra"))
		decision = engine.get_decision()
		if speed == 80:
			assert(decision.actor_id == "enemy-extra", "A faster new minion can act immediately")
		else:
			assert(decision.actor_id == "player-2", "A slower new minion waits behind remaining faster allies")
			response = engine.submit(BattleCommand.new(&"player-2", BattleCommand.Kind.USE_MOVE, strike.id, [&"enemy-extra"], int(decision.revision)))
			assert(response.accepted and engine.get_result().winning_team == 0, "A replacement can be defeated before its turn")
	return true
