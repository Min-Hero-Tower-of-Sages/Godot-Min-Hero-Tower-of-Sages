extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var catalog: ContentCatalog = root.get_node("CampaignRuntime").catalog
	var encounter_ids: Array[StringName] = [&"base:encounter/floor7_trainer_1", &"base:encounter/floor7_trainer_6_boss", &"base:encounter/floor8_trainer_1", &"base:encounter/floor8_trainer_2", &"base:encounter/floor8_trainer_3", &"base:encounter/floor8_trainer_6_boss", &"base:encounter/floor9_trainer_1", &"base:encounter/floor9_trainer_2", &"base:encounter/floor9_trainer_3", &"base:encounter/floor10_fire_sage"]
	for encounter_id in encounter_ids:
		var encounter := catalog.get_definition(encounter_id) as EncounterDefinition
		assert(encounter != null, "Authored timer encounter missing: %s" % encounter_id)
		var state := CampaignState.new()
		state.pending_battle = {"encounter_id": String(encounter_id), "battle_id": "stone-fixture-%s" % encounter_id}
		for index in 2:
			var owned := OwnedMinionState.new()
			owned.instance_id = StringName("stone-fixture-%d" % index)
			owned.definition_id = &"base:minion/fire_pig_1"
			owned.level = 26
			owned.learned_move_ids.assign((catalog.get_definition(owned.definition_id) as MinionDefinition).initial_move_ids)
			state.party.append(owned)
		var prepared := CampaignProgressionService.build_battle_setup(state, catalog, encounter)
		assert(prepared.ok)
		var rules := RuleSetDefinition.new()
		rules.configuration = {"refill_on_activation": true, "battle_modifiers": encounter.battle_modifier_configuration.duplicate(true)}
		var engine := BattleEngine.new()
		assert(engine.start(prepared, catalog, rules, BattleRng.new(1234)).accepted)
		var timer: Dictionary = encounter.battle_modifier_configuration.move_timer
		var caster: CombatantState = engine._timer_actor
		assert(caster.definition_id == (&"internal:minion/bmod_3" if int(timer.source_power) == 2 else &"internal:minion/bmod_2"))
		var first_enemy: Dictionary = prepared.combatants.filter(func(entry: Dictionary) -> bool: return int(entry.team) == 1 and int(entry.slot_index) == 0)[0]
		assert(caster.level == int(first_enemy.level), "Caster must use the actual first enemy level including source offsets")
		var caster_definition := catalog.get_definition(caster.definition_id) as MinionDefinition
		assert(caster.attack == int(LegacyMinionStats.current_stats(caster_definition, caster.level).attack))
		assert(caster.max_attack_stat == LegacyMinionStats.max_attack_stat(caster_definition) and caster.max_attack_stat > 0)
		assert(caster.max_energy > 0 and caster.type_ids == caster_definition.type_ids)
		assert(not engine._state.combatants.has(caster.instance_id) and caster.instance_id not in engine._state.turn_order)
		var buff := catalog.get_definition(StringName(timer.buff_move_id)) as MoveDefinition
		var player := engine._state.combatants[&"stone-fixture-0"] as CombatantState
		assert(player.health == player.max_health and player.energy == player.max_energy, "Campaign activation must refill the final buffed maxima")
		assert(player.battle_bonus_global_move_ids == [StringName(timer.buff_move_id)] and timer.buff_move_id not in player.move_ids)
		var health_rate := LegacyCombatModifiers.effective_max_health(player, catalog, engine._state.combatants)
		var speed_rate := LegacyCombatModifiers.effective_speed(player, catalog, engine._state.combatants)
		var crit_rate := LegacyCombatModifiers.critical_chance(player, catalog, engine._state.combatants)
		var attack_rate := LegacyCombatModifiers.effective_attack(player, catalog, engine._state.combatants)
		var energy_rate := LegacyCombatModifiers.effective_max_energy(player, catalog, engine._state.combatants)
		var reflect_rate := LegacyCombatModifiers.reflect_rate(player, catalog, engine._state.combatants)
		var baseline := BattleEngine.new()
		assert(baseline.start(prepared, catalog, RuleSetDefinition.new(), BattleRng.new(1234)).accepted)
		var plain := baseline._state.combatants[player.instance_id] as CombatantState
		var buff_percent := float(buff.effects[0].amount)
		if String(timer.buff_move_id).contains("hulk"):
			assert(health_rate == int(plain.base_max_health * (1.0 + buff_percent / 100.0)))
		elif String(timer.buff_move_id).contains("agile"):
			var percent := float(buff.effects[0].amount)
			assert(is_equal_approx(float(speed_rate), float(plain.speed) * (1 + percent / 100.0)))
		elif String(timer.buff_move_id).contains("energizing"):
			assert(energy_rate == int(plain.base_max_energy * (1.0 + buff_percent / 100.0)))
		elif String(timer.buff_move_id).contains("mirror"):
			assert(is_equal_approx(reflect_rate, buff_percent / 100.0))
		else:
			assert(is_equal_approx(attack_rate, plain.max_attack_stat * (1.0 + buff_percent / 100.0)))
		var other := engine._state.combatants[&"stone-fixture-1"] as CombatantState
		other.defeated = true
		assert(LegacyCombatModifiers.effective_max_health(player, catalog, engine._state.combatants) == health_rate)
		assert(LegacyCombatModifiers.effective_speed(player, catalog, engine._state.combatants) == speed_rate)
		assert(LegacyCombatModifiers.critical_chance(player, catalog, engine._state.combatants) == crit_rate)
		assert(LegacyCombatModifiers.effective_attack(player, catalog, engine._state.combatants) == attack_rate)
		assert(LegacyCombatModifiers.effective_max_energy(player, catalog, engine._state.combatants) == energy_rate)
		assert(LegacyCombatModifiers.reflect_rate(player, catalog, engine._state.combatants) == reflect_rate)
		# Learned global moves are deduplicated; the independently granted stone
		# bonus stacks once more, exactly like DynamicData's append-after-filter.
		player.move_ids.append(buff.id)
		if String(timer.buff_move_id).contains("hulk"):
			assert(LegacyCombatModifiers.effective_max_health(player, catalog, engine._state.combatants) == int(plain.base_max_health * 1.30))
		player.move_ids.erase(buff.id)
		var snapshot := engine.snapshot()
		engine.restore(snapshot)
		assert(engine.snapshot() == snapshot, "Caster stats and separate stone bonus must survive snapshot/restore")
		engine._state.modifier_state.move_timer_counter = int(timer.interval)
		assert(engine._maybe_run_move_timer())
		assert(engine._current_events.any(func(event: BattleEvent) -> bool: return event.kind == &"move_used" and event.actor_id == caster.instance_id))
		assert(not engine._state.acted_ids.has(caster.instance_id))
		print("Checked %s: source caster level %d, max attack %.1f, %s" % [encounter_id, caster.level, caster.max_attack_stat, buff.display_name])
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	root.add_child(main)
	main.catalog = catalog
	var visual_encounter := catalog.get_definition(&"base:encounter/floor7_trainer_1") as EncounterDefinition
	main._create_move_timer_visuals(visual_encounter.battle_modifier_configuration.move_timer)
	var times: Dictionary = {}
	main.presenter.event_presented.connect(func(event: BattleEvent) -> void:
		if event.kind in [&"battle_mod_timer_triggered", &"move_used"]: times[String(event.kind)] = Time.get_ticks_usec()
	)
	var events: Array[BattleEvent] = [
		BattleEvent.new(0, &"battle_mod_timer_triggered", &"fixture-timer", &"", {"move_id": "base:move/sear/tier1", "interval": 3}),
		BattleEvent.new(1, &"move_used", &"fixture-timer", &"", {"move_id": "base:move/sear/tier1", "target_ids": []}),
	]
	main.call("_present", events)
	await create_timer(0.3).timeout
	assert(times.has("battle_mod_timer_triggered") and not times.has("move_used"), "Stone must grow before the timer move starts")
	var icon := main.battle_modifier_layer.get_node("MoveTimerModVisuals/TimerMoveIcon") as Sprite2D
	assert(icon.scale.x > 0.8 and main._move_timer_icon_tween.is_running())
	var cast_timeout_usec := Time.get_ticks_usec() + 1500000
	while not times.has("move_used") and Time.get_ticks_usec() < cast_timeout_usec:
		await process_frame
	assert(times.has("move_used"), "Timer move presentation missing after lead-in: %s" % times)
	assert(int(times.move_used) - int(times.battle_mod_timer_triggered) >= 700000, "Timer lead-in too short: %s" % times)
	await create_timer(2.8).timeout
	assert(not main._move_timer_icon_tween.is_running() and icon.scale.is_equal_approx(Vector2(0.8, 0.8)))
	main.queue_free()
	await process_frame
	print("PASS: ten source-mapped floor-7–10 timer stones, hidden BMod stats/levels, health/energy/speed/attack/reflect bonuses, stacking, death independence, snapshots and .7s cast lead-in")
	quit(0)
